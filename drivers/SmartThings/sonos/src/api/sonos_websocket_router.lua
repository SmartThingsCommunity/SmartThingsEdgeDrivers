local log = require "log"
local cosock = require "cosock"
local socket = require "cosock.socket"
local channel = require "cosock.channel"
local ssl = require "cosock.ssl"
local LustreConfig = require "lustre".Config
local WebSocket = require "lustre".WebSocket
local Message = require "lustre".Message
local CloseCode = require "lustre.frame.close".CloseCode
local lb_utils = require "lunchbox.util"
local st_utils = require "st.utils"

--- A "singleton" module that maintains all of the websockets for a
--- home's Sonos players. A player as modeled in the driver will have
--- its own connection but it might not use that for all commands,
--- since it could be part of a group and need to speak to its coordinator.
--- @module 'api.sonos_websocket_router'
local SonosWebSocketRouter = {}
local control_tx, control_rx = channel.new()
control_rx:settimeout(0.5)

---@alias WsId string|number
---@alias chan_tx table
---@alias chan_rx table
---@alias ListenerUuid string
---@alias Listener table

--- @type table<PlayerId,WebSocket>
local websockets = {}
--- @type table<WsId,ListenerUuid[]>
local listener_ids_for_socket = {}
--- @type table<ListenerUuid,Listener>
local listeners = {}
--- @type PlayerId[]
local pending_close = {}

cosock.spawn(function()
  while true do
    for _, player_id in ipairs(pending_close) do -- close any sockets pending close before selecting/receiving on them
      local wss = websockets[player_id]
      if wss ~= nil then
        log.trace(string.format("Closing websocket for player_id %s", player_id))
        wss:close(CloseCode.normal(), "Shutdown requested by client")
      end
      websockets[player_id] = nil
    end
    pending_close = {}

    local socks = { control_rx }
    for _, wss in pairs(websockets) do
      table.insert(socks, wss)
    end
    local receivers, _, err = socket.select(socks, nil, 10)
    local msg

    if err ~= nil then
      if err ~= "timeout" then
        log.error("Error in Websocket Router event loop: " .. err)
      end
    else
      for _, recv in ipairs(receivers) do
        if recv.link and recv.link.queue and #recv.link.queue == 0 then -- workaround a bug in receiving
          log.warn("attempting to receive on empty channel")
          goto continue
        end

        msg, err = recv:receive()

        if err ~= nil and err ~= "closed" then
          log.error("Receive error: " .. err)
          if recv.id ~= nil then
            for _, uuid in ipairs(listener_ids_for_socket[recv.id]) do
              local listener = listeners[uuid]

              if listener ~= nil then
                listener.on_error(uuid, err)
              end
            end
          end
        elseif err == "closed" and recv.id then -- closed websocket
          log.trace(string.format("Websocket %s closed", tostring(recv.id)))
          local still_open_sockets = {}
          for player_id, wss in pairs(websockets) do
            if wss.id ~= recv.id then
              still_open_sockets[player_id] = wss
            end
          end
          websockets = still_open_sockets
          for _, uuid in ipairs(listener_ids_for_socket[recv.id]) do
            local listener = listeners[uuid]

            if listener ~= nil then
              listener.on_close(uuid)
            end
            listeners[uuid] = nil
          end
          listener_ids_for_socket[recv.id] = nil
        else
          if msg.header and msg.body then -- control message
            if msg.header.type and msg.header.type == "WebSocket" then
              local target = msg.header.target
              local wss = websockets[target]
              if wss == nil then
                --TODO is this silencing a crash that is an indication of a state management bug in the run loop?
                log.error(st_utils.stringify_table({msg = msg}, "Coordinator doesn't exist for player", false))
                goto continue
              end

              log.trace(string.format("Sending message over websocket for target %s", target))
              wss:send(Message.new(Message.TEXT, msg.body))
            end
          elseif msg.type and msg.data and recv.id then -- websocket message received
            log.trace(string.format("Received WebSocket message, fanning out to listeners"))
            for _, uuid in ipairs(listener_ids_for_socket[recv.id]) do
              local listener = listeners[uuid]

              if listener ~= nil then
                if listener.device and listener.device.label then
                  log.debug(string.format("SonosConnection for device %s handling websocket message", listener.device.label))
                end
                listener.on_message(uuid, msg)
              end
            end
          else
            log.debug(st_utils.stringify_table(msg, "Unknown Message", true))
          end
        end
        ::continue::
      end
    end
  end
end)

--- @param url_table table
--- @return WebSocket|nil
--- @return nil|string error
local function _make_websocket(url_table)
  local sock, err = socket.tcp()
  if not sock or err ~= nil then return nil, "Could not open TCP socket: " .. err end
  local _, err = sock:settimeout(3)
  if err ~= nil then return nil, "Could not set TCP socket timeout: " .. err end

  log.trace(string.format(
    "Opening up websocket connection for host/port %s %s",
    url_table.host, url_table.port))

  _, err = sock:connect(url_table.host, url_table.port)
  if err ~= nil then return nil, "Socket connect error: " .. err end

  _, err = sock:setoption("keepalive", true)
  if err ~= nil then return nil, "Socket set keepalive error: " .. err end

  sock, err = ssl.wrap(sock, {
    mode = "client",
    protocol = "any",
    verify = "none",
    options = "all"
  })
  if err ~= nil then return nil, "SSL Wrap error: " .. err end

  _, err = sock:dohandshake()
  if err ~= nil then return nil, "SSL Handhsake error: " .. err end

  --- SONOS_API_KEY is a Global added to the environment in the root init.lua.
  --- This API key is injected in to the driver at deploy time for production.
  --- To use your own API key, add an `app_key.lua` to the `src`
  --- directory and have the only code be to `return "YOUR_API_KEY"`
  local config = LustreConfig.default():header("X-Sonos-Api-Key", SONOS_API_KEY)
                                       :protocol("v1.api.smartspeaker.audio")

  local wss = WebSocket.client(sock, url_table.path, config)
  _, err = wss:client_handshake_and_start(url_table.host, url_table.port)
  if err ~= nil then return nil, "Error starting websocket: " .. err end

  return wss
end

function SonosWebSocketRouter.is_connected(player_id)
  local wss = websockets[player_id]
  return wss ~= nil and wss.state ~= nil and wss.state == "Active"
end

function SonosWebSocketRouter.register_listener_for_socket(listener,
                                                           player_id_for_socket)
  if listener and listener.device and listener.device.label then
    log.debug("Registering SonosConnection for device %s as listener for player_id's %s websocket", listener.device.label, player_id_for_socket)
  end
  local ws = websockets[player_id_for_socket]

  if ws ~= nil then
    ws._player_id = player_id_for_socket
    local uuid = st_utils.generate_uuid_v4()
    local listener_ids = listener_ids_for_socket[ws.id] or {}

    table.insert(listener_ids, uuid)
    listener_ids_for_socket[ws.id] = listener_ids

    listeners[uuid] = listener

    return uuid
  else
    return nil, "Cannot register listener; no websocket opened for " .. player_id_for_socket
  end

end

--- Open a websocket connection with the given look-up information
--- @param player_id PlayerId
--- @param wss_url string|table
--- @return boolean|nil success true on success, nil otherwise
--- @return nil|string error the error message in the failure case
function SonosWebSocketRouter.open_socket_for_player(player_id, wss_url)
  if not websockets[player_id] then
    log.debug("Opening websocket for player id " .. player_id)
    local url_table = lb_utils.force_url_table(wss_url)
    local wss, err = _make_websocket(url_table)

    if err or not wss then
      return nil, string.format(
        "Could not create websocket connection for %s: %s", player_id,
        err)
    else
      websockets[player_id] = wss
      return true
    end
  else
    log.debug("Websocket already open for " .. player_id)
    return true
  end
end

function SonosWebSocketRouter.send_message_to_player(target, json_payload)
  local websocket_message = {
    header = { type = "WebSocket", target = target },
    body = json_payload
  }

  control_tx:send(websocket_message)
end

--- Close a websocket connection with the given look-up information
--- @param target PlayerId
--- @return boolean|nil success true on success, nil otherwise
--- @return nil|string error the error message in the failure case
function SonosWebSocketRouter.close_socket_for_player(target)
  log.trace("Closing socket for player " .. target)
  local ws = websockets[target]

  if ws ~= nil then
    local ws_id = ws.id
    table.insert(pending_close, target)
    for _, uuid in ipairs((listener_ids_for_socket[ws_id] or {})) do
      local listener = listeners[uuid]

      if listener ~= nil then
        listener.on_close(uuid)
      end
      listeners[uuid] = nil
    end
    listener_ids_for_socket[ws_id] = nil
    return true
  else
    return nil, string.format("No currently open connection for %s", target)
  end
end

--- @param driver SonosDriver
function SonosWebSocketRouter.cleanup_unused_sockets(driver)
  log.trace("Begin cleanup of unused websockets")
  local should_keep = {}
  for player_id, _ in pairs(websockets) do
    local is_joined = driver.sonos:is_player_joined(player_id)
    log.debug(string.format("Is PlayerID %s joined? %s", player_id, is_joined))
    should_keep[player_id] = is_joined
  end

  local known_devices = driver:get_devices()

  for _, device in ipairs(known_devices) do
    local _, coordinator_id = driver.sonos:get_coordinator_for_device(device)
    if should_keep[coordinator_id] == false then -- looking for false specifically, not nil
      log.trace("Preserving coordinator socket " .. coordinator_id)
      should_keep[coordinator_id] = true
    end
  end

  for id, keep in pairs(should_keep) do
    if not keep then
      SonosWebSocketRouter.close_socket_for_player(id)
    end
  end
end

return SonosWebSocketRouter
