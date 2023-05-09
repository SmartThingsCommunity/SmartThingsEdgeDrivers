local cosock = require "cosock"
local socket = require "cosock.socket"
local protocol = require "protocol"
local Request = require 'luncheon.request'
local Response = require 'luncheon.response'
local log = require "log"

local ControlMessageType = {
  Shutdown = "shutdown",
  Subscribe = "subscribe",
  Unsubscribe = "unsubscribe",
  Prune = "prune"
}
local ControlMessage = {
  Shutdown = function() return { type = ControlMessageType.Shutdown } end,
  Subscribe = function(dev) return { type = ControlMessageType.Subscribe, device = dev } end,
  Unsubscribe = function(id) return { type = ControlMessageType.Unsubscribe, id = id } end,
  Prune = function() return { type = ControlMessageType.Prune } end,
}

local SubscriptionServer = {}
SubscriptionServer.mt = {
  __gc = function(self)
    if self.sock ~= nil then
      self.ctrl_tx:send(ControlMessage.Shutdown())
    end
  end,
  __index = SubscriptionServer
}

function SubscriptionServer:subscribe(device)
  if device ~= nil then
    self.ctrl_tx:send(ControlMessage.Subscribe(device))
  else
    log.warn("serve| invalid device, cannot subscribe")
  end
end

function SubscriptionServer:unsubscribe(device)
  if device ~= nil then
    self.ctrl_tx:send(ControlMessage.Unsubscribe(device))
  else
    log.warn("serve| invalid device, cannot unsubscribe")
  end
end

function SubscriptionServer:shutdown()
  self.ctrl_tx:send(ControlMessage.Shutdown())
end

function SubscriptionServer:prune()
  self.ctrl_tx:send(ControlMessage.Prune())
end

function SubscriptionServer.new_server()
  local ctrl_tx, ctrl_rx = cosock.channel.new()
  local notify_tx, notify_rx = cosock.channel.new()
  local sock = assert(socket.tcp());
  sock:bind('*', 0)
  sock:listen(1)
  local srv_addr, srv_port = sock:getsockname()
  -- Note: There is a bug in the hub firmware where the timeout causes an error, and using
  -- pcall to catch it breaks cosock. Without a timeout to check if we should kill the server
  -- we will leak sockets/tasks should a server ever be restarted (i.e. hub ip address changes)
  -- sock:settimeout(30)
  local self = {
    subscriptions = {}, --maps subscription ids to device objects
    ctrl_tx = ctrl_tx,
    notify_rx = notify_rx,
    sock = sock,
    listen_ip = srv_addr,
  }
  setmetatable(self, SubscriptionServer.mt)
  log.info_with({hub_logs = true}, string.format('serve| Started listening on %s:%s', srv_addr, srv_port))

  -- spawn task to handle incoming client connections
  cosock.spawn(function()
    while true do
      local client, err = sock:accept()
      if client then
        -- spawn handler for new client
        cosock.spawn(function()
          local req, recv_err = Request.tcp_source(client)
          if req and not recv_err then
            local sid = req:get_headers():get_one("sid")
            local body = req:get_body()
            notify_tx:send({id = sid, data = body})
            Response.new(200, client):send()
          else
            Response.new(400, client):send()
          end
          client:close()
        end)
      else
        log.error_with({hub_logs = true},
          "serve| shutting down tcp server due to unexpected accept error: " .. err)
        break
      end
    end
    sock:close()
    notify_tx:close()
  end, "tcp server")

  --spawn control task
  cosock.spawn(function()
    local shutdown_msg
    while true do
      local msg, err = ctrl_rx:receive()
      if err then
        shutdown_msg = "failed to receive on ctrl channel: " .. err
        break
      end
      if msg.type == ControlMessageType.Shutdown then
        shutdown_msg = "shutdown requested"
        break
      elseif msg.type == ControlMessageType.Subscribe then
        log.trace("serve| subscribing to device " .. msg.device.label)
        if msg.device:get_field("subscription_id") then
          local res = protocol.unsubscribe(msg.device, self.subscriptions[msg.device.id])
          log.trace(string.format("serve| unsubscribed from %s successfully? %s", msg.device.label, res))
          self.subscriptions[msg.device:get_field("subscription_id")] = nil
          msg.device:set_field("subscription_id", nil)
        end
        local sub_id = protocol.subscribe(msg.device, srv_addr, srv_port)
        if sub_id == nil then
          log.warn_with({hub_logs = true},
            "serve| failed to subscribe to device " .. msg.device.label)
        else
          log.info_with({hub_logs=true},
            "serve| successfully subscribed to device " .. msg.device.label)
          self.subscriptions[sub_id] = msg.device
          msg.device:set_field("subscription_id", sub_id)
        end
      elseif msg.type == ControlMessageType.Unsubscribe then
        log.trace("serve| unsubscribing from device " .. msg.device.label)
        if msg.device:get_field("subscription_id") then
          log.warn("serve| no existing subscription for device" .. msg.device.label)
        else
          local res = protocol.unsubscribe(msg.device, self.subscriptions[msg.device.id])
          log.trace(string.format("serve| unsubscribed from %s successfully? %s", msg.device.label, res))
          self.subscriptions[msg.device:get_field("subscription_id")] = nil
          msg.device:set_field("subscription_id", nil)
        end
      elseif msg.type == ControlMessageType.Prune then
        for sub_id, device in pairs(self.subscriptions) do
          if device.label == nil then
            log.trace("serve| removing subscription due to device removal", sub_id)
            self.subscriptions[sub_id] = nil
          end
        end
      end
    end
    self.sock:close() --TODO server task should manage its own socket once hub FW bugs are fixed
    self.sock = nil
    ctrl_rx:close()
    log.error_with({hub_logs=true}, "serve| control task shut down! ", shutdown_msg)
  end, "ServerControlTask")

  cosock.spawn(function()
    while true do
      local notification, err = notify_rx:receive()
      if err == "closed" then --this should only happen when the server is shutdown.
        log.warn("serve| notification channel closed")
        break
      end
      if self.subscriptions[notification.id] then
        local parser = require "parser"
        local device = self.subscriptions[notification.id]
        local label = device.label
        if label == nil then
          log.trace("serve| received notify event from deleted device")
          self.subscriptions[notification.id] = nil
        else
          log.trace("serve| received notify event from " .. self.subscriptions[notification.id].label)
          --Parser emits events for device
          parser.parse_subscription_resp_xml(self.subscriptions[notification.id], notification.data)
        end
      else
        log.warn("serve| received notify event from unknown subscription")
      end
    end
  end, "DeviceNotificationHandler")

  return self
end

return SubscriptionServer
