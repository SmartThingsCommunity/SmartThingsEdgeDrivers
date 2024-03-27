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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local OnOff = zcl_clusters.OnOff

local ZIGBEE_METERING_PLUG_FINGERPRINTS = {
  { mfr = "REXENSE", model = "HY0105" }          -- HONYAR Outlet"
}

local function switch_on_handler(driver, device, command)
  device:send_to_component(command.component, OnOff.server.commands.On(device))
  device:send(OnOff.server.commands.On(device):to_endpoint(0x02))
end

local function switch_off_handler(driver, device, command)
  device:send_to_component(command.component, OnOff.server.commands.Off(device))
  device:send(OnOff.server.commands.Off(device):to_endpoint(0x02))
end

local function is_zigbee_metering_plug(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_METERING_PLUG_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("rexense")
      return true, subdriver
    end
  end

  return false
end

local zigbee_metering_plug = {
  NAME = "zigbee metering plug",
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    }
  },
  can_handle = is_zigbee_metering_plug
}

return zigbee_metering_plug
