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
--- @type st.zwave.defaults.switch
local switch_defaults = require "st.zwave.defaults.switch"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1, strict=true })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local dualSwitchConfigurationsMap = require "zwave-dual-switch/dual_switch_configurations"
local utils = require "st.utils"

local ZWAVE_DUAL_SWITCH_FINGERPRINTS = {
  { mfr = 0x0086, prod = 0x0103, model = 0x008C }, -- Aeotec Switch 1
  { mfr = 0x0086, prod = 0x0003, model = 0x008C }, -- Aeotec Switch 1
  { mfr = 0x0258, prod = 0x0003, model = 0x008B }, -- NEO Coolcam Switch 1
  { mfr = 0x0258, prod = 0x0003, model = 0x108B }, -- NEO Coolcam Switch 1
  { mfr = 0x0312, prod = 0xC000, model = 0xC004 }, -- EVA Switch 1
  { mfr = 0x0312, prod = 0xFF00, model = 0xFF05 }, -- Minoston Switch 1
  { mfr = 0x0312, prod = 0xC000, model = 0xC007 }, -- Evalogik Switch 1
  { mfr = 0x010F, prod = 0x1B01, model = 0x1000 }, -- Fibaro Walli Double Switch
  { mfr = 0x027A, prod = 0xA000, model = 0xA003 }  -- Zooz Double Plug
}

local function can_handle_zwave_dual_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_DUAL_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("zwave-dual-switch")
      return true, subdriver
    end
  end
  return false
end

local function find_child(parent, src_channel)
  if src_channel == 1 then
    return parent
  else
    return parent:get_child_by_parent_assigned_key(string.format("%02X", src_channel))
  end
end

local function generate_child_name(parent_label)
  if string.sub(parent_label, -1) == '1' then
    return string.format("%s2", string.sub(parent_label, 0, -2))
  else
    return string.format("%s 2", parent_label)
  end
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    local dual_switch_configuration = dualSwitchConfigurationsMap.get_child_device_configuration(device)

    if not (device.child_ids and utils.table_size(device.child_ids) ~= 0) and --migration case will have non-zero
      (dual_switch_configuration ~= nil and find_child(device, 2) == nil) then
      local name = generate_child_name(device.label)
      local childDeviceProfile = dual_switch_configuration.child_switch_device_profile
      local metadata = {
        type = "EDGE_CHILD",
        label = name,
        profile = childDeviceProfile,
        parent_device_id = device.id,
        parent_assigned_child_key = string.format("%02X", 2),
        vendor_provided_label = name
      }
      driver:try_create_device(metadata)
    end
  end
  device:refresh()
end

local function component_to_endpoint(device, component)
  return { 1 }
end

local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_find_child(find_child)
    device:set_component_to_endpoint_fn(component_to_endpoint)
  end
end

local function basic_set_handler(driver, device, cmd)
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value
  local event = value == 0x00 and capabilities.switch.switch.off() or capabilities.switch.switch.on()

  device:emit_event_for_endpoint(cmd.src_channel, event)
end

local function do_refresh(driver, device, command)
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

local function switch_report(driver, device, cmd)
  switch_defaults.zwave_handlers[cc.SWITCH_BINARY][SwitchBinary.REPORT](driver, device, cmd)

  if device:supports_capability_by_id(capabilities.powerMeter.ID) then
    device:send(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { cmd.src_channel } }))
  end
end

local zwave_dual_switch = {
  NAME = "zwave dual switch",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler,
      [Basic.REPORT] = switch_report
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init
  },
  can_handle = can_handle_zwave_dual_switch
}

return zwave_dual_switch
