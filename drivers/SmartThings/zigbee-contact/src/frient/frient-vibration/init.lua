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
local zcl_clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local device_management = require "st.zigbee.device_management"
local data_types = require "st.zigbee.data_types"
local log = require "log"
local util = require "st.utils"
local threeAxis = capabilities.threeAxis

local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement
local IASZone = zcl_clusters.IASZone
local PowerConfiguration = zcl_clusters.PowerConfiguration
local POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT = 0x2D
local TEMPERATURE_ENDPOINT = 0x26

local FRIENT_DEVICE_FINGERPRINTS = {
  { mfr = "frient A/S", model = "WISZB-137", },
}

local function can_handle_vibration_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(FRIENT_DEVICE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local Frient_AccelerationMeasurementCluster = {
  ID = 0xFC04,
  ManufacturerSpecificCode = 0x1015,
  attributes = {
    MeasuredValueX = { ID = 0x0000, data_type = data_types.name_to_id_map["Int16"] },
    MeasuredValueY = { ID = 0x0001, data_type = data_types.name_to_id_map["Int16"] },
    MeasuredValueZ = { ID = 0x0002, data_type = data_types.name_to_id_map["Int16"] }
  },
}

local function acceleration_measure_value_attr_handler(driver, device, attr_val, zb_rx)
  -- Initialize variables to store the axis values
  local measured_x = device:get_field("measured_x")
  local measured_y = device:get_field("measured_y")
  local measured_z = device:get_field("measured_z")

  -- Process the attribute records
  for _, attribute_record in ipairs(zb_rx.body.zcl_body.attr_records) do
    local attribute_id = attribute_record.attr_id.value
    local axis_value = attribute_record.data.value

    if attribute_id == 0x0000 then
      measured_x = axis_value
      device:set_field("measured_x", measured_x)
      log.trace("Updated X value: " .. axis_value)
    elseif attribute_id == 0x0001 then
      measured_y = axis_value
      device:set_field("measured_y", measured_y)
      log.trace("Updated Y value: " .. axis_value)
    elseif attribute_id == 0x0002 then
      measured_z = axis_value
      device:set_field("measured_z", measured_z)
      log.trace("Updated Z value: " .. axis_value)
    else
      log.warn("Unknown AttributeId: " .. tostring(attribute_id))
    end
  end

  -- Ensure all values are non-nil before emitting
  if measured_x and measured_y and measured_z then
    device:emit_event(threeAxis.threeAxis({measured_x, measured_y, measured_z}))
  end

  if device.supports_capability(capabilities.contactSensor) then
    if measured_z < -900 then
        device:emit_event(capabilities.contactSensor.contact.open())
    elseif measured_z >= -100 then
        device:emit_event(capabilities.contactSensor.contact.closed())
    end
  end
end

local function get_cluster_configurations()
  return {
      {
          cluster = Frient_AccelerationMeasurementCluster.ID,
          attribute = Frient_AccelerationMeasurementCluster.attributes.MeasuredValueX.ID,
          minimum_interval = 0,
          maximum_interval = 300,
          reportable_change = 0x0001,
          data_type = data_types.Int16,
          mfg_code = Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
      },
      {
          cluster = Frient_AccelerationMeasurementCluster.ID,
          attribute = Frient_AccelerationMeasurementCluster.attributes.MeasuredValueY.ID,
          minimum_interval = 0,
          maximum_interval = 300,
          reportable_change = 0x0001,
          data_type = data_types.Int16,
          mfg_code = Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
      },
      {
          cluster = Frient_AccelerationMeasurementCluster.ID,
          attribute = Frient_AccelerationMeasurementCluster.attributes.MeasuredValueZ.ID,
          minimum_interval = 0,
          maximum_interval = 300,
          reportable_change = 0x0001,
          data_type = data_types.Int16,
          mfg_code = Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode
      }
  }
end

local function generate_event_from_zone_status(driver, device, zone_status, zb_rx)
  device:emit_event(zone_status:is_alarm1_set() and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
  device:emit_event(zone_status:is_alarm2_set() and capabilities.accelerationSensor.acceleration.active() or capabilities.accelerationSensor.acceleration.inactive())
end

local function ias_zone_status_attr_handler(driver, device, attr_val, zb_rx)
  log.debug("Received IAS Zone Status:"..util.stringify_table(attr_val))
  generate_event_from_zone_status(driver, device, attr_val, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  log.debug( "Received IAS Zone Change:"..util.stringify_table(zb_rx.body.zcl_body.zone_status))
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local function device_init(driver, device)
    log.trace "Initializing sensor"
    battery_defaults.build_linear_voltage_init(2.3, 3.0)(driver, device)
    --Add the manufacturer-specific attributes to generate their configure reporting and bind requests
    for _, config in pairs(get_cluster_configurations()) do
        device:add_configured_attribute(config)
    end
end

local function do_refresh(driver, device)
    log.trace "Refreshing vibration sensor attributes"
    device:send(IASZone.attributes.ZoneStatus:read(device):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT))
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Frient_AccelerationMeasurementCluster.ID, Frient_AccelerationMeasurementCluster.attributes.MeasuredValueX.ID, Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT))
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Frient_AccelerationMeasurementCluster.ID, Frient_AccelerationMeasurementCluster.attributes.MeasuredValueY.ID, Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT))
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Frient_AccelerationMeasurementCluster.ID, Frient_AccelerationMeasurementCluster.attributes.MeasuredValueZ.ID, Frient_AccelerationMeasurementCluster.ManufacturerSpecificCode):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT))
    device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device):to_endpoint(TEMPERATURE_ENDPOINT))
    device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
end

local function do_configure(driver, device, event, args)
    log.trace("Configuring sensor:" .. event)
    device:configure()

    device:send(device_management.build_bind_request(device, zcl_clusters.IASZone.ID, driver.environment_info.hub_zigbee_eui, POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT))
    device:send(IASZone.attributes.ZoneStatus:configure_reporting(device, 0, 1*60*60, 1):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT))
    device:send(device_management.build_bind_request(device, Frient_AccelerationMeasurementCluster.ID, driver.environment_info.hub_zigbee_eui, POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT))

    local sensitivityLevel = device.preferences.sensitivityLevel or 10
    log.debug("Writing CurrentZoneSensitivityLevel attribute to: " .. sensitivityLevel)
    device:send(IASZone.attributes.CurrentZoneSensitivityLevel:write(device, sensitivityLevel):to_endpoint(POWER_CONFIGURATION_AND_ACCELERATION_ENDPOINT))

    local sensitivity = math.floor((device.preferences.temperatureSensitivity or 0.1) * 100 + 0.5)
    log.debug("Configuring temperature sensitivity: " .. sensitivity)
    device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 1 * 60 * 60, sensitivity):to_endpoint(TEMPERATURE_ENDPOINT))

    device.thread:call_with_delay(5, function()
        device:refresh()
    end)
end

local function info_changed(driver, device, event, args)
  if args and args.old_st_store then
    if args.old_st_store.preferences.sensitivityLevel ~= device.preferences.sensitivityLevel then
      local sensitivityLevel = device.preferences.sensitivityLevel or 10
      log.debug("Writing Current Zone Sensitivity Level Attribute To: "..sensitivityLevel)
      device:send(IASZone.attributes.CurrentZoneSensitivityLevel:write(device, sensitivityLevel):to_endpoint(0x2D))
    end
    if args.old_st_store.preferences.temperatureSensitivity ~= device.preferences.temperatureSensitivity then
      local sensitivity = math.floor((device.preferences.temperatureSensitivity or 0.1)*100 + 0.5)
      log.debug("Configuring temperature sensitivity: "..sensitivity)
      device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 1*60*60, sensitivity):to_endpoint(0x26))
    end
    if args.old_st_store.preferences.garageSensor ~= device.preferences.garageSensor then
      if device.preferences.garageSensor == "Yes" then
        device:try_update_metadata({profile = "acceleration-motion-temperature-contact-battery"})
      elseif device.preferences.garageSensor == "No" then
        device:try_update_metadata({profile = "acceleration-motion-temperature-battery"})
      end
    end
    device.thread:call_with_delay(5, function()
      device:refresh()
    end)
  end
end

local frient_vibration_driver_template = {
  NAME = "frient vibration driver",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      },
      [Frient_AccelerationMeasurementCluster.ID] = {
        [Frient_AccelerationMeasurementCluster.attributes.MeasuredValueX.ID] = acceleration_measure_value_attr_handler,
        [Frient_AccelerationMeasurementCluster.attributes.MeasuredValueY.ID] = acceleration_measure_value_attr_handler,
        [Frient_AccelerationMeasurementCluster.attributes.MeasuredValueZ.ID] = acceleration_measure_value_attr_handler,
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = can_handle_vibration_sensor
}

return frient_vibration_driver_template