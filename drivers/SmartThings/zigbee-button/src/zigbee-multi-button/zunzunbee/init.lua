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
local Tone = capabilities.tone
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local utils = require "st.utils"
local device_management = require "st.zigbee.device_management"
local IASZone = clusters.IASZone
local IdentifyCluster = clusters.Identify

local log = require "log"
local button_utils = require "button_utils"

-- Constants
local BEEP_IDENTIFY_TIME = 5 -- seconds for device beep duration

-- Configure battery reporting
local battery_config = utils.deep_copy(battery_defaults.default_percentage_configuration)
battery_config.reportable_change = 0x02
battery_config.data_type = clusters.PowerConfiguration.attributes.BatteryVoltage.base_type

-- List of supported device fingerprints
local ZUNZUNBEE_BUTTON_FINGERPRINTS = {
  { mfr = "zunzunbee", model = "SSWZ8T" }
}

-- Initialize device attributes
local function init_handler(self, device)
  device:add_configured_attribute(battery_config)
  device:add_monitored_attribute(battery_config)
end

-- Check if a given device matches the supported fingerprints
local function is_zunzunbee_button(opts, driver, device)
  for _, fingerprint in ipairs(ZUNZUNBEE_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

-- Generate and emit button events based on IAS Zone status attribute
local function generate_button_event_from_zone_status(driver, device, zone_status, zb_rx)
  local raw_value = tonumber(zone_status.value)
  -- zone_status: button press bit pattern
  -- Bit 0 : Held action status (1 if held, 0 if not)
  -- Bit 1 : Button 1 pressed (1 if pressed, 0 if not)
  -- Bit 2 : Button 2 pressed
  -- Bit 3 : Button 3 pressed
  -- Bit 4 : Button 4 pressed
  -- Bit 5 : Button 5 pressed
  -- Bit 6 : Button 6 pressed
  -- Bit 7 : Button 7 pressed
  -- Bit 8 : Button 8 pressed
  -- Bits 10-13: Number of buttons in the product (value from 1 to 8)

  -- Extract number of buttons from bits 10-13 (4 bits)
  local button_count_bits = (raw_value >> 10) & 0x0F
  local number_of_buttons = math.max(1, math.min(button_count_bits, 8))

  -- Emit numberOfButtons event
  local number_event = capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = true } })
  device:emit_component_event(device.profile.components["main"], number_event)

  -- Map of zone status bit checks to button component names
  local button_bit_map = {
    { check = "is_alarm2_set", name = "button1" },
    { check = "is_tamper_set", name = "button2" },
    { check = "is_battery_low_set", name = "button3" },
    { check = "is_supervision_notify_set", name = "button4" },
    { check = "is_restore_notify_set", name = "button5" },
    { check = "is_trouble_set", name = "button6" },
    { check = "is_ac_mains_fault_set", name = "button7" },
    { check = "is_test_set", name = "button8" }
  }

  local additional_fields = { state_change = true }
  local button_name, event
  

  -- Check which button bit is set and determine if it was a hold or push
  for _, entry in ipairs(button_bit_map) do
    if zone_status[entry.check](zone_status) then
      button_name = entry.name
      event = zone_status:is_alarm1_set() and
              capabilities.button.button.held(additional_fields) or
              capabilities.button.button.pushed(additional_fields)
      break
    end
  end

  -- Emit the button event to the specific button component
  if button_name and event then
    local component = device.profile.components[button_name]
    if component then
      device:emit_component_event(component, event)
    else
      log.warn("Attempted to emit button event for non-existing component: " .. button_name)
    end

    -- Also emit the event to the "main" component as a general indicator
    device:emit_component_event(device.profile.components["main"], event)
  end
end

--- @param driver Driver The current driver running containing necessary context for execution
--- @param device ZigbeeDevice The device this message was received from containing identifying information
--- @param zone_status 2 byte bitmap zoneStatus attribute value of the IAS Zone cluster
--- @param zb_rx ZigbeeMessageRx the full message this report came in
local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_button_event_from_zone_status(driver, device, zone_status, zb_rx)
end

--- @param driver Driver The current driver running containing necessary context for execution
--- @param device ZigbeeDevice The device this message was received from containing identifying information
--- @param zb_rx containing zoneStatus attribute value of the IAS Zone cl
local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_button_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

-- Handle the beep capability command by sending Identify command to the device
local function beep_handler(self, device, command)
  device:send(IdentifyCluster.server.commands.Identify(device, BEEP_IDENTIFY_TIME))
end

-- Main device handler definition
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
