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

local st_device = require "st.device"
local utils = require "st.utils"
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({version = 3})
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1, strict = true })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version = 2, strict = true })

local energyMeterDefaults = require "st.zwave.defaults.energyMeter"
local powerMeterDefaults = require "st.zwave.defaults.powerMeter"
local switchDefaults = require "st.zwave.defaults.switch"
local MULTI_METERING_SWITCH_CONFIGURATION_MAP = require "multi-metering-switch/multi_metering_switch_configurations"

local PARENT_ENDPOINT = 1

local MULTI_METERING_SWITCH_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0003, model = 0x0084}, -- Aeotec Nano Switch 1
  {mfr = 0x0086, prod = 0x0103, model = 0x0084}, -- Aeotec Nano Switch 1
  {mfr = 0x0086, prod = 0x0203, model = 0x0084}, -- AU Aeotec Nano Switch 1
  {mfr = 0x027A, prod = 0xA000, model = 0xA004}, -- Zooz ZEN Power Strip 1
  {mfr = 0x015F, prod = 0x3102, model = 0x0201}, -- WYFY Touch 1-button Switch
  {mfr = 0x015F, prod = 0x3102, model = 0x0202}, -- WYFY Touch 2-button Switch
  {mfr = 0x015F, prod = 0x3102, model = 0x0204}, -- WYFY Touch 4-button Switch
  {mfr = 0x015F, prod = 0x3111, model = 0x5102}, -- WYFY Touch 1-button Switch
  {mfr = 0x015F, prod = 0x3121, model = 0x5102}, -- WYFY Touch 2-button Switch
  {mfr = 0x015F, prod = 0x3141, model = 0x5102} -- WYFY Touch 4-button Switch
}

local function can_handle_multi_metering_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(MULTI_METERING_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("multi-metering-switch")
      return true, subdriver
    end
  end
  return false
end

local function find_child(parent, ep_id)
  if ep_id == PARENT_ENDPOINT then
    return parent
  else
    return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
  end
end

local function create_child_device(driver, device, children_amount, device_profile)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD and
    not (device.child_ids and utils.table_size(device.child_ids) ~= 0) then
    for i = 2, children_amount+1, 1 do
      if find_child(device, i) == nil then
        local device_name_without_number = string.sub(device.label, 0,-2)
        local name = string.format("%s%d", device_name_without_number, i)
        local metadata = {
          type = "EDGE_CHILD",
          label = name,
          profile = device_profile,
          parent_device_id = device.id,
          parent_assigned_child_key = string.format("%02X", i),
          vendor_provided_label = name,
        }
        driver:try_create_device(metadata)
      end
    end
  end
end

local function device_added(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    local children_amount = MULTI_METERING_SWITCH_CONFIGURATION_MAP.get_child_amount(device)
    local device_profile = MULTI_METERING_SWITCH_CONFIGURATION_MAP.get_child_switch_device_profile(device)
    if children_amount == nil then
      children_amount = utils.table_size(device.zwave_endpoints)-1
    end
    create_child_device(driver, device, children_amount, device_profile)
  end
  device:refresh()
end

local function component_to_endpoint(device, component)
  return { PARENT_ENDPOINT }
end

local function device_init(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_find_child(find_child)
    device:set_component_to_endpoint_fn(component_to_endpoint)
  end
end

local function do_refresh(driver, device, command) -- should be deleted when v46 is released
  local component = command and command.component and command.component or "main"
  if device:is_cc_supported(cc.SWITCH_BINARY) then
    device:send_to_component(SwitchBinary:Get({}), component)
  elseif device:is_cc_supported(cc.BASIC) then
    device:send_to_component(Basic:Get({}), component)
  end
  if device:supports_capability_by_id(capabilities.powerMeter.ID) or device:supports_capability_by_id(capabilities.energyMeter.ID) then
    device:send_to_component(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }), component)
    device:send_to_component(Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }), component)
  end
end

local function meter_report_handler(driver, device, cmd)
  -- We got a meter report from the root node, so refresh all children
  -- endpoint 0 should have its reports dropped
  if (cmd.src_channel == 0) then
    device:refresh()
    for _, child in pairs(device:get_child_list()) do
      child:refresh()
    end
  else
    powerMeterDefaults.zwave_handlers[cc.METER][Meter.REPORT](driver, device, cmd)
    energyMeterDefaults.zwave_handlers[cc.METER][Meter.REPORT](driver, device, cmd)
  end
end

local function switch_report_handler(driver, device, cmd)
  if (cmd.src_channel ~= 0) then
    switchDefaults.zwave_handlers[cmd.cmd_class][cmd.cmd_id](driver, device, cmd)
    powerMeterDefaults.zwave_handlers[cmd.cmd_class][cmd.cmd_id](driver, device, cmd)
  end
end

-- Device appears to have some trouble with energy reset commands if the value is read too quickly
local function reset(driver, device, command)
  device.thread:call_with_delay(.5, function ()
    device:send_to_component(Meter:Reset({}), command.component)
  end)
  device.thread:call_with_delay(1.5, function()
    device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}), command.component)
  end)
end

local multi_metering_switch = {
  NAME = "multi metering switch",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.energyMeter.ID] = {
      [capabilities.energyMeter.commands.resetEnergyMeter.NAME] = reset
    }
  },
  zwave_handlers = {
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report_handler
    },
    [cc.BASIC] = {
      [Basic.REPORT] = switch_report_handler
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = can_handle_multi_metering_switch,
}

return multi_metering_switch
