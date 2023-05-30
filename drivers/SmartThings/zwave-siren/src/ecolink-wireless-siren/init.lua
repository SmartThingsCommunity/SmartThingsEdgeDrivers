-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

local ECOLINK_WIRELESS_SIREN_FINGERPRINTS = {
  { manufacturerId = 0x014A, productType = 0x0005, productId = 0x000A }, -- Ecolink Siren
}

local function can_handle_ecolink_wireless_siren(opts, driver, device, ...)
  for _, fingerprint in ipairs(ECOLINK_WIRELESS_SIREN_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function basic_set_handler(driver, device, cmd)
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value
  local alarm_event = value == 0x00 and capabilities.alarm.alarm.off() or capabilities.alarm.alarm.both()
  device:emit_event_for_endpoint(cmd.src_channel, alarm_event)
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("siren(%d)")
  if ep_num ~= nil then
    return { tonumber(ep_num) + 1 }
  else
    return { 1 }
  end
end

local function endpoint_to_component(device, ep)
  local siren_comp = string.format("siren%d", ep - 1)
  if device.profile.components[siren_comp] ~= nil then
    return siren_comp
  else
    return "main"
  end
end

local function device_init(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local do_refresh = function(self, device)
  for comp_id, comp in pairs(device.profile.components) do
    device:send_to_component(SwitchBinary:Get({}), comp.id)
  end
end

local function siren_on(self, device, cmd)
  device:send_to_component(Basic:Set({value = 0xFF}), cmd.component)
  device:send_to_component(SwitchBinary:Get({}), cmd.component)
  if cmd.component == "siren1" then
    local delayed_command = function()
      device:send_to_component(SwitchBinary:Get({}), cmd.component)
    end
    device.thread:call_with_delay(2, delayed_command)
  end
end

local function siren_off(self, device, cmd)
  device:send_to_component(Basic:Set({value = 0x00}), cmd.component)
  device:send_to_component(SwitchBinary:Get({}), cmd.component)
end

local ecolink_wireless_siren = {
  NAME = "Ecolink Wireless Siren",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.both.NAME] = siren_on,
      [capabilities.alarm.commands.off.NAME] = siren_off
    }
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = can_handle_ecolink_wireless_siren,
}

return ecolink_wireless_siren
