local config = require('config')
local log = require('log')
local caps = require('st.capabilities')
local wisers = require('deepsmart.wisers')
local lifecycle_handler = {}

function lifecycle_handler.init(driver, device)
  -- report test data
  --wisers.default_report(driver, device)
  local is_bridge = wisers.is_device_bridge(device)
  log.info('device '..device.id..' in init')
  -- for bridge do not reload devices&&config
  -- just use the devices&&config loaded from wiser's datastore
  -- only discover or refresh bridge will reload devices&&config
  if (is_bridge) then
    -- just add wiser(bridge) to wisers
    wisers.add_wiser(device.device_network_id, device:get_field(config.FIELD.IP), device)
    -- load devices
    wisers.refresh_wiser(device.device_network_id)
  else
    log.debug('save dev '..device.id..' networkid '..device.parent_assigned_child_key)
    wisers.idmap[device.parent_assigned_child_key] = device.id
    local devtype = wisers.get_dev_type(device)
    if (devtype == config.ENUM.AC) then
      local supported_modes = {'heat','cool','dry','fan','auto'}
      device:emit_event(caps.airConditionerMode.supportedAcModes(supported_modes, { visibility = { displayed = false } }))
      local supported_fan_modes = {'low','medium','high','auto'}
      device:emit_event(caps.airConditionerFanMode.supportedAcFanModes(supported_fan_modes, { visibility = { displayed = false } }))
    elseif devtype == config.ENUM.NEWFAN then
      local supported_fan_modes = {'low','medium','high','auto'}
      device:emit_event(caps.airConditionerFanMode.supportedAcFanModes(supported_fan_modes, { visibility = { displayed = false } }))
    elseif devtype == config.ENUM.HEATER then
      local supported_thermostat_modes = {'heat', 'off'}
      device:emit_event(caps.thermostatMode.supportedThermostatModes(supported_thermostat_modes, { visibility = { displayed = false } }))
    end
    -------------------
    log.info('device '..device.parent_assigned_child_key..' in lifecycle init')
  end
end

function lifecycle_handler.added(driver, device)
  log.info('device '..device.id..' added')
  if (device.parent_assigned_child_key == nil) then
    log.info('bridge device '..device.id..' added')
    local ip = wisers.ips[device.device_network_id]
    -- for bridge save some infos to bridge device
    device:set_field(config.FIELD.IP, ip, { persist = true})
    wisers.add_wiser(device.device_network_id, ip, device)
    log.info('bridge device '..device.id..' added over')
    return 0
  end
  log.debug('save dev '..device.id..' networkid '..device.parent_assigned_child_key)
  local devtype = wisers.get_dev_type(device)
  -- save device info
  wisers.idmap[device.parent_assigned_child_key] = device.id
  -- find device type
  log.info('device '..device.parent_assigned_child_key..' added devtype '..devtype)
  if (devtype == config.ENUM.AC) then
    local supported_modes = {'heat','cool','dry','fan','auto'}
    device:emit_event(caps.airConditionerMode.supportedAcModes(supported_modes, { visibility = { displayed = false } }))
    local supported_fan_modes = {'low','medium','high','auto'}
    device:emit_event(caps.airConditionerFanMode.supportedAcFanModes(supported_fan_modes, { visibility = { displayed = false } }))
  elseif devtype == config.ENUM.NEWFAN then
    local supported_fan_modes = {'low','medium','high','auto'}
    device:emit_event(caps.airConditionerFanMode.supportedAcFanModes(supported_fan_modes, { visibility = { displayed = false } }))
  elseif devtype == config.ENUM.HEATER then
    local supported_thermostat_modes = {'heat', 'off'}
    device:emit_event(caps.thermostatMode.supportedThermostatModes(supported_thermostat_modes, { visibility = { displayed = false } }))
  end
  log.info('edge device '..device.parent_assigned_child_key..' added over')
  -- do not refresh
  -- wiser loop will refresh all devices
end

function lifecycle_handler.removed(_, device)
  -- Notify device that the device
  -- instance has been deleted and
  -- parent node must be deleted at
  -- device app.
  wisers.del_device(device)
  -- Remove Schedules created under
  -- device.thread to avoid unnecessary
  -- CPU processing.
  for timer in pairs(device.thread.timers) do
    device.thread:cancel_timer(timer)
  end
end

return lifecycle_handler
