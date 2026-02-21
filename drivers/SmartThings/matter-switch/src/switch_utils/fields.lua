-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"

local SwitchFields = {}

SwitchFields.MOST_RECENT_TEMP = "mostRecentTemp"
SwitchFields.RECEIVED_X = "receivedX"
SwitchFields.RECEIVED_Y = "receivedY"
SwitchFields.HUESAT_SUPPORT = "huesatSupport"

SwitchFields.MIRED_KELVIN_CONVERSION_CONSTANT = 1000000

-- These values are a "sanity check" to check that values we are getting are reasonable
local COLOR_TEMPERATURE_KELVIN_MAX = 15000
local COLOR_TEMPERATURE_KELVIN_MIN = 1000
SwitchFields.COLOR_TEMPERATURE_MIRED_MAX = st_utils.round(SwitchFields.MIRED_KELVIN_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MIN)
SwitchFields.COLOR_TEMPERATURE_MIRED_MIN = st_utils.round(SwitchFields.MIRED_KELVIN_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MAX)

SwitchFields.SWITCH_LEVEL_LIGHTING_MIN = 1
SwitchFields.CURRENT_HUESAT_ATTR_MIN = 0
SwitchFields.CURRENT_HUESAT_ATTR_MAX = 254

SwitchFields.DEVICE_TYPE_ID = {
  AGGREGATOR = 0x000E,
  BRIDGED_NODE = 0x0013,
  CAMERA = 0x0142,
  CHIME = 0x0146,
  DIMMABLE_PLUG_IN_UNIT = 0x010B,
  DOORBELL = 0x0143,
  ELECTRICAL_SENSOR = 0x0510,
  FAN = 0x002B,
  GENERIC_SWITCH = 0x000F,
  MOUNTED_ON_OFF_CONTROL = 0x010F,
  MOUNTED_DIMMABLE_LOAD_CONTROL = 0x0110,
  ON_OFF_PLUG_IN_UNIT = 0x010A,
  LIGHT = {
    ON_OFF = 0x0100,
    DIMMABLE = 0x0101,
    COLOR_TEMPERATURE = 0x010C,
    EXTENDED_COLOR = 0x010D,
  },
  SWITCH = {
    ON_OFF_LIGHT = 0x0103,
    DIMMER = 0x0104,
    COLOR_DIMMER = 0x0105,
  },
}

SwitchFields.device_type_profile_map = {
  [SwitchFields.DEVICE_TYPE_ID.LIGHT.ON_OFF] = "light-binary",
  [SwitchFields.DEVICE_TYPE_ID.LIGHT.DIMMABLE] = "light-level",
  [SwitchFields.DEVICE_TYPE_ID.LIGHT.COLOR_TEMPERATURE] = "light-level-colorTemperature",
  [SwitchFields.DEVICE_TYPE_ID.LIGHT.EXTENDED_COLOR] = "light-color-level",
  [SwitchFields.DEVICE_TYPE_ID.SWITCH.ON_OFF_LIGHT] = "switch-binary",
  [SwitchFields.DEVICE_TYPE_ID.SWITCH.DIMMER] = "switch-level",
  [SwitchFields.DEVICE_TYPE_ID.SWITCH.COLOR_DIMMER] = "switch-color-level",
  [SwitchFields.DEVICE_TYPE_ID.ON_OFF_PLUG_IN_UNIT] = "plug-binary",
  [SwitchFields.DEVICE_TYPE_ID.DIMMABLE_PLUG_IN_UNIT] = "plug-level",
  [SwitchFields.DEVICE_TYPE_ID.MOUNTED_ON_OFF_CONTROL] = "switch-binary",
  [SwitchFields.DEVICE_TYPE_ID.MOUNTED_DIMMABLE_LOAD_CONTROL] = "switch-level",
}

-- COMPONENT_TO_ENDPOINT_MAP is here to preserve the endpoint mapping for
-- devices that were joined to this driver as MCD devices before the transition
-- to join switch devices as parent-child. This value will exist in the device
-- table for devices that joined prior to this transition, and is also used for
-- button devices that require component mapping.
SwitchFields.COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
SwitchFields.IS_PARENT_CHILD_DEVICE = "__is_parent_child_device"

--- If the ASSIGNED_CHILD_KEY field is populated for an endpoint, it should be
--- used as the key in the get_child_by_parent_assigned_key() function. This allows
--- multiple endpoints to associate with the same child device, though right now child
--- devices are keyed using only one endpoint id.
SwitchFields.ASSIGNED_CHILD_KEY = "__assigned_child_key"

SwitchFields.COLOR_TEMP_BOUND_RECEIVED_KELVIN = "__colorTemp_bound_received_kelvin"
SwitchFields.COLOR_TEMP_BOUND_RECEIVED_MIRED = "__colorTemp_bound_received_mired"
SwitchFields.COLOR_TEMP_MIN = "__color_temp_min"
SwitchFields.COLOR_TEMP_MAX = "__color_temp_max"
SwitchFields.LEVEL_BOUND_RECEIVED = "__level_bound_received"
SwitchFields.LEVEL_MIN = "__level_min"
SwitchFields.LEVEL_MAX = "__level_max"
SwitchFields.COLOR_MODE = "__color_mode"

SwitchFields.SUBSCRIBED_ATTRIBUTES_KEY = "__subscribed_attributes"

SwitchFields.updated_fields = {
  { current_field_name = "__component_to_endpoint_map_button", updated_field_name = SwitchFields.COMPONENT_TO_ENDPOINT_MAP },
  { current_field_name = "__switch_intialized", updated_field_name = nil },
  { current_field_name = "__energy_management_endpoint", updated_field_name = nil },
  { current_field_name = "__total_imported_energy", updated_field_name = nil },
  { current_field_name = "__last_imported_report_timestamp", updated_field_name = nil },
}

SwitchFields.vendor_overrides = {
  [0x115F] = { -- AQARA_MANUFACTURER_ID
    [0x1006] = { ignore_combo_switch_button = true }, -- 3 Buttons(Generic Switch), 1 Channel (Dimmable Light)
    [0x100A] = { ignore_combo_switch_button = true }, -- 1 Buttons(Generic Switch), 1 Channel (Dimmable Light)
    [0x2004] = { is_climate_sensor_w100 = true }, -- Climate Sensor W100, requires unique profile
  },
  [0x117C] = { -- IKEA_MANUFACTURER_ID
    [0x8000] = { is_ikea_scroll = true }
  },
  [0x1189] = { -- LEDVANCE_MANUFACTURER_ID
    [0x0891] = { target_profile = "switch-binary", initial_profile = "light-binary" },
  },
  [0x1321] = { -- SONOFF_MANUFACTURER_ID
    [0x000C] = { target_profile = "switch-binary", initial_profile = "plug-binary" },
    [0x000D] = { target_profile = "switch-binary", initial_profile = "plug-binary" },
  },
}

SwitchFields.switch_category_vendor_overrides = {
  [0x1432] = -- Elko
    {0x1000},
  [0x130A] = -- Eve
    {0x005D, 0x0043},
  [0x1339] = -- GE
    {0x007D, 0x0074, 0x0075},
  [0x1372] = -- Innovation Matters
    {0x0002},
  [0x1189] = -- Ledvance
    {0x0891, 0x0892},
  [0x1021] = -- Legrand
    {0x0005},
  [0x109B] = -- Leviton
    {0x1001, 0x1000, 0x100B, 0x100E, 0x100C, 0x100D, 0x1009, 0x1003, 0x1004, 0x1002},
  [0x142B] = -- LeTianPai
    {0x1004, 0x1003, 0x1002},
  [0x1509] = -- SmartSetup
    {0x0004, 0x0001},
  [0x1321] = -- SONOFF
    {0x000B, 0x000C, 0x000D},
  [0x147F] = -- U-Tec
    {0x0004},
  [0x139C] = -- Zemismart
    {0xEEE2, 0xAB08, 0xAB31, 0xAB04, 0xAB01, 0xAB43, 0xAB02, 0xAB03, 0xAB05}
}

--- stores a table of endpoints that support the Electrical Sensor device type, used during profiling
--- in AvailableEndpoints and PartsList handlers for SET and TREE PowerTopology features, respectively
SwitchFields.ELECTRICAL_SENSOR_EPS = "__electrical_sensor_eps"

--- used in tandem with an EP ID. Stores the required electrical tags "-power", "-energy-powerConsumption", etc.
--- for an Electrical Sensor EP with a "primary" endpoint, used during device profiling.
SwitchFields.ELECTRICAL_TAGS = "__electrical_tags"

SwitchFields.profiling_data = {
  POWER_TOPOLOGY = "__power_topology",
  BATTERY_SUPPORT = "__battery_support",
}

SwitchFields.battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE",
}

SwitchFields.ENERGY_METER_OFFSET = "__energy_meter_offset"
SwitchFields.CUMULATIVE_REPORTS_SUPPORTED = "__cumulative_reports_supported"
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

-- These are essentially storing the supported features of a given endpoint
-- TODO: add an is_feature_supported_for_endpoint function to matter.device that takes an endpoint
SwitchFields.EMULATE_HELD = "__emulate_held" -- for non-MSR (MomentarySwitchRelease) devices we can emulate this on the software side
SwitchFields.SUPPORTS_MULTI_PRESS = "__multi_button" -- for MSM devices (MomentarySwitchMultiPress), create an event on receipt of MultiPressComplete
SwitchFields.INITIAL_PRESS_ONLY = "__initial_press_only" -- for devices that support MS (MomentarySwitch), but not MSR (MomentarySwitchRelease)

SwitchFields.TEMP_BOUND_RECEIVED = "__temp_bound_received"
SwitchFields.TEMP_MIN = "__temp_min"
SwitchFields.TEMP_MAX = "__temp_max"

SwitchFields.TRANSITION_TIME = 0 -- number of 10ths of a second
SwitchFields.TRANSITION_TIME_FAST = 3 -- 0.3 seconds

-- For Level/Color Control cluster commands, this field indicates which bits in the OptionsOverride field are valid. In this case, we specify that the ExecuteIfOff option (bit 1) may be overridden.
SwitchFields.OPTIONS_MASK = 0x01
-- the OptionsOverride field's first bit overrides the ExecuteIfOff option, defining whether the command should take effect when the device is off.
SwitchFields.HANDLE_COMMAND_IF_OFF = 0x01
SwitchFields.IGNORE_COMMAND_IF_OFF = 0x00

return SwitchFields
