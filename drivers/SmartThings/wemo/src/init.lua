--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--
--  ===============================================================================================
--  Improvements to be made:
--
--  * Pull switch state if we get no async report after a certian amount of time.
--  * Re-discover if can't conect after initial discovery (aka IP scan)
--  ===============================================================================================

local capabilities = require "st.capabilities"
local command_handlers = require "command_handlers"
local discovery = require "discovery"
local protocol = require "protocol"

local Driver = require "st.driver"

local socket = require "cosock.socket"
local json = require "dkjson"
local log = require "log"
local utils = require "st.utils"

-- maps model name to profile name
local profiles = {
  ["Insight"] = "wemo.mini-smart-plug.v1",
  ["Socket"] = "wemo.mini-smart-plug.v1",
  ["Dimmer"] = "wemo.dimmer-switch.v1",
  ["Motion"] = "wemo.motion-sensor.v1",
  ["Lightswitch"] = "wemo.light-switch.v1",
}

local server = {}

local function start_server(driver)
  server.listen_sock = socket.tcp()

  -- create server on IP_ANY and os-assigned port
  assert(server.listen_sock:bind("*", 0))
  assert(server.listen_sock:listen(1))
  local ip, port, _ = server.listen_sock:getsockname()

  if ip ~= nil and port ~= nil then
    log.info_with({hub_logs=true}, string.format("Started listening server on %s:%s", ip, port))
    server.listen_port = port
    server.listen_ip = ip;
    driver:register_channel_handler(server.listen_sock, protocol.accept_handler)
  else
    log.error_with({hub_logs=true}, "could not get IP/port from TCP getsockname(), not listening for device status")
    server.listen_sock:close()
    server.listen_sock = nil
    --TODO schedule a retry if this happens?
  end
end

local function stop_server()
  log.info_with({hub_logs=true}, string.format("Shutting down listening server @ %s:%s", server.listen_ip, server.listen_port))

  if server.listen_sock ~= nil then
    server.listen_sock:close()
  end
  --TODO unregister channel handler? Seems possible to get in a state
  -- where sockets are never gc'd because they are held by the driver.
  server = {}
end

-- build a exponential backoff time value generator
--
-- max: the maximum wait interval (not including `rand factor`)
-- inc: the rate at which to exponentially back off
-- rand: a randomization range of (-rand, rand) to be added to each interval
local function backoff_builder(max, inc, rand)
  local count = 0
  inc = inc or 1
  return function()
    local randval = 0
    if rand then
      -- random value in range (-rand, rand)
      randval = math.random() * rand * 2 - rand
    end

    local base = inc * (2^count - 1)
    count = count + 1

    -- ensure base backoff (not including random factor) is less than max
    if max then
      base = math.min(base, max)
    end

    -- ensure total backoff is >= 0
    return math.max(base + randval, 0)
  end
end

local function device_init(driver, device)
  log.info_with({hub_logs=true}, "[" .. device.device_network_id .. "] initializing Wemo device")

  local backoff = backoff_builder(300, 1, 0.25)
  local info
  while true do
    discovery.find(device.device_network_id, function(found) info = found end)
    if info then break end
    local tm = backoff()
    log.debug("Failed to initialize device, retrying after delay", tm)
    socket.sleep(tm)
  end

  if not info or not info.ip or not info.serial_num then
    log.warn_with({hub_logs=true}, "[" .. device.device_network_id .. "] device not found on network")
    device:offline() -- Mark device as being unavailable/offline
    return
  end

  device:online()
 
  --ip and port are persisted since sometimes wemo just stop responding to ssdp even though
  --they are connected to the network. In this case we want them to continue to function
  --across driver restarts.
  device:set_field("ip", info.ip, {persist = true})
  device:set_field("port", info.port, {persist = true})
  device:set_field("serial_num", info.serial_num, {persist = true})

  --TODO maybe we should call_on_schedule with the device thread, and the polling.
  -- instead of doing the resubscribe for all devices at once.
  protocol.subscribe(server, device)
end

local function device_removed(_, device)
  protocol.unsubscribe(device)
end

--TODO handle polling devices individually rather than
-- spamming all at once
local function poll(driver)
  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
      log.info_with({hub_logs=true}, "[" .. device.device_network_id .. "] polling device")
      protocol.poll(driver, device)
  end
end

--TODO resubscribe for each device individually rather than all at once
local function resubscribe_all(driver)
  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    device.log.info("resubscribing Wemo device")
    protocol.unsubscribe(device)
    protocol.subscribe(server, device)
  end
end

local function lan_info_changed_handler(self, hub_ipv4)
  if self.listen_ip == nil or hub_ipv4 ~= self.listen_ip then
    log.info("hub IPv4 address has changed, restarting listen server and resubscribing")
    stop_server(self)
    start_server(self)

    resubscribe_all(self)
  end
end

local function discovery_handler(driver, _, should_continue)
  log.info("starting discovery")

  local known_devices = {}
  local found_devices = {}

  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    local serial_num = device:get_field("serial_num")
    --Note MAC is not used due to MAC mismatch for migrated devices
    if serial_num ~= nil then known_devices[serial_num] = true end
  end

  while should_continue() do
    log.info("making discovery request")
    discovery.find(
      nil,
      function(device)
        local id = device.id
        local ip = device.ip
        local serial_num = device.serial_num

        if not known_devices[serial_num] and not found_devices[serial_num] then
          found_devices[serial_num] = true
          local name = device.name or "Unnamed Wemo"
          local profile_name = device.model
          if string.find(name, "Motion") then
            profile_name = "Motion"
          end
          local profile = profiles[profile_name]

          if profile then
            -- add device
            log.info_with({hub_logs=true}, string.format("creating %s device [%s] at %s", name, id, ip))
            local create_device_msg = {
                type = "LAN",
                device_network_id = id,
                label = name,
                profile = profile,
                manufacturer = "Belkin",
                model = device.model,
                vendor_provided_label = device.name,
              }
            log.trace("create device with:", utils.stringify_table(create_device_msg))
            assert(
              driver:try_create_device(create_device_msg),
              "failed to create device record"
            )
          else
            log.warn("discovered device is an unknown model:", tostring(device.model))
          end
        else
          log.debug("device already known by driver")
        end
      end
    )
  end
  log.info("exiting discovery")
end

--------------------------------------------------------------------------------------------
-- Build driver context table
--------------------------------------------------------------------------------------------
local wemo = Driver("wemo", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    removed = device_removed
  },
  lan_info_changed_handler = lan_info_changed_handler,
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = command_handlers.handle_switch_on,
      [capabilities.switch.commands.off.NAME] = command_handlers.handle_switch_off,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = command_handlers.handle_set_level,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = command_handlers.handle_refresh,
    }
  }
})

log.info("script start")

-- BA: What should we do if we fail to create listen socket? Consider periodic check on listen port
-- and restart server when needed.
start_server(wemo)

-- Subscription timeout is set to 5400 (1.5), resubscribe 3600 (1hr) to be safe? (currently done in
-- LAN Wemo * DTH)
-- TODO.pb: Do this on device thread.
wemo:call_on_schedule(3600, resubscribe_all, "wemo resubscribe timer")
-- BA: Polling will be needed for device health
wemo:call_on_schedule(60, poll, "wemo poll timer")

wemo:run()
