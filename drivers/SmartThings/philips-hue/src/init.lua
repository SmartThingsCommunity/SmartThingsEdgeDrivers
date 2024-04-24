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
local set_hue_handler = safe_wrap_handler(command_handlers.set_hue_handler)
local set_saturation_handler = safe_wrap_handler(command_handlers.set_saturation_handler)
local set_color_temp_handler = safe_wrap_handler(command_handlers.set_color_temp_handler)

local disco = Discovery.discover
local added = safe_wrap_handler(lifecycle_handlers.initialize_device)
local init = safe_wrap_handler(lifecycle_handlers.initialize_device)

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
        [capabilities.colorControl.commands.setHue.NAME] = set_hue_handler,
        [capabilities.colorControl.commands.setSaturation.NAME] = set_saturation_handler,
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
    stray_bulb_tx = StrayDeviceHelper.spawn(),
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
