local commands = require('commands')
local config = require('config')
local log = require('log')
local cosock = require "cosock"
local caps = require('st.capabilities')
local wisers = require('deepsmart.wisers')
local lifecycle_handler = {}

function lifecycle_handler.init(driver, device)
  -- report test data
  --wisers.default_report(driver, device)
  log.info('device '..device.id..' init')
  if (device.parent_assigned_child_key ~= nil) then
    log.debug('save dev '..device.id..' networkid '..device.parent_assigned_child_key)
    wisers.idmap[device.parent_assigned_child_key] = device.id
    -------------------
    -- Set up scheduled
    -- services once the
    -- driver gets
    -- initialized.
    -- Refresh schedule
    log.info('device '..device.parent_assigned_child_key..' in lifecycle init')
  end
end

function lifecycle_handler.added(driver, device)
  log.info('device '..device.id..' added')
  if (device.parent_assigned_child_key == nil) then
    return 0
  end
  log.debug('save dev '..device.id..' networkid '..device.parent_assigned_child_key)
  wisers.idmap[device.parent_assigned_child_key] = device.id
  -- find device type
  log.info('device '..device.parent_assigned_child_key..' added acllback')
  local devtype = wisers.get_dev_type(device.parent_assigned_child_key)
  log.info('device '..device.parent_assigned_child_key..' added devtype '..devtype)
  if (devtype == config.ENUM.AC) then
    local supported_modes = {'heat','cool','dry','fan','auto'}
    device:emit_event(caps.airConditionerMode.supportedAcModes(supported_modes, { visibility = { displayed = false } }))
    local supported_fan_modes = {'low','medium','high','auto'}
    device:emit_event(caps.airConditionerFanMode.supportedAcFanModes(supported_fan_modes, { visibility = { displayed = false } }))
  elseif devtype == config.ENUM.NEWFAN then
    local supported_fan_modes = {'low','medium','high','auto'}
    device:emit_event(caps.airConditionerFanMode.supportedAcFanModes(supported_fan_modes, { visibility = { displayed = false } }))
  end
  -- Once device has been created
  -- at API level, poll its state
  -- via refresh command and send
  -- request to share server's ip
  -- and port to the device os it
  -- can communicate back.
  commands.refresh(nil, device)
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
