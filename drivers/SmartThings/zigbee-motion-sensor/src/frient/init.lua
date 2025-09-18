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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local IASZone = zcl_clusters.IASZone
local IlluminanceMeasurement = zcl_clusters.IlluminanceMeasurement
local OccupancySensing = zcl_clusters.OccupancySensing
local PowerConfiguration = zcl_clusters.PowerConfiguration
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement

local BATTERY_MIN_VOLTAGE = 2.3
local BATTERY_MAX_VOLTAGE = 3.0
local DEFAULT_OCCUPIED_TO_UNOCCUPIED_DELAY = 240
local DEFAULT_UNOCCUPIED_TO_OCCUPIED_DELAY = 0
local DEFAULT_UNOCCUPIED_TO_OCCUPIED_THRESHOLD = 0

local OCCUPANCY_ENDPOINT = 0x22
local TAMPER_ENDPOINT = 0x23
local POWER_CONFIGURATION_ENDPOINT = 0x23
local TEMPERATURE_ENDPOINT = 0x26
local ILLUMINANCE_ENDPOINT = 0x27

local FRIENT_DEVICE_FINGERPRINTS = {
  { mfr = "frient A/S", model = "MOSZB-140"},
  { mfr = "frient A/S", model = "MOSZB-141"},
  { mfr = "frient A/S", model = "MOSZB-153"}
}

local function can_handle_frient_motion_sensor(opts, driver, device)
  for _, fingerprint in ipairs(FRIENT_DEVICE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function occupancy_attr_handler(driver, device, occupancy, zb_rx)
  device:emit_event(occupancy.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local function generate_event_from_zone_status(driver, device, zone_status, zb_rx)
  device:emit_event(zone_status:is_tamper_set() and capabilities.tamperAlert.tamper.detected() or capabilities.tamperAlert.tamper.clear())
end

local function ias_zone_status_attr_handler(driver, device, attr_val, zb_rx)
  generate_event_from_zone_status(driver, device, attr_val, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end


local CONFIGURATIONS = {
  [OCCUPANCY_ENDPOINT] = {
    cluster = OccupancySensing.ID,
    attribute = OccupancySensing.attributes.Occupancy.ID,
    data_type = OccupancySensing.attributes.Occupancy.base_type,
    minimum_interval = 0,
    maximum_interval = 3600,
    endpoint = OCCUPANCY_ENDPOINT
  },
  [TAMPER_ENDPOINT] = {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 30,
    maximum_interval = 300,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1,
    endpoint = TAMPER_ENDPOINT
  },
  [TEMPERATURE_ENDPOINT] = {
    cluster = TemperatureMeasurement.ID,
    attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
    reportable_change = 10,
    endpoint = TEMPERATURE_ENDPOINT
  },
  [ILLUMINANCE_ENDPOINT] = {
    cluster = IlluminanceMeasurement.ID,
    attribute = IlluminanceMeasurement.attributes.MeasuredValue.ID,
    data_type = IlluminanceMeasurement.attributes.MeasuredValue.base_type,
    minimum_interval = 10,
    maximum_interval = 3600,
    reportable_change = 0x2711,
    endpoint = ILLUMINANCE_ENDPOINT
  }
}

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(BATTERY_MIN_VOLTAGE, BATTERY_MAX_VOLTAGE)(driver, device)

  local attribute
  if device:supports_capability_by_id(capabilities.temperatureMeasurement.ID) then
    attribute = CONFIGURATIONS[TEMPERATURE_ENDPOINT]
    device:add_configured_attribute(attribute)
  end
  if device:supports_capability_by_id(capabilities.illuminanceMeasurement.ID) then
    attribute = CONFIGURATIONS[ILLUMINANCE_ENDPOINT]
    device:add_configured_attribute(attribute)
  end
  if device:supports_capability_by_id(capabilities.tamperAlert.ID) then
    attribute = CONFIGURATIONS[TAMPER_ENDPOINT]
    device:add_configured_attribute(attribute)
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  if device:supports_capability_by_id(capabilities.tamperAlert.ID) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local function do_refresh(driver, device)
  device:send(OccupancySensing.attributes.Occupancy:read(device):to_endpoint(OCCUPANCY_ENDPOINT))
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device):to_endpoint(POWER_CONFIGURATION_ENDPOINT))

  if device:supports_capability_by_id(capabilities.temperatureMeasurement.ID) then
    device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device):to_endpoint(TEMPERATURE_ENDPOINT))
  end
  if device:supports_capability_by_id(capabilities.illuminanceMeasurement.ID) then
    device:send(IlluminanceMeasurement.attributes.MeasuredValue:read(device):to_endpoint(ILLUMINANCE_ENDPOINT))
  end
  if device:supports_capability_by_id(capabilities.tamperAlert.ID) then
    device:send(IASZone.attributes.ZoneStatus:read(device):to_endpoint(TAMPER_ENDPOINT))
  end
end


local function do_configure(driver, device)
  device:configure()
  device:send(device_management.build_bind_request(
          device,
          zcl_clusters.OccupancySensing.ID,
          driver.environment_info.hub_zigbee_eui,
          OCCUPANCY_ENDPOINT
  ))

  device:send(OccupancySensing.attributes.PIROccupiedToUnoccupiedDelay:write(device, tonumber(DEFAULT_OCCUPIED_TO_UNOCCUPIED_DELAY)):to_endpoint(OCCUPANCY_ENDPOINT))
  device:send(OccupancySensing.attributes.PIRUnoccupiedToOccupiedDelay:write(device, tonumber(DEFAULT_UNOCCUPIED_TO_OCCUPIED_DELAY)):to_endpoint(OCCUPANCY_ENDPOINT))
  device:send(OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold:write(device, tonumber(DEFAULT_UNOCCUPIED_TO_OCCUPIED_THRESHOLD)):to_endpoint(OCCUPANCY_ENDPOINT))
  device:send(OccupancySensing.attributes.Occupancy:configure_reporting(device, 0, 3600):to_endpoint(OCCUPANCY_ENDPOINT))

  device.thread:call_with_delay(5, function()
    do_refresh(driver, device)
  end)
end

local function info_changed(driver, device, event, args)
  for name, value in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      if (name == "temperatureSensitivity") then
        local input = device.preferences.temperatureSensitivity
        local temperatureSensitivity = math.floor(input * 100 + 0.5)
        device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 3600, temperatureSensitivity):to_endpoint(TEMPERATURE_ENDPOINT))
      elseif (name == "occupiedToUnoccupiedD") then
        local occupiedToUnoccupiedDelay = device.preferences.occupiedToUnoccupiedD or DEFAULT_OCCUPIED_TO_UNOCCUPIED_DELAY
        device:send(OccupancySensing.attributes.PIROccupiedToUnoccupiedDelay:write(device, occupiedToUnoccupiedDelay):to_endpoint(OCCUPANCY_ENDPOINT))
      elseif (name == "unoccupiedToOccupiedD") then
        local occupiedToUnoccupiedD = device.preferences.unoccupiedToOccupiedD or DEFAULT_UNOCCUPIED_TO_OCCUPIED_DELAY
        device:send(OccupancySensing.attributes.PIRUnoccupiedToOccupiedDelay:write(device, occupiedToUnoccupiedD):to_endpoint(OCCUPANCY_ENDPOINT))
      elseif (name == "unoccupiedToOccupiedT") then
        local unoccupiedToOccupiedThreshold = device.preferences.unoccupiedToOccupiedT or DEFAULT_UNOCCUPIED_TO_OCCUPIED_THRESHOLD
        device:send(OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold:write(device,unoccupiedToOccupiedThreshold):to_endpoint(OCCUPANCY_ENDPOINT))
      end
    end
  end
end

local frient_motion_driver = {
  NAME = "frient motion driver",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    init = device_init,
    infoChanged = info_changed
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      },
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  can_handle = can_handle_frient_motion_sensor
}
return frient_motion_driver