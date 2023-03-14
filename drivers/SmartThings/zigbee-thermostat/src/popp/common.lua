local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"

local last_setpointTemp = nil

local ThermostatMode = capabilities.thermostatMode
local TemperatureAlarm = capabilities.temperatureAlarm
local Switch = capabilities.switch

local log = require 'log'

local common = {}

common.MIN_SETPOINT = 5
common.MAX_SETPOINT = 30
common.STORED_HEAT_MODE = "stored_heat_mode"

common.THERMOSTAT_CLUSTER_ID = 0x0201
common.MFG_CODE = 0x1246
common.WINDOW_OPEN_FEATURE = nil

common.THERMOSTAT_SETPOINT_CMD_ID = 0x40
common.WINDOW_OPEN_DETECTION_ID = 0x4000
common.WINDOW_OPEN_DETECTION_MAP = {
  [0x00] = "cleared", -- // "quarantine" default
  [0x01] = "cleared", -- // "closed" window is closed
  [0x02] = "freeze", -- // "hold" window might be opened
  [0x03] = "freeze", -- // "opened" window is opened
  [0x04] = "freeze", -- // "opened_alarm" a closed window was opened externally (=alert)
}
common.EXTERNAL_OPEN_WINDOW_DETECTION_ID = 0x4003

local SUPPORTED_MODES = {
  ThermostatMode.thermostatMode.off.NAME,
  ThermostatMode.thermostatMode.heat.NAME,
  ThermostatMode.thermostatMode.eco.NAME
}

common.STORED_HEAT_MODE = "stored_heat_mode"

local function has_member(haystack, needle)
  for _, value in ipairs(haystack) do
    if (value == needle) then
      return true
    end
  end

  return false
end

--- Default handler for lock state attribute on the door lock cluster
---
--- This converts the lock state value to the appropriate value
---
--- @param driver Driver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param value LockState the value of the door lock cluster lock state attribute
--- @param zb_rx st.zigbee.ZigbeeMessageRx the full message this report came in
common.window_open_detection_handler = function(driver, device, value, zb_rx)
  device:emit_event(TemperatureAlarm.temperatureAlarm(common.WINDOW_OPEN_DETECTION_MAP[value.value]))
end

common.switch_handle_on = function(driver, device, cmd)
  local get_cmd = cmd.command or cmd

  if get_cmd == "on" then
    device:send(cluster_base.write_manufacturer_specific_attribute(device, common.THERMOSTAT_CLUSTER_ID,
      common.EXTERNAL_OPEN_WINDOW_DETECTION_ID,
      common.MFG_CODE, data_types.Boolean, false))
    --device:emit_event(Switch.switch.on())
  end
end

common.switch_handle_off = function(driver, device, cmd)
  local get_cmd = cmd.command or cmd

  if get_cmd == "off" then
    --device:send(cluster_base.build_manufacturer_specific_command(device, common.THERMOSTAT_CLUSTER_ID, common.EXTERNAL_OPEN_WINDOW_DETECTION_ID, common.MFG_CODE, '\x01'))
    device:send(cluster_base.write_manufacturer_specific_attribute(device, common.THERMOSTAT_CLUSTER_ID,
      common.EXTERNAL_OPEN_WINDOW_DETECTION_ID,
      common.MFG_CODE, data_types.Boolean, true))
    --device:emit_event(Switch.switch.off())
  end
end

--- Default handler for lock state attribute on the door lock cluster
---
--- This converts the lock state value to the appropriate value
---
--- @param driver Driver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param command LockState the value of the door lock cluster lock state attribute
common.heat_cmd_handler = function(driver, device, mode)
  local payload = nil

  if has_member(SUPPORTED_MODES, mode) then

    -- fetch last_setpointTemp
    last_setpointTemp = device:get_field("last_setpointTemp")

    if last_setpointTemp == nil then
      last_setpointTemp = device:get_latest_state("main", capabilities.thermostatHeatingSetpoint.ID, capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME) or 21
    end

    last_setpointTemp = math.floor(last_setpointTemp * 100) -- prepare for correct 4 char dec format

    -- convert setpoint value into bytes e.g. 25.5 -> 2550 -> \x09\xF6 -> \xF6\x09
    local s = string.format("%04X", tostring(last_setpointTemp))
    local p2 = tonumber(string.sub(s, 3, 4), 16)
    local p3 = tonumber(string.sub(s, 1, 2), 16)

    if mode == ThermostatMode.thermostatMode.heat.NAME then

      local t1 = 0x01 -- Setpoint type "1": the actuator will make a large movement to minimize reaction time to UI
      -- build the payload as byte array e.g. for 25.5 -> "\x01\xF6\x09"
      payload = string.char(t1, p2, p3)
      -- send the specific command as ZigbeeMessageTx to the device
      device:send(cluster_base.build_manufacturer_specific_command(device, common.THERMOSTAT_CLUSTER_ID, common.THERMOSTAT_SETPOINT_CMD_ID, common.MFG_CODE, payload))

      log.debug("### switch state heat:" .. device:get_latest_state("main", Switch.ID, Switch.switch.NAME))
      -- turn switch on
      if device:get_latest_state("main", Switch.ID, Switch.switch.NAME) == "off" then
        common.switch_handle_on(driver, device, 'on')
      end

    elseif mode == ThermostatMode.thermostatMode.eco.NAME then
      local t2 = 0x00 -- Setpoint type "0": the behavior will be the same as setting the attribute "Occupied Heating Setpoint" to the same value
      -- build the payload as byte array
      payload = string.char(t2, p2, p3)
      -- send the specific command as ZigbeeMessageTx to the device
      device:send(cluster_base.build_manufacturer_specific_command(device, common.THERMOSTAT_CLUSTER_ID, common.THERMOSTAT_SETPOINT_CMD_ID, common.MFG_CODE, payload))

      log.debug("### switch state eco:" .. device:get_latest_state("main", Switch.ID, Switch.switch.NAME))
      -- turn switch on
      if device:get_latest_state("main", Switch.ID, Switch.switch.NAME) == "off" then
        common.switch_handle_on(driver, device, 'on')
      end
    end

    -- turn switch on
    --[[ if device:get_latest_state("main", Switch.ID, Switch.switch.NAME) == "off" then
      common.switch_handle_on(driver, device, 'on')
    end ]]

    device:set_field(common.STORED_HEAT_MODE, mode)
    device:emit_event(ThermostatMode.thermostatMode[mode]())

  else
    -- Generate something for the mobile client if it is calling us
    device:emit_event(ThermostatMode.thermostatMode(device:get_latest_state("main", ThermostatMode.ID,
      ThermostatMode.thermostatMode.NAME)))
  end
end

return common
