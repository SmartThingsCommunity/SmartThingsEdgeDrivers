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
local capabilities_defaults = require "st.capabilities.defaults"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 1 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 4 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 7 })
--- @type st.zwave.constants
local constants = require "st.zwave.constants"

local QUBINO_FLUSH_2_RELAY_FINGERPRINT = { mfr = 0x0159, prod = 0x0002, model = 0x0051 }

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
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_find_child(find_child)
    device:set_component_to_endpoint_fn(component_to_endpoint)
  end
end

local function get_child_metadata(device, endpoint)
  local name
  local profile_name
  if endpoint ~= 3 then
    name = string.format("%s relay %d", device.label, endpoint)
    profile_name = "metering-switch"
  else
    name = string.format("%s extra temperature sensor", device.label)
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
    for i = 1, 2, 1 do
      driver:try_create_device(get_child_metadata(device, i))
    end
    if device:is_cc_supported(cc.SENSOR_MULTILEVEL) then
      driver:try_create_device(get_child_metadata(device, 3))
    end
  end

  for _, comp in pairs(device.st_store.profile.components) do
    capabilities_defaults.emit_default_events(device, comp.capabilities)
  end
end

local function send_refresh_to_endpoint(ep, driver, device)
  if ep ~= 3 then
    device:send(SwitchBinary:Get({}, { dst_channels = { ep } }))
    device:send(Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { ep } }))
    device:send(Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { ep } }))
  else
    device:send(SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE }, { dst_channels = { ep } }))
  end
end

local function do_refresh(driver, device)
  for i = 0, 2, 1 do
    send_refresh_to_endpoint(i, driver, device)
  end
  if device:is_cc_supported(cc.SENSOR_MULTILEVEL, 3) then
    send_refresh_to_endpoint(3, driver, device)
  end
end

local function switch_report_handler(driver, device, cmd)
  local event
  local value = cmd.args.target_value or cmd.args.value

  if value ~= nil then
    if value == SwitchBinary.value.OFF_DISABLE then
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
    local query_device = function()
      do_refresh(driver, device)
    end
    local delay = constants.DEFAULT_GET_STATUS_DELAY
    for _, ep in ipairs(device:component_to_endpoint(cmd.component)) do
      device:send(SwitchBinary:Set({ switch_value = value }, { dst_channels = { ep } }))
    end
    device.thread:call_with_delay(delay, query_device)
  end
end

local function sensor_multilevel_report(driver, device, cmd)
  if (cmd.args.sensor_type == SensorMultilevel.sensor_type.TEMPERATURE) then
    local scale = 'C'
    if (cmd.args.scale == SensorMultilevel.scale.temperature.FARENHEIT) then
      scale = 'F'
    end
    device:emit_event_for_endpoint(
        cmd.src_channel,
        capabilities.temperatureMeasurement.temperature({ value = cmd.args.sensor_value, unit = scale })
    )
  end
end

local qubino_flush_2_relay = {
  NAME = "qubino flush 2 relay",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = switch_report_handler
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_report_handler
    },
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report
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
