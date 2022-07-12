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
local device_management = require "st.zigbee.device_management"

local PollControl = clusters.PollControl

local CHECK_IN_INTERVAL = 0x00001C20
local SHORT_POLL_INTERVAL = 0x0200
local LONG_POLL_INTERVAL = 0xB1040000
local FAST_POLL_TIMEOUT = 0x0028

local ECOLINK_CONTACT_TEMPERATURE_FINGERPRINTS = {
  { mfr = "Ecolink", model = "4655BC0-R" },
  { mfr = "Ecolink", model = "DWZB1-ECO" }
}

local function can_handle_ecolink_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(ECOLINK_CONTACT_TEMPERATURE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function do_configure(driver, device)
  device:configure()
  device:send(device_management.build_bind_request(device, PollControl.ID, driver.environment_info.hub_zigbee_eui))
  device:refresh()
  device:send(PollControl.attributes.CheckInInterval:write(device, CHECK_IN_INTERVAL))
  device:send(PollControl.commands.SetShortPollInterval(device, SHORT_POLL_INTERVAL))
  device:send(PollControl.attributes.FastPollTimeout:write(device, FAST_POLL_TIMEOUT))
  device:send(PollControl.commands.SetLongPollInterval(device, LONG_POLL_INTERVAL))
end

local ecolink_sensor = {
  NAME = "Ecolink Contact Temperature",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_ecolink_sensor
}

return ecolink_sensor
