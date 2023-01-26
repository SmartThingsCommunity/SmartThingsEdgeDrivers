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

---@alias DNI string
---@alias WsId string|number
---@alias chan_tx table
---@alias chan_rx table
---@alias ListenerUuid string
---@alias Listener table

--- @type table<DNI,WebSocket>
local websockets = {}
--- @type table<WsId,ListenerUuid[]>
local listener_ids_for_socket = {}
--- @type table<ListenerUuid,Listener>
local listeners = {}
--- @type DNI[]
local pending_close = {}

cosock.spawn(function()
  while true do
    for _, dni in ipairs(pending_close) do -- close any sockets pending close before selecting/receiving on them
      local wss = websockets[dni]
      if wss ~= nil then
        local _, _err = wss:close(CloseCode.normal(),
          "Shutdown requested by client")
      end
      websockets[dni] = nil
    end
    pending_close = {}

    local socks = { control_rx }
    for _, wss in pairs(websockets) do
      table.insert(socks, wss)
    end
    local receivers, _, err = socket.select(socks, nil, 10)
    local msg = {}

    if err ~= nil then
      if err ~= "timeout" then
        log.error("Error in Websocket Router event loop: " .. err)
      end
    else
      for _, recv in ipairs(receivers) do
        if recv.link and recv.link.queue and #recv.link.queue == 0 then -- workaround a bug in receiving
          log.warn("attempting to receive on empty channel")
          control_tx:send("STOP IT")
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
              local dni = msg.header.target
              local wss = websockets[dni]

              wss:send(Message.new(Message.TEXT, msg.body))
            end
          elseif msg.type and msg.data and recv.id then -- websocket message received
            for _, uuid in ipairs(listener_ids_for_socket[recv.id]) do
              local listener = listeners[uuid]

              if listener ~= nil then
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

--- @param dni DNI
--- @param url_table table
--- @return WebSocket|nil
--- @return nil|string error
local function _make_websocket(dni, url_table)
  local sock, err = socket.tcp()

  if sock then
    sock:settimeout(3)
    log.trace(string.format(
      "Opening up websocket connection for host/port %s %s",
      url_table.host, url_table.port))
    _, err = sock:connect(url_table.host, url_table.port)
    if not err then
      sock:setoption("keepalive", true)

      sock, err = ssl.wrap(sock, {
        mode = "client",
        protocol = "any",
        verify = "none",
        options = "all"
      })

      if err then return nil, "SSL Wrap error: " .. err end

      sock:dohandshake()
    end
  else
    return nil, "Could not open TCP socket: " .. err
  end

  --- SONOS_API_KEY is a Global added to the environment in the root init.lua.
  --- This API key is injected in to the driver at deploy time for production.
  --- To use your own API key, add an `app_key.lua` to the `src`
  --- directory and have the only code be to `return "YOUR_API_KEY"`
  local config = LustreConfig.default():header("X-Sonos-Api-Key", SONOS_API_KEY)
                                       :protocol("v1.api.smartspeaker.audio")

  local wss = WebSocket.client(sock, url_table.path, config)

  _, err = wss:client_handshake_and_start(url_table.host, url_table.port)

  if err ~= nil then
    return nil, "Error starting websocket: " .. err
  end

  return wss
end

function SonosWebSocketRouter.is_connected(dni)
  return websockets[dni] ~= nil
end

function SonosWebSocketRouter.register_listener_for_socket(listener,
                                                           dni_for_socket)
  local ws = websockets[dni_for_socket]

  if ws ~= nil then
    local uuid = st_utils.generate_uuid_v4()
    local listener_ids = listener_ids_for_socket[ws.id] or {}

    table.insert(listener_ids, uuid)
    listener_ids_for_socket[ws.id] = listener_ids

    listeners[uuid] = listener

    return uuid
  else
    return nil, "Cannot register listener; no websocket opened for " .. dni_for_socket
  end

end

--- Open a websocket connection with the given look-up information
--- @param dni DNI
--- @param wss_url string|table
--- @return boolean|nil success true on success, nil otherwise
--- @return nil|string error the error message in the failure case
function SonosWebSocketRouter.open_socket_for_player(dni, wss_url)
  if not websockets[dni] then
    local url_table = lb_utils.force_url_table(wss_url)
    local wss, err = _make_websocket(dni, url_table)

    if err or not wss then
      return nil, string.format(
        "Could not create websocket connection for %s: %s", dni,
        err)
    else
      websockets[dni] = wss
      return true
    end
  else
    log.debug("Websocket already open for " .. dni)
    return true
  end
end

function SonosWebSocketRouter.send_message_to_player(dni, json_payload)
  local websocket_message = {
    header = { type = "WebSocket", target = dni },
    body = json_payload
  }

  control_tx:send(websocket_message)
end

--- Close a websocket connection with the given look-up information
--- @param dni DNI
--- @return boolean|nil success true on success, nil otherwise
--- @return nil|string error the error message in the failure case
function SonosWebSocketRouter.close_socket_for_player(dni)
  log.trace("Closing socket for player " .. dni)
  local ws = websockets[dni]

  if ws ~= nil then
    local ws_id = ws.id
    table.insert(pending_close, dni)
    for _, uuid in ipairs(listener_ids_for_socket[ws_id]) do
      local listener = listeners[uuid]

      if listener ~= nil then
        listener.on_close(uuid)
      end
      listeners[uuid] = nil
    end
    listener_ids_for_socket[ws_id] = nil
    return true
  else
    return nil, string.format("No currently open connection for %s", dni)
  end
end

--- @param driver SonosDriver
function SonosWebSocketRouter.cleanup_unused_sockets(driver)
  log.trace("Begin cleanup of unused websockets")
  local should_keep = {}
  for dni, _ in pairs(websockets) do
    local is_joined = driver.sonos:is_player_joined(dni)
    log.debug(string.format("Is DNI %s joined? %s", dni, is_joined))
    should_keep[dni] = is_joined
  end

  local known_devices = driver:get_devices()

  for _, device in ipairs(known_devices) do
    local _, coordinator_id = driver.sonos:get_coordinator_for_device(device)
    local dni = driver.sonos:get_dni_for_player_id(coordinator_id)
    if should_keep[dni] == false then -- looking for false specifically, not nil
      log.trace("Preserving coordinator socket " .. dni)
      should_keep[dni] = true
    end
  end

  for dni, keep in pairs(should_keep) do
    if not keep then
      SonosWebSocketRouter.close_socket_for_player(dni)
    end
  end
end

return SonosWebSocketRouter
