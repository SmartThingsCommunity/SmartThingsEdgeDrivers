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
local cc  = require "st.zwave.CommandClass"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
local SensorMultilevel = require "st.zwave.CommandClass.SensorMultilevel"
local constants = require "st.zwave.constants"

local QUBINO_FLUSH_2_RELAY_FINGERPRINT = {mfr = 0x0159, prod = 0x0002, model = 0x0051}

local function can_handle_qubino_flush_2_relay(opts, driver, device, ...)
  return device:id_match(QUBINO_FLUSH_2_RELAY_FINGERPRINT.mfr, QUBINO_FLUSH_2_RELAY_FINGERPRINT.prod, QUBINO_FLUSH_2_RELAY_FINGERPRINT.model)
end

local function component_to_endpoint(device, component_id)
    if component_id == "main" then
      return { 0, 1, 2 }
    else
      return {}
    end
end

local function endpoint_to_component(device, ep)
    return "main"
end

local function find_child(parent, src_channel)
  if src_channel == 0 then
    return parent
  else
    return parent:get_child_by_parent_assigned_key(string.format("%02X", src_channel))
  end
end

local function device_init(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:set_find_child(find_child)
  else
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
  end
end

local function get_child_metadata(device, endpoint)
  local name
  local profile_name
  if endpoint ~= 3 then
    name = string.format("%s relay %d", device.label, endpoint)
    profile_name = "metering-switch"
  else
    name = string.format("%s extra temperature sensor")
    profile_name = "child-temperature"
  end
  return {
    type = "EDGE_CHILD",
    label = name,
    profile = profile_name,
    parent_device_id = device.id,
    parent_assigned_child_key = string.format("%02X", endpoint),
    vendor_provided_label = name
  }
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    for i = 1, 3, 1 do
      driver:try_create_device(get_child_metadata(device, i))
    end
  end
end

local function send_refresh_to_endpoint(ep, driver, device)
  if device:supports_capability_by_id(capabilities.switch.ID) then
    device:send(SwitchBinary:Get({}, {dst_channels = {ep}}))
  end
  if device:supports_capability_by_id(capabilities.powerMeter.ID) then
    device:send(Meter:Get({scale = Meter.scale.electric_meter.WATTS}, {dst_channels = {ep}}))
  end
  if device:supports_capability_by_id(capabilities.energyMeter.ID) then
    device:send(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}, {dst_channels = {ep}}))
  end
  if device:supports_capability_by_id(capabilities.temperatureMeasurement.ID) then
    device:send(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}, {dst_channels = {ep}}))
  end
end

local function do_refresh(driver, device)
  for i= 0,3,1 do
    send_refresh_to_endpoint(i, driver, device)
  end
end

local function switch_report_handler(driver, device, cmd)
  local event
  if cmd.args.value ~= nil then
    if cmd.args.value == SwitchBinary.value.OFF_DISABLE then
      event = capabilities.switch.switch.off()
    else
      event = capabilities.switch.switch.on()
    end
  else
    if cmd.args.target_value == SwitchBinary.value.OFF_DISABLE then
      event = capabilities.switch.switch.off()
    else
      event = capabilities.switch.switch.on()
    end
  end
  if cmd.src_channel ~= 0 then
    send_refresh_to_endpoint(0, driver, device)
  end
  device:emit_event_for_endpoint(cmd.src_channel, event)
end

local function set_switch(value)
  return function(driver, device, cmd)
    local delay = constants.DEFAULT_GET_STATUS_DELAY
    local set = SwitchBinary:Set({
      target_value = value,
      duration = 0
    },{
      dst_channels = device:component_to_endpoint(cmd.component)
    })
    local query_device = function()
      do_refresh(driver, device)
    end
    device:send(set)
    device.thread:call_with_delay(delay, query_device)
  end
end


local qubino_flush_2_relay = {
  NAME = "qubino flush 2 relay",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  zwave_handlers = {
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report_handler
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = set_switch(SwitchBinary.value.ON_ENABLE),
      [capabilities.switch.commands.off.NAME] = set_switch(SwitchBinary.value.OFF_DISABLE)
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  can_handle = can_handle_qubino_flush_2_relay
}

return qubino_flush_2_relay
