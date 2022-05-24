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
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=1})

local ZOOZ_SWITCH_FINGERPRINTS = {
  {mfr = 0x027A, prod = 0xA000, model = 0xA003}, -- Zooz Double Plug
}

local function can_handle_zooz_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZOOZ_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function endpoint_to_component(device, endpoint)
  if endpoint == 1 then
    return "main"
  elseif endpoint == 2 then
    return "switch1"
  end
end

local function component_to_endpoint(device, component)
  if component == "main" then
    return {1}
  elseif component == "switch1" then
    return {2}
  end
end

local function map_components(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local do_refresh = function(self, device)
  for component, _ in pairs(device.profile.components) do
    device:send_to_component(SwitchBinary:Get({}), component)
    device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.WATTS}), component)
    device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}), component)
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
    local component = endpoint_to_component(device, cmd.src_channel)
    if (component ~= nil) then
      device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.WATTS}), component)
    end
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

local zooz_switch = {
  NAME = "Zooz Switch",
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
    init = map_components
  },
  can_handle = can_handle_zooz_switch,
}

return zooz_switch
