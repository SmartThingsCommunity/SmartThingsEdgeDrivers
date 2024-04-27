local cosock = require "cosock"
local log = require "log"
local st_utils = require "st.utils"

local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"
local HueDeviceTypes = require "hue_device_types"

local utils = require "utils"

local lazy_handlers = utils.lazy_handler_loader("handlers")

---@class StrayDeviceHelper
local StrayDeviceHelper = {}

---@enum MessageTypes
local MessageTypes = {
  FoundBridge = "FOUND_BRIDGE",
  NewStrayDevice = "NEW_STRAY_DEVICE",
}
StrayDeviceHelper.MessageTypes = MessageTypes

---@param driver HueDriver
---@param strays table<string,HueChildDevice>
---@param bridge_device_uuid string
function StrayDeviceHelper.process_strays(driver, strays, bridge_device_uuid)
  ---@type string[]
  local dnis_to_remove = {}
  for _, device in pairs(strays) do
    local device_rid, err = utils.get_hue_rid(device)
    if err or not device_rid then
      log.warn(tostring(err) or "could not determine device resource ID, continuing")
      goto continue
    end
    local cached_device_description = Discovery.device_state_disco_cache[device_rid]
    if cached_device_description then
      table.insert(dnis_to_remove, device.device_network_id)
      lazy_handlers.lifecycle_handlers.migrate_device(driver, device, bridge_device_uuid, cached_device_description, {force_migrate_type = HueDeviceTypes.LIGHT})
    end
    ::continue::
  end

  for _, dni in ipairs(dnis_to_remove) do
    strays[dni] = nil
  end
end

--- Spawn the stray device resolution task, returning a handle to the tx side of the
--- channel for controlling it.
function StrayDeviceHelper.spawn()
  local stray_device_tx, stray_device_rx = cosock.channel.new()
  stray_device_rx:settimeout(30)

  cosock.spawn(function()
    ---@type table<string,HueChildDevice>
    local stray_devices = {}
    ---@type table<string,HueBridgeDevice>
    local found_bridges = {}
    ---@type HueDriver?
    local thread_local_driver = nil

    while true do
      local msg, err = stray_device_rx:receive()
      if err and err ~= "timeout" then
        log.error_with({ hub_logs = true }, "Cosock Receive Error: ", err)
        goto continue
      end

      if err == "timeout" then
        if next(stray_devices) ~= nil and next(found_bridges) ~= nil and thread_local_driver ~= nil then
          log.info_with({ hub_logs = true },
            "No new stray devices received but some remain in queue, attempting to resolve remaining stray devices")
          for _, bridge in pairs(found_bridges) do
            stray_device_tx:send({
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
              msg_device:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
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
          -- needs to be scanned (maybe skip scanning if there are no stray devices?)
          --
          -- @doug.stephen@smartthings.com
          log.info(
            string.format(
              "Stray devices handler notified of new bridge %s, scanning bridge",
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
                  ---@type HueLightInfo
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
                    log.info(string.format("Caching previously unknown service description for %s",
                      device_data.metadata.name))
                    Discovery.device_state_disco_cache[light.id] = light_resource_description
                    if device_data.id_v1 then
                      Discovery.device_state_disco_cache[device_data.id_v1] = light_resource_description
                    end
                  end
                end
              end

              for _, stray_device in pairs(stray_devices) do
                local matching_v1_id = stray_device.data and stray_device.data.bulbId and
                    stray_device.data.bulbId == device_data.id_v1:gsub("/lights/", "")
                local matching_uuid = utils.get_hue_rid(stray_device) == svc_info.rid or
                    stray_device.device_network_id == svc_info.rid

                if matching_v1_id or matching_uuid then
                  stray_device:set_field(Fields.RESOURCE_ID, svc_info.rid, { persist = true })
                  local api_key_extracted = api_instance.headers["hue-application-key"]
                  log.info_with({ hub_logs = true }, " ", (stray_device.label or stray_device.id or "unknown device"),
                    ", re-adding")
                  log.info_with({ hub_logs = true }, string.format(
                    'Found Bridge for stray device %s, retrying onboarding flow.\n' ..
                    '\tMatching v1 id? %s\n' ..
                    '\tMatching uuid? %s\n' ..
                    '\tdevice DNI: %s\n' ..
                    '\tdevice Parent Assigned Key: %s\n' ..
                    '\tdevice parent device id: %s\n' ..
                    '\tProvided bridge_device_id: %s\n' ..
                    '\tAPI key cached for given bridge_device_id? %s\n' ..
                    '\tCached bridge device for given API key: %s\n'
                    ,
                    stray_device.label,
                    matching_v1_id,
                    matching_uuid,
                    stray_device.device_network_id,
                    stray_device.parent_assigned_child_key,
                    stray_device.parent_device_id,
                    bridge_device_uuid,
                    (Discovery.api_keys[hue_driver:get_device_info(bridge_device_uuid).device_network_id] ~= nil),
                    hue_driver.api_key_to_bridge_id[api_key_extracted]
                  ))
                  break
                end
              end
            end,
            "[process_strays]"
          )
          log.info(string.format(
            "Finished querying bridge %s for devices from stray devices handler",
            (msg.device.label or msg.device.device_network_id or msg.device.id or "unknown bridge")
          )
          )
          StrayDeviceHelper.process_strays(thread_local_driver, stray_devices, msg_device.id)
        elseif msg.type == StrayDeviceHelper.MessageTypes.NewStrayDevice then
          stray_devices[msg_device.device_network_id] = msg_device

          local maybe_bridge_id =
              msg_device.parent_device_id or msg_device:get_field(Fields.PARENT_DEVICE_ID)
          local maybe_bridge = found_bridges[maybe_bridge_id]

          if maybe_bridge ~= nil then
            local bridge_ip = maybe_bridge:get_field(Fields.IPV4)
            local api_instance =
                maybe_bridge:get_field(Fields.BRIDGE_API) --[[@as PhilipsHueApi]]
                or Discovery.disco_api_instances[maybe_bridge.device_network_id]

            if not api_instance then
              api_instance = HueApi.new_bridge_manager(
                "https://" .. bridge_ip,
                maybe_bridge:get_field(HueApi.APPLICATION_KEY_HEADER),
                utils.labeled_socket_builder((maybe_bridge.label or maybe_bridge.device_network_id or maybe_bridge.id or "unknown bridge"))
              )
              Discovery.disco_api_instances[maybe_bridge.device_network_id] = api_instance
            end

            StrayDeviceHelper.process_strays(thread_local_driver, stray_devices, maybe_bridge.id)
          end
        end
      end
      ::continue::
      if next(stray_devices) ~= nil then
        local stray_devices_pseudo_json = "{\"stray_devices\":["
        for _, device in pairs(stray_devices) do
          stray_devices_pseudo_json = stray_devices_pseudo_json ..
              string.format(
                [[{"label":"%s","dni":"%s","device_id":"%s"},]],
                (device.label or device.id or "unknown device"),
                device.device_network_id,
                device.id
              )
        end
        -- strip trailing comma and close array/root object
        stray_devices_pseudo_json = stray_devices_pseudo_json:sub(1, -2) .. "]}"
        log.info_with({ hub_logs = true },
          string.format("Stray device loop end, unprocessed devices: %s", stray_devices_pseudo_json))
      end
    end
  end, "Stray Hue Device Resolution Task")
  return stray_device_tx
end

return StrayDeviceHelper
