local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"

local cluster_base = require "st.zigbee.cluster_base"

-- Zigbee specific utils
local clusters = require "st.zigbee.zcl.clusters"
local ThermostatUIConfig = clusters.ThermostatUserInterfaceConfiguration

local last_setpointTemp = nil

local WindowOpenDetectionCap = capabilities["preparestream40760.windowOpenDetection"]
local HeatingMode = capabilities["preparestream40760.heatMode"]

local common = {}

common.THERMOSTAT_CLUSTER_ID = 0x0201
common.MFG_CODE = 0x1246
common.WINDOW_OPEN_FEATURE = nil

common.THERMOSTAT_SETPOINT_CMD_ID = 0x40
common.WINDOW_OPEN_DETECTION_ID = 0x4000
common.WINDOW_OPEN_DETECTION_MAP = {
  [0x00] = "quarantine", -- // default
  [0x01] = "closed", -- // window is closed
  [0x02] = "hold", -- // window might be opened
  [0x03] = "opened", -- // window is opened
  [0x04] = "opened_alarm", -- // a closed window was opened externally (=alert)
}

-- Preference variables
common.KEYPAD_LOCK = "keypadLock"
common.VIEWING_DIRECTION = "viewingDirection"
common.ETRV_ORIENTATION = "eTRVOrientation"
common.REGUALTION_SETPOINT_OFFSET = "regulationSetPointOffset"
common.WINDOW_OPEN_FEATURE = "windowOpenFeature"
common.VIEWING_DIRECTION_ATTR = 0x4000
common.ETRV_ORIENTATION_ATTR = 0x4014
common.REGULATION_SETPOINT_OFFSET_ATTR = 0x404B
common.WINDOW_OPEN_FEATURE_ATTR = 0x4051
common.ETRV_WINDOW_OPEN_DETECTION_ATTR = 0x4000

-- preference table
common.PREFERENCE_TABLES = {
  keypadLock = {
    clusterId = ThermostatUIConfig.ID,
    attributeId = ThermostatUIConfig.attributes.KeypadLockout.ID,
    dataType = data_types.Enum8
  },
  viewingDirection = {
    clusterId = ThermostatUIConfig.ID,
    attributeId = common.VIEWING_DIRECTION_ATTR,
    dataType = data_types.Enum8
  },
  eTRVOrientation = {
    clusterId = common.THERMOSTAT_CLUSTER_ID,
    attributeId = common.ETRV_ORIENTATION_ATTR,
    dataType = data_types.Boolean
  },
  regulationSetPointOffset = {
    clusterId = common.THERMOSTAT_CLUSTER_ID,
    attributeId = common.REGULATION_SETPOINT_OFFSET_ATTR,
    dataType = data_types.Int8
  },
  windowOpenFeature = {
    clusterId = common.THERMOSTAT_CLUSTER_ID,
    attributeId = common.WINDOW_OPEN_FEATURE_ATTR,
    dataType = data_types.Boolean
  }
}

--- Default handler for lock state attribute on the door lock cluster
---
--- This converts the lock state value to the appropriate value
---
--- @param driver Driver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param value LockState the value of the door lock cluster lock state attribute
--- @param zb_rx st.zigbee.ZigbeeMessageRx the full message this report came in
common.window_open_detection_handler = function(driver, device, value, zb_rx)
  device:emit_event(WindowOpenDetectionCap.windowOpenDetection(common.WINDOW_OPEN_DETECTION_MAP[value.value]))
end

--- Default handler for lock state attribute on the door lock cluster
---
--- This converts the lock state value to the appropriate value
---
--- @param driver Driver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param command LockState the value of the door lock cluster lock state attribute
common.heat_cmd_handler = function(driver, device, command)
  local payload = nil

  -- fetch last_setpointTemp
  last_setpointTemp = device:get_field("last_setpointTemp")

  if last_setpointTemp == nil then
    last_setpointTemp = device:get_latest_state("main", capabilities.thermostatHeatingSetpoint.ID,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME)
  end

  if last_setpointTemp == nil then
    last_setpointTemp = 21
  end

  last_setpointTemp = math.floor(last_setpointTemp * 100) -- prepare for correct 4 char dec format

  -- convert setpoint value into bytes e.g. 25.5 -> 2550 -> \x09\xF6 -> \xF6\x09
  local s = string.format("%04X", tostring(last_setpointTemp))
  local p2 = tonumber(string.sub(s, 3, 4), 16)
  local p3 = tonumber(string.sub(s, 1, 2), 16)

  if command.args.mode == "fast" then

    local t1 = 0x01 -- Setpoint type "1": the actuator will make a large movement to minimize reaction time to UI
    -- build the payload as byte array e.g. for 25.5 -> "\x01\xF6\x09"
    payload = string.char(t1, p2, p3)
    -- send the specific command as ZigbeeMessageTx to the device
    device:send(cluster_base.build_manufacturer_specific_command(device, common.THERMOSTAT_CLUSTER_ID,
      common.THERMOSTAT_SETPOINT_CMD_ID, common.MFG_CODE, payload))
    -- emit new capability state "fast"
    device:emit_event(HeatingMode.setpointMode.fast())

  elseif command.args.mode == "eco" then

    local t2 = 0x00 -- Setpoint type "0": the behavior will be the same as setting the attribute "Occupied Heating Setpoint" to the same value
    -- build the payload as byte array
    payload = string.char(t2, p2, p3)
    -- send the specific command as ZigbeeMessageTx to the device
    device:send(cluster_base.build_manufacturer_specific_command(device, common.THERMOSTAT_CLUSTER_ID,
      common.THERMOSTAT_SETPOINT_CMD_ID, common.MFG_CODE, payload))
    -- emit new capability state "eco"
    device:emit_event(HeatingMode.setpointMode.eco())
  end
end

function common.get_cluster_configurations()
  return {
    [WindowOpenDetectionCap.ID] = {
      {
        cluster = common.THERMOSTAT_CLUSTER_ID,
        attribute = common.WINDOW_OPEN_DETECTION_ID,
        minimum_interval = 60,
        maximum_interval = 43200,
        reportable_change = 0x00,
        data_type = data_types.Enum8,
        mfg_code = common.MFG_CODE
      }
    }
  }
end

return common
