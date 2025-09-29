local api_version = require("version").api
local capabilities = require "st.capabilities"

local cosock = require "cosock"
local log = require "log"
local utils = require "utils"
local PlayerFields = require "fields".SonosPlayerFields

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
  local event, err =
    capabilities.emit_event(device, component.id, device.capability_channel, capability_event)
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

  if api_version >= 14 and not driver:has_received_startup_state() then
    device.log.debug("Driver startup state not yet received, delaying initialization of device.")
    driver:queue_device_init_for_startup_state(device)
    return
  end

  -- spawn a task to handle initialization to avoid blocking the main driver or device
  -- threads, as this may involve long-yielding operations.
  cosock.spawn(
    function()
      local mac_addr = device.device_network_id
      local player_info_tx, player_info_rx = cosock.channel.new()
      while true do
        if driver.ssdp_task then
          driver.ssdp_task:get_player_info(player_info_tx, mac_addr)
          local recv_ready, _, select_err = cosock.socket.select({ player_info_rx }, nil, nil)

          if type(recv_ready) == "table" and recv_ready[1] == player_info_rx then
            local info, recv_err = player_info_rx:receive()
            if not info then
              device.log.warn(string.format("error receiving device info: %s", recv_err))
            else
              ---@cast info { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo, force_refresh: boolean }
              local auth_success, api_key_or_err = driver:check_auth(info)
              if not auth_success then
                device:offline()
                if auth_success == false and api_version >= 14 then
                  local token_event_receive = driver:oauth_token_event_subscribe()
                  if not token_event_receive then
                    log.error("token event bus closed, aborting initialization")
                    return
                  end
                  token_event_receive:settimeout(30)
                  local token, token_recv_err
                  -- max 30 mins
                  local backoff_builder = utils.backoff_builder(60 * 30, 30, 2)
                  driver:alert_unauthorized()

                  local backoff_timer = nil
                  while not token do
                    -- we use the backoff to create a timer and utilize a select loop here, instead of
                    -- utilizing a sleep, so that we can create a long delay on our polling of the cloud
                    -- without putting ourselves in a situation where we're sleeping for an extended period
                    -- of time so that we don't sleep through the users's log-in attempt and fail to resume
                    -- our connection attempts in a timely manner.
                    --
                    -- The backoff caps at 30 mins, as commented above
                    if not backoff_timer then
                      backoff_timer = cosock.timer.create_oneshot(backoff_builder())
                    end
                    local token_recv_ready, _, token_select_err =
                      cosock.socket.select({ token_event_receive, backoff_timer }, nil, nil)

                    if token_select_err then
                      log.warn(string.format("select error: %s", token_select_err))
                    end

                    token, token_recv_err = nil, nil
                    for _, receiver in pairs(token_recv_ready or {}) do
                      if receiver == backoff_timer then
                        -- we just make a note that the backoff has elapsed, rather than
                        -- put a request in flight immediately.
                        --
                        -- This is just in case both receivers are ready, so that we can prioritize
                        -- handling the token instead of putting another request in flight.
                        backoff_timer:handled()
                        backoff_timer = nil
                      end

                      if receiver == token_event_receive then
                        token, token_recv_err = token_event_receive:receive()
                      end
                    end

                    if token_recv_err == "timeout" then
                      log.debug("timeout waiting for OAuth token in reconnect task")
                    elseif token_recv_err and not token then
                      log.warn(
                        string.format(
                          "Unexpected error on token event receive bus: %s",
                          token_recv_err
                        )
                      )
                    end
                  end
                else
                  device.log.error(
                    string.format(
                      "error while checking authentication: %s, marking device offline",
                      api_key_or_err
                    )
                  )
                end
              else
                local success, error, error_code =
                  driver:handle_player_discovery_info(api_key_or_err, info, device)
                if success then
                  return
                end
                log.error_with(
                  { hub_logs = false },
                  string.format(
                    "Error handling Sonos player initialization: %s, error code: %s",
                    error,
                    (error_code or "N/A")
                  )
                )
              end
            end
          else
            device.log.warn(
              string.format("select error waiting for initialization device info: %s", select_err)
            )
          end
        else
          device.log.error_with(
            { hub_logs = true },
            string.format("Driver wasn't able to spin up SSDP task, cannot initialize devices.")
          )
        end
      end
    end,
    string.format(
      "%s initialization task",
      (device and (device.label or device.id) or "<unknown device>")
    )
  )
end

---@param driver SonosDriver
---@param device SonosDevice
---@param event "INIT"|"ADDED"
---@param _args table?
function SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event(
  driver,
  device,
  event,
  _args
)
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
  driver.sonos:remove_device_record_association(device)
  driver.dni_to_device_id[device.device_network_id] = nil
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  if sonos_conn and sonos_conn:is_running() then
    sonos_conn:stop()
  end
end

SonosDriverLifecycleHandlers.added = SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event
SonosDriverLifecycleHandlers.init = SonosDriverLifecycleHandlers.handle_initialize_lifecycle_event

return SonosDriverLifecycleHandlers
