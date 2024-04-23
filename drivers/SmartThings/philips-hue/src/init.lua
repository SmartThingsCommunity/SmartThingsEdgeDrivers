--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--
--  ===============================================================================================
--  Up to date API references are available here:
--  https://developers.meethue.com/develop/hue-api-v2/
--
--  Improvements to be made:
--
--  ===============================================================================================
local Driver = require "st.driver"

local cosock = require "cosock"
local log = require "log"
local capabilities = require "st.capabilities"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: table, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"
local StrayDeviceHelper = require "stray_device_helper"

local command_handlers = require "handlers.commands"
local lifecycle_handlers = require "handlers.lifecycle_handlers"

local bridge_utils = require "utils.hue_bridge_utils"
local utils = require "utils"

local function safe_wrap_handler(handler)
  return function(driver, device, ...)
    if device == nil or (device and device.id == nil) then
      log.warn("Tried to handle capability command for device that has been deleted")
      return
    end
    local success, result = pcall(handler, driver, device, ...)
    if not success then
      log.error_with({ hub_logs = true }, string.format("Failed to invoke capability command handler. Reason: %s", result))
    end
    return result
  end
end

local refresh_handler = safe_wrap_handler(command_handlers.refresh_handler)
local switch_on_handler = safe_wrap_handler(command_handlers.switch_on_handler)
local switch_off_handler = safe_wrap_handler(command_handlers.switch_off_handler)
local switch_level_handler = safe_wrap_handler(command_handlers.switch_level_handler)
local set_color_handler = safe_wrap_handler(command_handlers.set_color_handler)
local set_color_temp_handler = safe_wrap_handler(command_handlers.set_color_temp_handler)

local disco = Discovery.discover
local added = safe_wrap_handler(lifecycle_handlers.initialize_device)
local init = safe_wrap_handler(lifecycle_handlers.initialize_device)

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
        Discovery.search_bridge_for_supported_devices(thread_local_driver, msg_device:get_field(Fields.BRIDGE_ID), api_instance,
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


local function remove(driver, device)
  driver.datastore.dni_to_device_id[device.device_network_id] = nil
  if device:get_field(Fields.DEVICE_TYPE) == "bridge" then
    local api_instance = device:get_field(Fields.BRIDGE_API)
    if api_instance then
      api_instance:shutdown()
      device:set_field(Fields.BRIDGE_API, nil)
    end

    local event_source = device:get_field(Fields.EVENT_SOURCE)
    if event_source then
      event_source:close()
      device:set_field(Fields.EVENT_SOURCE, nil)
    end

    Discovery.api_keys[device.device_network_id] = nil
  end
end

local function supports_switch(hue_repr)
  return
      hue_repr.on ~= nil
      and type(hue_repr.on) == "table"
      and type(hue_repr.on.on) == "boolean"
end

local function supports_switch_level(hue_repr)
  return
      hue_repr.dimming ~= nil
      and type(hue_repr.dimming) == "table"
      and type(hue_repr.dimming.brightness) == "number"
end

local function supports_color_temp(hue_repr)
  return
      hue_repr.color_temperature ~= nil
      and type(hue_repr.color_temperature) == "table"
      and next(hue_repr.color_temperature) ~= nil
end

local function supports_color_control(hue_repr)
  return
      hue_repr.color ~= nil
      and type(hue_repr.color) == "table"
      and type(hue_repr.color.xy) == "table"
      and type(hue_repr.color.gamut) == "table"
end

local support_check_handlers = {
  [capabilities.switch.ID] = supports_switch,
  [capabilities.switchLevel.ID] = supports_switch_level,
  [capabilities.colorControl.ID] = supports_color_control,
  [capabilities.colorTemperature.ID] = supports_color_temp
}

--- @type HueDriver
local hue = Driver("hue",
  {
    discovery = disco,
    lifecycle_handlers = { added = added, init = init, removed = remove },
    capability_handlers = {
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
      },
      [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = switch_on_handler,
        [capabilities.switch.commands.off.NAME] = switch_off_handler,
      },
      [capabilities.switchLevel.ID] = {
        [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler,
      },
      [capabilities.colorControl.ID] = {
        [capabilities.colorControl.commands.setColor.NAME] = set_color_handler,
      },
      [capabilities.colorTemperature.ID] = {
        [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temp_handler,
      },
    },
    ignored_bridges = {},
    joined_bridges = {},
    light_id_to_device = {},
    device_rid_to_light_rid = {},
    -- the only real way we have to know which bridge a bulb wants to use at migration time
    -- is by looking at the stored api key so we will make a map to look up bridge IDs with
    -- the API key as the map key.
    api_key_to_bridge_id = {},
    stray_bulb_tx = stray_bulb_tx,
    _lights_pending_refresh = {},
    do_hue_light_delete = function(driver, device)
      if type(driver.try_delete_device) ~= "function" then
        local _log = device.log or log
        _log.warn("Requesting device delete on API version that doesn't support it. Marking device offline.")
        device:offline()
        return
      end

      driver:try_delete_device(device.id)
    end,
    check_hue_repr_for_capability_support = function(hue_repr, capability_id)
      local handler = support_check_handlers[capability_id]
      if type(handler) == "function" then
        return handler(hue_repr)
      else
        return false
      end
    end,
    update_bridge_netinfo = function(self, bridge_id, bridge_info)
      if self.joined_bridges[bridge_id] then
        local bridge_device = self:get_device_by_dni(bridge_id)
        if not bridge_device then
          log.warn_with({ hub_logs = true },
            string.format(
              "Couldn't locate bridge device for joined bridge with DNI %s",
              bridge_id
            )
          )
          return
        end

        if bridge_info.ip ~= bridge_device:get_field(Fields.IPV4) then
          bridge_utils.update_bridge_fields_from_info(self, bridge_info, bridge_device)
          local maybe_api_client = bridge_device:get_field(Fields.BRIDGE_API)
          local maybe_api_key = bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER) or Discovery.api_keys[bridge_id]
          local maybe_event_source = bridge_device:get_field(Fields.EVENT_SOURCE)
          local bridge_url = "https://" .. bridge_info.ip

          if maybe_api_key then
            if maybe_api_client then
              maybe_api_client:update_connection(bridge_url, maybe_api_key)
            end

            if maybe_event_source then
              maybe_event_source:close()
              bridge_device:set_field(Fields.EVENT_SOURCE, nil)
              bridge_utils.do_bridge_network_init(self, bridge_device, bridge_url, maybe_api_key)
            end
          end
        end
      end
    end,
    get_device_by_dni = function(self, dni, force_refresh)
      local device_uuid = self.datastore.dni_to_device_id[dni]
      if not device_uuid then return nil end
      return self:get_device_info(device_uuid, force_refresh)
    end
  }
)

if hue.datastore["bridge_netinfo"] == nil then
  hue.datastore["bridge_netinfo"] = {}
end

if hue.datastore["dni_to_device_id"] == nil then
  hue.datastore["dni_to_device_id"] = {}
end


if hue.datastore["api_keys"] == nil then
  hue.datastore["api_keys"] = {}
end

Discovery.api_keys = setmetatable({}, {
  __newindex = function (self, k, v)
    assert(
      type(v) == "string" or type(v) == "nil",
      string.format("Attempted to store value of type %s in application_key table which expects \"string\" types",
        type(v)
      )
    )
    hue.datastore.api_keys[k] = v
    hue.datastore:save()
  end,
  __index = function(self, k)
    return hue.datastore.api_keys[k]
  end
})

-- Kick off a scan right away to attempt to populate some information
hue:call_with_delay(3, Discovery.do_mdns_scan, "Philips Hue mDNS Initial Scan")

-- re-scan every minute
local MDNS_SCAN_INTERVAL_SECONDS = 600
hue:call_on_schedule(MDNS_SCAN_INTERVAL_SECONDS, Discovery.do_mdns_scan, "Philips Hue mDNS Scan Task")

log.info("Starting Hue driver")
hue:run()
log.warn("Hue driver exiting")
