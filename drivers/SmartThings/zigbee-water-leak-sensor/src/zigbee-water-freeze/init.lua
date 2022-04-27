-- Copyright 2021 SmartThings
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

local device_management = require "st.zigbee.device_management"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"

local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement
local PollControl = zcl_clusters.PollControl

-- the default amount of time between check-ins by the poll control server with the poll control client
local CHECK_IN_INTERVAL = 7200
-- the number of quarterseconds that an end device waits between MAC Data Requests to its parent when it is expecting data
local SHORT_POLL_INTERVAL = 512
-- the number of quarterseconds that an end device will stay in fast poll mode by default
local FAST_POLL_TIMEOUT = 40
-- the frequency of polling that an end device does when it is not in fast poll mode
local LONG_POLL_INTERVAL = 2969829376

local function temperature_attr_handler(driver, device, value, zb_rx)
  local raw_temp = value.value
  local celc_temp = raw_temp / 100.0
  local temp_scale = "C"

  device:emit_event_for_endpoint(
    zb_rx.address_header.src_endpoint.value,
    celc_temp <= 0 and capabilities.temperatureAlarm.temperatureAlarm.freeze() or capabilities.temperatureAlarm.temperatureAlarm.cleared())

  device:emit_event_for_endpoint(
    zb_rx.address_header.src_endpoint.value,
    capabilities.temperatureMeasurement.temperature({value = celc_temp, unit = temp_scale }))
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  device:send(device_management.build_bind_request(device, PollControl.ID, self.environment_info.hub_zigbee_eui))
  device:send(PollControl.attributes.CheckInInterval:write(device, data_types.Uint32(CHECK_IN_INTERVAL)))
  device:send(PollControl.server.commands.SetShortPollInterval(device, data_types.Uint16(SHORT_POLL_INTERVAL)))
  device:send(PollControl.attributes.FastPollTimeout:write(device, data_types.Uint16(FAST_POLL_TIMEOUT)))
  device:send(PollControl.server.commands.SetLongPollInterval(device, data_types.Uint32(LONG_POLL_INTERVAL)))
end

local zigbee_water_freeze = {
  NAME = "zigbee water freeze sensor",
  zigbee_handlers = {
    attr = {
      [TemperatureMeasurement.ID] = {
        [TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Ecolink" and device:get_model() == "FLZB1-ECO"
  end
}

return zigbee_water_freeze
