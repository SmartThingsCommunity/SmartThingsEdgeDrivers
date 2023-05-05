-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local DoorLock = clusters.DoorLock
local Lock = capabilities.lock
local lock_utils = require "lock_utils"

local SAMSUNG_SDS_MFR_SPECIFIC_UNLOCK_COMMAND = 0x1F
local SAMSUNG_SDS_MFR_CODE = 0x0003

local function handle_lock_state(driver, device, value, zb_rx)
  if value.value == DoorLock.attributes.LockState.LOCKED then
    device:emit_event(Lock.lock.locked())
  elseif value.value == DoorLock.attributes.LockState.UNLOCKED then
    device:emit_event(Lock.lock.unlocked())
  else
    device:emit_event(Lock.lock.unknown())
  end
end

local function mfg_lock_door_handler(driver, device, zb_rx)
  local cmd = zb_rx.body.zcl_body.body_bytes:byte(1)
  if cmd == 0x00 then
    device:emit_event(Lock.lock.unlocked())
  end
end

local function unlock_cmd_handler(driver, device, command)
  device:send(cluster_base.build_manufacturer_specific_command(
          device,
          DoorLock.ID,
          SAMSUNG_SDS_MFR_SPECIFIC_UNLOCK_COMMAND,
          SAMSUNG_SDS_MFR_CODE,
          "\x10\x04\x31\x32\x33\x35"))
end

local device_added = function(self, device)
  lock_utils.populate_state_from_data(device)
  -- device:emit_event(capabilities.lock.lock.unlocked())
  -- device:emit_event(capabilities.battery.battery(100))
end

local battery_init = battery_defaults.build_linear_voltage_init(4.0, 6.0)

local device_init = function(driver, device, event)
  battery_init(driver, device, event)
  lock_utils.populate_state_from_data(device)
end

local samsung_sds_driver = {
  NAME = "SAMSUNG SDS Lock Driver",
  zigbee_handlers = {
    cluster = {
      [DoorLock.ID] = {
        [SAMSUNG_SDS_MFR_SPECIFIC_UNLOCK_COMMAND] = mfg_lock_door_handler
      }
    },
    attr = {
      [DoorLock.ID] = {
        [DoorLock.attributes.LockState.ID] = handle_lock_state
      }
    }
  },
  capability_handlers = {
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.unlock.NAME] = unlock_cmd_handler
    }
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "SAMSUNG SDS"
  end
}

return samsung_sds_driver
