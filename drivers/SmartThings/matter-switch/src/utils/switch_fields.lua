-- Copyright 2025 SmartThings
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

local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local version = require "version"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded_clusters.ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "embedded_clusters.ElectricalPowerMeasurement"
end

local SwitchFields = {}

SwitchFields.HUE_SAT_COLOR_MODE = clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION
SwitchFields.X_Y_COLOR_MODE = clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY

SwitchFields.MOST_RECENT_TEMP = "mostRecentTemp"
SwitchFields.RECEIVED_X = "receivedX"
SwitchFields.RECEIVED_Y = "receivedY"
SwitchFields.HUESAT_SUPPORT = "huesatSupport"


SwitchFields.MIRED_KELVIN_CONVERSION_CONSTANT = 1000000

-- These values are a "sanity check" to check that values we are getting are reasonable
local COLOR_TEMPERATURE_KELVIN_MAX = 15000
local COLOR_TEMPERATURE_KELVIN_MIN = 1000
SwitchFields.COLOR_TEMPERATURE_MIRED_MAX = SwitchFields.MIRED_KELVIN_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MIN
SwitchFields.COLOR_TEMPERATURE_MIRED_MIN = SwitchFields.MIRED_KELVIN_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MAX

SwitchFields.SWITCH_LEVEL_LIGHTING_MIN = 1
SwitchFields.CURRENT_HUESAT_ATTR_MIN = 0
SwitchFields.CURRENT_HUESAT_ATTR_MAX = 254


-- DEVICE TYPES
SwitchFields.AGGREGATOR_DEVICE_TYPE_ID = 0x000E
SwitchFields.ON_OFF_LIGHT_DEVICE_TYPE_ID = 0x0100
SwitchFields.DIMMABLE_LIGHT_DEVICE_TYPE_ID = 0x0101
SwitchFields.COLOR_TEMP_LIGHT_DEVICE_TYPE_ID = 0x010C
SwitchFields.EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID = 0x010D
SwitchFields.ON_OFF_PLUG_DEVICE_TYPE_ID = 0x010A
SwitchFields.DIMMABLE_PLUG_DEVICE_TYPE_ID = 0x010B
SwitchFields.ON_OFF_SWITCH_ID = 0x0103
SwitchFields.ON_OFF_DIMMER_SWITCH_ID = 0x0104
SwitchFields.ON_OFF_COLOR_DIMMER_SWITCH_ID = 0x0105
SwitchFields.MOUNTED_ON_OFF_CONTROL_ID = 0x010F
SwitchFields.MOUNTED_DIMMABLE_LOAD_CONTROL_ID = 0x0110
SwitchFields.GENERIC_SWITCH_ID = 0x000F
SwitchFields.ELECTRICAL_SENSOR_ID = 0x0510

SwitchFields.device_type_profile_map = {
  [SwitchFields.ON_OFF_LIGHT_DEVICE_TYPE_ID] = "light-binary",
  [SwitchFields.DIMMABLE_LIGHT_DEVICE_TYPE_ID] = "light-level",
  [SwitchFields.COLOR_TEMP_LIGHT_DEVICE_TYPE_ID] = "light-level-colorTemperature",
  [SwitchFields.EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID] = "light-color-level",
  [SwitchFields.ON_OFF_PLUG_DEVICE_TYPE_ID] = "plug-binary",
  [SwitchFields.DIMMABLE_PLUG_DEVICE_TYPE_ID] = "plug-level",
  [SwitchFields.ON_OFF_SWITCH_ID] = "switch-binary",
  [SwitchFields.ON_OFF_DIMMER_SWITCH_ID] = "switch-level",
  [SwitchFields.ON_OFF_COLOR_DIMMER_SWITCH_ID] = "switch-color-level",
  [SwitchFields.MOUNTED_ON_OFF_CONTROL_ID] = "switch-binary",
  [SwitchFields.MOUNTED_DIMMABLE_LOAD_CONTROL_ID] = "switch-level",
}


SwitchFields.CONVERSION_CONST_MILLIWATT_TO_WATT = 1000 -- A milliwatt is 1/1000th of a watt


-- COMPONENT_TO_ENDPOINT_MAP is here to preserve the endpoint mapping for
-- devices that were joined to this driver as MCD devices before the transition
-- to join switch devices as parent-child. This value will exist in the device
-- table for devices that joined prior to this transition, and is also used for
-- button devices that require component mapping.
SwitchFields.COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
SwitchFields.ENERGY_MANAGEMENT_ENDPOINT = "__energy_management_endpoint"
SwitchFields.IS_PARENT_CHILD_DEVICE = "__is_parent_child_device"
SwitchFields.COLOR_TEMP_BOUND_RECEIVED_KELVIN = "__colorTemp_bound_received_kelvin"
SwitchFields.COLOR_TEMP_BOUND_RECEIVED_MIRED = "__colorTemp_bound_received_mired"
SwitchFields.COLOR_TEMP_MIN = "__color_temp_min"
SwitchFields.COLOR_TEMP_MAX = "__color_temp_max"
SwitchFields.LEVEL_BOUND_RECEIVED = "__level_bound_received"
SwitchFields.LEVEL_MIN = "__level_min"
SwitchFields.LEVEL_MAX = "__level_max"
SwitchFields.COLOR_MODE = "__color_mode"

SwitchFields.updated_fields = {
  { current_field_name = "__component_to_endpoint_map_button", updated_field_name = SwitchFields.COMPONENT_TO_ENDPOINT_MAP },
  { current_field_name = "__switch_intialized", updated_field_name = nil }
}

SwitchFields.HUE_SAT_COLOR_MODE = clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION
SwitchFields.X_Y_COLOR_MODE = clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY


SwitchFields.child_device_profile_overrides_per_vendor_id = {
  [0x1321] = {
    { product_id = 0x000C, target_profile = "switch-binary", initial_profile = "plug-binary" },
    { product_id = 0x000D, target_profile = "switch-binary", initial_profile = "plug-binary" },
  },
  [0x115F] = {
    { product_id = 0x1003, target_profile = "light-power-energy-powerConsumption" },       -- 2 Buttons(Generic Switch), 1 Channel(On/Off Light)
    { product_id = 0x1004, target_profile = "light-power-energy-powerConsumption" },       -- 2 Buttons(Generic Switch), 2 Channels(On/Off Light)
    { product_id = 0x1005, target_profile = "light-power-energy-powerConsumption" },       -- 4 Buttons(Generic Switch), 3 Channels(On/Off Light)
    { product_id = 0x1006, target_profile = "light-level-power-energy-powerConsumption" }, -- 3 Buttons(Generic Switch), 1 Channels(Dimmable Light)
    { product_id = 0x1008, target_profile = "light-power-energy-powerConsumption" },       -- 2 Buttons(Generic Switch), 1 Channel(On/Off Light)
    { product_id = 0x1009, target_profile = "light-power-energy-powerConsumption" },       -- 4 Buttons(Generic Switch), 2 Channels(On/Off Light)
    { product_id = 0x100A, target_profile = "light-level-power-energy-powerConsumption" }, -- 1 Buttons(Generic Switch), 1 Channels(Dimmable Light)
  }
}

SwitchFields.CUMULATIVE_REPORTS_NOT_SUPPORTED = "__cumulative_reports_not_supported"
SwitchFields.TOTAL_IMPORTED_ENERGY = "__total_imported_energy"
SwitchFields.LAST_IMPORTED_REPORT_TIMESTAMP = "__last_imported_report_timestamp"
SwitchFields.MINIMUM_ST_ENERGY_REPORT_INTERVAL = (15 * 60) -- 15 minutes, reported in seconds

SwitchFields.START_BUTTON_PRESS = "__start_button_press"
SwitchFields.TIMEOUT_THRESHOLD = 10 --arbitrary timeout
SwitchFields.HELD_THRESHOLD = 1

-- this is the number of buttons for which we have a static profile already made
SwitchFields.STATIC_BUTTON_PROFILE_SUPPORTED = {1, 2, 3, 4, 5, 6, 7, 8, 9}

-- Some switches will send a MultiPressComplete event as part of a long press sequence. Normally the driver will create a
-- button capability event on receipt of MultiPressComplete, but in this case that would result in an extra event because
-- the "held" capability event is generated when the LongPress event is received. The IGNORE_NEXT_MPC flag is used
-- to tell the driver to ignore MultiPressComplete if it is received after a long press to avoid this extra event.
SwitchFields.IGNORE_NEXT_MPC = "__ignore_next_mpc"

SwitchFields.MP_ONGOING = "__multipress_ongoing"

-- These are essentially storing the supported features of a given endpoint
-- TODO: add an is_feature_supported_for_endpoint function to matter.device that takes an endpoint
SwitchFields.EMULATE_HELD = "__emulate_held" -- for non-MSR (MomentarySwitchRelease) devices we can emulate this on the software side
SwitchFields.SUPPORTS_MULTI_PRESS = "__multi_button" -- for MSM devices (MomentarySwitchMultiPress), create an event on receipt of MultiPressComplete
SwitchFields.INITIAL_PRESS_ONLY = "__initial_press_only" -- for devices that support MS (MomentarySwitch), but not MSR (MomentarySwitchRelease)

SwitchFields.TEMP_BOUND_RECEIVED = "__temp_bound_received"
SwitchFields.TEMP_MIN = "__temp_min"
SwitchFields.TEMP_MAX = "__temp_max"

SwitchFields.AQARA_MANUFACTURER_ID = 0x115F
SwitchFields.AQARA_CLIMATE_SENSOR_W100_ID = 0x2004

SwitchFields.TRANSITION_TIME = 0 --1/10ths of a second
-- When sent with a command, these options mask and override bitmaps cause the command
-- to take effect when the switch/light is off.
SwitchFields.OPTIONS_MASK = 0x01
SwitchFields.OPTIONS_OVERRIDE = 0x01


SwitchFields.supported_capabilities = {
  capabilities.battery,
  capabilities.batteryLevel,
  capabilities.button,
  capabilities.colorControl,
  capabilities.colorTemperature,
  capabilities.energyMeter,
  capabilities.fanMode,
  capabilities.fanSpeedPercent,
  capabilities.illuminanceMeasurement,
  capabilities.level,
  capabilities.motionSensor,
  capabilities.powerMeter,
  capabilities.powerConsumptionReport,
  capabilities.relativeHumidityMeasurement,
  capabilities.switch,
  capabilities.switchLevel,
  capabilities.temperatureMeasurement,
  capabilities.valve,
}

SwitchFields.device_type_attribute_map = {
  [SwitchFields.ON_OFF_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [SwitchFields.DIMMABLE_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel
  },
  [SwitchFields.COLOR_TEMP_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.ColorControl.attributes.ColorTemperatureMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMinMireds
  },
  [SwitchFields.EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.ColorControl.attributes.ColorTemperatureMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    clusters.ColorControl.attributes.CurrentHue,
    clusters.ColorControl.attributes.CurrentSaturation,
    clusters.ColorControl.attributes.CurrentX,
    clusters.ColorControl.attributes.CurrentY
  },
  [SwitchFields.ON_OFF_PLUG_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [SwitchFields.DIMMABLE_PLUG_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel
  },
  [SwitchFields.ON_OFF_SWITCH_ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [SwitchFields.ON_OFF_DIMMER_SWITCH_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel
  },
  [SwitchFields.ON_OFF_COLOR_DIMMER_SWITCH_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.ColorControl.attributes.ColorTemperatureMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    clusters.ColorControl.attributes.CurrentHue,
    clusters.ColorControl.attributes.CurrentSaturation,
    clusters.ColorControl.attributes.CurrentX,
    clusters.ColorControl.attributes.CurrentY
  },
  [SwitchFields.GENERIC_SWITCH_ID] = {
    clusters.PowerSource.attributes.BatPercentRemaining,
    clusters.Switch.events.InitialPress,
    clusters.Switch.events.LongPress,
    clusters.Switch.events.ShortRelease,
    clusters.Switch.events.MultiPressComplete
  },
  [SwitchFields.ELECTRICAL_SENSOR_ID] = {
    clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported
  }
}

return SwitchFields