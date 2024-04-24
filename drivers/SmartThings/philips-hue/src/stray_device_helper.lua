local cosock = require "cosock"
local log = require "log"
local st_utils = require "st.utils"

local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"

local lifecycle_handlers = require "handlers.lifecycle_handlers"
local utils = require "utils"

---@class StrayDeviceHelper
local StrayDeviceHelper = {}

---@enum MessageTypes
local MessageTypes = {
  FoundBridge = "FOUND_BRIDGE",
  NewStrayLight = "NEW_STRAY_LIGHT",
}
StrayDeviceHelper.MessageTypes = MessageTypes

--- Spawn the stray device resolution task, returning a handle to the tx side of the
--- channel for controlling it.
function StrayDeviceHelper.spawn()
  local stray_bulb_tx, stray_bulb_rx = cosock.channel.new()
  stray_bulb_rx:settimeout(30)

  cosock.spawn(function()
    local stray_lights = {}
    local stray_dni_to_rid = {}
    local found_bridges = {}
    local thread_local_driver = nil

    local process_strays = function(driver, strays, bridge_device_uuid)
      local dnis_to_remove = {}

      for light_dni, light_device in pairs(strays) do
        local light_rid = stray_dni_to_rid[light_dni]
        local cached_light_description = Discovery.device_state_disco_cache[light_rid]
        if cached_light_description then
          table.insert(dnis_to_remove, light_dni)
          lifecycle_handlers.migrate_device(driver, light_device, bridge_device_uuid, cached_light_description)
        end
      end

      for _, dni in ipairs(dnis_to_remove) do
        strays[dni] = nil
      end
    end

    while true do
      local msg, err = stray_bulb_rx:receive()
      if err and err ~= "timeout" then
        log.error_with({ hub_logs = true }, "Cosock Receive Error: ", err)
        goto continue
      end

      if err == "timeout" then
        if next(stray_lights) ~= nil and next(found_bridges) ~= nil and thread_local_driver ~= nil then
          log.info_with({ hub_logs = true },
            "No new stray lights received but some remain in queue, attempting to resolve remaining stray lights")
          for _, bridge in pairs(found_bridges) do
            stray_bulb_tx:send({
              type = StrayDeviceHelper.MessageTypes.FoundBridge,
              driver = thread_local_driver,
              device = bridge
            })
          end
        end
        goto continue
      end

      do
        local msg_device = msg.device
        thread_local_driver = msg.driver
        if msg.type == StrayDeviceHelper.MessageTypes.FoundBridge then
          local bridge_ip = msg_device:get_field(Fields.IPV4)
          local api_instance =
              msg_device:get_field(Fields.BRIDGE_API)
              or Discovery.disco_api_instances[msg_device.device_network_id]

          if not api_instance then
            api_instance = HueApi.new_bridge_manager(
              "https://" .. bridge_ip,
              msg_device:get_field(HueApi.APPLICATION_KEY_HEADER),
              utils.labeled_socket_builder((msg_device.label or msg_device.device_network_id or msg_device.id or "unknown bridge"))
            )
            Discovery.disco_api_instances[msg_device.device_network_id] = api_instance
          end

          found_bridges[msg_device.id] = msg.device
          local bridge_device_uuid = msg_device.id

          -- TODO: We can optimize around this by keeping track of whether or not this bridge
          -- needs to be scanned (maybe skip scanning if there are no stray lights?)
          --
          -- @doug.stephen@smartthings.com
          log.info(
            string.format(
              "Stray light handler notified of new bridge %s, scanning bridge",
              (msg.device.label or msg.device.device_network_id or msg.device.id or "unknown bridge")
            )
          )
          Discovery.search_bridge_for_supported_devices(thread_local_driver, msg_device:get_field(Fields.BRIDGE_ID),
            api_instance,
            function(hue_driver, svc_info, device_data)
              if not (svc_info.rid and svc_info.rtype and svc_info.rtype == "light") then return end

              local device_light_resource_id = svc_info.rid
              local light_resource, rest_err, _ = api_instance:get_light_by_id(device_light_resource_id)
              if rest_err ~= nil or not light_resource then
                log.error_with({ hub_logs = true }, string.format(
                  "Error getting light info while processing new bridge %s",
                  (msg_device.label or msg_device.id or "unknown device"), rest_err
                ))
                return
              end

              if light_resource.errors and #light_resource.errors > 0 then
                log.error_with({ hub_logs = true }, "Errors found in API response:")
                for idx, resource_err in ipairs(light_resource.errors) do
                  log.error_with({ hub_logs = true }, string.format(
                    "Error Number %s in get_light_by_id response while onboarding bridge %s: %s",
                    idx,
                    (msg_device.label or msg_device.id or "unknown device"),
                    st_utils.stringify_table(resource_err)
                  ))
                end
                return
              end

              if light_resource.data and #light_resource.data > 0 then
                for _, light in ipairs(light_resource.data) do
                  local light_resource_description = {
                    hue_provided_name = device_data.metadata.name,
                    id = light.id,
                    on = light.on,
                    color = light.color,
                    dimming = light.dimming,
                    color_temperature = light.color_temperature,
                    mode = light.mode,
                    parent_device_id = bridge_device_uuid,
                    hue_device_id = light.owner.rid,
                    hue_device_data = device_data
                  }
                  if not Discovery.device_state_disco_cache[light.id] then
                    log.info(string.format("Caching previously unknown light service description for %s",
                      device_data.metadata.name))
                    Discovery.device_state_disco_cache[light.id] = light_resource_description
                  end
                end
              end

              for stray_dni, stray_light in pairs(stray_lights) do
                local matching_v1_id = stray_light.data and stray_light.data.bulbId and
                    stray_light.data.bulbId == device_data.id_v1:gsub("/lights/", "")
                local matching_uuid = utils.get_hue_rid(stray_light) == svc_info.rid or
                    stray_light.device_network_id == svc_info.rid

                if matching_v1_id or matching_uuid then
                  local api_key_extracted = api_instance.headers["hue-application-key"]
                  log.info_with({ hub_logs = true }, " ", (stray_light.label or stray_light.id or "unknown light"),
                    ", re-adding")
                  log.info_with({ hub_logs = true }, string.format(
                    'Found Bridge for stray light %s, retrying onboarding flow.\n' ..
                    '\tMatching v1 id? %s\n' ..
                    '\tMatching uuid? %s\n' ..
                    '\tlight_device DNI: %s\n' ..
                    '\tlight_device Parent Assigned Key: %s\n' ..
                    '\tlight_device parent device id: %s\n' ..
                    '\tProvided bridge_device_id: %s\n' ..
                    '\tAPI key cached for given bridge_device_id? %s\n' ..
                    '\tCached bridge device for given API key: %s\n'
                    ,
                    stray_light.label,
                    matching_v1_id,
                    matching_uuid,
                    stray_light.device_network_id,
                    stray_light.parent_assigned_child_key,
                    stray_light.parent_device_id,
                    bridge_device_uuid,
                    (Discovery.api_keys[hue_driver:get_device_info(bridge_device_uuid).device_network_id] ~= nil),
                    hue_driver.api_key_to_bridge_id[api_key_extracted]
                  ))
                  stray_dni_to_rid[stray_dni] = svc_info.rid
                  break
                end
              end
            end,
            "[process_strays]"
          )
          log.info(string.format(
            "Finished querying bridge %s for devices from stray light handler",
            (msg.device.label or msg.device.device_network_id or msg.device.id or "unknown bridge")
          )
          )
          process_strays(thread_local_driver, stray_lights, msg_device.id)
        elseif msg.type == StrayDeviceHelper.MessageTypes.NewStrayLight then
          stray_lights[msg_device.device_network_id] = msg_device

          local maybe_bridge_id =
              msg_device.parent_device_id or msg_device:get_field(Fields.PARENT_DEVICE_ID)
          local maybe_bridge = found_bridges[maybe_bridge_id]

          if maybe_bridge ~= nil then
            local bridge_ip = maybe_bridge:get_field(Fields.IPV4)
            local api_instance =
                maybe_bridge:get_field(Fields.BRIDGE_API)
                or Discovery.disco_api_instances[maybe_bridge.device_network_id]

            if not api_instance then
              api_instance = HueApi.new_bridge_manager(
                "https://" .. bridge_ip,
                maybe_bridge:get_field(HueApi.APPLICATION_KEY_HEADER),
                utils.labeled_socket_builder((maybe_bridge.label or maybe_bridge.device_network_id or maybe_bridge.id or "unknown bridge"))
              )
              Discovery.disco_api_instances[maybe_bridge.device_network_id] = api_instance
            end

            process_strays(thread_local_driver, stray_lights, maybe_bridge.id)
          end
        end
      end
      ::continue::
      if next(stray_lights) ~= nil then
        local stray_lights_pseudo_json = "{\"stray_bulbs\":["
        for dni, light in pairs(stray_lights) do
          stray_lights_pseudo_json = stray_lights_pseudo_json ..
              string.format(
                [[{"label":"%s","dni":"%s","device_id":"%s"},]],
                (light.label or light.id or "unknown light"),
                dni,
                light.id
              )
        end
        -- strip trailing comma and close array/root object
        stray_lights_pseudo_json = stray_lights_pseudo_json:sub(1, -2) .. "]}"
        log.info_with({ hub_logs = true },
          string.format("Stray light loop end, unprocessed lights: %s", stray_lights_pseudo_json))
      end
    end
  end, "Stray Hue Bulb Resolution Task")
  return stray_bulb_tx
end

return StrayDeviceHelper
