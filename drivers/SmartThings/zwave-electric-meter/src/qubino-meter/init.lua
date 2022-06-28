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
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version=3 })
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"

local QUBINO_FINGERPRINTS = {
  {mfr = 0x0159, prod = 0x0007, model = 0x0054},  -- Qubino 3 Phase Meter
  {mfr = 0x0159, prod = 0x0007, model = 0x0052}   -- Qubino Smart Meter
}

local POWER_UNIT_WATT = "W"
local ENERGY_UNIT_KWH = "kWh"

local function can_handle_qubino_meter(opts, driver, device, ...)
  for _, fingerprint in ipairs(QUBINO_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function meter_report_handler(self, device, cmd)

  if cmd.args.scale == Meter.scale.electric_meter.KILOWATT_HOURS then
    local event_arguments = {
      value = cmd.args.meter_value,
      unit = ENERGY_UNIT_KWH
    }
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.energyMeter.energy(event_arguments)
    )
  elseif cmd.args.scale == Meter.scale.electric_meter.WATTS then
    local event_arguments = {
      value = cmd.args.meter_value,
      unit = POWER_UNIT_WATT
    }
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.powerMeter.power(event_arguments)
    )
  end
end

local function component_to_endpoint(device, component_id)
  local ep_str = component_id:match("endpointMeter(%d)")
  local ep_num = ep_str and math.floor(ep_str + 1)
  return {ep_num and tonumber(ep_num)}
end

local function endpoint_to_component(device, ep)
  local meter_comp = string.format("endpointMeter%d", ep - 1)
  if device.profile.components[meter_comp] ~= nil then
    return meter_comp
  else
    return "main"
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local do_configure = function (self, device)
  -- device will report energy consumption every 30 minutes
  device:send(Configuration:Set({parameter_number = 42, size = 2, configuration_value = 1800}))

  for _, component in pairs(device.st_store.profile.components) do
    -- endpoint will report on 10% power change
    device:send_to_component(Configuration:Set({parameter_number = 40, size = 1, configuration_value = 10}), component.id)
  end
end

local qubino_meter = {
  zwave_handlers = {
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    init = device_init
  },
  NAME = "qubino meter",
  can_handle = can_handle_qubino_meter
}

return qubino_meter
