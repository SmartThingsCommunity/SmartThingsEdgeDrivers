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

local device_management                    = require "st.zigbee.device_management"
local clusters                             = require "st.zigbee.zcl.clusters"
local cluster_base                         = require "st.zigbee.cluster_base"
local data_types                           = require "st.zigbee.data_types"
local Thermostat                           = clusters.Thermostat
local ThermostatUserInterfaceConfiguration = clusters.ThermostatUserInterfaceConfiguration

local capabilities              = require "st.capabilities"
local ThermostatMode            = capabilities.thermostatMode
local ThermostatOperatingState  = capabilities.thermostatOperatingState

local SINOPE_TECHNOLOGIES_THERMOSTAT_FINGERPRINTS = {
  { mfr = "Sinope Technologies", model = "TH1123ZB" },
  { mfr = "Sinope Technologies", model = "TH1124ZB" },
  { mfr = "Sinope Technologies", model = "TH1300ZB" },
  { mfr = "Sinope Technologies", model = "TH1400ZB" },
  { mfr = "Sinope Technologies", model = "TH1500ZB" }
}

local MFG_CODE = 0x0000
local SINOPE_CUSTOM_CLUSTER = 0xFF01
local MFR_TIME_FORMAT_ATTRIBUTE = 0x0114
local MFR_AIR_FLOOR_MODE_ATTRIBUTE = 0x0105
local MFR_AMBIENT_LIMIT_ATTRIBUTE = 0x0108
local MFR_FLOOR_LOW_LIMIT_ATTRIBUTE = 0x0109
local MFR_FLOOR_SENSOR_TYPE_ATTRIBUTE = 0x010B
local MFR_FLOOR_HIGH_LIMIT_ATTRIBUTE = 0x010A
local MFR_BACKLIGHT_MODE_ATTRIBUTE = 0x0402
local MFR_AUXILIARY_CYCLE_LENGTH_ATTRIBUTE = 0x0404
local KEYPAD_LOCK = "keypadLock"
local LOCK = "Lock"
local UNLOCK = "Unlock"
local TIME_FORMAT_12H = "12h"
local TIME_FORMAT_24H = "24h"
local BACKLIGHT_ALWAYS_ON = "AlwaysOn"
local BACKLIGHT_ON_DEMAND = "OnDemand"

local PREFERENCE_TABLES = {
  keypadLock = {
    prefType = "enumeration",
    clusterId = ThermostatUserInterfaceConfiguration.ID,
    attributeId = ThermostatUserInterfaceConfiguration.attributes.KeypadLockout.ID,
    dataType = data_types.Enum8
  },
  backlightSetting = {
    prefType = "enumeration",
    clusterId = Thermostat.ID,
    attributeId = MFR_BACKLIGHT_MODE_ATTRIBUTE,
    dataType = data_types.Enum8
  },
  timeFormat = {
    prefType = "enumeration",
    clusterId = SINOPE_CUSTOM_CLUSTER,
    attributeId = MFR_TIME_FORMAT_ATTRIBUTE,
    dataType = data_types.Enum8
  },
  airFloorMode = {
    prefType = "enumeration",
    clusterId = SINOPE_CUSTOM_CLUSTER,
    attributeId = MFR_AIR_FLOOR_MODE_ATTRIBUTE,
    dataType = data_types.Enum8
  },
  floorSensorType = {
    prefType = "enumeration",
    clusterId = SINOPE_CUSTOM_CLUSTER,
    attributeId = MFR_FLOOR_SENSOR_TYPE_ATTRIBUTE,
    dataType = data_types.Enum8
  },
  ambientLimit = {
    prefType = "integer",
    clusterId = SINOPE_CUSTOM_CLUSTER,
    attributeId = MFR_AMBIENT_LIMIT_ATTRIBUTE,
    dataType = data_types.Int16
  },
  floorLowLimit = {
    prefType = "integer",
    clusterId = SINOPE_CUSTOM_CLUSTER,
    attributeId = MFR_FLOOR_LOW_LIMIT_ATTRIBUTE,
    dataType = data_types.Int16
  },
  floorHighLimit = {
    prefType = "integer",
    clusterId = SINOPE_CUSTOM_CLUSTER,
    attributeId = MFR_FLOOR_HIGH_LIMIT_ATTRIBUTE,
    dataType = data_types.Int16
  },
  auxiliaryCycleLength = {
    prefType = "enumeration",
    clusterId = Thermostat.ID,
    attributeId = MFR_AUXILIARY_CYCLE_LENGTH_ATTRIBUTE,
    dataType = data_types.Uint16
  }
}

local is_sinope_thermostat = function(opts, driver, device)
  for _, fingerprint in ipairs(SINOPE_TECHNOLOGIES_THERMOSTAT_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local do_refresh = function(self, device)
  local attributes = {
    Thermostat.attributes.LocalTemperature,
    Thermostat.attributes.OccupiedHeatingSetpoint,
    Thermostat.attributes.PIHeatingDemand,
    Thermostat.attributes.SystemMode
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 19, 300, 25)) -- report temperature changes over 0.25°C
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 8, 302, 40))
  device:send(Thermostat.attributes.PIHeatingDemand:configure_reporting(device, 11, 301, 10))
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 10, 305))
end

local thermostat_heating_demand_handler = function(driver, device, heatingDemand)
  if (heatingDemand.value < 10) then
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.idle())
  else
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.heating())
  end
end

local function info_changed(driver, device, event, args)
  for name, info in pairs(PREFERENCE_TABLES) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local input = device.preferences[name]
      if (name == KEYPAD_LOCK) then
        device:send(ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:write(device, input))
      else
        if (info.prefType == "enumeration") then
          device:send(cluster_base.write_manufacturer_specific_attribute(device, info.clusterId, info.attributeId, MFG_CODE, info.dataType, input))
        elseif (info.prefType == "integer") then
          device:send(cluster_base.write_manufacturer_specific_attribute(device, info.clusterId, info.attributeId, MFG_CODE, info.dataType, input * 100))
        end
      end
    end
  end
end

local sinope_thermostat = {
  NAME = "Sinope Thermostat Handler",
  supported_capabilities = {
    TemperatureMeasurement,
    ThermostatHeatingSetpoint,
    ThermostatMode,
    ThermostatOperatingState,
  },
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.PIHeatingDemand.ID] = thermostat_heating_demand_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  can_handle = is_sinope_thermostat
}

return sinope_thermostat
