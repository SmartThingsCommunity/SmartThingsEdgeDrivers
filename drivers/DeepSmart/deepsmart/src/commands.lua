local caps = require('st.capabilities')
local log = require('log')

local config = require('config')
local wisers = require('deepsmart.wisers')

local command_handler = {}

------------------
-- Refresh command
function command_handler.refresh(_, device)
  local bridge_id = device.device_network_id
  local parent_assigned_child_key = device.parent_assigned_child_key
  local success = false
  local is_bridge = wisers.is_device_bridge(device)
  log.info('refresh bridge '..bridge_id..' device')
  if (not is_bridge) then
    success = wisers.refresh(device)
    log.info('hub refresh device '..parent_assigned_child_key)
  else
    -- reload wiser devices
    wisers.refresh_wiser(bridge_id)
    log.info('hub refresh device '..bridge_id)
  end
  -- Check success
  if success then
    -- Define online status
    device:online()
  else
    log.error('failed to poll device state')
    -- Set device as offline
    device:offline()
  end
end

----------------
-- Switch command
----------------
function command_handler.set_switch(_, device, command)
  local on_off = command.command
  log.info('hub control device '..device.parent_assigned_child_key..' onoff '..on_off)
  -- gt devtype
  local devtype = wisers.get_dev_type(device)
  local addrtypes = {}
  -- get devtype onoff addrtype
  if (devtype == config.ENUM.AC or devtype == config.ENUM.HEATER or devtype == config.ENUM.NEWFAN) then
    addrtypes[1] = config.DEVICE.ONOFF
  else
    addrtypes[1] = 0
  end
  -- send command
  local success = wisers.control(device, command, addrtypes)
  -- Check if success
  if success then
    if on_off == 'off' then
      return device:emit_event(caps.switch.switch.off())
    end
    return device:emit_event(caps.switch.switch.on())
  end
  log.error('no response from device')
  return 0
end

----------------
-- fan mode command
----------------
function command_handler.set_thermostat_fan_mode(driver, device, command)
  local devtype = wisers.get_dev_type(device)
  local addrtypes = {}
  if (devtype == config.ENUM.AC) then
    addrtypes[1] = config.AC.FAN
  elseif devtype == config.ENUM.NEWFAN then
    addrtypes[1] = config.NEWFAN.FAN
  end
  local success = wisers.control(device, command, addrtypes)
  -- Check if success
  if success then
    return device:emit_event(caps.airConditionerFanMode.fanMode(command.args.fanMode))
  end
  log.error('no response from device')
  return 0
end

----------------
-- mode command
----------------
function command_handler.set_airconditioner_mode(driver, device, command)
  local success = wisers.control(device, command, {config.AC.MODE})
  -- Check if success
  if success then
    return device:emit_event(caps.airConditionerMode.airConditionerMode(command.args.mode))
  end
  log.error('no response from device')
end

----------------
-- heater mode command
----------------
function command_handler.set_thermostat_mode(driver, device, command)
  -- send command
  local success = wisers.control(device, command, {config.HEATER.ONOFF})
  -- Check if success
  if success then
    if command.args.mode == 'off' then
      device:emit_event(caps.thermostatMode.thermostatMode.off())
      device:emit_event(caps.thermostatOperatingState.thermostatOperatingState.idle())
    else
      device:emit_event(caps.thermostatMode.thermostatMode.heat())
      device:emit_event(caps.thermostatOperatingState.thermostatOperatingState.heating())
    end
    return
  end
  log.error('no response from device')
  return 0
end

----------------
-- set heating point command
----------------
function command_handler.set_setheatingpoint(driver, device, command)
  local devtype = wisers.get_dev_type(device)
  local addrtypes = {}
  if (devtype == config.ENUM.AC) then
    addrtypes[1] = config.AC.SETTEMP
  elseif devtype == config.ENUM.HEATER then
    addrtypes[1] = config.HEATER.SETTEMP
  end
  local success = wisers.control(device, command, addrtypes)
  -- Check if success
  if success then
    return device:emit_event(caps.thermostatHeatingSetpoint.heatingSetpoint({value=command.args.setpoint,unit='C'}))
  end
  log.error('no response from device')
end


return command_handler
