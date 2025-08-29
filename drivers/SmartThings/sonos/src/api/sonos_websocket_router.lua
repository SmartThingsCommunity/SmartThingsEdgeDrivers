local channel = require "cosock.channel"
local cosock = require "cosock"
local log = require "log"
local socket = require "cosock.socket"
local ssl = require "cosock.ssl"
local LustreConfig = require "lustre".Config
local WebSocket = require "lustre".WebSocket
local Message = require "lustre".Message
local CloseCode = require "lustre.frame.close".CloseCode
local lb_utils = require "lunchbox.util"
local st_utils = require "st.utils"

local SonosApi = require "api"
local utils = require "utils"

--- A "singleton" module that maintains all of the websockets for a
--- home's Sonos players. A player as modeled in the driver will have
--- its own connection but it might not use that for all commands,
--- since it could be part of a group and need to speak to its coordinator.
--- @class SonosWebSocketRouter
local SonosWebSocketRouter = {}
local control_tx, control_rx = channel.new()
control_rx:settimeout(0.5)

---@alias WsId string|number
---@alias chan_tx table
---@alias chan_rx table
---@alias ListenerUuid string
---@alias Listener table

--- @type table<UniqueKey,WebSocket>
local websockets = {}
--- @type table<WsId,ListenerUuid[]>
local listener_ids_for_socket = {}
--- @type table<ListenerUuid,Listener>
local listeners = {}
--- @type UniqueKey[]
local pending_close = {}

cosock.spawn(function()
  while true do
    for _, unique_key in ipairs(pending_close) do -- close any sockets pending close before selecting/receiving on them
      local wss = websockets[unique_key]
      if wss ~= nil then
        log.trace(string.format("Closing websocket for player %s", unique_key))
        wss:close(CloseCode.normal(), "Shutdown requested by client")
        local ws_id = wss.id
        for _, uuid in ipairs((listener_ids_for_socket[ws_id] or {})) do
            local listener = listeners[uuid]

            if listener ~= nil then
              listener.on_close(uuid)
            end
            listeners[uuid] = nil
        end
        listener_ids_for_socket[ws_id] = nil
      end
      websockets[unique_key] = nil
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
          for unique_key, wss in pairs(websockets) do
            if wss.id ~= recv.id then
              still_open_sockets[unique_key] = wss
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
                log.error(
                  st_utils.stringify_table(
                    { msg = msg },
                    "Coordinator doesn't exist for player",
                    false
                  )
                )
                goto continue
              end

              log.trace(string.format("Sending message over websocket for target %s", target))
              local response = table.pack(wss:send(Message.new(Message.TEXT, msg.body)))
              if msg.header.reply_tx then
                msg.header.reply_tx:send(response)
              end
            end
          elseif msg.type and msg.data and recv.id then -- websocket message received
            log.trace(string.format("Received WebSocket message, fanning out to listeners"))
            for _, uuid in ipairs(listener_ids_for_socket[recv.id]) do
              local listener = listeners[uuid]

              if listener ~= nil then
                if listener.device and listener.device.label then
                  log.debug(
                    string.format(
                      "SonosConnection for device %s handling websocket message",
                      listener.device.label
                    )
                  )
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
end, "Sonos Websocket Router Task")

--- @param url_table table
--- @param api_key string
--- @return WebSocket|nil
--- @return nil|string error
local function _make_websocket(url_table, api_key)
  local sock, make_socket_err = socket.tcp()
  if not sock or make_socket_err ~= nil then
    return nil, "Could not open TCP socket: " .. make_socket_err
  end
  local _, sock_operation_err = sock:settimeout(3)
  if sock_operation_err ~= nil then
    return nil, "Could not set TCP socket timeout: " .. sock_operation_err
  end

  log.trace(
    string.format(
      "Opening up websocket connection for host/port %s %s",
      url_table.host,
      url_table.port
    )
  )

  _, sock_operation_err = sock:connect(url_table.host, url_table.port)
  if sock_operation_err ~= nil then
    return nil, "Socket connect error: " .. sock_operation_err
  end

  _, sock_operation_err = sock:setoption("keepalive", true)
  if sock_operation_err ~= nil then
    return nil, "Socket set keepalive error: " .. sock_operation_err
  end

  sock, sock_operation_err = ssl.wrap(sock, {
    mode = "client",
    protocol = "any",
    verify = "none",
    options = "all",
  })
  if sock_operation_err ~= nil then
    return nil, "SSL Wrap error: " .. sock_operation_err
  end

  _, sock_operation_err = sock:dohandshake()
  if sock_operation_err ~= nil then
    return nil, "SSL Handhsake error: " .. sock_operation_err
  end

  local headers = SonosApi.make_headers(api_key)
  local config = LustreConfig.default():protocol("v1.api.smartspeaker.audio")
  for k, v in pairs(headers) do
    config = config:header(k, v)
  end

  local wss = WebSocket.client(sock, url_table.path, config)
  _, sock_operation_err = wss:client_handshake_and_start(url_table.host, url_table.port)
  if sock_operation_err ~= nil then
    return nil, "Error starting websocket: " .. sock_operation_err
  end

  return wss
end

---@param unique_key UniqueKey
---@return boolean
function SonosWebSocketRouter.is_connected(unique_key)
  local wss = websockets[unique_key]
  return wss ~= nil and wss.state ~= nil and wss.state == "Active"
end

---@param listener any
---@param unique_key_for_socket UniqueKey
---@return string?
---@return string?
function SonosWebSocketRouter.register_listener_for_socket(listener, unique_key_for_socket)
  if listener and listener.device and listener.device.label then
    log.debug(
      "Registering SonosConnection for device %s as listener for player %s websocket",
      listener.device.label,
      unique_key_for_socket
    )
  end
  local ws = websockets[unique_key_for_socket]

  if ws ~= nil then
    local uuid = st_utils.generate_uuid_v4()
    local listener_ids = listener_ids_for_socket[ws.id] or {}

    table.insert(listener_ids, uuid)
    listener_ids_for_socket[ws.id] = listener_ids

    listeners[uuid] = listener

    return uuid
  else
    return nil, "Cannot register listener; no websocket opened for " .. unique_key_for_socket
  end
end

--- Open a websocket connection with the given look-up information
--- @param household_id HouseholdId
--- @param player_id PlayerId
--- @param wss_url string|table
--- @param api_key string
--- @return boolean|nil success true on success, nil otherwise
--- @return nil|string error the error message in the failure case
function SonosWebSocketRouter.open_socket_for_player(household_id, player_id, wss_url, api_key)
  local unique_key, bad_key_part = utils.sonos_unique_key(household_id, player_id)
  if not websockets[unique_key] then
    log.debug("Opening websocket for player id " .. unique_key)
    local url_table = lb_utils.force_url_table(wss_url)
    local wss, err = _make_websocket(url_table, api_key)

    if err or not wss then
      return nil, string.format("Could not create websocket connection for %s: %s", unique_key, err)
    elseif not unique_key then
      return nil, string.format("Invalid Sonos Unique Key Part: %s", bad_key_part)
    else
      websockets[unique_key] = wss
      return true
    end
  else
    log.debug("Websocket already open for " .. unique_key)
    return true
  end
end

function SonosWebSocketRouter.send_message_to_player(target, json_payload, reply_tx)
  local websocket_message = {
    header = { type = "WebSocket", target = target, reply_tx = reply_tx },
    body = json_payload,
  }

  control_tx:send(websocket_message)
end

--- Close a websocket connection with the given look-up information
--- @param target UniqueKey
--- @return boolean|nil success true on success, nil otherwise
--- @return nil|string error the error message in the failure case
function SonosWebSocketRouter.close_socket_for_player(target)
  log.trace("Closing socket for player " .. target)
  local ws = websockets[target]

  if ws ~= nil then
    table.insert(pending_close, target)
    return true
  else
    return nil, string.format("No currently open connection for %s", target)
  end
end

--- @param driver SonosDriver
function SonosWebSocketRouter.cleanup_unused_sockets(driver)
  log.trace("Begin cleanup of unused websockets")
  local should_keep = {}
  for unique_key, _ in pairs(websockets) do
    local household_id, player_id = unique_key:match("(.*)/(.*)")
    local is_joined = driver.sonos:get_device_id_for_player(household_id, player_id) ~= nil
    log.debug(string.format("Is Player %s joined? %s", player_id, is_joined))
    should_keep[unique_key] = is_joined
  end

  local known_devices = driver:get_devices()

  for _, device in ipairs(known_devices) do
    local household_id, coordinator_id = driver.sonos:get_coordinator_for_device(device)
    local coordinator_unique_key, bad_key_part =
      utils.sonos_unique_key(household_id, coordinator_id)
    if bad_key_part then
      log.warn(
        string.format(
          "Invalid Sonos Unique Key Part while cleaning up unused websockets: %s",
          bad_key_part
        )
      )
    end
    if coordinator_unique_key and should_keep[coordinator_unique_key] == false then -- looking for false specifically, not nil
      log.trace("Preserving coordinator socket " .. coordinator_id)
      should_keep[coordinator_unique_key] = true
    end
  end

  for unique_key, keep in pairs(should_keep) do
    if not keep then
      SonosWebSocketRouter.close_socket_for_player(unique_key)
    end
  end
end

return SonosWebSocketRouter
