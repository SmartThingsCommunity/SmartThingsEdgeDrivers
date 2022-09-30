-- Zigbee driver utilities
local device_management = require "st.zigbee.device_management"
local battery_defaults  = require "st.zigbee.defaults.battery_defaults"
local data_types        = require "st.zigbee.data_types"
local utils             = require "st.utils"
local log               = require "log"

-- Zigbee specific cluster
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local ThermostatUIConfig = clusters.ThermostatUserInterfaceConfiguration
local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

-- ST Capabilities
local capabilities = require "st.capabilities"
local TemperatureMeasurement = capabilities.TemperatureMeasurement
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState
local Battery = capabilities.battery
local WindowOpenDetectionCap = capabilities["preparestream40760.windowOpenDetection"]
local HeatingMode = capabilities["preparestream40760.heatMode"]

-- Subdriver for custom capabilities
local common = require("popp/common")

local POPP_THERMOSTAT_FINGERPRINTS = {
  { mfr = "D5X84YU", model = "eT093WRO" }
}

local THERMOSTAT_MODE_MAP = {
  [Thermostat.attributes.SystemMode.HEAT] = ThermostatMode.thermostatMode.heat
}

-- Thermostat Mode Handler
local thermostat_mode_handler = function(driver, device, thermostat_mode)
  if THERMOSTAT_MODE_MAP[thermostat_mode.value] then
    device:emit_event(THERMOSTAT_MODE_MAP[thermostat_mode.value]())
  end
end

-- Thermostat Operating State Handler
local thermostat_operating_state_handler = function(driver, device, operating_state)
  if (operating_state:is_heat_second_stage_on_set() or operating_state:is_heat_on_set()) then
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.heating())
  else
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.idle())
  end
end

-- Set Setpoint Factory
local set_setpoint_factory = function(setpoint_attribute)
  return function(driver, device, command)
    local value = command.args.setpoint

    -- fetch and set latest setpoint for heat mode
    common.last_setpointTemp = device:get_field("last_setpointTemp")

    if value ~= common.last_setpointTemp then
      device:set_field("last_setpointTemp", value)
    end

    -- write new setpoint
    device:send(setpoint_attribute:write(device, value * 100))

    device.thread:call_with_delay(2, function(d)
      device:send(setpoint_attribute:read(device))
    end)
  end
end

-- Read Temperature
local thermostat_local_temp_attr_handler = function(driver, device, value, zb_rx)

  local temperature = value.value
  local last_temp = device:get_latest_state("main", capabilities.temperatureMeasurement.ID,
    capabilities.temperatureMeasurement.temperature.NAME)
  local use_last = nil

  if (temperature == 0x8000 or temperature == -32768) then -- fetch invalid temperature

    if (last_temp ~= nil) then
      -- use last temperature instead
      temperature = last_temp
      use_last = "set"
    else
      log.error("Sensor Temperature: INVALID VALUE")
      return
    end
  elseif (temperature > 0x8000) then -- Handle negative C (< 32F) readings
    temperature = -(utils.round(2 * (65536 - temperature)) / 2) -- Handle negative C (< 32F) readings
  end

  if (use_last == nil) then
    temperature = temperature / 100
  end

  device:emit_event(capabilities.temperatureMeasurement.temperature({ value = temperature, unit = "C" }))
end

local is_popp_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(POPP_THERMOSTAT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local supported_thermostat_modes_handler = function(driver, device)
  device:emit_event(ThermostatMode.supportedThermostatModes({ "heat" }))
end

local function thermostat_heating_set_point_attr_handler(driver, device, value, zb_rx)
  local point_value = value.value
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = point_value / 100, unit = "C" }))
end

-- Attribute Refresh Function
local do_refresh = function(driver, device)

  local attributes = {
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.ControlSequenceOfOperation,
    Thermostat.attributes.ThermostatRunningState,
    Thermostat.attributes.ThermostatRunningMode,
    Thermostat.attributes.SystemMode,
    ThermostatUIConfig.attributes.KeypadLockout,
    PowerConfiguration.attributes.BatteryVoltage,
    PowerConfiguration.attributes.BatteryPercentageRemaining
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
  -- refresh window open state
  device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, common.VIEWING_DIRECTION_ATTR,
    common.MFG_CODE))
end

-- Device Added Function
local device_added = function(driver, device)

  --Add the manufacturer-specific attributes to generate their configure reporting and bind requests
  for capability_id, configs in pairs(common.get_cluster_configurations()) do
    if device:supports_capability_by_id(capability_id) then
      for _, config in pairs(configs) do
        device:add_configured_attribute(config)
        device:add_monitored_attribute(config)
      end
    end
  end

  do_refresh(driver, device)
end

-- Configuration Function
local do_configure = function(driver, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, driver.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, driver.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 5, 300, 10)) -- report temperature changes over 0.1°C
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 5, 300, 50))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))

end

-- Device Init Function
local device_init = function(driver, device)
  -- set battery defaults
  battery_defaults.build_linear_voltage_init(2.4, 3.2)(driver, device)

  -- initial set of heat mode
  device.thread:call_with_delay(3, function()
    device:emit_event(HeatingMode.setpointMode.eco())
    -- refresh window open state
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, common.VIEWING_DIRECTION_ATTR,
      common.MFG_CODE))
  end)
end

local function info_changed(driver, device, event, args)
  for name, info in pairs(common.PREFERENCE_TABLES) do

    -- add namespace to name reference
    local preferenceId = "preparestream40760." .. name

    if (device.preferences[preferenceId] ~= nil and
        args.old_st_store.preferences[preferenceId] ~= device.preferences[preferenceId]) then
      local input = device.preferences[preferenceId]

      if (name == common.KEYPAD_LOCK or name == common.VIEWING_DIRECTION) then
        input = tonumber(input);
      elseif (name == common.REGUALTION_SETPOINT_OFFSET) then
        input = tonumber(input) * 10 -- prepare to 4 char dec
      end

      -- set keypad lock (child lock)
      if (name == common.KEYPAD_LOCK) then
        device:send(cluster_base.write_attribute(device,
          data_types.ClusterId(info.clusterId),
          data_types.AttributeId(info.attributeId),
          data_types.validate_or_build_type(input, info.dataType, "payload")
        ))
      else
        -- set viewing direction (0° or 180°)
        -- set orientation (vertical true/false)
        -- set regulation setpoint offset (-2.5 to 2.5)
        -- enable window open state detection feature (true/false)
        device:send(cluster_base.write_manufacturer_specific_attribute(device, info.clusterId, info.attributeId,
          common.MFG_CODE, info.dataType, input))
      end
    end
  end
end

-- do refresh with delay of 5 seconds after driver has changed
local driver_switched = function(driver, device)
  device.thread:call_with_delay(5, function()
    do_refresh(driver, device)
    do_configure(driver, device)
  end)
end

local popp_thermostat = {
  NAME = "POPP Smart Thermostat (Zigbee)",
  supported_capabilities = {
    TemperatureMeasurement,
    ThermostatHeatingSetpoint,
    ThermostatMode,
    ThermostatOperatingState,
    Battery,
    WindowOpenDetectionCap,
    HeatingMode
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint_factory(Thermostat.attributes
        .OccupiedHeatingSetpoint)
    },
    [HeatingMode.ID] = {
      [HeatingMode.commands.setSetpointMode.NAME] = common.heat_cmd_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_modes_handler,
        [Thermostat.attributes.ThermostatRunningState.ID] = thermostat_operating_state_handler,
        [Thermostat.attributes.ThermostatRunningMode.ID] = thermostat_mode_handler,
        [Thermostat.attributes.SystemMode.ID] = thermostat_mode_handler,
        [Thermostat.attributes.LocalTemperature.ID] = thermostat_local_temp_attr_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_heating_set_point_attr_handler,
        [common.WINDOW_OPEN_DETECTION_ID] = common.window_open_detection_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed,
    driverSwitched = driver_switched
  },
  can_handle = is_popp_thermostat
}

return popp_thermostat
