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
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({version = 3})
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version = 1})
local Basic = (require "st.zwave.CommandClass.Basic")({version = 1})

local MULTI_METERING_SWITCH_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0003, model = 0x0084, children = 2}, -- Aeotec Nano Switch 1
  {mfr = 0x0086, prod = 0x0103, model = 0x0084, children = 2}, -- Aeotec Nano Switch 1
  {mfr = 0x0086, prod = 0x0203, model = 0x0084, children = 2}, -- AU Aeotec Nano Switch 1
  {mfr = 0x027A, prod = 0xA000, model = 0xA003, children = 2}, -- Zooz Double Plug 1
  {mfr = 0x027A, prod = 0xA000, model = 0xA004, children = 5}, -- Zooz ZEN Power Strip 1
  {mfr = 0x015F, prod = 0x3102, model = 0x0201, children = 1}, -- WYFY Touch 1-button Switch
  {mfr = 0x015F, prod = 0x3102, model = 0x0202, children = 2}, -- WYFY Touch 2-button Switch
  {mfr = 0x015F, prod = 0x3102, model = 0x0204, children = 4}, -- WYFY Touch 4-button Switch
  {mfr = 0x015F, prod = 0x3111, model = 0x5102, children = 1}, -- WYFY Touch 1-button Switch
  {mfr = 0x015F, prod = 0x3121, model = 0x5102, children = 2}, -- WYFY Touch 2-button Switch
  {mfr = 0x015F, prod = 0x3141, model = 0x5102, children = 4}, -- WYFY Touch 4-button Switch
}

local function can_handle_multi_metering_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(MULTI_METERING_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function get_children_amount(device)
  for _, fingerprint in ipairs(MULTI_METERING_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return fingerprint.children
    end
  end
end

local function get_profile(device)
  if device:get_manufacturer() == 0x015F then
    return "switch-binary"
  else
    return "metering-switch"
  end
end

local function device_added(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    local children_amount = get_children_amount(device)
    for i = 2, children_amount+1 do
      local device_name_without_number = string.sub(driver.label, 0,-2)
      local name = print(string.format("%s%d", device_name_without_number, i))
      local metadata = {
        type = "EDGE_CHILD",
        label = name,
        profile = get_profile(device),
        parent_device_id = device.id,
        parent_assigned_child_key = string.format("%02X", i),
        vendor_provided_label = name,
      }
      driver:try_create_device(metadata)
    end
  end
end

local function find_child(parent, ep_id)
  if ep_id == 1 then
    return parent
  else
    return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
  end
end

local function component_to_endpoint(device, component)
  return { 1 }
end

local function device_init(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_find_child(find_child)
    device:set_component_to_endpoint_fn(component_to_endpoint)
  end
end

local function do_refresh(driver, device, command)
  if device:is_cc_supported(cc.SWITCH_BINARY) then
    device:send_to_component(SwitchBinary:Get({}), command.component)
  elseif device:is_cc_supported(cc.BASIC) then
    device:send_to_component(Basic:Get({}), command.component)
  end
  if device:supports_capability_by_id(capabilities.powerMeter.ID) or device:supports_capability_by_id(capabilities.energyMeter.ID) then
    device:send_to_component(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }), command.component)
    device:send_to_component(Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }), command.component)
  end
end

local function switch_binary_report_handler(driver, device, cmd)
  local event
  local newValue
  if(cmd.args.target_value ~= nil) then
    newValue = cmd.args.target_value
  elseif cmd.args.value ~= nil then
    newValue = cmd.args.value
  end
  
  if newValue ~= nil and cmd.src_channel > 0 then
    if newValue == SwitchBinary.value.OFF_DISABLE then
      event = capabilities.switch.switch.off()
    else
      event = capabilities.switch.switch.on()
    end
    device:emit_event_for_endpoint(cmd.src_channel, event)
  end
end

local map_unit = {
  [Meter.scale.electric_meter.WATTS] = "W",
  [Meter.scale.electric_meter.KILOWATT_HOURS] = "kWh"
}

local map_scale_to_capability = {
  [Meter.scale.electric_meter.WATTS] = capabilities.powerMeter.power,
  [Meter.scale.electric_meter.KILOWATT_HOURS] = capabilities.energyMeter.energy,
}

local function power_energy_meter_report_handler(self, device, cmd)
  local supportedUnit = map_unit[cmd.args.scale]
  
  if cmd.src_channel > 0 and supportedUnit ~=nil then
    local event_arguments = {
      value = cmd.args.meter_value,
      unit = supportedUnit
    }
    
    local capabilityAttribute = map_scale_to_capability[cmd.args.scale]
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilityAttribute(event_arguments)
    )
  end
end

local multi_metering_switch = {
  NAME = "Multi Metering Switch",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zwave_handlers = {
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_binary_report_handler
    },
    [cc.METER] = {
      [Meter.REPORT] = power_energy_meter_report_handler
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = can_handle_multi_metering_switch,
}

return multi_metering_switch
