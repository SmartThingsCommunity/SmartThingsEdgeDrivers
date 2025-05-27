local capabilities = require "st.capabilities"

local cosock = require "cosock"
local log = require "log"
local utils = require "utils"
local PlayerFields = require "fields".SonosPlayerFields
local SonosConnection = require "api.sonos_connection"

---@class SonosDriverLifecycleHandlers
local SonosDriverLifecycleHandlers = {}

local function emit_component_event_no_cache(device, component, capability_event)
  if not device:supports_capability(capability_event.capability, component.id) then
    local err_msg = string.format(
      "Attempted to generate event for %s.%s but it does not support capability %s",
      device.id,
      component.id,
      capability_event.capability.NAME
    )
    log.warn_with({ hub_logs = true }, err_msg)
    return false, err_msg
  end
  local event, err = capabilities.emit_event(device, component.id, device.capability_channel, capability_event)
  if err ~= nil then
    log.warn_with({ hub_logs = true }, err)
  end
  return event, err
end

---@param driver SonosDriver
---@param device SonosDevice
function SonosDriverLifecycleHandlers.initialize_device(driver, device)
  if
    not (
      driver:get_device_by_dni(device.device_network_id)
      and driver:get_device_by_dni(device.device_network_id).id == device.id
    )
  then
    driver.dni_to_device_id[device.device_network_id] = device.id
  end
  if not device:get_field(PlayerFields._IS_SCANNING) then
    device.log.debug("Starting Scan in _initialize_device for %s", device.label)
    device:set_field(PlayerFields._IS_SCANNING, true)
    cosock.spawn(function()
      if not device:get_field(PlayerFields._IS_INIT) then
        log.trace(string.format("%s setting up device", device.label))
        local is_already_found = (
          (driver.found_ips and driver.found_ips[device.device_network_id])
          or driver.sonos:is_player_joined(device.device_network_id)
        ) and driver._field_cache[device.device_network_id]

        if not is_already_found then
          device.log.debug(
            string.format("Rescanning for player with DNI %s", device.device_network_id)
          )
          device:offline()
          local success = false

          local backoff = utils.backoff_builder(360, 1)
          while not success do
            success = driver:find_player_for_device(device)
            if not success then
              device.log.warn_with(
                { hub_logs = true },
                string.format(
                  "Couldn't find Sonos Player [%s] during SSDP scan, trying again shortly",
                  device.label
                )
              )
              cosock.socket.sleep(backoff())
            end
          end
        end

        device.log.trace("Setting persistent fields")
        local fields = driver._field_cache[device.device_network_id]
        driver:update_fields_from_ssdp_scan(device, fields)

        device:set_field(PlayerFields._IS_INIT, true)
      end

      local sonos_conn = device:get_field(PlayerFields.CONNECTION) --- @type SonosConnection

      if not sonos_conn then
        log.trace("Setting transient fields")
        -- device is offline until the websocket connection is established
        device:offline()
        sonos_conn = SonosConnection.new(driver, device)
        device:set_field(PlayerFields.CONNECTION, sonos_conn)
      end

      if not sonos_conn:is_running() then
        -- device is offline until the websocket connection is established
        device:offline()
        sonos_conn:start()
      else
        sonos_conn:refresh_subscriptions()
      end
    end, string.format("%s device init and SSDP scan", device.label))
  end
end

---@param driver SonosDriver
---@param device SonosDevice
---@param event "INIT"|"ADDED"
---@param _args table?
function SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event(driver, device, event, _args)
  device.log.trace(string.format("handling lifecycle event %s", event))
  SonosDriverLifecycleHandlers.initialize_device(driver, device)

  -- Remove usage of the state cache for sonos devices to avoid large datastores
  device:set_field("__state_cache", nil, { persist = true })
  device:extend_device("emit_component_event", emit_component_event_no_cache)

  device:emit_event(capabilities.mediaPlayback.supportedPlaybackCommands({
    capabilities.mediaPlayback.commands.play.NAME,
    capabilities.mediaPlayback.commands.pause.NAME,
    capabilities.mediaPlayback.commands.stop.NAME,
  }))

  device:emit_event(capabilities.mediaTrackControl.supportedTrackControlCommands({
    capabilities.mediaTrackControl.commands.nextTrack.NAME,
    capabilities.mediaTrackControl.commands.previousTrack.NAME,
  }))
end

---@param driver SonosDriver
---@param device SonosDevice
function SonosDriverLifecycleHandlers.removed(driver, device)
  log.trace(string.format("%s device removed", device.label))
  driver.dni_to_device_id[device.device_network_id] = nil
  local player_id = device:get_field(PlayerFields.PLAYER_ID)
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  if sonos_conn and sonos_conn:is_running() then
    sonos_conn:stop()
  end
  driver.sonos:mark_player_as_removed(device:get_field(PlayerFields.PLAYER_ID))
  driver._player_id_to_device[player_id] = nil
end

SonosDriverLifecycleHandlers.added = SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event
SonosDriverLifecycleHandlers.init = SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event

return SonosDriverLifecycleHandlers
