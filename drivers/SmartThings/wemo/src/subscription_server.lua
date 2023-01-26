local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"
local protocol = require "protocol"

local ControlMessageType = {
  Shutdown = "shutdown",
  Subscribe = "subscribe",
  Unsubscribe = "unsubscribe",
}
local ControlMessage = {
  Shutdown = function() return { type = ControlMessageType.Shutdown } end,
  Subscribe = function(dev) return { type = ControlMessageType.Subscribe, device = dev } end,
  Unsubscribe = function(id) return { type = ControlMessageType.Unsubscribe, id = id } end,
}

local SubscriptionServer = {}
SubscriptionServer.mt = {
  __gc = function(self)
    if self.sock then
      self.ctrl_tx:send(ControlMessage.Shutdown())
    end
  end,
  __index = SubscriptionServer
}

function SubscriptionServer:subscribe(device)
  self.ctrl_tx:send(ControlMessage.Subscribe(device))
end

function SubscriptionServer:unsubscribe(device)
  self.ctrl_tx:send(ControlMessage.Unsubscribe(device))
end

function SubscriptionServer:shutdown()
  self.ctrl_tx:send(ControlMessage.Shutdown())
end

function SubscriptionServer.new_server()
  local ctrl_tx, ctrl_rx = cosock.channel.new()
  local notify_tx, notify_rx = cosock.channel.new()
  local self = {
    subscriptions = {},
    ctrl_tx = ctrl_tx,
    notify_rx = notify_rx,
  }
  setmetatable(self, SubscriptionServer.mt)

  cosock.spawn(function()
    local sock = assert(socket.tcp());
    sock:bind('*', 0)
    sock:listen(1)
    print('server| listening on:', sock:getsockname())
    local srv_addr, srv_port = sock:getsockname()

    while true do
      local recvr, _, _ = socket.select({sock, ctrl_rx})
      if recvr and (recvr[1] == ctrl_rx or recvr[2] == ctrl_rx) then
        local msg, err = ctrl_rx:receive()
        if err then
          print("server| failed to receive on control channel") --TODO
        end
        if msg.type == ControlMessageType.Shutdown then
          print("server| shutting down")
          break
        elseif msg.type == ControlMessageType.Subscribe then
          print("server| (re)subscribing to device")
          if self.subscriptions[msg.device.id] then
            local error = protocol.unsubscribe(msg.device, self.subscriptions[msg.device.id])
            if error then
              print("server| failed to unsubscribe from device")
            else
              self.subscriptions[msg.device.id] = nil
            end
          end
          local sub_id = protocol.subscribe(msg.device, srv_addr, srv_port)
          if sub_id == nil then
            print("server| failed to subscribe to device " .. msg.device.label)
          else
            self.subscriptions[msg.device.id] = sub_id
          end
        elseif msg.type == ControlMessageType.Unsubscribe then
          print("server| unsubscribing from device" .. msg.device.label)
          if self.subscriptions[msg.device.id] == nil then
            print("server| no existing subscription for device" .. msg.device.label)
            goto continue
          end
          local error = protocol.unsubscribe(msg.device, self.subscriptions[msg.device.id])
          if error then
            print("server| failed to unsubscribe from device: " .. error)
          else
            self.subscriptions[msg.device.id] = nil
          end
        end
      end

      if recvr and (recvr[1] == sock or recvr[2] == sock) then
        print("!!!!! accepting client")
        local client, err = sock:accept()
        print("!!!!! accepted client", client, err)
        if err then
          print("server| error accepting client" .. err)
        else
          -- spawn handler for new client
          cosock.spawn(function()
            print("!!!!! running spawned client task")
            client:settimeout(5)
            local res = ""
            while true do
              local data, err = client:receive()
              if err then
                print("server| client receive failure" .. err, client:getpeername())
                break
              end
              res = res .. data
            end
            -- clean up socket
            client:close()
            print("!!!!! received data on socket:", res)
            notify_tx:send(res)
          end)
        end
      end
      ::continue::
    end
    sock:close()
    notify_tx:close()
    print("server| finished shutting down")
  end, "SubscriptionServer")

  cosock.spawn(function()
    while true do
      local raw, err = notify_rx:receive()
      if err == "closed" then --this should only happen when the server is shutdown.
        print("server| notification channel closed")
        break
      end
      print("server| received notification from client", raw, err)
    end
  end, "DeviceNotificationHandler")

  return self
end

return SubscriptionServer
