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

local cc = require "st.zwave.CommandClass"
local Basic = (require "st.zwave.CommandClass.Basic")({version=1,strict=true})
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
local BatteryDefaults = require "st.zwave.defaults.battery"

local UTILITECH_MFR = 0x0060
local UTILITECH_SIREN_PRODUCT_ID = 0x0001

local function can_handle_utilitech_siren(opts, driver, device, ...)
  return device.zwave_manufacturer_id == UTILITECH_MFR and device.zwave_product_id == UTILITECH_SIREN_PRODUCT_ID
end

local function device_added(self, device)
  device:send(Basic:Get({}))
  device:send(Battery:Get({}))
end

local function battery_report_handler(self, device, cmd)
  -- The Utilitech siren always sends low battery events (0xFF) below 20%,
	-- so we will ignore 0% events that sometimes seem to come before valid events.
  if cmd.args.battery_level ~= 0 then
    BatteryDefaults.zwave_handlers[cc.BATTERY][Battery.REPORT](self, device, cmd)
  end
end

local utilitech_siren = {
  NAME = "utilitech-siren",
  can_handle = can_handle_utilitech_siren,
  zwave_handlers = {
    [cc.BATTERY] = {
      [Battery.REPORT] = battery_report_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  }
}

return utilitech_siren
