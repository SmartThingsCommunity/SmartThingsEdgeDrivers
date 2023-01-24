local log = require "log"
local json = require "st.json"

local lb_utils = require "lunchbox.util"

local EventHandlers = require "api.event_handlers"
local PlayerFields = require "fields".SonosPlayerFields
local Router = require "api.sonos_websocket_router"
local SonosApi = require "api"
local SonosRestApi = require "api.rest"

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
--- @field private _self_listener_uuid string
--- @field private _coord_listener_uuid string
--- @field private _initialized boolean
local SonosConnection = {}
SonosConnection.__index = SonosConnection

local self_subscriptions = { "groups", "playerVolume" }
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
_update_subscriptions_helper = function(sonos_conn, householdId, playerId, groupId, namespaces, command)
  for _, namespace in ipairs(namespaces) do
    local payload_table = {
      {
        namespace = namespace,
        command = command,
        householdId = householdId,
        groupId = groupId,
        playerId = playerId
      },
      {}
    }
    local payload = json.encode(payload_table)
    local dni = sonos_conn.driver.sonos:get_dni_for_player_id(playerId)
    Router.send_message_to_player(dni, payload)
  end
end

---@param sonos_conn SonosConnection
---@param namespaces string[]
---@param command "subscribe"|"unsubscribe"
_update_self_subscriptions = function(sonos_conn, namespaces, command)
  local householdId = sonos_conn.device:get_field(PlayerFields.HOUSEHOULD_ID)
  local _, playerId = sonos_conn.driver.sonos:get_player_for_device(sonos_conn.device)
  local _, groupId = sonos_conn.driver.sonos:get_group_for_device(sonos_conn.device)
  _update_subscriptions_helper(sonos_conn, householdId, playerId, groupId, namespaces, command)
end

---@param sonos_conn SonosConnection
---@param namespaces string[]
---@param command "subscribe"|"unsubscribe"
_update_coordinator_subscriptions = function(sonos_conn, namespaces, command)
  local householdId = sonos_conn.device:get_field(PlayerFields.HOUSEHOULD_ID)
  local _, coordinatorId = sonos_conn.driver.sonos:get_coordinator_for_device(sonos_conn.device)
  local _, groupId = sonos_conn.driver.sonos:get_group_for_device(sonos_conn.device)
  _update_subscriptions_helper(sonos_conn, householdId, coordinatorId, groupId, namespaces, command)
end

---@param sonos_conn SonosConnection
---@param household_id HouseholdId
---@param self_player_id PlayerId
local function _open_coordinator_socket(sonos_conn, household_id, self_player_id)
  log.trace("Open coordinator socket: " .. household_id .. ":" .. self_player_id)
  local _, coordinator_id, err = sonos_conn.driver.sonos:get_coordinator_for_device(sonos_conn.device)
  if err ~= nil then
    log.error(
      string.format(
        "Could not look up coordinator info for player %s: %s", sonos_conn.device.label, err
      )
    )
  end

  if coordinator_id ~= self_player_id then
    local coordinator = sonos_conn.driver.sonos:get_household(household_id).players[coordinator_id]
    local coordinator_dni = sonos_conn.driver.sonos:get_dni_for_player_id(coordinator_id)
    local _, err =
    Router.open_socket_for_player(coordinator_dni, coordinator.websocketUrl)

    if err ~= nil then
      log.error(
        string.format(
          "Couldn't open connection to coordinator for %s: %s", sonos_conn.device.label, err
        )
      )
    end

    listener_id, err = Router.register_listener_for_socket(sonos_conn, coordinator_dni)
    if err ~= nil or not listener_id then
      log.error(err)
    else
      sonos_conn._coord_listener_uuid = listener_id
    end
  end
end

--- Create a new Sonos connection to manage the given device
--- @param driver SonosDriver
--- @param device SonosDevice
--- @return SonosConnection
function SonosConnection.new(driver, device)
  local self = setmetatable({ driver = driver, device = device, _listener_uuids = {}, _initialized = false },
    SonosConnection)
  local _name = self.device.label

  self.on_message = function(uuid, msg)
    if msg.data then
      local header, body = table.unpack(json.decode(msg.data))
      if header.type == "groups" then
        local household_id, current_coordinator = self.driver.sonos:get_coordinator_for_device(self.device)
        local _, player_id = self.driver.sonos:get_player_for_device(self.device)
        self.driver.sonos:update_household_info(header.householdId, body)
        local _, updated_coordinator = self.driver.sonos:get_coordinator_for_device(self.device)

        Router.cleanup_unused_sockets(self.driver)

        if not self:coordinator_running() then
          _open_coordinator_socket(self, household_id, player_id)
        end

        if current_coordinator ~= updated_coordinator then
          self:refresh_subscriptions()
        end
      elseif header.type == "playerVolume" then
        local player_id = self.device:get_field(PlayerFields.PLAYER_ID)
        if player_id == header.playerId and body.volume and (body.muted ~= nil) then
          EventHandlers.handle_player_volume(self.device, body.volume, body.muted)
        end
      elseif header.type == "groupVolume" then
        if body.volume and (body.muted ~= nil) then
          local group = self.driver.sonos:get_household(header.householdId).groups[header.groupId] or { playerIds = {} }
          for _, player_id in ipairs(group.playerIds) do
            EventHandlers.handle_player_volume(self.driver._dni_to_device[device.device_network_id], body.volume, body.muted)
          end
        end
      elseif header.type == "playbackStatus" then
        local group = self.driver.sonos:get_household(header.householdId).groups[header.groupId] or { playerIds = {} }
        for _, player_id in ipairs(group.playerIds) do
          EventHandlers.handle_playback_status(self.driver._dni_to_device[device.device_network_id], body.playbackState)
        end
      elseif header.type == "metadataStatus" then
        local group = self.driver.sonos:get_household(header.householdId).groups[header.groupId] or { playerIds = {} }
        for _, player_id in ipairs(group.playerIds) do
          EventHandlers.handle_playback_metadata_update(self.driver._dni_to_device[device.device_network_id], body)
        end
      elseif header.namespace == "favorites" and header.type == "versionChanged" then
        if body.version ~= favorites_version then
          favorites_version = body.version

          local household = self.driver.sonos:get_household(header.householdId)

          for group_id, group in pairs(household.groups) do
            local coordinator_id = self.driver.sonos:get_coordinator_for_group(header.householdId, group_id)
            local coordinator_player = household.players[coordinator_id]

            local url_ip = lb_utils.force_url_table(coordinator_player.websocketUrl).host

            local favorites_response, err, _ =
            SonosRestApi.get_favorites(url_ip, SonosApi.DEFAULT_SONOS_PORT, header.householdId)

            if err or not favorites_response then
              log.error("Error querying for favorites: " .. err)
            else
              local new_favorites = {}
              for _, favorite in ipairs(favorites_response.items or {}) do
                local new_item = { id = favorite.id, name = favorite.name }
                if favorite.imageUrl then new_item.imageUrl = favorite.imageUrl end
                if favorite.service and favorite.service.name then new_item.mediaSource = favorite.service.name end
                table.insert(new_favorites, new_item)
              end
              self.driver.sonos:update_household_favorites(header.householdId, new_favorites)

              for _, player_id in ipairs(group.playerIds) do
                EventHandlers.update_favorites(self.driver._dni_to_device[device.device_network_id], new_favorites)
              end
            end
          end
        end
      end
    end
  end

  self.on_error = function(uuid, err)
  end

  self.on_close = function(uuid)
    if self._initialized then self.device:offline() end
  end

  return self
end

--- Whether or not the connection has a live websocket connection
--- @return boolean
function SonosConnection:is_running()
  return not err and Router.is_connected(self.device.device_network_id) and self._initialized
end

--- Whether or not the connection has a live websocket connection
--- @return boolean
function SonosConnection:coordinator_running()
  local _, coordinator_id = self.driver.sonos:get_coordinator_for_device(self.device)
  local coordinator_dni = self.driver.sonos:get_dni_for_player_id(coordinator_id)
  return not err and Router.is_connected(coordinator_dni) and self._initialized
end

function SonosConnection:refresh_subscriptions()
  log.trace("Refresh subscriptions on " .. self.device.label)
  _update_self_subscriptions(self, self_subscriptions, "subscribe")
  _update_coordinator_subscriptions(self, coordinator_subscriptions, "subscribe")
end

--- Send a Sonos command object to the player for this connection
--- @param cmd SonosCommand
function SonosConnection:send_command(cmd)
  log.trace("Sending command over websocket channel for device " .. self.device.label)
  local _, coordinator_id = self.driver.sonos:get_coordinator_for_device(self.device)
  local coordinator_dni = self.driver.sonos:get_dni_for_player_id(coordinator_id)
  local json_payload, err = json.encode(cmd)

  if err or not json_payload then
    log.error("Json encoding error: " .. err)
  else
    Router.send_message_to_player(coordinator_dni, json_payload)
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

  local url = self.device:get_field(PlayerFields.WSS_URL) or {}
  local household_id = self.device:get_field(PlayerFields.HOUSEHOULD_ID)
  local player_id = self.device:get_field(PlayerFields.PLAYER_ID)

  local _, err = Router.open_socket_for_player(self.device.device_network_id, url)
  if err ~= nil then
    log.error(err)
    return false
  end

  local listener_id, err = Router.register_listener_for_socket(self, self.device.device_network_id)
  if err ~= nil or not listener_id then
    log.error(err)
  else
    self._self_listener_uuid = listener_id
  end

  if not self:coordinator_running() then
    _open_coordinator_socket(self, household_id, player_id)
  end

  self:refresh_subscriptions()
  self.device:online()
  self._initialized = true
  return true
end

--- Stop the websocket processing loop and close the connection
function SonosConnection:stop()
  self._initialized = false
  log.info("Stopping Sonos connection for " .. self.device.label)
  local _, player_id = self.driver.sonos:get_player_for_device(self.device)

  local known_devices = self.driver:get_devices()
  local is_socket_in_use = false

  local dni_equal = self.driver.is_same_mac_address
  for _, device in ipairs(known_devices) do
    if dni_equal(device.device_network_id, self.device.device_network_id) then
      local _, coordinator_id = self.driver.sonos:get_coordinator_for_device(device)

      if player_id == coordinator_id then
        is_socket_in_use = true
        break
      end
    end
  end

  if not is_socket_in_use then
    Router.close_socket_for_player(self.device.device_network_id)
  end
end

return SonosConnection
