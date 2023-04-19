-- Zigbee driver utilities
local device_management = require "st.zigbee.device_management"
local battery_defaults  = require "st.zigbee.defaults.battery_defaults"
local data_types        = require "st.zigbee.data_types"

-- Zigbee specific cluster
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local ThermostatUIConfig = clusters.ThermostatUserInterfaceConfiguration
local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

-- Capabilities
local capabilities = require "st.capabilities"
local TemperatureMeasurement = capabilities.temperatureMeasurement
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState
local Battery = capabilities.battery
local TemperatureAlarm = capabilities.temperatureAlarm
local Switch = capabilities.switch

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
        reportable_change = 1,
        data_type = data_types.Enum8,
        mfg_code = common.MFG_CODE
      },
      {
        cluster = Thermostat.ID,
        attribute = common.EXTERNAL_OPEN_WINDOW_DETECTION_ID,
        minimum_interval = 0,
        maximum_interval = 65534,
        reportable_change = 5,
        data_type = data_types.Enum8,
        mfg_code = common.MFG_CODE
      }
    }
end

-- Preference variables
local KEYPAD_LOCK = "keypadLock"
local VIEWING_DIRECTION = "viewingDirection"
local REGUALTION_SETPOINT_OFFSET = "regulationSetPointOffset"
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

  -- refresh custom attributes:
  -- window open state
  -- external window open state
  local custom_thermostat_attributes = {
    VIEWING_DIRECTION_ATTR,
    common.EXTERNAL_OPEN_WINDOW_DETECTION_ID
  }
  for _, attribute in pairs(custom_thermostat_attributes) do
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Thermostat.ID, attribute, common.MFG_CODE))
  end

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
  for _, config in pairs(get_cluster_configurations()) do
    device:add_configured_attribute(config)
    device:add_monitored_attribute(config)
  end

  device.thread:call_with_delay(2, function(d)
    -- initial set of heating mode
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
  end)
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
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = common.handle_set_setpoint
    },
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = common.setpoint_cmd_handler
    },
    [Switch.ID] = {
      [Switch.commands.on.NAME] = common.switch_handler_factory('on'),
      [Switch.commands.off.NAME] = common.switch_handler_factory('off')
    }
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.LocalTemperature.ID] = common.thermostat_local_temp_attr_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = common.thermostat_heating_set_point_attr_handler,
        [common.WINDOW_OPEN_DETECTION_ID] = common.window_open_detection_handler,
        [common.EXTERNAL_OPEN_WINDOW_DETECTION_ID] = common.external_open_window_detection_handler
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
