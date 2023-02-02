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

local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local presence_utils = require "presence_utils"

-- Capabilities
local capabilities   = require "st.capabilities"
local Tone           = capabilities.tone
local PresenceSensor = capabilities.presenceSensor

-- Zigbee Spec Utils
local clusters             = require "st.zigbee.zcl.clusters"
local Basic                = clusters.Basic
local PowerConfiguration   = clusters.PowerConfiguration
local IdentifyCluster      = clusters.Identify
local zcl_global_commands  = require "st.zigbee.zcl.global_commands"
local Status               = (require "st.zigbee.zcl.types").ZclStatus

local buf_lib = require "st.buf"
local zb_messages = require "st.zigbee.messages"

local BEEP_IDENTIFY_TIME = 5 -- seconds
local IS_PRESENCE_BASED_ON_BATTERY_REPORTS = "isPresenceBasedOnBatteryReports"
local ST_ARRIVAL_SENSOR_CUSTOM_PROFILE = 0xFC01
local DEFAULT_PRESENCE_TIMEOUT_S = 120

local battery_voltage_attr_configuration = {
  cluster = PowerConfiguration.ID,
  attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
  minimum_interval = 1,
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

local function battery_config_response_handler(self, device, zb_rx)
  if zb_rx.body.zcl_body.global_status.value == Status.SUCCESS then
    device:set_field(IS_PRESENCE_BASED_ON_BATTERY_REPORTS, true, {persist = true})
    local poll_timer = device:get_field(presence_utils.RECURRING_POLL_TIMER)
    if poll_timer ~= nil then
      device.thread:cancel_timer(poll_timer)
      device:set_field(presence_utils.RECURRING_POLL_TIMER, nil)
    end
  end
end

local function create_poll_schedule(device)
  local should_schedule_recurring_polling = not (device:get_field(IS_PRESENCE_BASED_ON_BATTERY_REPORTS) or true)
  local timer = device:get_field(presence_utils.RECURRING_POLL_TIMER)
  if should_schedule_recurring_polling then
    if timer ~= nil then
      device.thread:cancel_timer(timer)
    end
    -- Set the poll interval to 1/2 the actual check interval so a single missed message doens't result in not present
    local new_timer = device.thread:call_on_schedule(math.floor(device.preferences.check_interval / 2) - 1, function()
      device:send(Basic.attributes.ZCLVersion:read(device))
    end, "polling_schedule_timer")
    device:set_field(presence_utils.RECURRING_POLL_TIMER, new_timer)
  elseif timer ~= nil then
    device.thread:cancel_timer(timer)
    device:set_field(presence_utils.RECURRING_POLL_TIMER, nil)
  end
end

local function info_changed(self, device, event, args)
  if args.old_st_store.preferences.check_interval ~= device.preferences.check_interval then
    create_poll_schedule(device)
  end
end

local function get_check_interval_int(device)
  if type(device.preferences.checkInterval) == "number" then
    return device.preferences.checkInterval
  elseif type(device.preferences.checkInterval) == "string" and tonumber(device.preferences.checkInterval) ~= nil then
    return tonumber(device.preferences.checkInterval)
  end
  return DEFAULT_PRESENCE_TIMEOUT_S
end

local function init_handler(self, device, event, args)
  device:set_field(battery_defaults.DEVICE_VOLTAGE_TABLE_KEY, battery_table)
  device:add_configured_attribute(battery_voltage_attr_configuration)
  device:add_monitored_attribute(battery_voltage_attr_configuration)
  device:remove_monitored_attribute(PowerConfiguration.ID, PowerConfiguration.attributes.BatteryPercentageRemaining.ID)
  device:remove_configured_attribute(PowerConfiguration.ID, PowerConfiguration.attributes.BatteryPercentageRemaining.ID)

  device:set_field(
      presence_utils.PRESENCE_CALLBACK_CREATE_FN,
      function(device)
        return device.thread:call_with_delay(
                  get_check_interval_int(device),
                  function()
                    device:emit_event(PresenceSensor.presence("not present"))
                    device:set_field(presence_utils.PRESENCE_CALLBACK_TIMER, nil)
                  end
        )
      end
  )

  local should_schedule_recurring_polling = not (device:get_field(IS_PRESENCE_BASED_ON_BATTERY_REPORTS) or true)
  if should_schedule_recurring_polling then
    create_poll_schedule(device)
  end
  presence_utils.create_presence_timeout(device)
end

local function beep_handler(self, device, command)
  device:send(IdentifyCluster.server.commands.Identify(device, BEEP_IDENTIFY_TIME))
end

local function added_handler(self, device)
  -- device:emit_event(PresenceSensor.presence("present"))
  device:set_field(IS_PRESENCE_BASED_ON_BATTERY_REPORTS, false, {persist = true})
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
end

local function poke(device)
  -- If we receive any message from the device, we should mark it present and start the timeout to mark it offline
  device:emit_event(PresenceSensor.presence("present"))
  presence_utils.create_presence_timeout(device)
end

local function all_zigbee_message_handler(self, message_channel)
  local device_uuid, data = message_channel:receive()
  local buf = buf_lib.Reader(data)
  local zb_rx = zb_messages.ZigbeeMessageRx.deserialize(buf, {additional_zcl_profiles = self.additional_zcl_profiles})
  local device = self:get_device_info(device_uuid)
  if zb_rx ~= nil then
    device.log.info(string.format("received Zigbee message: %s", zb_rx:pretty_print()))
    device:attribute_monitor(zb_rx)
    poke(device)
    device.thread:queue_event(self.zigbee_message_dispatcher.dispatch, self.zigbee_message_dispatcher, self, device, zb_rx)
  end
end

local zigbee_presence_driver = {
  supported_capabilities = {
    capabilities.presenceSensor,
    capabilities.tone,
    capabilities.battery,
    capabilities.refresh
  },
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_defaults.battery_volt_attr_handler
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
    init = init_handler,
    infoChanged = info_changed,
  },
  additional_zcl_profiles = {
    [ST_ARRIVAL_SENSOR_CUSTOM_PROFILE] = true
  },
  -- Custom handler for every Zigbee message
  zigbee_message_handler = all_zigbee_message_handler,
  sub_drivers = {
    require("arrival-sensor-v1")
  }
}

defaults.register_for_default_handlers(zigbee_presence_driver, zigbee_presence_driver.supported_capabilities)
local driver = ZigbeeDriver("zigbee-presence-sensor", zigbee_presence_driver)
driver:run()
