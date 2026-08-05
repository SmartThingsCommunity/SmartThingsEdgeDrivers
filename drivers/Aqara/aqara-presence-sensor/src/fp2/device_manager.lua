local log = require "log"
local json = require "st.json"
local fields = require "fields"
local capabilities = require "st.capabilities"
local multipleZonePresence = require "multipleZonePresence"

local PresenceSensor = capabilities.presenceSensor
local MovementSensor = capabilities.movementSensor
local ActivitySensor = capabilities.activitySensor
local DeviceMode = capabilities["stse.deviceMode"]

local MOVEMENT_TIMER = "movement_timer"
local MOVEMENT_TIME = 5
local COMP_MODE = "mode"

local device_manager = {}
device_manager.__index = device_manager

local FP2_MODES = { "zoneDetection", "fallDetection", "sleepMonitoring" }

function device_manager.presence_handler(driver, device, zone, evt_value)
  if not device:supports_capability(PresenceSensor) then return end
  local evt_action = "not present"
  if evt_value == 1 then evt_action = "present" end
  device:emit_event(PresenceSensor.presence(evt_action))
end

function device_manager.movement_handler(driver, device, zone, evt_value)
  if not device:supports_capability(MovementSensor) then return end

  local val = evt_value
  local no_movement = function()
    if not device:supports_capability(MovementSensor) then return end
    device:emit_event(MovementSensor.movement("inactive"))
  end
  device:set_field(MOVEMENT_TIMER, device.thread:call_with_delay(MOVEMENT_TIME, no_movement))

  if val == 0 then
    device:emit_event(MovementSensor.movement("entering"))
  elseif val == 1 then
    device:emit_event(MovementSensor.movement("leaving"))
  elseif val == 2 then
    device:emit_event(MovementSensor.movement("enteringLeft"))
  elseif val == 3 then
    device:emit_event(MovementSensor.movement("leavingRight"))
  elseif val == 4 then
    device:emit_event(MovementSensor.movement("enteringRight"))
  elseif val == 5 then
    device:emit_event(MovementSensor.movement("leavingLeft"))
  elseif val == 6 then
    device:emit_event(MovementSensor.movement("approaching"))
  elseif val == 7 then
    device:emit_event(MovementSensor.movement("movingAway"))
  end
end

function device_manager.zone_presence_handler(driver, device, zone, evt_value)
  if not device:supports_capability(capabilities.multipleZonePresence) then return end

  local zoneInfo = multipleZonePresence.findZoneById(driver, device, zone)
  if not zoneInfo then
    multipleZonePresence.createZone(driver, device, "zone" .. zone, zone)
  end
  local evt_action = multipleZonePresence.notPresent
  if evt_value == 1 then evt_action = multipleZonePresence.present end
  multipleZonePresence.changeState(driver, device, zone, evt_action)
  multipleZonePresence.updateAttribute(driver, device)
end

function device_manager.illuminance_handler(driver, device, zone, evt_value)
  device:emit_event(capabilities.illuminanceMeasurement.illuminance(evt_value))
end

function device_manager.work_mode_handler(driver, device, zone, evt_value)
  local cur_mode = device:get_latest_state(COMP_MODE, DeviceMode.ID, DeviceMode.mode.NAME) or 0
  local mode = 1
  local profile_name = "aqara-fp2-zoneDetection"
  if not cur_mode then
    device:emit_component_event(device.profile.components[COMP_MODE], DeviceMode.mode(FP2_MODES[mode]))
    return
  elseif evt_value == 0x03 then
    if cur_mode == FP2_MODES[1] then return end
  elseif evt_value == 0x05 then
    if cur_mode == FP2_MODES[2] then return end
    mode = 2
    profile_name = "aqara-fp2-fallDetection"
  elseif evt_value == 0x09 then
    if cur_mode == FP2_MODES[3] then return end
    mode = 3
    profile_name = "aqara-fp2-sleepMonitoring"
  end
  device:emit_component_event(device.profile.components[COMP_MODE], DeviceMode.mode(FP2_MODES[mode]))
  device:try_update_metadata({ profile = profile_name })
end

function device_manager.zone_quantities_handler(driver, device, zone, evt_value)
  if not device:supports_capability(capabilities.multipleZonePresence) then return end

  for i = 0, 29 do
    local zonePos = tostring(i + 1)
    local zoneInfo = multipleZonePresence.findZoneById(driver, device, zonePos)
    local curStatus = 0x1 & (evt_value >> i)
    if zoneInfo and curStatus == 0 then         -- delete
      multipleZonePresence.deleteZone(driver, device, zonePos)
    elseif not zoneInfo and curStatus == 1 then -- create
      multipleZonePresence.createZone(driver, device, "zone" .. zonePos, zonePos)
      multipleZonePresence.changeState(driver, device, zonePos, multipleZonePresence.notPresent)
    end
  end
  multipleZonePresence.updateAttribute(driver, device)
end

function device_manager.monitoring_mode_handler(driver, device, zone, evt_value)
  if not device:supports_capability(MovementSensor) then return end

  local supportedEnum = { "inactive", "approaching", "movingAway", "entering", "leaving" }
  if evt_value == 0x01 then
    local additional = { "enteringLeft", "enteringRight", "leavingLeft", "leavingRight" }
    table.move(additional, 1, #additional, 4, supportedEnum)
  end

  device:emit_event(MovementSensor.supportedMovements(supportedEnum, { visibility = { displayed = false } }))
end

function device_manager.fall_event_handler(driver, device, zone, evt_value)
  if not device:supports_capability(ActivitySensor) then return end

  local event_name = "noActivity"
  if evt_value == 0x01 then
    event_name = "falling"
  end

  device:emit_event(ActivitySensor.activity(event_name))
end

local resource_id = {
  ["3.51.85"] = { zone = "", event_handler = device_manager.presence_handler },
  ["13.27.85"] = { zone = "", event_handler = device_manager.movement_handler },
  ["3.1.85"] = { zone = "1", event_handler = device_manager.zone_presence_handler },
  ["3.2.85"] = { zone = "2", event_handler = device_manager.zone_presence_handler },
  ["3.3.85"] = { zone = "3", event_handler = device_manager.zone_presence_handler },
  ["3.4.85"] = { zone = "4", event_handler = device_manager.zone_presence_handler },
  ["3.5.85"] = { zone = "5", event_handler = device_manager.zone_presence_handler },
  ["3.6.85"] = { zone = "6", event_handler = device_manager.zone_presence_handler },
  ["3.7.85"] = { zone = "7", event_handler = device_manager.zone_presence_handler },
  ["3.8.85"] = { zone = "8", event_handler = device_manager.zone_presence_handler },
  ["3.9.85"] = { zone = "9", event_handler = device_manager.zone_presence_handler },
  ["3.10.85"] = { zone = "10", event_handler = device_manager.zone_presence_handler },
  ["3.11.85"] = { zone = "11", event_handler = device_manager.zone_presence_handler },
  ["3.12.85"] = { zone = "12", event_handler = device_manager.zone_presence_handler },
  ["3.13.85"] = { zone = "13", event_handler = device_manager.zone_presence_handler },
  ["3.14.85"] = { zone = "14", event_handler = device_manager.zone_presence_handler },
  ["3.15.85"] = { zone = "15", event_handler = device_manager.zone_presence_handler },
  ["3.16.85"] = { zone = "16", event_handler = device_manager.zone_presence_handler },
  ["3.17.85"] = { zone = "17", event_handler = device_manager.zone_presence_handler },
  ["3.18.85"] = { zone = "18", event_handler = device_manager.zone_presence_handler },
  ["3.19.85"] = { zone = "19", event_handler = device_manager.zone_presence_handler },
  ["3.20.85"] = { zone = "20", event_handler = device_manager.zone_presence_handler },
  ["3.21.85"] = { zone = "21", event_handler = device_manager.zone_presence_handler },
  ["3.22.85"] = { zone = "22", event_handler = device_manager.zone_presence_handler },
  ["3.23.85"] = { zone = "23", event_handler = device_manager.zone_presence_handler },
  ["3.24.85"] = { zone = "24", event_handler = device_manager.zone_presence_handler },
  ["3.25.85"] = { zone = "25", event_handler = device_manager.zone_presence_handler },
  ["3.26.85"] = { zone = "26", event_handler = device_manager.zone_presence_handler },
  ["3.27.85"] = { zone = "27", event_handler = device_manager.zone_presence_handler },
  ["3.28.85"] = { zone = "28", event_handler = device_manager.zone_presence_handler },
  ["3.29.85"] = { zone = "29", event_handler = device_manager.zone_presence_handler },
  ["3.30.85"] = { zone = "30", event_handler = device_manager.zone_presence_handler },
  ["0.4.85"] = { zone = "", event_handler = device_manager.illuminance_handler },
  ["14.49.85"] = { zone = "", event_handler = device_manager.work_mode_handler },
  ["14.55.85"] = { zone = "", event_handler = device_manager.monitoring_mode_handler },
  ["4.31.85"] = { zone = "", event_handler = device_manager.fall_event_handler },
  ["200.2.20000"] = { zone = "", event_handler = device_manager.zone_quantities_handler }
}

function device_manager.init_presence(driver, device)
  if device:supports_capability(PresenceSensor)
      and device:get_latest_state("main", PresenceSensor.ID, PresenceSensor.presence.NAME) == nil then
    device:emit_event(PresenceSensor.presence("not present"))
  end
end

function device_manager.init_movement(driver, device)
  if not device:supports_capability(MovementSensor) then return end
  device:emit_event(MovementSensor.movement("inactive"))
end

function device_manager.init_activity(driver, device)
  if not device:supports_capability(ActivitySensor) then return end
  device:emit_event(ActivitySensor.activity("noActivity"))
end

function device_manager.set_zone_info_to_latest_state(driver, device)
  if not device:supports_capability(capabilities.multipleZonePresence) then return end

  local zoneInfoTable = device:get_latest_state("main", capabilities.multipleZonePresence.ID,
    capabilities.multipleZonePresence.zoneState.NAME, {})
  multipleZonePresence.setZoneInfo(driver, device, zoneInfoTable)
end

function device_manager.handle_status(driver, device, status)
  if not status then
    log.warn("device_manager.handle_status : status is nil")
    return
  end

  for k, _ in pairs(status) do
    if resource_id[k] then
      resource_id[k].event_handler(driver, device, resource_id[k].zone, tonumber(status[k]))
    else
      log.warn("device_manager.handle_status : resource id status is nil")
    end
  end
end

function device_manager.update_status(driver, device)
  local conn_info = device:get_field(fields.CONN_INFO)

  if not conn_info then
    log.warn(string.format("device_manager.update_status : failed to find conn_info, dni = %s",
      device.device_network_id))
    return
  end

  local _, err, status = conn_info:get_attr()

  if err or status ~= 200 then
    log.error(string.format("device_manager.update_status : failed to get status, dni= %s, err= %s, status= %s",
      device.device_network_id, err, status))
    if status == 404 then
      device:offline()
    end
    return
  end
end

local sse_event_handlers = {
  ["message"] = device_manager.handle_status
}

function device_manager.handle_sse_event(driver, device, event_type, data)
  local _, device_json = pcall(json.decode, data)

  local event_handler = sse_event_handlers[event_type]
  if event_handler and device_json then
    event_handler(driver, device, device_json)
  else
    log.error(string.format("handle_sse_event : unknown event type. dni = %s, event_type = '%s'",
      device.device_network_id, event_type))
  end
end

function device_manager.is_valid_connection(driver, device, conn_info)
  if not conn_info then
    log.warn(string.format("device_manager.is_valid_connection : failed to find conn_info, dni = %s",
      device.device_network_id))
    return false
  end

  local _, err, status = conn_info:get_attr()
  if err or status ~= 200 then
    log.warn(string.format(
      "device_manager.is_valid_connection : failed to connect to device, dni = %s, err= %s, status= %s",
      device.device_network_id, err, status))
    return false
  end

  return true
end

function device_manager.device_monitor(driver, device, device_info)
  device_manager.update_status(driver, device)
end

function device_manager.get_sse_url(driver, device, conn_info)
  return conn_info:get_sse_url()
end

return device_manager
