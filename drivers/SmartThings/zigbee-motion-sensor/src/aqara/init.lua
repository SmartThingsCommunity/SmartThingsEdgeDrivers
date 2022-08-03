local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
local detectionFrequency = capabilities["stse.detectionFrequency"]
local sensitivityAdjustmentId = "stse.sensitivityAdjustment"
local detectionFrequencyId = "stse.detectionFrequency"
local sensitivityAdjustmentCommand = "setSensitivityAdjustment"
local detectionFrequencyCommand = "setDetectionFrequency"

local PowerConfiguration = clusters.PowerConfiguration
local OccupancySensing = clusters.OccupancySensing

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local MOTION_TEMP_ATTRIBUTE_ID = 0x0112
local FREQUENCY_ATTRIBUTE_ID = 0x0102
local SENSITIVITY_ATTRIBUTE_ID = 0x010C
local FREQUENCY_DEFAULT_VALUE = 120
local UNOCCUPIED_TIMER = "unoccupiedTimer"
local FREQUENCY_PREF = "frequencyPref"
local SENSITIVITY_HIGH = 3
local SENSITIVITY_MEDIUM = 2
local SENSITIVITY_LOW = 1
local OCCUPANCY_OCCUPIED = 1

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.motion.agl02" },
  { mfr = "LUMI", model = "lumi.motion.agl04" }
}

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local write_motion_pref_attribute = function(device, cluster, attr, value)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, cluster, attr, MFG_CODE,
    data_types.Uint8, value))
end

local function added_handler(self, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Medium())
  device:emit_event(detectionFrequency.detectionFrequency(FREQUENCY_DEFAULT_VALUE))
  device:emit_event(capabilities.battery.battery(100))
end

local do_configure = function(self, device)
  device:configure()

  device:send(device_management.build_bind_request(device, OccupancySensing.ID, self.environment_info.hub_zigbee_eui))
  device:send(OccupancySensing.attributes.Occupancy:configure_reporting(device, 30, 3600))

  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 3600, 1))

  device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID,
    MFG_CODE, data_types.Uint8, 1))
end

local function motion_active_handler(driver, device, value, zb_rx)
  device:emit_event(capabilities.motionSensor.motion.active())

  local unoccupied_timer = device:get_field(UNOCCUPIED_TIMER)
  if unoccupied_timer then
    device.thread:cancel_timer(unoccupied_timer)
    device:set_field(UNOCCUPIED_TIMER, nil)
  end
  local detect_duration = device:get_field(FREQUENCY_PREF) or FREQUENCY_DEFAULT_VALUE
  local inactive_state = function()
    device:emit_event(capabilities.motionSensor.motion.inactive())
  end
  unoccupied_timer = device.thread:call_with_delay(detect_duration, inactive_state)
  device:set_field(UNOCCUPIED_TIMER, unoccupied_timer)
end

local function attr_handler(driver, device, value, zb_rx)
  -- The low 16 bits for Illuminance
  -- The high 16 bits for Motion Detection
  if value.value > 65536 then
    -- active
    local lux = value.value - 65536
    device:emit_event(capabilities.illuminanceMeasurement.illuminance(lux))

    motion_active_handler(driver, device, value, zb_rx)
  end
end

local function occupancy_attr_handler(driver, device, value, zb_rx)
  if value.value == OCCUPANCY_OCCUPIED then
    motion_active_handler(driver, device, value, zb_rx)
  end
end

local function sensitivity_adjustment_handler(driver, device, command)
  local sensitivity = command.args.sensitivity
  if sensitivity == 'High' then
    write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID, SENSITIVITY_HIGH)
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
  elseif sensitivity == 'Medium' then
    write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID, SENSITIVITY_MEDIUM)
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Medium())
  elseif sensitivity == 'Low' then
    write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, SENSITIVITY_ATTRIBUTE_ID, SENSITIVITY_LOW)
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Low())
  end
end

local function detection_frequency_handler(driver, device, command)
  local prefValue = command.args.frequency
  write_motion_pref_attribute(device, PRIVATE_CLUSTER_ID, FREQUENCY_ATTRIBUTE_ID, prefValue)
  device:emit_event(detectionFrequency.detectionFrequency(prefValue))
  device:set_field(FREQUENCY_PREF, prefValue)
end

local aqara_motion_handler = {
  NAME = "Aqara Motion Handler",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.6, 3.0),
    added = added_handler,
    doConfigure = do_configure
  },
  capability_handlers = {
    [sensitivityAdjustmentId] = {
      [sensitivityAdjustmentCommand] = sensitivity_adjustment_handler,
    },
    [detectionFrequencyId] = {
      [detectionFrequencyCommand] = detection_frequency_handler,
    }
  },
  zigbee_handlers = {
    attr = {
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      },
      [PRIVATE_CLUSTER_ID] = {
        [MOTION_TEMP_ATTRIBUTE_ID] = attr_handler,
      }
    }
  },
  can_handle = is_aqara_products
}

return aqara_motion_handler
