-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local utils = require "st.utils"
local json = require "st.json"
local log = require "log"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local PowerConfiguration = clusters.PowerConfiguration
local IASACE = clusters.IASACE
local SecuritySystem = capabilities.securitySystem
local LockCodes = capabilities.lockCodes
local IASZone = clusters.IASZone
local tamperAlert = capabilities.tamperAlert

local ArmMode = IASACE.types.ArmMode
local ArmNotification = IASACE.types.ArmNotification
local PanelStatus = IASACE.types.IasacePanelStatus
local AudibleNotification = IASACE.types.IasaceAudibleNotification
local AlarmStatus = IASACE.types.IasaceAlarmStatus

local BATTERY_INIT = battery_defaults.build_linear_voltage_init(4.0, 6.0)

local LOCK_CODES_FIELD = "lockCodes"
local LOCK_CODE_PINS_FIELD = "lockCodePins"
local LOCK_CODE_LENGTH_FIELD = "lockCodeLength"
local LOCK_CODES_MAX_LEN = 255
local LOCK_CODES_CHUNK_MAX_LEN = 220
local armCommandFromKeypad = false
local DEVELCO_MANUFACTURER_CODE = 0x1015

-- Update these tables to match your local user map.
local LOCAL_USER_MAP = {
  pins = {
  },
  rfids = {
  },
}

local SECURITY_STATUS_EVENTS = {
  armedAway = SecuritySystem.securitySystemStatus.armedAway,
  armedStay = SecuritySystem.securitySystemStatus.armedStay,
  disarmed = SecuritySystem.securitySystemStatus.disarmed,
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

local function emit_supported(device)
  device:emit_event(SecuritySystem.supportedSecuritySystemStatuses({ "armedAway", "armedStay", "disarmed" }, { visibility = { displayed = false } }))
  device:emit_event(SecuritySystem.supportedSecuritySystemCommands({ "armAway", "armStay", "disarm" }, { visibility = { displayed = false } }))
end

local function emit_status_event(device, status, extra_data)
  local event_factory = SECURITY_STATUS_EVENTS[status] or SecuritySystem.securitySystemStatus.disarmed
  local event = event_factory({ state_change = true })
  if extra_data ~= nil then
    device:set_field("securitySystem_last_context", extra_data, { persist = false })
    device.log.info(string.format("securitySystemStatus extra data captured (keys=%s)", table.concat((function()
      local keys = {}
      for k, _ in pairs(extra_data) do
        keys[#keys + 1] = tostring(k)
      end
      return keys
    end)(), ",")))
  end
  device.log.info(string.format("Emitting securitySystemStatus=%s", status))
  device:emit_event(event)
end

local function get_pref_number(value)
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" and value ~= "" then
    local parsed = tonumber(value)
    if parsed ~= nil then
      return parsed
    end
    local numeric_fragment = value:match("[-+]?%d+%.?%d*")
    if numeric_fragment ~= nil then
      return tonumber(numeric_fragment)
    end
  end
  return nil
end

local function is_pin_length_valid(device, pin)
  if pin == nil or pin == "" then
    return false
  end
  local min_len = get_pref_number(device.preferences.minCodeLength)
  local max_len = get_pref_number(device.preferences.maxCodeLength)
  local len = string.len(tostring(pin))

  if min_len ~= nil and len < min_len then
    return false
  end
  if max_len ~= nil and len > max_len then
    return false
  end
  return true
end

local function parse_user_map(value, validator)
  local map = {}
    if value == nil or value == "" then
      return map
    end

    for pair in string.gmatch(value, "[^,]+") do
      local code, name = pair:match("^%s*([^:]+)%s*:%s*(.+)%s*$")
      if code ~= nil and name ~= nil and code ~= "" and name ~= "" then
        if validator == nil or validator(code) then
          map[code] = name
        end
      end
    end

  return map
end

local function parse_delete_list(value)
  local items = {}
  if value == nil or value == "" then
    return items
  end

  for token in string.gmatch(value, "[^,]+") do
    local code = token:match("^%s*(.-)%s*$")
    if code ~= nil and code ~= "" then
      items[code] = true
    end
  end

  return items
end

local function get_lock_codes(device)
  return device:get_field(LOCK_CODES_FIELD) or {}
end

local function get_lock_code_pins(device)
  return device:get_field(LOCK_CODE_PINS_FIELD) or {}
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

local function get_sorted_slots(lock_codes)
  local slots = {}
  for slot, _ in pairs(lock_codes or {}) do
    slots[#slots + 1] = tostring(slot)
  end

  table.sort(slots, function(left, right)
    local left_num = tonumber(left)
    local right_num = tonumber(right)
    if left_num ~= nil and right_num ~= nil then
      return left_num < right_num
    end
    if left_num ~= nil then
      return true
    end
    if right_num ~= nil then
      return false
    end
    return left < right
  end)

  return slots
end

local function emit_lock_codes_chunks(device, lock_codes, lock_pins)
  local chunks = {}
  local current = ""
  local slots = get_sorted_slots(lock_codes)

  for _, slot in ipairs(slots) do
    local name = tostring(lock_codes[slot] or ("Code " .. slot))
    local pin = lock_pins and lock_pins[slot] or nil
    local entry = pin and pin ~= "" and string.format("%s:%s (%s)", slot, name, pin) or string.format("%s:%s", slot, name)

    if current == "" then
      current = entry
    elseif (#current + 2 + #entry) <= LOCK_CODES_CHUNK_MAX_LEN then
      current = current .. ", " .. entry
    else
      chunks[#chunks + 1] = current
      current = entry
    end
  end

  if current ~= "" then
    chunks[#chunks + 1] = current
  end

  for index, chunk in ipairs(chunks) do
    local message = string.format("codes %d/%d: %s", index, #chunks, chunk)
    device:emit_event(LockCodes.codeChanged(message, { state_change = true }))
  end
end

local function encode_payload(payload)
  local ok, encoded = pcall(json.encode, utils.deep_copy(payload))
  if ok and type(encoded) == "string" then
    return encoded
  end
  return "{}"
end

local function build_partial_payload(payload)
  local partial = {}
  local slots = get_sorted_slots(payload)
  for _, slot in ipairs(slots) do
    partial[slot] = tostring(payload[slot] or "")
    local encoded = encode_payload(partial)
    if #encoded > LOCK_CODES_MAX_LEN then
      partial[slot] = nil
      break
    end
  end
  return partial
end

local function emit_lock_codes(device, lock_codes, lock_pins)
  local full_payload = build_lock_codes_payload(device, lock_codes, lock_pins)
  local full_encoded = encode_payload(full_payload)
  if #full_encoded <= LOCK_CODES_MAX_LEN then
    device:emit_event(LockCodes.lockCodes(full_encoded, { state_change = true }, { visibility = { displayed = true } }))
    return
  end

  local partial_payload = build_partial_payload(full_payload)
  local partial_encoded = encode_payload(partial_payload)
  device:emit_event(LockCodes.lockCodes(partial_encoded, { state_change = true }, { visibility = { displayed = true } }))
  emit_lock_codes_chunks(device, lock_codes, lock_pins)
end

local function emit_lock_code_limits(device)
  local min_len = get_pref_number(device.preferences.minCodeLength)
  local max_len = get_pref_number(device.preferences.maxCodeLength)
  local code_len = device:get_field(LOCK_CODE_LENGTH_FIELD)

  if min_len ~= nil then
    device:emit_event(LockCodes.minCodeLength(min_len, { visibility = { displayed = false } }))
  end
  if max_len ~= nil then
    device:emit_event(LockCodes.maxCodeLength(max_len, { visibility = { displayed = false } }))
  end
  if code_len ~= nil then
    device:emit_event(LockCodes.codeLength(code_len, { visibility = { displayed = false } }))
  end
end

local function get_next_index(map_section)
  local max_index = 0
  for _, entry in pairs(map_section or {}) do
    if type(entry.index) == "number" and entry.index > max_index then
      max_index = entry.index
    end
  end
  return max_index + 1
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

local function normalize_user_entry(entry)
  if type(entry) == "table" then
    return {
      name = normalize_user_name(entry.name) or normalize_user_name(entry),
      index = tonumber(entry.index),
    }
  end
  return {
    name = normalize_user_name(entry),
    index = nil,
  }
end

local function merge_user_section(base_section, updates)
  local merged = {}
  for code, entry in pairs(base_section or {}) do
    merged[code] = normalize_user_entry(entry)
  end

  local next_index = get_next_index(merged)
  for code, value in pairs(updates or {}) do
    local name = normalize_user_name(value)
    local existing = merged[code]
    if existing ~= nil and name ~= nil and name ~= "" then
      existing.name = name
    elseif existing == nil and name ~= nil and name ~= "" then
      merged[code] = { name = name, index = next_index }
      next_index = next_index + 1
    end
  end

  return merged
end

local function get_user_map(device)
  return device:get_field("securitySystem_user_map")
end

local function emit_code_changed(device, code_slot, change_type, code_name)
  local event = LockCodes.codeChanged(tostring(code_slot) .. change_type, { state_change = true })
  if code_name ~= nil then
    event.data = { codeName = code_name }
  end
  device:emit_event(event)
end

local function sync_lock_codes_from_user_map(device, map)
  local previous_lock_codes = utils.deep_copy(get_lock_codes(device))
  local previous_lock_pins = utils.deep_copy(get_lock_code_pins(device))
  local lock_codes = {}
  local lock_pins = {}
  local used_slots = {}

  local entries = {}
  for pin, entry in pairs(map.pins or {}) do
    local normalized = normalize_user_entry(entry)
    entries[#entries + 1] = {
      pin = pin,
      name = normalized.name,
      index = normalized.index,
    }
  end

  table.sort(entries, function(left, right)
    local left_index = left.index or math.huge
    local right_index = right.index or math.huge
    if left_index == right_index then
      return tostring(left.pin) < tostring(right.pin)
    end
    return left_index < right_index
  end)

  local next_slot = 1
  for _, entry in ipairs(entries) do
    local slot_index = entry.index
    if slot_index == nil or slot_index < 1 or used_slots[slot_index] then
      while used_slots[next_slot] do
        next_slot = next_slot + 1
      end
      slot_index = next_slot
    end

    used_slots[slot_index] = true
    map.pins[entry.pin] = map.pins[entry.pin] or {}
    map.pins[entry.pin].index = slot_index
    map.pins[entry.pin].name = entry.name or map.pins[entry.pin].name or ("Code " .. tostring(slot_index))

    local slot = tostring(slot_index)
    lock_pins[slot] = entry.pin
    lock_codes[slot] = entry.name or normalize_user_name(previous_lock_codes[slot]) or ("Code " .. slot)
  end

  for slot, pin in pairs(previous_lock_pins or {}) do
    if pin ~= nil and lock_pins[slot] == nil then
      emit_code_changed(device, slot, " deleted", nil)
    end
  end
  log.error("previous lock codes " .. json.encode(previous_lock_codes))
  log.error("previous lock pins " .. json.encode(previous_lock_pins))
  log.error("lock codes" .. json.encode(lock_codes))
  log.error("lock pins " .. json.encode(lock_pins))

  device:set_field("securitySystem_user_map", map, { persist = true })
  device:set_field(LOCK_CODES_FIELD, lock_codes, { persist = true })
  device:set_field(LOCK_CODE_PINS_FIELD, lock_pins, { persist = true })
  emit_lock_codes(device, lock_codes, lock_pins)
end

local function resolve_user_from_code(device, code)
  local map = get_user_map(device)
  if map.pins ~= nil and map.pins[code] ~= nil then
    return map.pins[code], "pin"
  end
  if map.rfids ~= nil and map.rfids[code] ~= nil then
    return map.rfids[code], "rfid"
  end
  return nil, nil
end

local function emit_arm_activity(device, status, user_name)
  local activity = STATUS_TO_ACTIVITY[status] or status
  local actor = user_name or "Unknown"
  local event = LockCodes.codeChanged(string.format("%s by %s", activity, actor), { state_change = true })
  if user_name ~= nil then
    event.data = { codeName = user_name }
  end
  device:emit_event(event)
end

local function get_current_status(device)
  return device:get_latest_state("main", SecuritySystem.ID, SecuritySystem.securitySystemStatus.NAME) or "disarmed"
end

local function send_panel_status(device, status)
  local length = device.preferences.length or 5
  local panel_status = STATUS_TO_PANEL[status] or PanelStatus.PANEL_DISARMED_READY_TO_ARM
  device:send(IASACE.client.commands.PanelStatusChanged(
    device,
    panel_status,
    length,
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
  local pin_len = pin ~= nil and string.len(pin) or 0
  log.info(string.format("IAS ACE Arm received (mode=%s, pin_len=%d)", tostring(cmd.arm_mode.value), pin_len))

  local status = ARM_MODE_TO_STATUS[cmd.arm_mode.value]
  if status == nil then
    log.warn("IAS ACE Arm received with unsupported arm mode")
    return
  end

  if pin == nil or pin == "" then
    log.warn("IAS ACE Arm rejected: missing pin or rfid")
    return
  end

  if not is_pin_length_valid(device, pin) then
    log.warn(string.format("IAS ACE Arm rejected: invalid pin length (len=%d)", pin_len))
    return
  end

  local user, auth_type = resolve_user_from_code(device, pin)
  if user == nil then
    device:emit_event(LockCodes.codeChanged(tostring(pin) .. " is not assigned to any user on this keypad. You can create a new user with this code in settings.", { state_change = true }))
    log.warn("IAS ACE Arm rejected: unknown pin or rfid")
    return
  end
  log.error("Dupsko")

  local data = {
    source = "keypad",
    authType = auth_type,
    userIndex = user.index,
    userName = user.name,
  }
  device:set_field("securitySystem_last_user", data, { persist = false })
  if can_process_arm_command(status, get_current_status(device)) then
    if device.preferences.exitDelay == true and status ~= "disarmed" then
      log.error("Twój stary")
      send_panel_status(device, "exitDelay")
      device.thread:call_with_delay(device.preferences.length or 5, function()
        emit_status_event(device, status, data)
        emit_arm_activity(device, status, user.name)
        device:send(IASACE.client.commands.ArmResponse(
          device,
          ARM_MODE_TO_NOTIFICATION[cmd.arm_mode.value] or ArmNotification.ALL_ZONES_DISARMED
        ))
      end)
    else
      emit_status_event(device, status, data)
      emit_arm_activity(device, status, user.name)
      device:send(IASACE.client.commands.ArmResponse(
        device,
        ARM_MODE_TO_NOTIFICATION[cmd.arm_mode.value] or ArmNotification.ALL_ZONES_DISARMED
      ))
    end
  else
    log.info("Arm command ignored: already in target state or incompatible state")
    device:send(IASACE.client.commands.ArmResponse(
      device,
      0xFF
    ))
  end
end

local function handle_get_panel_status(driver, device, zb_rx)
  local length = device.preferences.length or 5
  local status = get_current_status(device)
  device:send(IASACE.client.commands.GetPanelStatusResponse(
    device,
    STATUS_TO_PANEL[status] or PanelStatus.PANEL_DISARMED_READY_TO_ARM,
    length,
    AudibleNotification.DEFAULT_SOUND,
    AlarmStatus.NO_ALARM
  ))
end

local function handle_arm(device, status)
  local length = device.preferences.length or 5
  if not armCommandFromKeypad and can_process_arm_command(status, get_current_status(device)) then
    if device.preferences.exitDelay == true then
      send_panel_status(device, "exitDelay")
      device.thread:call_with_delay(length, function()
        emit_status_event(device, status, { source = "app" })
        emit_arm_activity(device, status, "App")
        send_panel_status(device, status)
      end)
    else
      emit_status_event(device, status, { source = "app" })
      emit_arm_activity(device, status, "App")
      send_panel_status(device, status)
    end
  else
    armCommandFromKeypad = false
    return
  end
  armCommandFromKeypad = false
end

local function handle_arm_away(driver, device, command)
  handle_arm(device, "armedAway")
end

local function handle_arm_stay(driver, device, command)
  handle_arm(device, "armedStay")
end

local function handle_disarm(driver, device, command)
  if can_process_arm_command("disarmed", get_current_status(device)) and not armCommandFromKeypad then
    emit_status_event(device, "disarmed", { source = "app" })
    emit_arm_activity(device, "disarmed", "App")
    send_panel_status(device, "disarmed")
  else
    armCommandFromKeypad = false
    return
  end
  armCommandFromKeypad = false
end

local function refresh(driver, device, command)
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  send_panel_status(device, get_current_status(device))
end

local function device_added(driver, device)
  emit_supported(device)
  if device:get_latest_state("main", SecuritySystem.ID, SecuritySystem.securitySystemStatus.NAME) == nil then
    emit_status_event(device, "disarmed", { source = "driver" })
  end
end

local function do_configure(self, device)
  device:send(device_management.build_bind_request(device, IASACE.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
end

local function device_init(driver, device)
  BATTERY_INIT(driver, device)
  emit_supported(device)
  local base_map = device:get_field("securitySystem_user_map") or LOCAL_USER_MAP
  device:set_field("securitySystem_user_map", base_map, { persist = true })
  sync_lock_codes_from_user_map(device, base_map)
  emit_lock_code_limits(device)
end

local function send_iasace_mfg_write(device, attr_id, data_type, payload)
  local msg = cluster_base.write_manufacturer_specific_attribute(device, IASACE.ID, attr_id, DEVELCO_MANUFACTURER_CODE, data_type, payload)
  msg.body.zcl_header.frame_ctrl:set_direction_client()
  device:send(msg)
end

local function info_changed(driver, device, event, args)
  local base_map = device:get_field("securitySystem_user_map") or LOCAL_USER_MAP
  emit_lock_code_limits(device)
  for name, value in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      if (name == "pinMap") then
        local pin_updates = parse_user_map(device.preferences.pinMap, function(pin)
          if is_pin_length_valid(device, pin) then
            return true
          end
          log.warn(string.format("Ignoring pinMap entry with invalid length (pin=%s)", tostring(pin)))
          return false
        end)
        local map = {
          pins = merge_user_section(base_map and base_map.pins or {}, pin_updates),
          rfids = merge_user_section(base_map and base_map.rfids or {}, {}),
        }
        device:set_field("securitySystem_user_map", map, { persist = true })
        sync_lock_codes_from_user_map(device, map)
      end
      if (name == "rfidMap") then
        local rfid_updates = parse_user_map(device.preferences.rfidMap)
        local map = {
          pins = merge_user_section(base_map and base_map.pins or {}, {}),
          rfids = merge_user_section(base_map and base_map.rfids or {}, rfid_updates),
        }
        device:set_field("securitySystem_user_map", map, { persist = true })
        --sync_lock_codes_from_user_map(device, map)
      end
      if (name == "deletePinMap") then
        local delete_pins = parse_delete_list(device.preferences.deletePinMap)
        for pin, _ in pairs(delete_pins) do
          if base_map.pins[pin] ~= nil then
            base_map.pins[pin] = nil
          end
        end
        device:set_field("securitySystem_user_map", base_map, { persist = true })
        sync_lock_codes_from_user_map(device, base_map)
      end
      if (name == "deleteRfidMap") then
        local delete_rfids = parse_delete_list(device.preferences.deleteRfidMap)
        for rfid, _ in pairs(delete_rfids) do
          if base_map.rfids[rfid] ~= nil then
            base_map.rfids[rfid] = nil
          end
        end
        device:set_field("securitySystem_user_map", base_map, { persist = true })
        --sync_lock_codes_from_user_map(device, base_map)
      end
      if (name == "autoArmDisarmMode") then
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
      elseif (name == "pinLengthSetting") then
        local pinLengthSetting = tonumber(device.preferences.pinLengthSetting)
        if pinLengthSetting ~= nil then
          send_iasace_mfg_write(device, 0x8006, data_types.Uint8, pinLengthSetting)
        end
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

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
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
      },
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      },
    }
  },
  capability_handlers = {
    [SecuritySystem.ID] = {
      [SecuritySystem.commands.armAway.NAME] = handle_arm_away,
      [SecuritySystem.commands.armStay.NAME] = handle_arm_stay,
      [SecuritySystem.commands.disarm.NAME] = handle_disarm,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh,
    },
  },
  can_handle = require("frient-keypad.can_handle"),
}

return frient_keypad
