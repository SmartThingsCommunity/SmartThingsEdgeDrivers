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
local switch_defaults = require "st.zwave.defaults.switch"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1, strict = true })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2, strict = true })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local utils = require "st.utils"
local constants = require "st.zwave.constants"

local ON = 0xFF
local OFF = 0x00

local ENDPOINTS = {
  parent = 1,
  child = 2
}

local FIBARO_DOUBLE_SWITCH_FINGERPRINTS = {
  {mfr = 0x010F, prod = 0x0203, model = 0x1000}, -- Fibaro Switch
  {mfr = 0x010F, prod = 0x0203, model = 0x2000}, -- Fibaro Switch
  {mfr = 0x010F, prod = 0x0203, model = 0x3000} -- Fibaro Switch
}

local function can_handle_fibaro_double_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(FIBARO_DOUBLE_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("fibaro-double-switch")
      return true, subdriver
    end
  end
  return false
end

local function do_refresh(driver, device, command)
  local component = command and command.component and command.component or "main"
  device:send_to_component(SwitchBinary:Get({}), component)
  device:send_to_component(Basic:Get({}), component)
  device:send_to_component(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }), component)
  device:send_to_component(Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }), component)
end

local function find_child(parent, ep_id)
  if ep_id == ENDPOINTS.parent then
    return parent
  else
    return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
  end
end

local function device_added(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE and
    not (device.child_ids and utils.table_size(device.child_ids) ~= 0) and
    find_child(device, ENDPOINTS.child) == nil then

    local name = string.format("%s %s", device.label, "(CH2)")
    local metadata = {
      type = "EDGE_CHILD",
      label = name,
      profile = "metering-switch",
      parent_device_id = device.id,
      parent_assigned_child_key = string.format("%02X", ENDPOINTS.child),
      vendor_provided_label = name,
    }
    driver:try_create_device(metadata)
  end
  do_refresh(driver, device)
end

local function component_to_endpoint(device, component)
  return { ENDPOINTS.parent }
end

local function device_init(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_find_child(find_child)
    device:set_component_to_endpoint_fn(component_to_endpoint)
  end
end

local function switch_report(driver, device, cmd)
  switch_defaults.zwave_handlers[cc.SWITCH_BINARY][SwitchBinary.REPORT](driver, device, cmd)

  if device:supports_capability_by_id(capabilities.powerMeter.ID) then
    device:send(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { cmd.src_channel } }))
  end
end

local function set_switch(value)
  return function(driver, device, cmd)
    local delay = constants.MIN_DIMMING_GET_STATUS_DELAY
    local query_device = function()
      local component = cmd and cmd.component and cmd.component or "main"
      device:send_to_component(SwitchBinary:Get({}), component)
    end

    device:send_to_component(Basic:Set({ value = value }), cmd.component)
    device.thread:call_with_delay(delay, query_device)
  end
end

local fibaro_double_switch = {
  NAME = "fibaro double switch",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = switch_report
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = set_switch(ON),
      [capabilities.switch.commands.off.NAME] = set_switch(OFF)
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = can_handle_fibaro_double_switch,
}

return fibaro_double_switch
