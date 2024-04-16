local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local data_types = require "st.zigbee.data_types"
local aqara_utils = require "aqara/aqara_utils"

local OccupancySensing = clusters.OccupancySensing

local detectionFrequency = capabilities["stse.detectionFrequency"]
local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
local sensitivityAdjustmentCommandName = "setSensitivityAdjustment"

local MOTION_ILLUMINANCE_ATTRIBUTE_ID = 0x0112
local SENSITIVITY_ATTRIBUTE_ID = 0x010C

local PREF_SENSITIVITY_KEY = "prefSensitivity"
local PREF_SENSITIVITY_VALUE_HIGH = 3
local PREF_SENSITIVITY_VALUE_MEDIUM = 2
local PREF_SENSITIVITY_VALUE_LOW = 1

local function send_sensitivity_adjustment_value(device, value)
  -- store key
  aqara_utils.set_pref_changed_field(device, PREF_SENSITIVITY_KEY, value)
  -- write
  device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    SENSITIVITY_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.Uint8, value))
end

local function motion_illuminance_attr_handler(driver, device, value, zb_rx)
  -- not implemented
end

local function write_attr_res_handler(driver, device, zb_rx)
  local key, value = aqara_utils.get_pref_changed_field(device)
  if key == aqara_utils.PREF_FREQUENCY_KEY then
    -- detection frequency

    -- reset key
    aqara_utils.set_pref_changed_field(device, '', 0)

    -- for unoccupied timer
    device:set_field(aqara_utils.PREF_FREQUENCY_KEY, value, { persist = true })
    -- update ui
    device:emit_event(detectionFrequency.detectionFrequency(value, {visibility = {displayed = false}}))
  elseif key == PREF_SENSITIVITY_KEY then
    -- sensitivity adjustment

    -- reset key
    aqara_utils.set_pref_changed_field(device, '', 0)

    -- update ui
    if value == PREF_SENSITIVITY_VALUE_HIGH then
      device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
    elseif value == PREF_SENSITIVITY_VALUE_MEDIUM then
      device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Medium())
    elseif value == PREF_SENSITIVITY_VALUE_LOW then
      device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Low())
    end
  end
end

local function occupancy_attr_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    aqara_utils.motion_detected(device)
  end
end

local function sensitivity_adjustment_capability_handler(driver, device, command)
  local sensitivity = command.args.sensitivity
  if sensitivity == 'High' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_HIGH)
  elseif sensitivity == 'Medium' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_MEDIUM)
  elseif sensitivity == 'Low' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_LOW)
  end
end

local function added_handler(self, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:emit_event(detectionFrequency.detectionFrequency(aqara_utils.PREF_FREQUENCY_VALUE_DEFAULT, {visibility = {displayed = false}}))
  device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Medium())
  device:emit_event(capabilities.battery.battery(100))
end

local function do_configure(self, device)
  device:configure()
  device:send(cluster_base.write_manufacturer_specific_attribute(device, aqara_utils.PRIVATE_CLUSTER_ID,
    aqara_utils.PRIVATE_ATTRIBUTE_ID,
    aqara_utils.MFG_CODE, data_types.Uint8, 1))
end

local aqara_high_precision_motion_handler = {
  NAME = "Aqara High Precision Motion Handler",
  lifecycle_handlers = {
    added = added_handler,
    doConfigure = do_configure
  },
  capability_handlers = {
    [sensitivityAdjustment.ID] = {
      [sensitivityAdjustmentCommandName] = sensitivity_adjustment_capability_handler,
    }
  },
  zigbee_handlers = {
    global = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [zcl_commands.WriteAttributeResponse.ID] = write_attr_res_handler
      }
    },
    attr = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [MOTION_ILLUMINANCE_ATTRIBUTE_ID] = motion_illuminance_attr_handler
      },
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "lumi.motion.agl04"
  end
}

return aqara_high_precision_motion_handler
