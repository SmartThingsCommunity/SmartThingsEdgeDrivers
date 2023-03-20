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
local TemperatureMeasurement = capabilities.temperatureMeasurement
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState
local Battery = capabilities.battery
local TemperatureAlarm = capabilities.temperatureAlarm
local Switch = capabilities.switch

-- Subdriver for custom capabilities
local common = require("popp/common")

local POPP_THERMOSTAT_FINGERPRINTS = {
  { mfr = "D5X84YU", model = "eT093WRO" },
  { mfr = "D5X84YU", model = "eT093WRG" }
}

local get_cluster_configurations = function()
  return {
      {
        cluster = Thermostat.ID,
        attribute = common.WINDOW_OPEN_DETECTION_ID,
        minimum_interval = 60,
        maximum_interval = 43200,
        reportable_change = 0x00,
        data_type = data_types.Enum8,
        mfg_code = common.MFG_CODE
      },
      {
        cluster = Thermostat.ID,
          attribute = common.EXTERNAL_OPEN_WINDOW_DETECTION_ID,
        minimum_interval = 0,
        maximum_interval = 1,
        reportable_change = 0x00,
        data_type = data_types.Enum8,
        mfg_code = common.MFG_CODE
      }
    }
end

-- Preference variables
local KEYPAD_LOCK = "keypadLock"
local VIEWING_DIRECTION = "viewingDirection"
local ETRV_ORIENTATION = "eTRVOrientation"
local REGUALTION_SETPOINT_OFFSET = "regulationSetPointOffset"
local WINDOW_OPEN_FEATURE = "windowOpenFeature"
local VIEWING_DIRECTION_ATTR = 0x4000
local ETRV_ORIENTATION_ATTR = 0x4014
local REGULATION_SETPOINT_OFFSET_ATTR = 0x404B
local WINDOW_OPEN_FEATURE_ATTR = 0x4051

-- preference table
local PREFERENCE_TABLES = {
  keypadLock = {
    clusterId = ThermostatUIConfig.ID,
    attributeId = ThermostatUIConfig.attributes.KeypadLockout.ID,
    dataType = data_types.Enum8
  },
  viewingDirection = {
    clusterId = ThermostatUIConfig.ID,
    attributeId = VIEWING_DIRECTION_ATTR,
    dataType = data_types.Enum8
  },
  eTRVOrientation = {
    clusterId = Thermostat.ID,
    attributeId = ETRV_ORIENTATION_ATTR,
    dataType = data_types.Boolean
  },
  regulationSetPointOffset = {
    clusterId = Thermostat.ID,
    attributeId = REGULATION_SETPOINT_OFFSET_ATTR,
    dataType = data_types.Int8
  },
  windowOpenFeature = {
    clusterId = Thermostat.ID,
    attributeId = WINDOW_OPEN_FEATURE_ATTR,
    dataType = data_types.Boolean
  }
}

local SUPPORTED_MODES = {
  ThermostatMode.thermostatMode.heat.NAME,
  ThermostatMode.thermostatMode.eco.NAME
}

local is_popp_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(POPP_THERMOSTAT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
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
  local last_temp = device:get_latest_state("main", TemperatureMeasurement.ID,
          TemperatureMeasurement.temperature.NAME)
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

  device:emit_event(TemperatureMeasurement.temperature({ value = temperature, unit = "C" }))
end

local function thermostat_heating_set_point_attr_handler(driver, device, value, zb_rx)
  local point_value = value.value
  device:emit_event(ThermostatHeatingSetpoint.heatingSetpoint({ value = point_value / 100, unit = "C" }))
end


local function external_open_window_detection_handler(driver, device, value, zb_rx)
  if (value.value == false) then
    device:emit_event(Switch.switch.on())
  else
    device:emit_event(Switch.switch.off())
  end
end

local function thermostat_mode_setter(mode_name)
  return function(driver, device, command)
    return common.heat_cmd_handler(driver, device, mode_name)
  end
end

local function handle_set_thermostat_mode_command(driver, device, command)
  return common.heat_cmd_handler(driver, device, command.args.mode)
end

-- Attribute Refresh Function
local do_refresh = function(driver, device)

  local attributes = {
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.LocalTemperature,
    ThermostatUIConfig.attributes.KeypadLockout,
    PowerConfiguration.attributes.BatteryVoltage
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
  -- refresh window open state
  device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, VIEWING_DIRECTION_ATTR,common.MFG_CODE))
  -- refresh external windo open state
  device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, common.EXTERNAL_OPEN_WINDOW_DETECTION_ID, common.MFG_CODE))
end

-- Device Added Function
local device_added = function(driver, device)
  -- Set supported thermostat modes
  device:emit_event(ThermostatMode.supportedThermostatModes(SUPPORTED_MODES, { visibility = { displayed = false } }))
end

-- Configuration Function
local do_configure = function(driver, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, driver.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, driver.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 5, 300, 10)) -- report temperature changes over 0.1°C
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 5, 300, 50))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.4, 3.2)(driver, device)

  -- Add the manufacturer-specific attributes to generate their configure reporting and bind requests
  for capability_id, config in pairs(get_cluster_configurations()) do
    device:add_configured_attribute(config)
    device:add_monitored_attribute(config)
  end

  -- initial set of heating mode
  --device.thread:call_with_delay(3, function()
    local stored_heat_mode = device:get_field(common.STORED_HEAT_MODE) or 'eco'
    local stored_switch_state = device:get_latest_state("main", Switch.ID, Switch.switch.NAME) or 'on'

    -- Use the stored mode
    -- Otherwise, set to eco
    if stored_heat_mode ~= nil then
      device:emit_event(ThermostatMode.thermostatMode[stored_heat_mode]())
    end

    -- Use the last switch state
    -- Otherwise, set to on
    if stored_switch_state ~= nil then
      device:emit_event(Switch.switch[stored_switch_state]())
    end

    do_refresh(driver, device)
  --end)
end

local function info_changed(driver, device, event, args)
  for name, info in pairs(PREFERENCE_TABLES) do

    -- add namespace to name reference
    if (device.preferences[name] ~= nil and
        args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local input = device.preferences[name]

      if (name == KEYPAD_LOCK or name == VIEWING_DIRECTION) then
        input = tonumber(input);
      elseif (name == REGUALTION_SETPOINT_OFFSET) then
        input = tonumber(input) * 10 -- prepare to 4 char dec
      end

      -- set keypad lock (child lock)
      if (name == KEYPAD_LOCK) then
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

local popp_thermostat = {
  NAME = "POPP Smart Thermostat (Zigbee)",
  supported_capabilities = {
    TemperatureMeasurement,
    ThermostatHeatingSetpoint,
    ThermostatMode,
    ThermostatOperatingState,
    Battery,
    TemperatureAlarm,
    Switch
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_setpoint_factory(Thermostat.attributes.OccupiedHeatingSetpoint)
    },
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = handle_set_thermostat_mode_command,
      [ThermostatMode.commands.heat.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.heat.NAME)
    },
    [Switch.ID] = {
      [Switch.commands.on.NAME] = common.switch_handle_on,
      [Switch.commands.off.NAME] = common.switch_handle_off
    }
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.LocalTemperature.ID] = thermostat_local_temp_attr_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_heating_set_point_attr_handler,
        [common.WINDOW_OPEN_DETECTION_ID] = common.window_open_detection_handler,
        [common.EXTERNAL_OPEN_WINDOW_DETECTION_ID] = external_open_window_detection_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  can_handle = is_popp_thermostat
}

return popp_thermostat
