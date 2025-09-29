-- Copyright 2025 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local IASZone = clusters.IASZone
local Basic = clusters.Basic
local PowerConfiguration = clusters.PowerConfiguration

local function generate_event_from_zone_status(driver, device, zone_status, zigbee_message)
  device:emit_event_for_endpoint(
    zigbee_message.address_header.src_endpoint.value,
    zone_status:is_ac_mains_fault_set() and capabilities.powerSource.powerSource.battery() or capabilities.powerSource.powerSource.mains()
  )
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local function device_added(driver, device)
  device:emit_event(capabilities.powerSource.powerSource.mains())
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(3.3, 4.1)(driver, device)
end

local function do_refresh(driver, device)
  device:send(Basic.attributes.ZCLVersion:read(device))
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  device:send(IASZone.attributes.ZoneStatus:read(device))
end

local frient_range_extender = {
  NAME = "frient Range Extender",
  lifecycle_handlers = {
    added = device_added,
    init = device_init
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
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
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "frient A/S" and (device:get_model() == "REXZB-111")
  end
}

return frient_range_extender