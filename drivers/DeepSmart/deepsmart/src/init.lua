local Driver = require('st.driver')
local caps = require('st.capabilities')
local wisers = require('deepsmart.wisers')
local log = require('log')
-- local imports
local discovery = require('discovery')
local lifecycles = require('lifecycles')
local commands = require('commands')

--------------------
-- Driver definition
local driver =
Driver(
'DEEPSMART',
{
  discovery = discovery.start,
  lifecycle_handlers = lifecycles,
  supported_capabilities = {
    caps.switch,
    caps.refresh,
    caps.airConditionerMode,
    caps.thermostatHeatingSetpoint,
    caps.airConditionerFanMode,
    caps.thermostatMode,
    caps.thermostatOperatingState
  },
  capability_handlers = {
    -- Switch command handler
    [caps.switch.ID] = {
      [caps.switch.commands.on.NAME] = commands.set_switch,
      [caps.switch.commands.off.NAME] = commands.set_switch
    },
    -- Refresh command handler
    [caps.refresh.ID] = {
      [caps.refresh.commands.refresh.NAME] = commands.refresh
    },
    [caps.airConditionerMode.ID] = {
      [caps.airConditionerMode.commands.setAirConditionerMode.NAME] = commands.set_airconditioner_mode,
    },
    [caps.airConditionerFanMode.ID] = {
      [caps.airConditionerFanMode.commands.setFanMode.NAME] = commands.set_thermostat_fan_mode,
    },
    [caps.thermostatHeatingSetpoint.ID] = {
      [caps.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = commands.set_setheatingpoint
    },
    [caps.thermostatMode.ID] = {
      [caps.thermostatMode.commands.setThermostatMode.NAME] = commands.set_thermostat_mode
    }
  }
}
)

---------------------------------------
-- Switch control for external commands
function driver:set_switch(device, on_off)
  device:online()
  if on_off == 'off' then
    return device:emit_event(caps.switch.switch.off())
  end
  return device:emit_event(caps.switch.switch.on())
end

-- Switch control for external commands
function driver:ac_report(device, onoff, mode, fan, settemp, temp, err)
  device:online()
  if (onoff ~= nil) then
    log.info('device '..device.parent_assigned_child_key..' report onoff '..onoff)
    if (onoff == "off") then
      device:emit_event(caps.switch.switch.off())
    else
      device:emit_event(caps.switch.switch.on())
    end
  end
  if (mode ~= nil) then
    log.info('device '..device.parent_assigned_child_key..' report mode '..mode)
    device:emit_event(caps.airConditionerMode.airConditionerMode(mode))
  end
  -- fan
  if (fan ~= nil) then
    log.info('device '..device.parent_assigned_child_key..' report fan '..fan)
    device:emit_event(caps.airConditionerFanMode.fanMode(fan))
  end
  -- settemp
  if (settemp ~= nil) then
    log.info('device '..device.parent_assigned_child_key..' report settemp '..settemp)
    device:emit_event(caps.thermostatHeatingSetpoint.heatingSetpoint({value=settemp,unit='C'}))
  end
  if (temp ~= nil) then
    log.info('device '..device.parent_assigned_child_key..' report temp '..temp)
    device:emit_event(caps.temperatureMeasurement.temperature({value=temp,unit='C'}))
  end
  return true,nil
end

-- Heater control from bridge
function driver:heater_report(device, onoff, settemp, temp, err)
  device:online()
  if (onoff ~= nil) then
    log.info('device '..device.parent_assigned_child_key..' report onoff '..onoff)
    if (onoff == "off") then
      device:emit_event(caps.thermostatMode.thermostatMode.off())
      device:emit_event(caps.thermostatOperatingState.thermostatOperatingState.idle())
    else
      device:emit_event(caps.thermostatMode.thermostatMode.heat())
      device:emit_event(caps.thermostatOperatingState.thermostatOperatingState.heating())
    end
  end
  -- settemp
  if (settemp ~= nil) then
    log.info('device '..device.parent_assigned_child_key..' report settemp '..settemp)
    device:emit_event(caps.thermostatHeatingSetpoint.heatingSetpoint({value=settemp,unit='C'}))
  end
  if (temp ~= nil) then
    log.info('device '..device.parent_assigned_child_key..' report temp '..temp)
    device:emit_event(caps.temperatureMeasurement.temperature({value=temp,unit='C'}))
  end
  return true,nil
end

-- global params init
wisers.driver = driver
-- start ssdp schedule to check bridge ip
driver:call_on_schedule(
600,
function ()
  return wisers.check_ip(discovery)
end,
'Check ip schedule')
--------------------
-- Initialize Driver
driver:run()
