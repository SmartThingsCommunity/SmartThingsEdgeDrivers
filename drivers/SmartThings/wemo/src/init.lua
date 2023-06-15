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
local SubscriptionServer = require "subscription_server"
local cosock = require "cosock"

local Driver = require "st.driver"

local socket = require "cosock.socket"
local log = require "log"
local utils = require "st.utils"

-- maps model name to profile name
local profiles = {
  ["Insight"] = "wemo.mini-smart-plug.v1",
  ["Socket"] = "wemo.mini-smart-plug.v1",
  ["Dimmer"] = "wemo.dimmer-switch.v1",
  ["Motion"] = "wemo.motion-sensor.v1",
  ["Lightswitch"] = "wemo.light-switch.v1",
  ["LightSwitch"] = "wemo.light-switch.v1",
}

local function device_removed(driver, device)
  driver.server:prune()
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
    if max then base = math.min(base, max) end

    -- ensure total backoff is >= 0
    return math.max(base + randval, 0)
  end
end

local function device_init(driver, device)
  -- at the time of authoring, there is a bug with LAN Edge Drivers where `init`
  -- may not be called on every device that gets added to the driver
  if device:get_field("init_started") then
    return
  end
  device:set_field("init_started", true)
  device.log.info_with({ hub_logs = true }, "initializing device")
  local ip = device:get_field("ip")
  local port = device:get_field("port")
  -- Carry over DTH discovered ip/port during migration, since wemo devices often
  -- stop responding to SSDP requests after being on the network for a long time.
  if not (ip and port) and device.data and device.data.ip and device.data.port then
    local nu = require "st.net_utils"
    ip = nu.convert_ipv4_hex_to_dotted_decimal(device.data.ip)
    port = tonumber(device.data.port, 16)
    device:set_field("ip", ip, { persist = true })
    device:set_field("port", port, { persist = true })
    --try to get the metadata for this device so scan nearby doesn't create a device
    --for a migrated device that has yet to be rediscovered on the lan
    local meta = discovery.fetch_device_metadata(string.format("http://%s:%s/setup.xml", ip, port))
    if meta then
      device:set_field("serial_num", meta.serial_num, { persist = true })
    else
      device.log.warn_with({ hub_logs = true },
        "Unable to fetch migrated device serial number, driver discovery may recreate the device.")
    end
  end

  -- Setup the polling and subscription
  local jitter = 2 * math.random()
  if driver.server and ip and port then
    device.thread:call_with_delay(jitter, function() driver.server:subscribe(device) end)
  end
  device.thread:call_on_schedule(
    3600 + jitter,
    function() driver.server:subscribe(device) end,
    device.id .. "subcribe"
  )
  device.thread:call_on_schedule(
    60 + jitter,
    function() protocol.poll(device) end,
    device.id .. "poll"
  )

  --Rediscovery task. Needs task because if device init doesn't return, no events are handled
  -- on the device thread.
  cosock.spawn(function()
    local backoff = backoff_builder(300, 1, 0.25)
    local info
    while true do
      discovery.find(device.device_network_id, function(found) info = found end)
      if info then break end
      local tm = backoff()
      device.log.info_with({ hub_logs = true }, string.format("Failed to initialize device, retrying after delay: %.1f", tm))
      socket.sleep(tm)
    end

    if not info or not info.ip or not info.serial_num then
      device.log.error_with({ hub_logs = true }, "device not found on network")
      device:offline()
      return
    end
    device.log.info_with({ hub_logs = true },"Device init re-discovered device on the lan")
    device:online()

    --Sometimes wemos just stop responding to ssdp even though they are connected to the network.
    --Persist to avoid issues with driver restart
    device:set_field("ip", info.ip, { persist = true })
    device:set_field("port", info.port, { persist = true })
    device:set_field("serial_num", info.serial_num, { persist = true })
    if driver.server and (ip ~= info.ip or port ~= info.port) then
      device.log.debug("Resubscribe because ip/port has changed since last discovery")
      driver.server:subscribe(device)
    end
  end, device.id.." discovery")
end

local function device_added(driver, device)
  device_init(driver, device)
end

local function resubscribe_all(driver)
  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    driver.server:unsubscribe(device)
    driver.server:subscribe(device)
  end
end

local function lan_info_changed_handler(driver, hub_ipv4)
  if driver.server.listen_ip == nil or hub_ipv4 ~= driver.server.listen_ip then
    log.info_with({ hub_logs = true },
      "hub IPv4 address has changed, restarting listen server and resubscribing")
    driver.server:shutdown()
    driver.server = SubscriptionServer:new_server()
    resubscribe_all(driver)
  end
end

local function discovery_handler(driver, _, should_continue)

  local known_devices = {}
  local found_devices = {}

  local device_list = driver:get_devices()
  for _, device in ipairs(device_list) do
    local serial_num = device:get_field("serial_num")
    --Note MAC is not used due to MAC mismatch for migrated devices
    if serial_num ~= nil then known_devices[serial_num] = true end
  end

  log.info_with({ hub_logs = true }, "Starting discovery scanning")
  while should_continue() do
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
            log.info_with({ hub_logs = true }, string.format("creating %s device [%s] at %s", name, id, ip))
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
  log.info_with({ hub_logs = true }, "Discovery scanning ended")
end

--------------------------------------------------------------------------------------------
-- Build driver context table
--------------------------------------------------------------------------------------------
local wemo = Driver("wemo", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    removed = device_removed,
    added = device_added,
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

log.info("Spinning up subscription server and running driver")
-- TODO handle case where the subscription server is not started
wemo.server = SubscriptionServer.new_server()
wemo:run()
