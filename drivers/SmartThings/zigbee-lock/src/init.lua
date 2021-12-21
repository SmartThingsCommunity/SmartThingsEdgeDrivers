-- Zigbee Driver utilities
local defaults          = require "st.zigbee.defaults"
local device_management = require "st.zigbee.device_management"
local ZigbeeDriver      = require "st.zigbee"

-- Zigbee Spec Utils
local clusters                = require "st.zigbee.zcl.clusters"
local Alarm                   = clusters.Alarms
local LockCluster             = clusters.DoorLock
local PowerConfiguration      = clusters.PowerConfiguration

-- Capabilities
local capabilities              = require "st.capabilities"
local Battery                   = capabilities.battery
local Lock                      = capabilities.lock
local LockCodes                 = capabilities.lockCodes
local Tamper                    = capabilities.tamperAlert

-- Enums
local UserStatusEnum            = LockCluster.types.DrlkUserStatus
local UserTypeEnum              = LockCluster.types.DrlkUserType
local ProgrammingEventCodeEnum  = LockCluster.types.ProgramEventCode

local lock_constants = require "lock_constants"

local json = require "dkjson"

local get_lock_codes = function(device)
  return device:get_field(lock_constants.LOCK_CODES) or {}
end

local lock_codes_event = function(device, lock_codes)
  device:set_field(lock_constants.LOCK_CODES, lock_codes)
  device:emit_event(capabilities.lockCodes.lockCodes(json.encode(lock_codes)))
end

local reload_all_codes = function(driver, device, command)
  -- starts at first user code index then iterates through all lock codes as they come in
  device:send(LockCluster.attributes.SendPINOverTheAir:write(device, true))
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodeLength.NAME) == nil) then
    device:send(LockCluster.attributes.MaxPINCodeLength:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.minCodeLength.NAME) == nil) then
    device:send(LockCluster.attributes.MinPINCodeLength:read(device))
  end
  if (device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME) == nil) then
    device:send(LockCluster.attributes.NumberOfPINUsersSupported:read(device))
  end
  if (device:get_field(lock_constants.CHECKING_CODE) == nil) then device:set_field(lock_constants.CHECKING_CODE, 0) end
  device:emit_event(LockCodes.scanCodes("Scanning"))
  device:send(LockCluster.server.commands.GetPINCode(device, device:get_field(lock_constants.CHECKING_CODE)))
end

local refresh = function(driver, device, cmd)
  device:refresh()
  device:send(LockCluster.attributes.LockState:read(device))
  device:send(Alarm.attributes.AlarmCount:read(device))
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 600, 21600, 1))

  device:send(device_management.build_bind_request(device, LockCluster.ID, self.environment_info.hub_zigbee_eui))
  device:send(LockCluster.attributes.LockState:configure_reporting(device, 0, 3600, 0))

  device:send(device_management.build_bind_request(device, Alarm.ID, self.environment_info.hub_zigbee_eui))
  device:send(Alarm.attributes.AlarmCount:configure_reporting(device, 0, 21600, 0))

  -- Do the device refresh
  self:inject_capability_command(device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {}
  })

  device.thread:call_with_delay(2, function(d)
    self:inject_capability_command(device, { 
      capability = capabilities.lockCodes.ID,
      command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
      args = {} 
    })
  end)
end

local get_code_name = function(device, code_id)
  if (device:get_field(lock_constants.CODE_STATE) ~= nil and device:get_field(lock_constants.CODE_STATE)["setName"..code_id] ~= nil) then
    -- this means a code set operation succeeded
    return device:get_field(lock_constants.CODE_STATE)["setName"..code_id]
  elseif (get_lock_codes(device)[code_id] ~= nil) then
    return get_lock_codes(device)[code_id]
  else
    return "Code " .. code_id
  end
end

local get_change_type = function(device, code_id)
  if (get_lock_codes(device)[code_id] == nil) then
    return " set"
  else
    return " changed"
  end
end

local alarm_handler = function(driver, device, zb_mess)
  local ALARM_REPORT = {
    [0] = Lock.lock.unknown(),
    [1] = Lock.lock.unknown(),
    -- Events 16-19 are low battery events, but are presented as descriptionText only
  }
  if (ALARM_REPORT[zb_mess.body.zcl_body.alarm_code.value] ~= nil) then
    device:emit_event(ALARM_REPORT[zb_mess.body.zcl_body.alarm_code.value])
  end
end

local code_deleted = function(device, code_slot)
  local lock_codes = get_lock_codes(device)
  local event = LockCodes.codeChanged(code_slot.." deleted")
  event.data = {codeName = get_code_name(device, code_slot)}
  lock_codes[code_slot] = nil
  device:emit_event(event)
  return lock_codes
end

local get_pin_response_handler = function(driver, device, zb_mess)
  local event = LockCodes.codeChanged("")
  local code_slot = tostring(zb_mess.body.zcl_body.user_id.value)
  event.data = {codeName = get_code_name(device, code_slot)}
  if (zb_mess.body.zcl_body.user_status.value == UserStatusEnum.OCCUPIED_ENABLED) then
    -- Code slot is occupied
    event.value = code_slot .. get_change_type(device, code_slot)
    local lock_codes = get_lock_codes(device)
    lock_codes[code_slot] = event.data.codeName
    device:emit_event(event)
    lock_codes_event(device, lock_codes)
  else
    -- Code slot is unoccupied
    if (get_lock_codes(device)[code_slot] ~= nil) then
      -- Code has been deleted
      lock_codes_event(device, code_deleted(device, code_slot))
    else
      -- Code is unset
      event.value = code_slot .. " unset"
      device:emit_event(event)
    end
  end

  code_slot = tonumber(code_slot)
  if (code_slot == device:get_field(lock_constants.CHECKING_CODE)) then
    -- the code we're checking has arrived
    if (code_slot >= device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)) then
      device:emit_event(LockCodes.scanCodes("Complete"))
      device:set_field(lock_constants.CHECKING_CODE, nil)
    else
      local checkingCode = device:get_field(lock_constants.CHECKING_CODE) + 1
      device:set_field(lock_constants.CHECKING_CODE, checkingCode)
      device:send(LockCluster.server.commands.GetPINCode(device, checkingCode))
    end
  end
end

local programming_event_handler = function(driver, device, zb_mess)
  local event = LockCodes.codeChanged("")
  local code_slot = tostring(zb_mess.body.zcl_body.user_id.value)
  event.data = {}
  if (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.MASTER_CODE_CHANGED) then
    -- Master code changed
    event.value = "0 set"
    event.data = {codeName = "Master Code"}
    device:emit_event(event)
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_DELETED) then
    if (zb_mess.body.zcl_body.user_id.value == 0xFF) then
      -- All codes deleted
      for cs, _ in pairs(get_lock_codes(device)) do
        code_deleted(device, cs)
      end
      lock_codes_event(device, {})
    else
      -- One code deleted
      lock_codes_event(device, code_deleted(device, code_slot))
    end
  elseif (zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_ADDED or
          zb_mess.body.zcl_body.program_event_code.value == ProgrammingEventCodeEnum.PIN_CODE_CHANGED) then
    -- Code added or changed
    local change_type = get_change_type(device, code_slot)
    local code_name = get_code_name(device, code_slot)
    event.value = code_slot .. change_type
    event.data = {codeName = code_name}
    device:emit_event(event)
    if (change_type == " set") then
      local lock_codes = get_lock_codes(device)
      lock_codes[code_slot] = code_name
      lock_codes_event(device, lock_codes)
    end
  end
end

local handle_max_codes = function(driver, device, value)
  device:emit_event(LockCodes.maxCodes(value.value))
end

local handle_max_code_length = function(driver, device, value)
  device:emit_event(LockCodes.maxCodeLength(value.value))
end

local handle_min_code_length = function(driver, device, value)
  device:emit_event(LockCodes.minCodeLength(value.value))
end

local update_codes = function(driver, device, command)
  -- args.codes is json
  for name, code in pairs(command.args.codes) do
    -- these seem to come in the format "code[slot#]: code"
    local code_slot = tonumber(string.gsub(name, "code", ""), 10)
    if (code_slot ~= nil) then
      if (code ~= nil and code ~= "0") then
        device:send(LockCluster.server.commands.SetPINCode(device,
                code_slot,
                UserStatusEnum.OCCUPIED_ENABLED,
                UserTypeEnum.UNRESTRICTED,
                code)
        )
      else
        device:send(LockCluster.client.commands.ClearPINCode(device, code_slot))
        device.thread:call_with_delay(2, function(d)
          device:send(LockCluster.server.commands.GetPINCode(device, code_slot))
        end)
      end
    end
  end
end

local delete_code = function(driver, device, command)
  device:send(LockCluster.attributes.SendPINOverTheAir:write(device, true))
  device:send(LockCluster.server.commands.ClearPINCode(device, command.args.codeSlot))
  device.thread:call_with_delay(2, function(d)
    device:send(LockCluster.server.commands.GetPINCode(device, command.args.codeSlot))
  end)
end

local request_code = function(driver, device, command)
  device:send(LockCluster.server.commands.GetPINCode(device, command.args.codeSlot))
end

local set_code = function(driver, device, command)
  device:send(LockCluster.server.commands.SetPINCode(device,
          command.args.codeSlot,
          UserStatusEnum.OCCUPIED_ENABLED,
          UserTypeEnum.UNRESTRICTED,
          command.args.codePIN)
  )
  if (command.args.codeName ~= nil) then
    -- wait for confirmation from the lock to commit this to memory
    -- Groovy driver has a lot more info passed here as a description string, may need to be investigated
    local codeState = device:get_field(lock_constants.CODE_STATE) or {}
    codeState["setName"..command.args.codeSlot] = command.args.codeName
    device:set_field(lock_constants.CODE_STATE, codeState)
  end

  device.thread:call_with_delay(4, function(d)
    device:send(LockCluster.server.commands.GetPINCode(device, command.args.codeSlot))
  end)
end

local name_slot = function(driver, device, command)
  local code_slot = tostring(command.args.codeSlot)
  if (get_lock_codes(device)[code_slot] ~= nil) then
    local lock_codes = get_lock_codes(device)
    lock_codes[code_slot] = command.args.codeName
    device:emit_event(LockCodes.codeChanged(code_slot .. " renamed"))
    device:emit_event(capabilities.lockCodes.lockCodes(json.encode(get_lock_codes(device))))
  end
end

local zigbee_lock_driver = {
  supported_capabilities = {
    Lock,
    LockCodes,
    Battery,
  },
  zigbee_handlers = {
    cluster = {
      [Alarm.ID] = {
        [Alarm.client.commands.Alarm.ID] = alarm_handler
      },
      [LockCluster.ID] = {
        [LockCluster.client.commands.GetPINCodeResponse.ID] = get_pin_response_handler,
        [LockCluster.client.commands.ProgrammingEventNotification.ID] = programming_event_handler
      }
    },
    attr = {
      [LockCluster.ID] = {
        [LockCluster.attributes.MaxPINCodeLength.ID] = handle_max_code_length,
        [LockCluster.attributes.MinPINCodeLength.ID] = handle_min_code_length,
        [LockCluster.attributes.NumberOfPINUsersSupported.ID] = handle_max_codes
      }
    }
  },
  capability_handlers = {
    [LockCodes.ID] = {
      [LockCodes.commands.updateCodes.NAME] = update_codes,
      [LockCodes.commands.deleteCode.NAME] = delete_code,
      [LockCodes.commands.reloadAllCodes.NAME] = reload_all_codes,
      [LockCodes.commands.requestCode.NAME] = request_code,
      [LockCodes.commands.setCode.NAME] = set_code,
      [LockCodes.commands.nameSlot.NAME] = name_slot
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh
    }
  },
  sub_drivers = { require("samsungsds"), require("yale"), require("yale-fingerprint-lock") },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
}

defaults.register_for_default_handlers(zigbee_lock_driver, zigbee_lock_driver.supported_capabilities)
local lock = ZigbeeDriver("zigbee-lock", zigbee_lock_driver)
lock:run()
