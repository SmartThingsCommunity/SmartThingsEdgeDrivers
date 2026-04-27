-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local utils = require "st.utils"
local json = require "st.json"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local PowerConfiguration = clusters.PowerConfiguration
local IASACE = clusters.IASACE
local IASZone = clusters.IASZone
local SecuritySystem = capabilities.securitySystem
local LockCodes = capabilities.lockCodes
local tamperAlert = capabilities.tamperAlert
local mode = capabilities.mode
local panicAlarm = capabilities.panicAlarm

local ArmMode = IASACE.types.ArmMode
local ArmNotification = IASACE.types.ArmNotification
local PanelStatus = IASACE.types.IasacePanelStatus
local AudibleNotification = IASACE.types.IasaceAudibleNotification
local AlarmStatus = IASACE.types.IasaceAlarmStatus

local armCommandFromKeypad = false
local DEVELCO_MANUFACTURER_CODE = 0x1015
local EXIT_DELAY_UNTIL = "exit_delay_until"
local EXIT_DELAY_TARGET_STATUS = "exit_delay_target_status"

local SECURITY_STATUS_EVENTS = {
  armedAway = SecuritySystem.securitySystemStatus.armedAway,
  armedStay = SecuritySystem.securitySystemStatus.armedStay,
  disarmed = SecuritySystem.securitySystemStatus.disarmed,
}

local MODE_STATUS_VALUES = {
  Locked = "Locked",
  Unlocked = "Unlocked",
}

local ARM_MODE_TO_STATUS = {
  [ArmMode.DISARM] = "disarmed",
  [ArmMode.ARM_DAY_HOME_ZONES_ONLY] = "armedStay",
  [ArmMode.ARM_NIGHT_SLEEP_ZONES_ONLY] = "armedStay",
  [ArmMode.ARM_ALL_ZONES] = "armedAway",
}

local ARM_MODE_TO_NOTIFICATION = {
  [ArmMode.DISARM] = ArmNotification.ALL_ZONES_DISARMED,
  [ArmMode.ARM_DAY_HOME_ZONES_ONLY] = ArmNotification.ONLY_DAY_HOME_ZONES_ARMED,
  [ArmMode.ARM_NIGHT_SLEEP_ZONES_ONLY] = ArmNotification.ONLY_NIGHT_SLEEP_ZONES_ARMED,
  [ArmMode.ARM_ALL_ZONES] = ArmNotification.ALL_ZONES_ARMED,
}

local STATUS_TO_PANEL = {
  armedAway = PanelStatus.ARMED_AWAY,
  armedStay = PanelStatus.ARMED_STAY,
  disarmed = PanelStatus.PANEL_DISARMED_READY_TO_ARM,
  exitDelay = PanelStatus.EXIT_DELAY,
}

local STATUS_TO_ACTIVITY = {
  armedAway = "armed away",
  armedStay = "armed stay",
  disarmed = "disarmed",
  exitDelay = "exit delay",
}

local LOCK_STATUS_TO_ACTIVITY = {
  Locked = "Locked",
  Unlocked = "Unlocked",
}

local function emit_supported(device)
    device:emit_event(mode.supportedModes({ "Locked", "Unlocked" }, { visibility = { displayed = false } }))
    device:emit_event(mode.supportedArguments({ "Locked", "Unlocked" }, { visibility = { displayed = false } }))
    device:emit_event(SecuritySystem.supportedSecuritySystemStatuses({ "armedAway", "armedStay", "disarmed" }, { visibility = { displayed = false } }))
    device:emit_event(SecuritySystem.supportedSecuritySystemCommands({ "armAway", "armStay", "disarm" }, { visibility = { displayed = false } }))
end

local function emit_status_event(device, status, extra_data)
  local event_factory = SECURITY_STATUS_EVENTS[status] or SecuritySystem.securitySystemStatus.disarmed
  local event = event_factory({ state_change = true })
  device:emit_event(event)
end

local function emit_mode_event(device, lock_state, extra_data)
  local mode_value = MODE_STATUS_VALUES[lock_state] or "Unlocked"
  local event = mode.mode(mode_value, { state_change = true })
  device:emit_event(event)
end

local function emit_mode_status_event(device, status, extra_data)
  if tonumber(device.preferences.mode) == 1 then
    emit_mode_event(device, status == "disarmed" and "Unlocked" or "Locked", extra_data)
  elseif tonumber(device.preferences.mode) == 0 then
    emit_status_event(device, status, extra_data)
  end
end

local function is_pin_length_valid(device, pin)
  local pinStr = tostring(pin)
  if pinStr:sub(1,1) == "+" then -- device adds + to the rfid codes, so ignore length check for those
    return true
  end
  if pin == nil or pin == "" then
    return false
  end
  local min_len = device.preferences.minCodeLength
  local max_len = device.preferences.maxCodeLength
  local len = string.len(tostring(pin))

  if min_len ~= nil and len < min_len then
    return false
  end
  if max_len ~= nil and len > max_len then
    return false
  end
  return true
end

local function parse_user_map(value)
  local map = {}
    if value == nil or value == "" then
      return map
    end

    for pair in string.gmatch(value, "[^,]+") do
      local code, name = pair:match("^%s*([^:]+)%s*:%s*(.+)%s*$")
      if code ~= nil and name ~= nil and code ~= "" and name ~= "" then
        map[code] = name
      end
    end

  return map
end

local function get_exit_delay_duration(device)
  local duration = device.preferences.duration
  return duration or 5
end

local function is_exit_delay_active(device)
  local deadline = device:get_field(EXIT_DELAY_UNTIL)
  return type(deadline) == "number" and os.time() < deadline
end

local function clear_exit_delay(device)
  device:set_field(EXIT_DELAY_UNTIL, nil, { persist = false })
  device:set_field(EXIT_DELAY_TARGET_STATUS, nil, { persist = false })
end

local function start_exit_delay(device, target_status)
  local duration = get_exit_delay_duration(device)
  device:set_field(EXIT_DELAY_UNTIL, os.time() + duration, { persist = false })
  device:set_field(EXIT_DELAY_TARGET_STATUS, target_status, { persist = false })
  device:send(IASACE.client.commands.PanelStatusChanged(
    device,
    PanelStatus.EXIT_DELAY,
    duration,
    AudibleNotification.DEFAULT_SOUND,
    AlarmStatus.NO_ALARM
  ))
  return duration
end

local function build_lock_code_state_from_prefs(device)
  local pin_updates = parse_user_map(device.preferences.pinMap)
  local rfid_updates = parse_user_map(device.preferences.rfidMap)

  local lock_codes = {}
  local lock_code_pins = {}
  local pins = {}
  local rfids = {}

  for pin, _ in pairs(pin_updates) do
    pins[#pins + 1] = pin
  end

  for rfid, _ in pairs(rfid_updates) do
    rfids[#rfids + 1] = rfid
  end

  table.sort(pins)
  table.sort(rfids)

  for slot_index, pin in ipairs(pins) do
    local slot_key = tostring(slot_index)
    lock_code_pins[slot_key] = pin
    lock_codes[slot_key] = pin_updates[pin]
  end

  local rfid_start = #pins + 1
  for offset, rfid in ipairs(rfids) do
    local slot_key = tostring(rfid_start + offset - 1)
    lock_code_pins[slot_key] = rfid
    lock_codes[slot_key] = rfid_updates[rfid]
  end

  return lock_codes, lock_code_pins
end

local function build_user_map_from_prefs(device)
  return {
    pins = parse_user_map(device.preferences.pinMap),
    rfids = parse_user_map(device.preferences.rfidMap),
  }
end

local function build_lock_codes_payload(device, lock_codes, lock_pins)
  local payload = {}
  local show_pins = device.preferences.showPinSnapshot ~= false

  for slot, name in pairs(lock_codes or {}) do
    local pin = lock_pins and lock_pins[slot] or nil
    if show_pins and pin ~= nil and pin ~= "" then
      payload[slot] = string.format("%s: %s", name, pin)
    else
      payload[slot] = name
    end
  end

  return payload
end

local function encode_payload(payload)
  local ok, encoded = pcall(json.encode, utils.deep_copy(payload))
  if ok and type(encoded) == "string" then
    return encoded
  end
  return "{}"
end

local function emit_lock_codes(device, lock_codes, lock_pins)
  local full_payload = build_lock_codes_payload(device, lock_codes, lock_pins)
  local full_encoded = encode_payload(full_payload)
  device:emit_event(LockCodes.lockCodes(full_encoded, { state_change = true }, { visibility = { displayed = true } }))
end

local function emit_lock_code_limits(device)
  local min_len = device.preferences.minCodeLength
  local max_len = device.preferences.maxCodeLength

  if min_len ~= nil then
    device:emit_event(LockCodes.minCodeLength(min_len, { visibility = { displayed = true } }))
  end
  if max_len ~= nil then
    device:emit_event(LockCodes.maxCodeLength(max_len, { visibility = { displayed = true } }))
  end
end

local function normalize_user_name(value)
  if type(value) == "string" then
    return value
  end
  if type(value) == "table" then
    if type(value.name) == "string" then
      return value.name
    end
    if type(value.value) == "string" then
      return value.value
    end
  end
  return nil
end

local function get_user_map(device)
  local map = device:get_field("user_map")
  if map == nil then
    map = build_user_map_from_prefs(device)
  end
  return map
end

local function resolve_user_from_code(device, code)
  local user_map = get_user_map(device) or {}
  local pin_map = user_map.pins or {}
  local rfid_map = user_map.rfids or {}
  local pins = {}
  local rfids = {}

  for pin, _ in pairs(pin_map) do
    pins[#pins + 1] = pin
  end
  for rfid, _ in pairs(rfid_map) do
    rfids[#rfids + 1] = rfid
  end

  table.sort(pins)
  table.sort(rfids)

  for index, pin in ipairs(pins) do
    if pin == code then
      return { name = normalize_user_name(pin_map[pin]), index = index }, "pin"
    end
  end

  for offset, rfid in ipairs(rfids) do
    if rfid == code then
      return { name = normalize_user_name(rfid_map[rfid]), index = #pins + offset }, "rfid"
    end
  end

  return nil, nil
end

local function emit_mode_activity(device, status, user_name)
  local activity
  if status == "Locked" or status == "Unlocked" then
    activity = "Lock " .. (LOCK_STATUS_TO_ACTIVITY[status] or status)
  else
    activity =  "Lock " .. LOCK_STATUS_TO_ACTIVITY[status == "disarmed" and "Unlocked" or "Locked"]
  end
  local actor = user_name or "Unknown"
  local event = LockCodes.codeChanged(string.format("%s by %s", activity, actor), { state_change = true })
  if user_name ~= nil then
    event.data = { codeName = user_name }
  end
  device:emit_event(event)
end

local function emit_security_activity(device, status, user_name)
  local activity = "Security System " .. (STATUS_TO_ACTIVITY[status] or status)
  local actor = user_name or "Unknown"
  local event = LockCodes.codeChanged(string.format("%s by %s", activity, actor), { state_change = true })
  if user_name ~= nil then
    event.data = { codeName = user_name }
  end
  device:emit_event(event)
end

local function emit_arm_activity(device, status, user_name)
  local activity
  if tonumber(device.preferences.mode) == 1 then
    if status == "Locked" or status == "Unlocked" then
      activity = "Lock " .. (LOCK_STATUS_TO_ACTIVITY[status] or status)
    else
      activity =  "Lock " .. LOCK_STATUS_TO_ACTIVITY[status == "disarmed" and "Unlocked" or "Locked"]
    end
  elseif tonumber(device.preferences.mode) == 0 then
    activity = "Security System " .. (STATUS_TO_ACTIVITY[status] or status)
  end
  local actor = user_name or "Unknown"
  local event = LockCodes.codeChanged(string.format("%s by %s", activity, actor), { state_change = true })
  if user_name ~= nil then
    event.data = { codeName = user_name }
  end
  device:emit_event(event)
end

local function get_current_mode_status(device)
  local lock_status = device:get_latest_state("main", mode.ID, mode.mode.NAME) or "Unlocked"
  return lock_status == "Locked" and "armedAway" or "disarmed"
end

local function get_current_security_status(device)
  return device:get_latest_state("main", SecuritySystem.ID, SecuritySystem.securitySystemStatus.NAME) or "disarmed"
end

local function get_current_status(device)
  if tonumber(device.preferences.mode) == 1 then
    return get_current_mode_status(device)
  elseif tonumber(device.preferences.mode) == 0 then
    return get_current_security_status(device)
  end
end

local function send_panel_status(device, status)
  local duration = get_exit_delay_duration(device)
  local panel_status = STATUS_TO_PANEL[status] or PanelStatus.PANEL_DISARMED_READY_TO_ARM
  device:send(IASACE.client.commands.PanelStatusChanged(
    device,
    panel_status,
    duration,
    AudibleNotification.DEFAULT_SOUND,
    AlarmStatus.NO_ALARM
  ))
end

local function can_process_arm_command(command, status)
  if command == status then
    return false
  else
    return true
  end
end

local function handle_arm_command(driver, device, zb_rx)
  armCommandFromKeypad = true
  local cmd = zb_rx.body.zcl_body
  local pin = cmd.arm_disarm_code.value

  local status = ARM_MODE_TO_STATUS[cmd.arm_mode.value]
  if status == nil then
    return
  end

  if pin == nil or pin == "" then
    return
  end

  if not is_pin_length_valid(device, pin) then
    return
  end

  local user, auth_type = resolve_user_from_code(device, pin)
  if user == nil then
    device:emit_event(LockCodes.codeChanged(tostring(pin) .. " is not assigned to any user on this keypad. You can create a new user with this code in settings.", { state_change = true }))
    return
  end

  local data = {
    source = "keypad",
    authType = auth_type,
    userIndex = user.index,
    userName = user.name,
  }

  if is_exit_delay_active(device) then
    device:send(IASACE.client.commands.ArmResponse(device, 0xFF))
    armCommandFromKeypad = false
    return
  end

  if can_process_arm_command(status, get_current_status(device)) then
    if device.preferences.exitDelay == true and status == "armedAway" and tonumber(device.preferences.mode) == 0 then
      local duration = start_exit_delay(device, status)
      device.thread:call_with_delay(duration, function()
        clear_exit_delay(device)
        emit_mode_status_event(device, status, data)
        emit_arm_activity(device, status, user.name)
        device:send(IASACE.client.commands.ArmResponse(
          device,
          ARM_MODE_TO_NOTIFICATION[cmd.arm_mode.value] or ArmNotification.ALL_ZONES_DISARMED
        ))
      end)
    else
      emit_mode_status_event(device, status, data)
      emit_arm_activity(device, status, user.name)
      device:send(IASACE.client.commands.ArmResponse(
        device,
        ARM_MODE_TO_NOTIFICATION[cmd.arm_mode.value] or ArmNotification.ALL_ZONES_DISARMED
      ))
    end
  else
    device:send(IASACE.client.commands.ArmResponse(
      device,
      0xFF
    ))
  end
  armCommandFromKeypad = false
end

local function handle_get_panel_status(driver, device, zb_rx)
  local duration = get_exit_delay_duration(device)
  if is_exit_delay_active(device) then
    device:send(IASACE.client.commands.GetPanelStatusResponse(
      device,
      PanelStatus.EXIT_DELAY,
      duration,
      AudibleNotification.DEFAULT_SOUND,
      AlarmStatus.NO_ALARM
    ))
    return
  end
  local status = get_current_status(device)
  device:send(IASACE.client.commands.GetPanelStatusResponse(
    device,
    STATUS_TO_PANEL[status] or PanelStatus.PANEL_DISARMED_READY_TO_ARM,
    duration,
    AudibleNotification.DEFAULT_SOUND,
    AlarmStatus.NO_ALARM
  ))
end

local function handle_emergency_command(driver, device, zb_rx)
  device:emit_event(panicAlarm.panicAlarm.panic({ state_change = true }))
  device.thread:call_with_delay(10, function()
    device:emit_event(panicAlarm.panicAlarm.clear({ state_change = true }))
  end)
end
local function handle_arm(device, status)
  local duration = get_exit_delay_duration(device)
  if is_exit_delay_active(device) then
    return
  end
  if not armCommandFromKeypad and can_process_arm_command(status, get_current_security_status(device)) then
    if device.preferences.exitDelay == true and status == "armedAway" and tonumber(device.preferences.mode) == 0 then
      duration = start_exit_delay(device, status)
      device.thread:call_with_delay(duration, function()
        clear_exit_delay(device)
        emit_status_event(device, status, { source = "app" })
        emit_security_activity(device, status, "App")
        send_panel_status(device, status)
      end)
    else
      emit_status_event(device, status, { source = "app" })
      emit_security_activity(device, status, "App")
      if tonumber(device.preferences.mode) == 0 then
        send_panel_status(device, status)
      end
    end
  else
    return
  end
end

local function handle_lock(device, status)
  if is_exit_delay_active(device) then
    return
  end
  if not armCommandFromKeypad and can_process_arm_command(status, get_current_mode_status(device)) then
    emit_mode_event(device, status, { source = "app" })
    emit_mode_activity(device, status, "App")
    if tonumber(device.preferences.mode) == 1 then
      send_panel_status(device, status)
    end
  else
    return
  end
end

local function handle_arm_away(driver, device, command)
  handle_arm(device, "armedAway")
end

local function handle_arm_stay(driver, device, command)
  handle_arm(device, "armedStay")
end

local function handle_disarm(driver, device, command)
    if is_exit_delay_active(device) then
      clear_exit_delay(device)
    end
    if can_process_arm_command("disarmed", get_current_security_status(device)) and not armCommandFromKeypad then
      emit_status_event(device, "disarmed", { source = "app" })
      emit_security_activity(device, "disarmed", "App")
      if tonumber(device.preferences.mode) == 0 then
        send_panel_status(device, "disarmed")
      end
    else
      return
    end
end

local function handle_unlock(driver, device, command)
    if is_exit_delay_active(device) then
      clear_exit_delay(device)
    end
    if can_process_arm_command("Unlocked", get_current_mode_status(device)) and not armCommandFromKeypad then
      emit_mode_event(device, "Unlocked", { source = "app" })
      emit_mode_activity(device, "Unlocked", "App")
      if tonumber(device.preferences.mode) == 1 then
        send_panel_status(device, "Unlocked")
      end
    else
      return
    end
end

local function handle_set_mode(driver, device, command)
  local desired = command.args.mode
  if desired == "Locked" then
    handle_lock(device, "Locked")
  elseif desired == "Unlocked" then
    handle_unlock(driver, device, command)
  end
end

local function update_user_map(device)
  local map = build_user_map_from_prefs(device)
  device:set_field("user_map", map, { persist = true })
  local lock_codes, lock_code_pins = build_lock_code_state_from_prefs(device)
  emit_lock_codes(device, lock_codes, lock_code_pins)
end

local function refresh(driver, device)
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  send_panel_status(device, get_current_status(device))
end

local function set_states(device)
  local current_mode = device:get_latest_state("main", mode.ID, mode.mode.NAME)
  if current_mode == nil then
    current_mode = "Unlocked"
  end
  emit_mode_event(device, current_mode, { source = "driver" })
  emit_mode_activity(device, current_mode, "App")
  local current_security_status = device:get_latest_state("main", SecuritySystem.ID, SecuritySystem.securitySystemStatus.NAME)
  if current_security_status == nil then
    current_security_status = "disarmed"
  end
  emit_status_event(device, current_security_status, { source = "driver" })
  emit_security_activity(device, current_security_status, "App")
end

local function get_and_update_state(device)
  if tonumber(device.preferences.mode) == 1 then
    local current_mode = device:get_latest_state("main", mode.ID, mode.mode.NAME)
    if current_mode == nil then
      current_mode = "Unlocked"
    end
    emit_mode_event(device, current_mode, { source = "driver" })
    emit_mode_activity(device, current_mode, "App")
  elseif tonumber(device.preferences.mode) == 0 then
    local current_security_status = device:get_latest_state("main", SecuritySystem.ID, SecuritySystem.securitySystemStatus.NAME)
    if current_security_status == nil then
      current_security_status = "disarmed"
    end
    emit_status_event(device, current_security_status, { source = "driver" })
    emit_security_activity(device, current_security_status, "App")
  end
end

local function device_added(driver, device)
  emit_supported(device)
end

local function do_configure(self, device)
  device:send(device_management.build_bind_request(device, IASACE.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
end

local function send_iasace_mfg_write(device, attr_id, data_type, payload)
  local msg = cluster_base.write_manufacturer_specific_attribute(device, IASACE.ID, attr_id, DEVELCO_MANUFACTURER_CODE, data_type, payload)
  msg.body.zcl_header.frame_ctrl:set_direction_client()
  device:send(msg)
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(4.0, 6.0)(driver, device)
  update_user_map(device)
  emit_lock_code_limits(device)
  set_states(device)
  device:emit_event(panicAlarm.panicAlarm.clear({ state_change = true }))
end

local function info_changed(driver, device, event, args)
  emit_lock_code_limits(device)
  for name, value in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      if (name == "pinMap") then
        update_user_map(device)
      elseif (name == "rfidMap") then
        update_user_map(device)
      elseif (name == "autoArmDisarmMode") then
        local autoArmDisarmMode = tonumber(device.preferences.autoArmDisarmMode)
        if autoArmDisarmMode ~= nil then
          send_iasace_mfg_write(device, 0x8003, data_types.Enum8, autoArmDisarmMode)
        end
      elseif (name == "autoDisarmModeSetting") then
        local autoDisarmModeSetting = device.preferences.autoDisarmModeSetting
        send_iasace_mfg_write(device, 0x8004, data_types.Boolean, autoDisarmModeSetting)
      elseif (name == "autoArmModeSetting") then
        local autoArmModeSetting = tonumber(device.preferences.autoArmModeSetting)
        if autoArmModeSetting ~= nil then
          send_iasace_mfg_write(device, 0x8005, data_types.Enum8, autoArmModeSetting)
        end
      elseif (name == "autoArmModeSettingBool") then
        local autoArmModeSetting = device.preferences.autoArmModeSettingBool
        if autoArmModeSetting == true then
          send_iasace_mfg_write(device, 0x8005, data_types.Enum8, 1)
        else
          send_iasace_mfg_write(device, 0x8005, data_types.Enum8, 0)
        end
      elseif (name == "pinLengthSetting") then
        local pinLengthSetting = tonumber(device.preferences.pinLengthSetting)
        if pinLengthSetting ~= nil then
          send_iasace_mfg_write(device, 0x8006, data_types.Uint8, pinLengthSetting)
        end
      elseif (name == "mode") then
        get_and_update_state(device)
        refresh(driver, device)
      end
    end
  end
end

local function generate_event_from_zone_status(driver, device, zone_status, zigbee_message)
  if zone_status:is_tamper_set() then
    device:emit_event(tamperAlert.tamper.detected())
  else
    device:emit_event(tamperAlert.tamper.clear())
  end
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  local zone_status = zb_rx.body.zcl_body.zone_status
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local frient_keypad = {
  NAME = "frient Keypad",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    init = device_init,
    infoChanged = info_changed,
  },
  zigbee_handlers = {
    cluster = {
      [IASACE.ID] = {
        [IASACE.server.commands.Arm.ID] = handle_arm_command,
        [IASACE.server.commands.GetPanelStatus.ID] = handle_get_panel_status,
        [IASACE.server.commands.Emergency.ID] = handle_emergency_command,
      },
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = generate_event_from_zone_status
      },
    }
  },
  capability_handlers = {
    [SecuritySystem.ID] = {
      [SecuritySystem.commands.armAway.NAME] = handle_arm_away,
      [SecuritySystem.commands.armStay.NAME] = handle_arm_stay,
      [SecuritySystem.commands.disarm.NAME] = handle_disarm,
    },
    [mode.ID] = {
      [mode.commands.setMode.NAME] = handle_set_mode,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh,
    },
  },
  can_handle = require("frient-keypad.can_handle"),
}

return frient_keypad
