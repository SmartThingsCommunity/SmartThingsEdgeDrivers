--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
--  in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions and
--  limitations under the License.
--

-- smartthings libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"

-- the coroutine runtime's socket interface
local socket = require "cosock".socket

-- driver specific libraries from this repo
local client = require "rpcclient"
local discovery = require "discovery"

----------------------------------------------------------------------------------------------------
-- Local Helpers
----------------------------------------------------------------------------------------------------

-- search network for specific thing using custom discovery library
local function find_thing(id)
  -- for the sake of brevity, this currently sends out an SSDP broadcast for each thing, though you
  -- should coalesce these to just send out a single request for the whole driver
  return table.remove(discovery.find({id}) or {})
end

-- get an rpc client for thing if thing is reachable on the network
local function get_thing_client(device)
  local thingclient = device:get_field("client")

  if not thingclient then
    local thing = find_thing(device.device_network_id)
    if thing then
      thingclient = client.new(thing.ip, thing.rpcport)
      device:set_field("client", thingclient)
      device:online()
    end
  end

  if not thingclient then
    device:offline()
    return nil, "unable to reach thing"
  end

  return thingclient
end

----------------------------------------------------------------------------------------------------
-- Device and Driver Event Handlers
----------------------------------------------------------------------------------------------------

-- handle setup for newly added devices (before device_init)
local function device_added(driver, device)
  log.info("[" .. tostring(device.id) .. "] New ThingSim RPC Client device added")

  -- nothing to do here, everything happens in init this is just here for completeness, if you
  -- don't need this callback you can remove it
end

-- initialize device at startup or when added
local function device_init(driver, device)
  log.info("[" .. tostring(device.id) .. "] Initializing ThingSim RPC Client device")

  local client = assert(get_thing_client(device))

  if client then
    log.info("Connected")

    -- get current state and emit in case it has changed
    local attrs = client:getattr({"power"})
    if attrs and attrs.power == "on" then
      device:emit_event(capabilities.switch.switch.on())
    else
      device:emit_event(capabilities.switch.switch.off())
    end
  else
    log.warn(
      "Device not found at initial discovery (no async events until controlled)",
      device:get_field("name") or device.device_network_id
    )
  end
end

-- discover not already known devices listening on the network
local function discovery_handler(driver, options, should_continue)
  log.info("starting discovery")
  local known_devices = {}
  local found_devices = {}

  -- get a list of devices already added
  local device_list = driver:get_devices()
  for i, device in ipairs(device_list) do
    -- for each, add to a table keyed by the the DNI for easy lookup later
    local id = device.device_network_id
    known_devices[id] = true
  end

  -- as long as a user is on the device discovery page in the app, calling `should_continue()`
  -- will return `true` and we should keep trying to discover more thingsim devices
  while should_continue() do
    log.info("making discovery request")
    discovery.find_cb(
      nil, -- find all things
      function(device)
        -- handle when any (known or new) device responds
        local id = device.id
        local ip = device.ip
        local name = device.name or "Unnamed ThingSim RPC Client"

        -- but only add if we didn't already know about it and haven't just found it in a prev loop
        if not known_devices[id] and not found_devices[id] then
          found_devices[id] = true
          log.info(string.format("adding %s at %s", name or id, ip))
          assert(
            driver:try_create_device({
              type = "LAN",
              device_network_id = id,
              label = name,
              profile = "thingsim.onoff.v1",
              manufacturer = "thingsim",
              model = "On/Off Bulb",
              vendor_provided_name = name
            }),
            "failed to send found_device"
          )
        end
      end
    )
  end
  log.info("exiting discovery")
end

----------------------------------------------------------------------------------------------------
-- Command Handlers
----------------------------------------------------------------------------------------------------

function handle_on(driver, device, command)
  log.info("switch on", device.id)

  local client = assert(get_thing_client(device))
  if client:setattr{power = "on"} then
    device:emit_event(capabilities.switch.switch.on())
  else
    log.error("failed to set power on")
  end
end

function handle_off(driver, device, command)
  log.info("switch off", device.id)

  local client = assert(get_thing_client(device))
  if client:setattr{power = "off"} then
    device:emit_event(capabilities.switch.switch.off())
  else
    log.error("failed to set power on")
  end
end

----------------------------------------------------------------------------------------------------
-- Build and Run Driver
----------------------------------------------------------------------------------------------------

local rpc_client_driver = Driver("rpc client",
  {
    discovery = discovery_handler,
    lifecycle_handlers = {
      added = device_added,
      init = device_init,
    },
    capability_handlers = {
      [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = handle_on,
        [capabilities.switch.commands.off.NAME] = handle_off
      },
    }
  }
)

rpc_client_driver.bulb_handles = {}

rpc_client_driver:run()
