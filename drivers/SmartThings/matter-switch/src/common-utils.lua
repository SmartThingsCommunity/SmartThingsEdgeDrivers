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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"

local common_utils = {}

common_utils.supported_capabilities = {
  capabilities.switch,
  capabilities.switchLevel,
  capabilities.colorControl,
  capabilities.colorTemperature,
  capabilities.level,
  capabilities.motionSensor,
  capabilities.illuminanceMeasurement,
  capabilities.powerMeter,
  capabilities.energyMeter,
  capabilities.powerConsumptionReport,
  capabilities.valve,
  capabilities.button,
  capabilities.battery,
  capabilities.batteryLevel,
  capabilities.temperatureMeasurement,
  capabilities.relativeHumidityMeasurement,
  capabilities.fanMode,
  capabilities.fanSpeedPercent
}

-- COMPONENT_TO_ENDPOINT_MAP is here to preserve the endpoint mapping for
-- devices that were joined to this driver as MCD devices before the transition
-- to join switch devices as parent-child. This value will exist in the device
-- table for devices that joined prior to this transition, and is also used for
-- button devices that require component mapping.
common_utils.COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
common_utils.ENERGY_MANAGEMENT_ENDPOINT = "__energy_management_endpoint"
common_utils.IS_PARENT_CHILD_DEVICE = "__is_parent_child_device"

common_utils.AQARA_MANUFACTURER_ID = 0x115F
common_utils.AQARA_CLIMATE_SENSOR_W100_ID = 0x2004

common_utils.AGGREGATOR_DEVICE_TYPE_ID = 0x000E
common_utils.ON_OFF_LIGHT_DEVICE_TYPE_ID = 0x0100
common_utils.DIMMABLE_LIGHT_DEVICE_TYPE_ID = 0x0101
common_utils.COLOR_TEMP_LIGHT_DEVICE_TYPE_ID = 0x010C
common_utils.EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID = 0x010D
common_utils.ON_OFF_PLUG_DEVICE_TYPE_ID = 0x010A
common_utils.DIMMABLE_PLUG_DEVICE_TYPE_ID = 0x010B
common_utils.ON_OFF_SWITCH_ID = 0x0103
common_utils.ON_OFF_DIMMER_SWITCH_ID = 0x0104
common_utils.ON_OFF_COLOR_DIMMER_SWITCH_ID = 0x0105
common_utils.MOUNTED_ON_OFF_CONTROL_ID = 0x010F
common_utils.MOUNTED_DIMMABLE_LOAD_CONTROL_ID = 0x0110
common_utils.GENERIC_SWITCH_ID = 0x000F
common_utils.ELECTRICAL_SENSOR_ID = 0x0510
common_utils.WATER_VALVE_ID = 0x0042

common_utils.device_type_profile_map = {
  [common_utils.ON_OFF_LIGHT_DEVICE_TYPE_ID] = "light-binary",
  [common_utils.DIMMABLE_LIGHT_DEVICE_TYPE_ID] = "light-level",
  [common_utils.COLOR_TEMP_LIGHT_DEVICE_TYPE_ID] = "light-level-colorTemperature",
  [common_utils.EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID] = "light-color-level",
  [common_utils.ON_OFF_PLUG_DEVICE_TYPE_ID] = "plug-binary",
  [common_utils.DIMMABLE_PLUG_DEVICE_TYPE_ID] = "plug-level",
  [common_utils.ON_OFF_SWITCH_ID] = "switch-binary",
  [common_utils.ON_OFF_DIMMER_SWITCH_ID] = "switch-level",
  [common_utils.ON_OFF_COLOR_DIMMER_SWITCH_ID] = "switch-color-level",
  [common_utils.MOUNTED_ON_OFF_CONTROL_ID] = "switch-binary",
  [common_utils.MOUNTED_DIMMABLE_LOAD_CONTROL_ID] = "switch-level",
}

common_utils.device_type_attribute_map = {
  [common_utils.ON_OFF_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [common_utils.DIMMABLE_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel
  },
  [common_utils.COLOR_TEMP_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.ColorControl.attributes.ColorTemperatureMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMinMireds
  },
  [common_utils.EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID] = {
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
  [common_utils.ON_OFF_PLUG_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [common_utils.DIMMABLE_PLUG_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel
  },
  [common_utils.ON_OFF_SWITCH_ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [common_utils.ON_OFF_DIMMER_SWITCH_ID] = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel
  },
  [common_utils.ON_OFF_COLOR_DIMMER_SWITCH_ID] = {
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
  [common_utils.GENERIC_SWITCH_ID] = {
    clusters.PowerSource.attributes.BatPercentRemaining,
    clusters.Switch.events.InitialPress,
    clusters.Switch.events.LongPress,
    clusters.Switch.events.ShortRelease,
    clusters.Switch.events.MultiPressComplete
  },
  [common_utils.ELECTRICAL_SENSOR_ID] = {
    clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported
  }
}

local child_device_profile_overrides_per_vendor_id = {
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

common_utils.battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}

function common_utils.detect_matter_thing(device)
  for _, capability in ipairs(common_utils.supported_capabilities) do
    if device:supports_capability(capability) then
      return false
    end
  end
  return device:supports_capability(capabilities.refresh)
end

function common_utils.detect_bridge(device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == common_utils.AGGREGATOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

function common_utils.find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%d", ep_id))
end

function common_utils.supports_modular_profile(device)
  return version.api >= 14 and version.rpc >= 8 and
    not (device.manufacturer_info.vendor_id == common_utils.AQARA_MANUFACTURER_ID and
      device.manufacturer_info.product_id == common_utils.AQARA_CLIMATE_SENSOR_W100_ID)
end

function common_utils.tbl_contains(array, value)
  for _, element in ipairs(array) do
    if element == value then
      return true
    end
  end
  return false
end

function common_utils.get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

function common_utils.set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

--- device_type_supports_button_switch_combination helper function used to check
--- whether the device type for an endpoint is currently supported by a profile for
--- combination button/switch devices.
function common_utils.device_type_supports_button_switch_combination(device, endpoint_id)
  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == endpoint_id then
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id == common_utils.DIMMABLE_LIGHT_DEVICE_TYPE_ID then
          for _, fingerprint in ipairs(child_device_profile_overrides_per_vendor_id[0x115F]) do
            if device.manufacturer_info.product_id == fingerprint.product_id then
              return false -- For Aqara Dimmer Switch with Button.
            end
          end
          return true
        end
      end
    end
  end
  return false
end

local function get_first_non_zero_endpoint(endpoints)
  table.sort(endpoints)
  for _,ep in ipairs(endpoints) do
    if ep ~= 0 then -- 0 is the matter RootNode endpoint
      return ep
    end
  end
  return nil
end

--- find_default_endpoint is a helper function to handle situations where
--- device does not have endpoint ids in sequential order from 1
function common_utils.find_default_endpoint(device)
  if device.manufacturer_info.vendor_id == common_utils.AQARA_MANUFACTURER_ID and
    device.manufacturer_info.product_id == common_utils.AQARA_CLIMATE_SENSOR_W100_ID then
    -- In case of Aqara Climate Sensor W100, in order to sequentially set the button name to button 1, 2, 3
    return device.MATTER_DEFAULT_ENDPOINT
  end

  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})

  -- Return the first switch endpoint as the default endpoint if no button endpoints are present
  if #button_eps == 0 and #switch_eps > 0 then
    return get_first_non_zero_endpoint(switch_eps)
  end

  -- Return the first button endpoint as the default endpoint if no switch endpoints are present
  if #switch_eps == 0 and #button_eps > 0 then
    return get_first_non_zero_endpoint(button_eps)
  end

  -- If both switch and button endpoints are present, check the device type on the main switch
  -- endpoint. If it is not a supported device type, return the first button endpoint as the
  -- default endpoint.
  if #switch_eps > 0 and #button_eps > 0 then
    local main_endpoint = get_first_non_zero_endpoint(switch_eps)
    if common_utils.supports_modular_profile(device) or common_utils.device_type_supports_button_switch_combination(device, main_endpoint) then
      return get_first_non_zero_endpoint(switch_eps)
    else
      device.log.warn("The main switch endpoint does not contain a supported device type for a component configuration with buttons")
      return get_first_non_zero_endpoint(button_eps)
    end
  end

  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

function common_utils.component_to_endpoint(device, component)
  local map = device:get_field(common_utils.COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return common_utils.find_default_endpoint(device)
end

function common_utils.endpoint_to_component(device, ep)
  local map = device:get_field(common_utils.COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function assign_child_profile(device, child_ep)
  local profile

  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == child_ep then
      -- Some devices report multiple device types which are a subset of
      -- a superset device type (For example, Dimmable Light is a superset of
      -- On/Off light). This mostly applies to the four light types, so we will want
      -- to match the profile for the superset device type. This can be done by
      -- matching to the device type with the highest ID
      local id = 0
      for _, dt in ipairs(ep.device_types) do
        id = math.max(id, dt.device_type_id)
      end
      profile = device_type_profile_map[id]
      break
    end
  end

  -- Check if device has an overridden child profile that differs from the profile that would match
  -- the child's device type for the following two cases:
  --   1. To add Electrical Sensor only to the first EDGE_CHILD (light-power-energy-powerConsumption)
  --      for the Aqara Light Switch H2. The profile of the second EDGE_CHILD for this device is
  --      determined in the "for" loop above (e.g., light-binary)
  --   2. The selected profile for the child device matches the initial profile defined in
  --      child_device_profile_overrides
  for _, vendor in pairs(child_device_profile_overrides_per_vendor_id) do
    for _, fingerprint in ipairs(vendor) do
      if device.manufacturer_info.product_id == fingerprint.product_id and
        ((device.manufacturer_info.vendor_id == common_utils.AQARA_MANUFACTURER_ID and child_ep == 1) or profile == fingerprint.initial_profile) then
        return fingerprint.target_profile
      end
    end
  end

  -- default to "switch-binary" if no profile is found
  return profile or "switch-binary"
end

function common_utils.build_child_switch_profiles(driver, device, main_endpoint)
  local num_switch_server_eps = 0
  local parent_child_device = false
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  table.sort(switch_eps)
  for _, ep in ipairs(switch_eps) do
    if device:supports_server_cluster(clusters.OnOff.ID, ep) then
      num_switch_server_eps = num_switch_server_eps + 1
      if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
        local name = string.format("%s %d", device.label, num_switch_server_eps)
        local child_profile = assign_child_profile(device, ep)
        driver:try_create_device(
          {
            type = "EDGE_CHILD",
            label = name,
            profile = child_profile,
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%d", ep),
            vendor_provided_label = name
          }
        )
        parent_child_device = true
        if _ == 1 and string.find(child_profile, "energy") then
          -- when energy management is defined in the root endpoint(0), replace it with the first switch endpoint and process it.
          device:set_field(common_utils.ENERGY_MANAGEMENT_ENDPOINT, ep, {persist = true})
        end
      end
    end
  end

  -- If the device is a parent child device, set the find_child function on init. This is persisted because initialize_buttons_and_switches
  -- is only run once, but find_child function should be set on each driver init.
  if parent_child_device then
    device:set_field(common_utils.IS_PARENT_CHILD_DEVICE, true, {persist = true})
  end

  -- this is needed in initialize_buttons_and_switches
  return num_switch_server_eps
end

return common_utils
