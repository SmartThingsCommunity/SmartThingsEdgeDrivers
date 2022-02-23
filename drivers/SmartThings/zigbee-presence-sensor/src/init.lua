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
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local constants = require "st.zigbee.constants"

-- Capabilities
local capabilities   = require "st.capabilities"
local Tone           = capabilities.tone
local PresenceSensor = capabilities.presenceSensor
local SignalStrength = capabilities.signalStrength

-- Zigbee Spec Utils
local clusters             = require "st.zigbee.zcl.clusters"
local Basic                = clusters.Basic
local PowerConfiguration   = clusters.PowerConfiguration
local IdentifyCluster      = clusters.Identify
local zcl_global_commands  = require "st.zigbee.zcl.global_commands"
local Status               = (require "st.zigbee.zcl.types").ZclStatus

local BEEP_IDENTIFY_TIME = 5 -- seconds
local POLL_DEFAULT_INTERVAL = 20 -- seconds

local IS_PRESENCE_BASED_ON_BATTERY_REPORTS = "isPresenceBasedOnBatteryReports"

local LAST_BATTERY_REPORT_TIMESTAMP = "lastBatteryReportTimestamp" -- used when presence events are based on battery reports
local DEVICE_RESPONDED_TO_POLL_FIELD = "pollStatus"                -- used when presence events are based on recurring poll of Basic cluster's attribute

-- Timers
local PRESENCE_CALLBACK_TIMER = "presenceCallbackTimer" -- events are based on battery reports
local RECURRING_POLL_TIMER = "recurringPollTimer"       -- events are based on recurring poll of Basic cluster's attribute

local battery_voltage_attr_configuration = {
  cluster = PowerConfiguration.ID,
  attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
  minimum_interval = 20,
  maximum_interval = 21,
  data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
  reportable_change = 1
}

local battery_table = {
  [2.80] = 100,
  [2.70] = 100,
  [2.60] = 100,
  [2.50] = 90,
  [2.40] = 80,
  [2.30] = 70,
  [2.20] = 70,
  [2.10] = 50,
  [2.00] = 50,
  [1.90] = 30,
  [1.80] = 30,
  [1.70] = 15,
  [1.60] = 1,
  [1.50] = 0
}

local function send_presence_and_signal_events(device, zb_rx)
  device:emit_event(PresenceSensor.presence("present"))
  device:emit_event(SignalStrength.lqi(zb_rx.lqi.value))
  device:emit_event(SignalStrength.rssi({value = zb_rx.rssi.value, unit = 'dBm'}))
end

local function verify_presence_with_battery_report(device, zb_rx)
  send_presence_and_signal_events(device, zb_rx)
  device:set_field(LAST_BATTERY_REPORT_TIMESTAMP, os.time())
  local timer = device:get_field(PRESENCE_CALLBACK_TIMER)
  if timer ~= nil then
    device.thread:cancel_timer(timer)
  end
  timer = device.thread:call_with_delay(3 * POLL_DEFAULT_INTERVAL + 1, function() 
    device:emit_event(PresenceSensor.presence("not present"))
    device:set_field(PRESENCE_CALLBACK_TIMER, nil)
  end)
  device:set_field(PRESENCE_CALLBACK_TIMER, timer)
end

local function battery_voltage_handler(self, device, value, zb_rx)
  local is_presence_based_on_battery_reports = device:get_field(IS_PRESENCE_BASED_ON_BATTERY_REPORTS) or false
  if is_presence_based_on_battery_reports then
    verify_presence_with_battery_report(device, zb_rx)
  end
  battery_defaults.battery_volt_attr_handler(self, device, value, zb_rx)
end

local function battery_config_response_handler(self, device, zb_rx)
  if zb_rx.body.zcl_body.global_status.value == Status.SUCCESS then
    device:set_field(IS_PRESENCE_BASED_ON_BATTERY_REPORTS, true, {persist = true})
    local poll_timer = device:get_field(RECURRING_POLL_TIMER)
    if poll_timer ~= nil then
      device.thread:cancel_timer(poll_timer)
      device:set_field(RECURRING_POLL_TIMER, nil)
    end
  end
end

local function device_poll_response_handler(self, device, value, zb_rx)
  send_presence_and_signal_events(device, zb_rx)
  device:set_field(DEVICE_RESPONDED_TO_POLL_FIELD, true)
end

local function init_handler(self, device, event, args)
  device:set_field(battery_defaults.DEVICE_VOLTAGE_TABLE_KEY, battery_table)
  local should_schedule_recurring_polling = not device:get_field(IS_PRESENCE_BASED_ON_BATTERY_REPORTS)
  if should_schedule_recurring_polling then
    local timer = device.thread:call_on_schedule(POLL_DEFAULT_INTERVAL, function()
      if not device:get_field(DEVICE_RESPONDED_TO_POLL_FIELD) then
        device:emit_event(PresenceSensor.presence("not present"))
      end
      device:send(Basic.attributes.ZCLVersion:read(device))
      device:set_field(DEVICE_RESPONDED_TO_POLL_FIELD, false)
    end)
    device:set_field(RECURRING_POLL_TIMER, timer)
  end
end

local function beep_handler(self, device, command)
  device:send(IdentifyCluster.server.commands.Identify(device, BEEP_IDENTIFY_TIME))
end

local function custom_battery_voltage_config(device)
  device:add_configured_attribute(battery_voltage_attr_configuration)
  device:add_monitored_attribute(battery_voltage_attr_configuration)
  device:remove_monitored_attribute(PowerConfiguration.ID, PowerConfiguration.attributes.BatteryPercentageRemaining.ID)
  device:remove_configured_attribute(PowerConfiguration.ID, PowerConfiguration.attributes.BatteryPercentageRemaining.ID)
end

local function added_handler(self, device)
  custom_battery_voltage_config(device)
  device:emit_event(PresenceSensor.presence("present"))
  device:set_field(IS_PRESENCE_BASED_ON_BATTERY_REPORTS, false, {persist = true})
  device:set_field(DEVICE_RESPONDED_TO_POLL_FIELD, true)
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
end

local zigbee_presence_driver = {
  supported_capabilities = {
    capabilities.presenceSensor,
    capabilities.tone,
    capabilities.signalStrength,
    capabilities.battery,
    capabilities.refresh
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.ZCLVersion.ID] = device_poll_response_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_voltage_handler
      }
    },
    global = {
      [PowerConfiguration.ID] = {
        [zcl_global_commands.CONFIGURE_REPORTING_RESPONSE_ID] = battery_config_response_handler
      }
    }
  },
  capability_handlers = {
    [Tone.ID] = {
      [Tone.commands.beep.NAME] = beep_handler
    }
  },
  lifecycle_handlers = {
    added = added_handler,
    init = init_handler
  }--,
  -- sub_drivers = {
  --   require("arrival-sensor-v1")
  -- }
}

defaults.register_for_default_handlers(zigbee_presence_driver, zigbee_presence_driver.supported_capabilities)
local driver = ZigbeeDriver("zigbee-presence-sensor", zigbee_presence_driver)
driver:run()
