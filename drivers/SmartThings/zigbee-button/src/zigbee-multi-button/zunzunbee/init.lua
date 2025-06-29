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
local Tone           = capabilities.tone
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local utils = require "st.utils"
local device_management = require "st.zigbee.device_management"
local IASZone = (require "st.zigbee.zcl.clusters").IASZone
local IdentifyCluster      = clusters.Identify

local log = require "log"
local button_utils = require "button_utils"

local BEEP_IDENTIFY_TIME = 5 -- time in seconds

local battery_config = utils.deep_copy(battery_defaults.default_percentage_configuration)
battery_config.reportable_change = 0x02
--battery_config.maximum_interval = 1800
battery_config.data_type = clusters.PowerConfiguration.attributes.BatteryVoltage.base_type


local ZUNZUNBEE_BUTTON_FINGERPRINTS = {
  { mfr = "zunzunbee", model = "SSWZ8T"}
}

local function init_handler(self, device)
  device:add_configured_attribute(battery_config)
  device:add_monitored_attribute(battery_config)
end

local is_zunzunbee_button = function(opts, driver, device)
  for _, fingerprint in ipairs(ZUNZUNBEE_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then      
      return true
    end
  end
  return false
end

local generate_button_event_from_zone_status = function(driver, device, zone_status, zb_rx)
  local event
  local button_name = "main"
  local number_of_buttons = 1
  local additional_fields = {
    state_change = true
  }
  event = nil
 
 -- check number of buttons encoded in zone_status attribute
  if tonumber(zone_status.value) > 0x0400 then
	number_of_buttons = 1
  end
  if tonumber(zone_status.value)  > 0x0800 then
	number_of_buttons = 2
  end
  if tonumber(zone_status.value) > 0x0C00 then
	number_of_buttons = 3
  end
  if tonumber(zone_status.value) > 0x1000 then
    number_of_buttons = 4
  end
  if tonumber(zone_status.value) > 0x1400 then
    number_of_buttons = 5
  end
  if tonumber(zone_status.value) > 0x1800 then
	number_of_buttons = 6
  end
  if tonumber(zone_status.value) > 0x1C00 then
	number_of_buttons = 7
  end  
  if tonumber(zone_status.value) > 0x2000 then
	number_of_buttons = 8
  end  
  event = capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = true } })
  -- set number of buttons to component - main
  local comp = device.profile.components["main"]
  device:emit_component_event(comp, event)
  -- emit event based on button number bit set in zone_status. 
  if zone_status:is_alarm2_set() and zone_status:is_alarm1_set() then
    button_name = "button1"
    event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_alarm2_set() then
    button_name = "button1"
    event = capabilities.button.button.pushed(additional_fields)
  elseif zone_status:is_tamper_set() and zone_status:is_alarm1_set() then
    button_name = "button2"
    event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_tamper_set() then
    button_name = "button2"
	event = capabilities.button.button.pushed(additional_fields)
  elseif zone_status:is_battery_low_set() and zone_status:is_alarm1_set() then
    button_name = "button3"
	event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_battery_low_set() then
    button_name = "button3"
	event = capabilities.button.button.pushed(additional_fields)
  elseif zone_status:is_supervision_notify_set() and zone_status:is_alarm1_set() then
    button_name = "button4"
	event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_supervision_notify_set() then
    button_name = "button4"
	event = capabilities.button.button.pushed(additional_fields)
  elseif zone_status:is_restore_notify_set() and zone_status:is_alarm1_set() then
    button_name = "button5"
	event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_restore_notify_set() then
    button_name = "button5"
	event = capabilities.button.button.pushed(additional_fields)
  elseif zone_status:is_trouble_set() and zone_status:is_alarm1_set() then
    button_name = "button6"
	event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_trouble_set() then
    button_name = "button6"
	event = capabilities.button.button.pushed(additional_fields)
  elseif zone_status:is_ac_mains_fault_set() and zone_status:is_alarm1_set() then
    button_name = "button7"
	event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_ac_mains_fault_set() then
    button_name = "button7"
	event = capabilities.button.button.pushed(additional_fields)
  elseif zone_status:is_test_set() and zone_status:is_alarm1_set() then
    button_name = "button8"
	event = capabilities.button.button.held(additional_fields)
  elseif zone_status:is_test_set() then
    button_name = "button8"
	event = capabilities.button.button.pushed(additional_fields)	
  end  
  local component = device.profile.components[button_name]
  if component ~= nil and event ~= nil then
      device:emit_component_event(component, event)
  else
      log.warn("Attempted to emit button event for non-existing component: " .. button_name)
  end
  -- By default emit any button press on "main" component. "Main" represents any button press
  component = device.profile.components["main"]
  if event ~= nil then
      device:emit_component_event(component, event)
  else
      log.warn("Attempted to emit button event for non-existing component: " .. button_name)
  end
end

--- @param driver Driver The current driver running containing necessary context for execution
--- @param device ZigbeeDevice The device this message was received from containing identifying information
--- @param zone_status 2 byte bitmap zoneStatus attribute value of the IAS Zone cluster
--- @param zb_rx ZigbeeMessageRx the full message this report came in
local ias_zone_status_attr_handler = function(driver, device, zone_status, zb_rx)
  generate_button_event_from_zone_status(driver, device, zone_status, zb_rx)
end

--- @param driver Driver The current driver running containing necessary context for execution
--- @param device ZigbeeDevice The device this message was received from containing identifying information
--- @param zb_rx containing zoneStatus attribute value of the IAS Zone cluster
local ias_zone_status_change_handler = function(driver, device, zb_rx)
  generate_button_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local function beep_handler(self, device, command)
  device:send(IdentifyCluster.server.commands.Identify(device, BEEP_IDENTIFY_TIME))
end

local zunzunbee_device_handler = {
  NAME = "Zunzunbee Device handler",
  lifecycle_handlers = {
	init = init_handler	
  },
  supported_capabilities = {
    capabilities.button,
    capabilities.battery,
	capabilities.tone,
    capabilities.temperatureMeasurement
  },
  capability_handlers = {
    [Tone.ID] = {
      [Tone.commands.beep.NAME] = beep_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    },
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    }
  },
  can_handle = is_zunzunbee_button
}

return zunzunbee_device_handler
