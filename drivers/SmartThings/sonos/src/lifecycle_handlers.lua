local capabilities = require "st.capabilities"

local cosock = require "cosock"
local log = require "log"
local utils = require "utils"
local PlayerFields = require "fields".SonosPlayerFields

---@class SonosDriverLifecycleHandlers
local SonosDriverLifecycleHandlers = {}

local function emit_component_event_no_cache(device, component, capability_event)
  if not device:supports_capability(capability_event.capability, component.id) then
    local err_msg = string.format("Attempted to generate event for %s.%s but it does not support capability %s",
      device.id, component.id, capability_event.capability.NAME)
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

  if not driver:has_received_startup_state() then
    device.log.debug("Driver startup state not yet received, delaying initialization of device.")
    driver:queue_device_init_for_startup_state(device)
    return
  end

  -- spawn a task to handle initialization to avoid blocking the main driver or device
  -- threads, as this may involve long-yielding operations.
  cosock.spawn(function()
    device.log.debug("top of init loop")
    local mac_addr = device.device_network_id
    local player_info_tx, player_info_rx = cosock.channel.new()
    while true do
      device.log.debug("sending player info request")
      driver.ssdp_task:get_player_info(player_info_tx, mac_addr)
      device.log.debug("selecton on player info receive")
      local recv_ready, _, select_err = cosock.socket.select({ player_info_rx }, nil, nil)
      device.log.debug("select done")

      if type(recv_ready) == "table" and recv_ready[1] == player_info_rx then
        device.log.debug("player info receive")
        local info, recv_err = player_info_rx:receive()
        if not info then
          device.log.warn(string.format("error receiving device info: %s", recv_err))
        else
          ---@cast info { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo, force_refresh: boolean }
          local success, error, error_code = driver:handle_player_discovery_info(info, device)
          if not success then
            device.log.error(string.format("initialization error: %s, marking device offline. Error code: %s", error,
              (error_code or "N/A")))
            device:offline()
            if error_code == "ERROR_NOT_AUTHORIZED" then
              local token_event_receive = driver:oauth_token_event_subscribe()
              if not token_event_receive then
                log.error("token event bus closed, aborting initialization")
                return
              end
              local security_result, security_err = driver:request_oauth_token()
              log.debug(string.format("security request result: %s, security request error: %s", security_result,
                security_err))

              local receive, receive_err = token_event_receive:receive()
              log.debug(string.format("token event result: %s, security request error: %s", receive, receive_err))
            end
          end
          return
        end
      else
        device.log.warn(string.format("select error waiting for initialization device info: %s", select_err))
      end
    end
  end, string.format("%s initialization task", (device and (device.label or device.id) or "<unknown device>")))
end

---@param driver SonosDriver
---@param device SonosDevice
---@param event "INIT"|"ADDED"
---@param _args table?
function SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event(driver, device, event, _args)
  device.log.trace(string.format("handling lifecycle event %s", event))
  local field_changed = utils.update_field_if_changed(device, PlayerFields._IS_INIT, true)
  if field_changed then
    device.log.trace("initializing device in response to lifecycle event")
    SonosDriverLifecycleHandlers.initialize_device(driver, device)
  end
end

---@param driver SonosDriver
---@param device SonosDevice
function SonosDriverLifecycleHandlers.removed(driver, device)
  log.trace(string.format("%s device removed", device.label))
  driver.dni_to_device_id[device.device_network_id] = nil
  local player_id = device:get_field(PlayerFields.PLAYER_ID)
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  if sonos_conn and sonos_conn:is_running() then sonos_conn:stop() end
  driver.sonos:remove_device_record_association(device)
end

SonosDriverLifecycleHandlers.added = SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event
SonosDriverLifecycleHandlers.init = SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event

return SonosDriverLifecycleHandlers
