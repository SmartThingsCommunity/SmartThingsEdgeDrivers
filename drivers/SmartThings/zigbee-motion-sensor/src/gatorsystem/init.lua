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
local zcl_clusters = require "st.zigbee.zcl.clusters"
local IASZone = zcl_clusters.IASZone

local generate_event_from_zone_status = function(driver, device, zone_status, zigbee_message)
  local result_occupied = 0x8000
  local result_open = 0x4000
  local result_close = 0x2000
  local result_battery_new = 0x1000
  local result_battery_low = 0x0800
  if zone_status:is_alarm1_set() then
    device:emit_event(capabilities.motionSensor.motion.active())
    -- emit inactive after 2 minutes
    device.thread:call_with_delay(120, function(d)
      device:emit_event(capabilities.motionSensor.motion.inactive())
    end
    )
  elseif zone_status:is_battery_low_set() then
    device:emit_event(capabilities.battery.battery(10))
  elseif zone_status.value == result_occupied then
    device:emit_event(capabilities.presenceSensor.presence.present())
    -- emit inactive after 1 minute
    device.thread:call_with_delay(60, function(d)
      device:emit_event(capabilities.presenceSensor.presence.not_present())
    end
    )
  elseif zone_status.value == result_open or zone_status.value == result_close then
    device:emit_event(zone_status.value == result_open and capabilities.contactSensor.contact.open() or capabilities.contactSensor.contact.closed())
  elseif zone_status.value == result_battery_new then
    device:emit_event(capabilities.battery.battery(100))
  elseif zone_status.value == result_battery_low then
    device:emit_event(capabilities.battery.battery(0))
  end
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local device_added = function(self, device)
  -- device:emit_event(capabilities.motionSensor.motion.inactive())
  -- device:emit_event(capabilities.contactSensor.contact.closed())
  -- device:emit_event(capabilities.presenceSensor.presence.not_present())
  -- device:emit_event(capabilities.battery.battery(100))
end

local do_configure = function(self, device)
  -- Override default as none of attribute requires to be configured
end

local gator_handler = {
  NAME = "GatorSystem Handler",
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "GatorSystem" and device:get_model() == "GSHW01"
  end
}

return gator_handler
