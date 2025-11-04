-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=5})
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4})
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=1})

local constants = require "qubino-switches/constants/qubino-constants"

local fingerprints = require("qubino-switches.fingerprints")

local function getDeviceProfile(device, isTemperatureSensorOnboard)
  local newDeviceProfile
  for _, fingerprint in ipairs(fingerprints) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      newDeviceProfile = fingerprint.deviceProfile
      if(isTemperatureSensorOnboard) then
        return newDeviceProfile.."-temperature"
      else
        return newDeviceProfile
      end
    end
  end
  return nil
end

local function add_temperature_sensor_if_needed(device)
  if not (device:supports_capability_by_id(capabilities.temperatureMeasurement.ID)) then
    local new_profile = getDeviceProfile(device, true)
    device:try_update_metadata({profile = new_profile})
  end
end

local function sensor_multilevel_report(self, device, cmd)
  if (cmd.args.sensor_type == SensorMultilevel.sensor_type.TEMPERATURE) then
    local scale = 'C'
    if (cmd.args.sensor_value > constants.TEMP_SENSOR_WORK_THRESHOLD) then
      add_temperature_sensor_if_needed(device)
      if (cmd.args.scale == SensorMultilevel.scale.temperature.FARENHEIT) then
        scale = 'F'
      end
      device:emit_event_for_endpoint(
        cmd.src_channel,
        capabilities.temperatureMeasurement.temperature({value = cmd.args.sensor_value, unit = scale})
      )
    end
  end
end

local do_refresh = function(self, device)
  if device:supports_capability_by_id(capabilities.switchLevel.ID) then
    device:send(SwitchMultilevel:Get({}))
  end
  for component, _ in pairs(device.profile.components) do
    if device:supports_capability_by_id(capabilities.powerMeter.ID, component) then
      device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.WATTS}), component)
    end
    if device:supports_capability_by_id(capabilities.energyMeter.ID, component) then
      device:send_to_component(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}), component)
    end
    if device:supports_capability_by_id(capabilities.switch.ID, component) then
      device:send_to_component(SwitchBinary:Get({}), component)
    end
  end
  if device:supports_capability_by_id(capabilities.temperatureMeasurement.ID) then
    if device.profile.components["extraTemperatureSensor"] ~= nil then
      device:send_to_component(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}), "extraTemperatureSensor")
    else
      device:send(SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}))
    end
  end
end

local function device_added(self, device)
  do_refresh(self, device)
end

local qubino_relays = {
  NAME = "Qubino Relays",
  can_handle = require("qubino-switches.can_handle"),
  zwave_handlers = {
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  sub_drivers = require("qubino-switches.sub_drivers"),
}

return qubino_relays
