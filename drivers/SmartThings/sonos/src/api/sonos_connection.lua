local api_version = require "version".api
local cosock = require "cosock"
local json = require "st.json"
local log = require "log"
local st_utils = require "st.utils"

local lb_utils = require "lunchbox.util"

local EventHandlers = require "api.event_handlers"
local PlayerFields = require "fields".SonosPlayerFields
local Router = require "api.sonos_websocket_router"
local SonosApi = require "api"
local SonosRestApi = require "api.rest"
local utils = require "utils"

--- A class-like lua module that allows for instantiation of a SonosConnection
--- table providing an abstraction layer above the concept of a Sonos websocket connection.
--- The reason for this abstraction is because of the fact that when a Sonos speaker is part
--- of a group, certain messages can be sent to the player directly but others must be sent
--- to a player's "coordinator" device. This abstracts those concerns away from the user,
--- providing an opaque "connection" interface for sending and listening on messages from
--- the speaker itself as well as its coordinator in the event that a player is not
--- its own coordinator.
--- @class SonosConnection
--- @field public driver SonosDriver reference to the Edge Driver
--- @field public device SonosDevice the player for this connection
--- @field package _self_listener_uuid string
--- @field package _coord_listener_uuid string
--- @field package _initialized boolean
--- @field package _reconnecting boolean if a reconnect task is active
--- @field package on_message fun(...)?
--- @field package on_error fun(...)?
--- @field package on_close fun(...)?
local SonosConnection = {}
SonosConnection.__index = SonosConnection

local self_subscriptions = { "groups", "playerVolume", "audioClip" }
local coordinator_subscriptions = { "groupVolume", "playback", "favorites", "playbackMetadata" }
local favorites_version = ""

--- Update subscriptions by constructing Sonos JSON payloads for sending. Sonos
--- commands are JSON that take the form of a 2-element array where the first index is the header
--- and the second index is the body. Hence the empty table in the second position.
---
--- https://developer.sonos.com/reference/control-api-examples-lan/
---@param sonos_conn SonosConnection
---@param namespaces string[]
---@param command "subscribe"|"unsubscribe"
local _update_subscriptions_helper = function(
  sonos_conn,
  householdId,
  playerId,
  groupId,
  namespaces,
  command,
  reply_tx
)
  for _, namespace in ipairs(namespaces) do
    local wss_msg_header = {
      namespace = namespace,
      command = command,
      householdId = householdId,
      groupId = groupId,
      playerId = playerId,
    }
    local maybe_token, err = sonos_conn.driver:get_oauth_token()
    if err then
      log.warn(string.format("notice: get_oauth_token -> %s", err))
    end

    if maybe_token then
      wss_msg_header.authorization = string.format("Bearer %s", maybe_token.accessToken)
    end
    local payload_table = {
      wss_msg_header,
      {},
    }
    local payload = json.encode(payload_table)
    local unique_key, bad_key_part = utils.sonos_unique_key(householdId, playerId)
    if not unique_key then
      local err_msg = string.format("Invalid Sonos Unique Key Part: %s", bad_key_part)
      if reply_tx then
        reply_tx:send(table.pack(nil, err_msg))
      else
        log.warn(string.format("Update Subscriptions Error: %s", err_msg))
      end
      return
    end
    Router.send_message_to_player(unique_key, payload, reply_tx)
  end
end

---@param sonos_conn SonosConnection
---@param namespaces string[]
---@param command "subscribe"|"unsubscribe"
local _update_self_subscriptions = function(sonos_conn, namespaces, command, reply_tx)
  local householdId = sonos_conn.device:get_field(PlayerFields.HOUSEHOLD_ID)
  local _, playerId = sonos_conn.driver.sonos:get_player_for_device(sonos_conn.device)
  local _, groupId = sonos_conn.driver.sonos:get_group_for_device(sonos_conn.device)
  _update_subscriptions_helper(
    sonos_conn,
    householdId,
    playerId,
    groupId,
    namespaces,
    command,
    reply_tx
  )
end

---@param sonos_conn SonosConnection
---@param namespaces string[]
---@param command "subscribe"|"unsubscribe"
local _update_coordinator_subscriptions = function(sonos_conn, namespaces, command, reply_tx)
  local householdId = sonos_conn.device:get_field(PlayerFields.HOUSEHOLD_ID)
  local _, coordinatorId = sonos_conn.driver.sonos:get_coordinator_for_device(sonos_conn.device)
  local _, groupId = sonos_conn.driver.sonos:get_group_for_device(sonos_conn.device)
  _update_subscriptions_helper(
    sonos_conn,
    householdId,
    coordinatorId,
    groupId,
    namespaces,
    command,
    reply_tx
  )
end

---@param sonos_conn SonosConnection
---@param household_id HouseholdId
---@param self_player_id PlayerId
---@param api_key string
local function _open_coordinator_socket(sonos_conn, household_id, self_player_id, api_key)
  log.debug("Open coordinator socket for: " .. sonos_conn.device.label)
  local _, coordinator_id, err =
    sonos_conn.driver.sonos:get_coordinator_for_device(sonos_conn.device)
  if err ~= nil then
    log.error(
      string.format(
        "Could not look up coordinator info for player %s: %s",
        sonos_conn.device.label,
        err
      )
    )
    return
  end

  if coordinator_id ~= self_player_id then
    local household = sonos_conn.driver.sonos:get_household(household_id)
    if household == nil then
      log.error(
        string.format("Cannot open coordinator socket, houshold doesn't exist: %s", household_id)
      )
      return
    end

    local coordinator = household.players[coordinator_id]
    if coordinator == nil then
      log.error(
        st_utils.stringify_table(
          { household = sonos_conn.driver.sonos:get_household(household_id) },
          string.format("Coordinator doesn't exist for player: %s", sonos_conn.device.label),
          false
        )
      )
      return
    end

    _, err =
      Router.open_socket_for_player(household_id, coordinator_id, coordinator.websocketUrl, api_key)
    if err ~= nil then
      log.error(
        string.format(
          "Couldn't open connection to coordinator for %s: %s",
          sonos_conn.device.label,
          err
        )
      )
      return
    end

    local listener_id
    local unique_key, bad_key_part = utils.sonos_unique_key(household_id, coordinator_id)

    if not unique_key then
      log.error(string.format("Invalid Sonos Unique Key Part: %s", bad_key_part))
    end

    listener_id, err = Router.register_listener_for_socket(sonos_conn, unique_key)
    if err ~= nil or not listener_id then
      log.error(err)
    else
      sonos_conn._coord_listener_uuid = listener_id
    end
  end
end

--TODO remove function in favor of "st.utils" function once
--all hubs have 0.46 firmware
local function backoff_builder(max, inc, rand)
  local count = 0
  inc = inc or 1
  return function()
    local randval = 0
    if rand then
      --- We use this pattern because the version of math.random()
      --- that takes a range only works for integer values and we
      --- want floating point.
      randval = math.random() * rand * 2 - rand
    end

    local base = inc * (2 ^ count - 1)
    count = count + 1

    -- ensure base backoff (not including random factor) is less than max
    if max then
      base = math.min(base, max)
    end

    -- ensure total backoff is >= 0
    return math.max(base + randval, 0)
  end
end

---@param sonos_conn SonosConnection
local function _legacy_reconnect_task(sonos_conn)
  log.debug("Spawning reconnect task for ", sonos_conn.device.label)
  cosock.spawn(function()
    local backoff = backoff_builder(60, 1, 0.1)
    while not sonos_conn:is_running() do
      local start_success = sonos_conn:start()
      if start_success then
        sonos_conn._reconnecting = false
        return
      end
      cosock.socket.sleep(backoff())
    end
    sonos_conn._reconnecting = false
  end, string.format("%s Reconnect Task", sonos_conn.device.label))
end

---@param sonos_conn SonosConnection
local function _oauth_reconnect_task(sonos_conn)
  log.debug("Spawning reconnect task for ", sonos_conn.device.label)
  local check_auth = sonos_conn.driver:check_auth(sonos_conn.device)
  local unauthorized = (check_auth == false)
  if unauthorized and not sonos_conn.driver:is_waiting_for_oauth_token() then
    sonos_conn.driver:request_oauth_token()
  end
  local token_receive_handle, err = sonos_conn.driver:oauth_token_event_subscribe()
  if not token_receive_handle then
    log.warn(string.format("error creating oauth token receive handle for respawn task: %s", err))
  end
  cosock.spawn(function()
    local backoff = backoff_builder(60, 1, 0.1)
    while not sonos_conn:is_running() do
      if sonos_conn.driver:is_waiting_for_oauth_token() and token_receive_handle then
        local token, channel_error = token_receive_handle:receive()
        if not token then
          log.warn(string.format("Error requesting token: %s", channel_error))
          local _, get_token_err = sonos_conn.driver:get_oauth_token()
          if get_token_err then
            log.warn(string.format("notice: get_oauth_token -> %s", get_token_err))
          end
        end
      else
        local start_success = sonos_conn:start()
        if start_success then
          sonos_conn._reconnecting = false
          return
        end
      end

      check_auth = sonos_conn.driver:check_auth(sonos_conn.device)
      unauthorized = (check_auth == false)

      if unauthorized and not sonos_conn.driver:is_waiting_for_oauth_token() then
        sonos_conn.driver:request_oauth_token()
      end
      cosock.socket.sleep(backoff())
    end
    sonos_conn._reconnecting = false
  end, string.format("%s Reconnect Task", sonos_conn.device.label))
end

---@param sonos_conn SonosConnection
local function _spawn_reconnect_task(sonos_conn)
  if sonos_conn._reconnecting then
    return
  end
  sonos_conn._reconnecting = true
  if type(api_version) == "number" and api_version >= 14 then
    _oauth_reconnect_task(sonos_conn)
  else
    _legacy_reconnect_task(sonos_conn)
  end
end

--- Create a new Sonos connection to manage the given device
--- @param driver SonosDriver
--- @param device SonosDevice
--- @return SonosConnection
function SonosConnection.new(driver, device)
  log.debug(string.format("Creating new SonosConnection for %s", device.label))
  local self = setmetatable(
    { driver = driver, device = device, _listener_uuids = {}, _initialized = false, _reconnecting = false },
    SonosConnection
  )

  -- capture the label here in case something goes wonky like a callback being fired after a
  -- device is removed
  local device_name = device.label
  self.on_message = function(_, msg)
    log.debug(string.format("OnMessage for %s", device_name))
    if msg.data then
      log.debug(string.format("Message for %s has data", device_name))
      local json_result = table.pack(pcall(json.decode, msg.data))
      local success = table.remove(json_result, 1)
      if not success then
        log.error(
          st_utils.stringify_table(
            { response_body = msg.data, json = json_result },
            "Couldn't decode JSON in WebSocket callback:",
            false
          )
        )
        return
      end
      local header, body = table.unpack(table.unpack(json_result))
      if header.type == "globalError" then
        if body.errorCode == "ERROR_NOT_AUTHORIZED" then
          if api_version < 14 then
            log.error(
              "Unable to authenticate Sonos WebSocket Connection, and current API does not support Sonos OAuth"
            )
            self:stop()
          else
            local household_id, player_id = driver.sonos:get_player_for_device(device)
            device.log.warn(
              string.format("WebSocket connection no longer authorized, disconnecting")
            )
            local _, security_err = driver:request_oauth_token()
            if security_err then
              log.warn(string.format("Error during request for oauth token: %s", security_err))
            end
            -- closing the socket directly without calling `:stop()` triggers the reconnect loop,
            -- which is where we wait for the token to come in.
            local unique_key, bad_key_part = utils.sonos_unique_key(household_id, player_id)
            if not unique_key then
              log.error(string.format("Invalid Sonos Unique Key Part: %s", bad_key_part))
            else
              Router.close_socket_for_player(unique_key)
            end
          end
        end
      elseif header.type == "groups" then
        log.trace(string.format("Groups type message for %s", device_name))
        local household_id, current_coordinator =
          self.driver.sonos:get_coordinator_for_device(self.device)
        local _, player_id = self.driver.sonos:get_player_for_device(self.device)
        self.driver.sonos:update_household_info(header.householdId, body, self.device)
        self.driver.sonos:update_device_record_from_state(header.householdId, self.device)
        local _, updated_coordinator = self.driver.sonos:get_coordinator_for_device(self.device)

        Router.cleanup_unused_sockets(self.driver)

        if not self:coordinator_running() then
          --TODO this is not infallible
          _open_coordinator_socket(self, household_id, player_id)
        end

        if current_coordinator ~= updated_coordinator then
          self:refresh_subscriptions()
        end
      elseif header.type == "playerVolume" then
        log.trace(string.format("PlayerVolume type message for %s", device_name))
        local player_id = self.device:get_field(PlayerFields.PLAYER_ID)
        if player_id == header.playerId and body.volume and (body.muted ~= nil) then
          EventHandlers.handle_player_volume(self.device, body.volume, body.muted)
        end
      elseif header.type == "audioClipStatus" then
        log.trace(string.format("AudioClipStatus type message for %s", device_name))
        local player_id = self.device:get_field(PlayerFields.PLAYER_ID)
        if player_id == header.playerId then
          EventHandlers.handle_audio_clip_status(self.device, body.audioClips)
        end
      elseif header.type == "groupVolume" then
        log.trace(string.format("GroupVolume type message for %s", device_name))
        if body.volume and (body.muted ~= nil) then
          local household = self.driver.sonos:get_household(header.householdId)
          if household == nil or household.groups == nil then
            log.error(
              st_utils.stringify_table(
                { response_body = msg.data, household = household or header.householdId },
                "Received groupVolume message for non-existent household or household groups dont exist",
                false
              )
            )
            return
          end
          local group = household.groups[header.groupId] or { playerIds = {} }
          for _, player_id in ipairs(group.playerIds) do
            local device_for_player = self.driver:device_for_player(header.householdId, player_id)
            --- we've seen situations where these messages can be processed while a device
            --- is being deleted so we check for the presence of emit event as a proxy for
            --- whether or not this device is currently capable of emitting events.
            if device_for_player and device_for_player.emit_event then
              EventHandlers.handle_group_volume(device_for_player, body.volume, body.muted)
            end
          end
        end
      elseif header.type == "playbackStatus" then
        log.trace(string.format("PlaybackStatus type message for %s", device_name))
        local household = self.driver.sonos:get_household(header.householdId)
        if household == nil or household.groups == nil then
          log.error(
            st_utils.stringify_table(
              { response_body = msg.data, household = household or header.householdId },
              "Received playbackStatus message for non-existent household or household groups dont exist",
              false
            )
          )
          return
        end
        local group = household.groups[header.groupId] or { playerIds = {} }
        for _, player_id in ipairs(group.playerIds) do
          local device_for_player = self.driver:device_for_player(header.householdId, player_id)
          --- we've seen situations where these messages can be processed while a device
          --- is being deleted so we check for the presence of emit event as a proxy for
          --- whether or not this device is currently capable of emitting events.
          if device_for_player and device_for_player.emit_event then
            EventHandlers.handle_playback_status(device_for_player, body.playbackState)
          end
        end
      elseif header.type == "metadataStatus" then
        log.trace(string.format("MetadataStatus type message for %s", device_name))
        local household = self.driver.sonos:get_household(header.householdId)
        if household == nil or household.groups == nil then
          log.error(
            st_utils.stringify_table(
              { response_body = msg.data, household = household or header.householdId },
              "Received metadataStatus message for non-existent household or household groups dont exist",
              false
            )
          )
          return
        end
        local group = household.groups[header.groupId] or { playerIds = {} }
        for _, player_id in ipairs(group.playerIds) do
          local device_for_player = self.driver:device_for_player(header.householdId, player_id)
          --- we've seen situations where these messages can be processed while a device
          --- is being deleted so we check for the presence of emit event as a proxy for
          --- whether or not this device is currently capable of emitting events.
          if device_for_player and device_for_player.emit_event then
            EventHandlers.handle_playback_metadata_update(device_for_player, body)
          end
        end
      elseif header.namespace == "favorites" and header.type == "versionChanged" then
        log.trace(string.format("Favorites VersionChanged type message for %s", device_name))
        if body.version ~= favorites_version then
          favorites_version = body.version

          local household = self.driver.sonos:get_household(header.householdId) or { groups = {} }

          for group_id, group in pairs(household.groups) do
            local coordinator_id =
              self.driver.sonos:get_coordinator_for_group(header.householdId, group_id)
            local coordinator_player = household.players[coordinator_id]
            if coordinator_player == nil then
              log.error(
                st_utils.stringify_table(
                  { household = household, coordinator_id = coordinator_id },
                  "Received message for non-existent coordinator player",
                  false
                )
              )
              return
            end

            local url_ip = lb_utils.force_url_table(coordinator_player.websocketUrl).host
            local base_url = lb_utils.force_url_table(
              string.format("https://%s:%s", url_ip, SonosApi.DEFAULT_SONOS_PORT)
            )
            local _, api_key = driver:check_auth(device)
            local maybe_token = driver:get_oauth_token()
            local headers = SonosApi.make_headers(api_key, maybe_token and maybe_token.accessToken)
            local favorites_response, err, _ =
              SonosRestApi.get_favorites(base_url, header.householdId, headers)

            if err or not favorites_response then
              log.error("Error querying for favorites: " .. err)
            else
              local new_favorites = {}
              for _, favorite in ipairs(favorites_response.items or {}) do
                local new_item = { id = favorite.id, name = favorite.name }
                if favorite.imageUrl then
                  new_item.imageUrl = favorite.imageUrl
                end
                if favorite.service and favorite.service.name then
                  new_item.mediaSource = favorite.service.name
                end
                table.insert(new_favorites, new_item)
              end
              self.driver.sonos:update_household_favorites(header.householdId, new_favorites)

              for _, player_id in ipairs(group.playerIds) do
                local device_for_player =
                  self.driver:device_for_player(header.householdId, player_id)
                --- we've seen situations where these messages can be processed while a device
                --- is being deleted so we check for the presence of emit event as a proxy for
                --- whether or not this device is currently capable of emitting events.
                if device_for_player and device_for_player.emit_event then
                  EventHandlers.update_favorites(device_for_player, new_favorites)
                end
              end
            end
          end
        end
      end
    else
      log.warn(
        string.format(
          "WebSocket Message for %s did not have a data payload: %s",
          device_name,
          st_utils.stringify_table(msg)
        )
      )
    end
  end

  self.on_error = function(_, err)
    log.error(err or ("unknown websocket error for " .. (self.device.label or "unknown device")))
  end

  self.on_close = function(_)
    log.debug(string.format("OnClose for %s", device_name))
    if self._initialized then
      self.device:offline()
    end
    if self._keepalive then
      _spawn_reconnect_task(self)
    end
  end

  return self
end

--- Whether or not the connection has all of the live websocket connections it needs to function
--- @return boolean
function SonosConnection:is_running()
  local self_running = self:self_running()
  local coord_running = self:coordinator_running()
  log.debug(
    string.format(
      "%s all connections running? %s",
      self.device.label,
      st_utils.stringify_table({ coordinator = self_running, mine = self_running })
    )
  )
  return self_running and coord_running
end

--- Whether or not the connection has a live websocket connection
--- @return boolean
function SonosConnection:self_running()
  local household_id = self.device:get_field(PlayerFields.HOUSEHOLD_ID)
  local player_id = self.device:get_field(PlayerFields.PLAYER_ID)
  local unique_key, bad_key_part = utils.sonos_unique_key(household_id, player_id)
  if bad_key_part then
    self.device.log.warn(
      string.format(
        "Bad Unique Key Part While Inspecting Connections in 'self_running': %s",
        bad_key_part
      )
    )
  end
  return type(unique_key) == "string" and Router.is_connected(unique_key) and self._initialized
end

--- Whether or not the connection has a live websocket connection to its coordinator
--- @return boolean
function SonosConnection:coordinator_running()
  local household_id, coordinator_id = self.driver.sonos:get_coordinator_for_device(self.device)
  local unique_key, bad_key_part = utils.sonos_unique_key(household_id, coordinator_id)
  if bad_key_part then
    self.device.log.warn(
      string.format(
        "Bad Unique Key Part While Inspecting Connections in 'coordinator_running': %s",
        bad_key_part
      )
    )
  end
  return type(unique_key) == "string" and Router.is_connected(unique_key) and self._initialized
end

function SonosConnection:refresh_subscriptions(maybe_reply_tx)
  log.debug("Refresh subscriptions on " .. self.device.label)
  _update_self_subscriptions(self, self_subscriptions, "subscribe")
  _update_coordinator_subscriptions(self, coordinator_subscriptions, "subscribe")
  if maybe_reply_tx then
    maybe_reply_tx:send("success")
  end
end

--- Send a Sonos command object to the player for this connection
--- @param cmd SonosCommand
--- @param use_coordinator boolean
function SonosConnection:send_command(cmd, use_coordinator)
  log.debug("Sending command over websocket channel for device " .. self.device.label)
  local household_id, target_id
  if use_coordinator then
    household_id, target_id = self.driver.sonos:get_coordinator_for_device(self.device)
  else
    household_id, target_id = self.driver.sonos:get_player_for_device(self.device)
  end
  local json_payload, err = json.encode(cmd)

  if err or not json_payload then
    log.error("Json encoding error: " .. err)
  else
    local unique_key, bad_key_part = utils.sonos_unique_key(household_id, target_id)
    if not unique_key then
      self.device.log.error(string.format("Invalid Sonos Unique Key Part: %s", bad_key_part))
      return
    end
    Router.send_message_to_player(unique_key, json_payload)
  end
end

--- Start a new websocket connection
--- @return boolean success
function SonosConnection:start()
  if self:is_running() then
    log.warn(
      "Called Start on a Sonos WebSocket that was already connected for device "
        .. self.device.label
    )
    return false
  end

  log.debug(string.format("Starting SonosConnection for %s", self.device.label))
  local household_id = self.device:get_field(PlayerFields.HOUSEHOLD_ID)
  local player_id = self.device:get_field(PlayerFields.PLAYER_ID)

  local auth_success, api_key = self.driver:check_auth(self.device)

  if not auth_success then
    self.device:offline()
    _spawn_reconnect_task(self)
    return false
  end

  if not self:self_running() then
    local url = self.device:get_field(PlayerFields.WSS_URL) or {}
    local _, err = Router.open_socket_for_player(household_id, player_id, url, api_key)
    if err ~= nil then
      log.error(err)
      return false
    end

    local unique_key, bad_key_part = utils.sonos_unique_key(household_id, player_id)
    if bad_key_part then
      self.device.log.error(string.format("Invalid Sonos Unique Key Part: %s", bad_key_part))
    else
      local listener_id, register_listener_err =
        Router.register_listener_for_socket(self, unique_key)
      if register_listener_err ~= nil or not listener_id then
        log.error(register_listener_err)
      else
        self._self_listener_uuid = listener_id
      end
    end
  end

  if not self:coordinator_running() then
    --TODO this is not infallible
    _open_coordinator_socket(self, household_id, player_id, api_key)
  end

  self:refresh_subscriptions()
  local coordinator_id = self.driver.sonos:get_coordinator_for_player(household_id, player_id)
  local self_unique_key, self_bad_key_part = utils.sonos_unique_key(household_id, player_id)
  local coordinator_unique_key, coordinator_bad_key_part =
    utils.sonos_unique_key(household_id, coordinator_id)
  if
    self_unique_key
    and Router.is_connected(self_unique_key)
    and coordinator_unique_key
    and Router.is_connected(coordinator_unique_key)
  then
    self.device:online()
    self._initialized = true
    self._keepalive = true
    return true
  end

  if self_bad_key_part then
    self.device.log.error(
      string.format(
        "Invalid Unique Key Part for 'self' Player during connection bring-up: %s",
        self_bad_key_part
      )
    )
  end

  if coordinator_bad_key_part then
    self.device.log.error(
      string.format(
        "Invalid Unique Key Part for 'coordinator' Player during connection bring-up: %s",
        coordinator_bad_key_part
      )
    )
  end

  return false
end

--- Stop the websocket processing loop and close the connection
function SonosConnection:stop()
  self._initialized = false
  self._keepalive = false
  log.debug("Stopping Sonos connection for " .. self.device.label)
  local _, player_id = self.driver.sonos:get_player_for_device(self.device)
  local household_id, group_id = self.driver.sonos:get_group_for_device(self.device)
  local coordinator_id = self.driver.sonos:get_coordinator_for_group(household_id, group_id)

  if player_id ~= coordinator_id then
    local unique_key, bad_key_part = utils.sonos_unique_key(household_id, player_id)
    if not unique_key then
      self.device.log.error(string.format("Invalid Sonos Unique Key Part: %s", bad_key_part))
      return
    end
    Router.close_socket_for_player(unique_key)
  end
end

return SonosConnection
