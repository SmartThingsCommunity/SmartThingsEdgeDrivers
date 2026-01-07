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

local lazy_load_if_possible = function(sub_driver_name)
  -- gets the current lua libs api version
  local version = require "version"
  -- if version.api >= 16 then
  --   return ZwaveDriver.lazy_load_sub_driver_v2(sub_driver_name)
  if version.api >= 9 then
    return ZwaveDriver.lazy_load_sub_driver(require(sub_driver_name))
  else
    return require(sub_driver_name)
  end
end

local do_refresh = function(self, device)
  local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
  local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
  device:send(DoorLock:OperationGet({}))
  device:send(Battery:Get({}))
end

local function time_get_handler(driver, device, cmd)
  local Time = (require "st.zwave.CommandClass.Time")({ version = 1 })
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
    capabilities.lockUsers,
    capabilities.lockCredentials,
    capabilities.battery,
    capabilities.tamperAlert
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zwave_handlers = {
    [cc.TIME] = {
      [0x01] = time_get_handler -- used by DanaLock
    }
  },
  sub_drivers = {
    lazy_load_if_possible("using-old-capabilities"),
    lazy_load_if_possible("using-new-capabilities"),
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local lock = ZwaveDriver("zwave_lock", driver_template)
lock:run()
