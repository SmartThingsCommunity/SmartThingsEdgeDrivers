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

-- This device needs to pair with an Identify command and send an acknowledgement for both the push and hold option.
-- Best way to do this is to press the pairing button 4 times within 5 seconds.
-- The LED will flash fast and then breath flash
-- Wait 10 seconds and then pair with the hub
-- The trick is making sure the Identify has worked properly otherwise the switch will not send push or hold Zigbee commands.

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local log = require "log"
local button_utils = require "button_utils"
local device_management = require "st.zigbee.device_management"

local Level = clusters.Level
local OnOff = clusters.OnOff
local Identify = clusters.Identify

local function added_handler(self, device)
  log.info("added handler")
  for comp_name, comp in pairs(device.profile.components) do
    device:emit_component_event(comp, capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }}))
    if comp_name == "main" then
      device:emit_component_event(comp, capabilities.button.numberOfButtons({value = 2}, {visibility = { displayed = false }}))
    else
      device:emit_component_event(comp, capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
    end
  end
--  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:emit_event(capabilities.button.button.pushed({state_change = false}))
end

local do_configure = function(self, device)
--  log.info(self.environment_info.hub_zigbee_eui)
  log.info("do_configure")
--  device:send()
-- device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  return(true)
end

local do_refresh = function(self, device)
  log.info("do_refresh")
--  log(self.environment_info.hub_zigbee_eui)
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
end


local IdentifyResponse = function(self, device, zb_mess)
  log.info("...............IdentifyResponse.................")
--  log(self.environment_info.hub_zigbee_eui)
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
end

local RODRET_Dimmer = {
  NAME = "REDRET Dimmer",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    cluster = {
      [Identify.ID] = {
        [Identify.server.commands.IdentifyQuery.ID] = IdentifyResponse,
        [Identify.server.commands.Identify.ID] = IdentifyResponse
      },
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = button_utils.build_button_handler("button1", capabilities.button.button.pushed),
        [OnOff.server.commands.Off.ID] = button_utils.build_button_handler("button2", capabilities.button.button.pushed)
      },
      [Level.ID] = {
        [Level.server.commands.MoveWithOnOff.ID] = button_utils.build_button_handler("button1", capabilities.button.button.held),
        [Level.server.commands.Move.ID] = button_utils.build_button_handler("button2", capabilities.button.button.held)
      }
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = added_handler
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "RODRET Dimmer"
  end
}

--[Level.server.commands.StepWithOnOff.ID] = button_utils.build_button_handler("on", capabilities.button.button.held)
--[Level.server.commands.Step.ID] = button_utils.build_button_handler("off", capabilities.button.button.held),




return RODRET_Dimmer
