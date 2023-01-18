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

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass.DoorLock
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.Time
local Time = (require "st.zwave.CommandClass.Time")({ version = 1 })
local constants = require "st.zwave.constants"
local utils = require "st.utils"
local json = require "st.json"

local SCAN_CODES_CHECK_INTERVAL = 30
local MIGRATION_COMPLETE = "migrationComplete"
local MIGRATION_RELOAD_SKIPPED = "migrationReloadSkipped"

local function periodic_codes_state_verification(driver, device)
  local scan_codes_state = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.scanCodes.NAME)
  if scan_codes_state == "Scanning" then
    driver:inject_capability_command(device,
            { capability = capabilities.lockCodes.ID,
              command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
              args = {}
            }
    )
    device.thread:call_with_delay(
      SCAN_CODES_CHECK_INTERVAL,
      function(d)
        periodic_codes_state_verification(driver, device)
      end
    )
  end
end

local function populate_state_from_data(device)
  if device.data.lockCodes ~= nil and device:get_field(MIGRATION_COMPLETE) ~= true then
    -- build the lockCodes table
    local lockCodes = {}
    local lc_data = json.decode(device.data.lockCodes)
    for k, v in pairs(lc_data) do
      lockCodes[k] = v
    end
    -- Populate the devices `lockCodes` field
    device:set_field(constants.LOCK_CODES, utils.deep_copy(lockCodes), { persist = true })
    -- Populate the devices state history cache
    device.state_cache["main"] = device.state_cache["main"] or {}
    device.state_cache["main"][capabilities.lockCodes.ID] = device.state_cache["main"][capabilities.lockCodes.ID] or {}
    device.state_cache["main"][capabilities.lockCodes.ID][capabilities.lockCodes.lockCodes.NAME] = {value = json.encode(utils.deep_copy(lockCodes))}

    device:set_field(MIGRATION_COMPLETE, true, { persist = true })
  end
end

--- Builds up initial state for the device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function added_handler(self, device)
  populate_state_from_data(device)
  if device.data.lockCodes == nil or device:get_field(MIGRATION_RELOAD_SKIPPED) == true then
    if (device:supports_capability(capabilities.lockCodes)) then
      self:inject_capability_command(device,
          { capability = capabilities.lockCodes.ID,
            command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
            args = {} })
      device.thread:call_with_delay(
          SCAN_CODES_CHECK_INTERVAL,
          function(d)
            periodic_codes_state_verification(self, device)
          end
      )
    end
  else
    device:set_field(MIGRATION_RELOAD_SKIPPED, true, { persist = true })
  end
  device:send(DoorLock:OperationGet({}))
  device:send(Battery:Get({}))
  -- if (device:supports_capability(capabilities.tamperAlert)) then
  --   device:emit_event(capabilities.tamperAlert.tamper.clear())
  -- end
end

local init_handler = function(driver, device, event)
  populate_state_from_data(device)
end

--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd table
local function update_codes(driver, device, cmd)
  local delay = 0
  -- args.codes is json
  for name, code in pairs(cmd.args.codes) do
    -- these seem to come in the format "code[slot#]: code"
    local code_slot = tonumber(string.gsub(name, "code", ""), 10)
    if (code_slot ~= nil) then
      if (code ~= nil and (code ~= "0" and code ~= "")) then
        -- code changed
        device.thread:call_with_delay(delay, function ()
          device:send(UserCode:Set({
            user_identifier = code_slot,
            user_code = code,
            user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}))
        end)
        delay = delay + 2.2
      else
        -- code deleted
        device.thread:call_with_delay(delay, function ()
          device:send(UserCode:Set({user_identifier = code_slot, user_id_status = UserCode.user_id_status.AVAILABLE}))
        end)
        delay = delay + 2.2
        device.thread:call_with_delay(delay, function ()
          device:send(UserCode:Get({user_identifier = code_slot}))
        end)
        delay = delay + 2.2
      end
    end
  end
end

local function time_get_handler(driver, device, cmd)
  local time = os.date("*t")
  device:send_to_component(
    Time:Report({
      hour_local_time = time.hour,
      minute_local_time = time.min,
      second_local_time = time.sec
    }),
    device:endpoint_to_component(cmd.src_channel)
  )
end

local driver_template = {
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCodes,
    capabilities.battery,
    capabilities.tamperAlert
  },
  lifecycle_handlers = {
    added = added_handler,
    init = init_handler,
  },
  capability_handlers = {
    [capabilities.lockCodes.ID] = {
      [capabilities.lockCodes.commands.updateCodes.NAME] = update_codes
    }
  },
  zwave_handlers = {
    [cc.TIME] = {
      [Time.GET] = time_get_handler -- used by DanaLock
    }
  },
  sub_drivers = {
    require("zwave-alarm-v1-lock"),
    require("schlage-lock"),
    require("samsung-lock"),
    require("keywe-lock")
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local lock = ZwaveDriver("zwave_lock", driver_template)
lock:run()
