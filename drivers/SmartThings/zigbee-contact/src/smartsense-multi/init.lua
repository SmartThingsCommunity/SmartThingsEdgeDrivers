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
local multi_utils = require "multi-sensor/multi_utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local contactSensor_defaults = require "st.zigbee.defaults.contactSensor_defaults"

local ACCELERATION_MASK = 0x01
local CONTACT_MASK = 0x02
local SMARTSENSE_MULTI_CLUSTER = 0xFC03
local SMARTSENSE_MULTI_ACC_CMD = 0x00
local SMARTSENSE_MULTI_XYZ_CMD = 0x05
local SMARTSENSE_MULTI_STATUS_CMD = 0x07
local SMARTSENSE_MULTI_STATUS_REPORT_CMD = 0x09
local SMARTSENSE_PROFILE_ID = 0xFC01

local SMARTSENSE_MULTI_FINGERPRINTS = {
  { mfr = "SmartThings", model = "PGC313" },
  { mfr = "SmartThings", model = "PGC313EU" }
}

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(SMARTSENSE_MULTI_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  if device.zigbee_endpoints[1].profileId == SMARTSENSE_PROFILE_ID then return true end
  return false
end

local function acceleration_handler(driver, device, zb_rx)
  -- This is a custom cluster command for the kickstarter multi.
  -- This has no body but is sent everytime the accelerometer transitions from an unmoving state to a moving one.
  device:emit_event(capabilities.accelerationSensor.acceleration.active())
end

local function battery_handler(device, value, zb_rx)
  local MAX_VOLTAGE = 3.0
  local batteryPercentage = math.min(math.floor(((value / MAX_VOLTAGE) * 100) + 0.5), 100)

  if batteryPercentage ~= nil then
    device:emit_event_for_endpoint(
      zb_rx.address_header.src_endpoint.value,
      capabilities.battery.battery(batteryPercentage)
    )
  end
end

local function zone_status_change_handler(driver, device, zb_rx)
  if not device.preferences["certifiedpreferences.garageSensor"] then
    contactSensor_defaults.ias_zone_status_change_handler(driver, device, zb_rx)
  end
end

local function zone_status_handler(driver, device, zone_status, zb_rx)
  if not device.preferences["certifiedpreferences.garageSensor"] then
    contactSensor_defaults.ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  end
end

local function contact_handler(device, value)
  local event
  if not device.preferences["certifiedpreferences.garageSensor"] then
    if value == 0x01 then
      event = capabilities.contactSensor.contact.open()
    else
      event = capabilities.contactSensor.contact.closed()
    end
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

local function temperature_handler(device, temperature)
  -- legacy code (C):
  -- Value is in tenths of a degree so divide by 10.
  -- tempEventVal = ((float)attrVal.int16Val) / 10.0 + tempOffsetVal
  -- tempOffset is handled outside of the driver

  -- if temperature > 32767, this represents a negative number in int16 data types
  -- Apply 'two's complement' to temperature value
  if temperature > 32767 then
    temperature = temperature - 65536
  end

  local tempDivisor = 10.0
  local tempCelsius = temperature / tempDivisor
  device:emit_event(capabilities.temperatureMeasurement.temperature({value = tempCelsius, unit = "C"}))
end

local function status_handler(driver, device, zb_rx)
  -- This is a custom cluster command for the kickstarter multi.  It contains 2 fields
  -- a 16-bit temp field and an 8-bit status field
  -- The status fields is further broken up into 3 bit values:
  --   bit 0 is 1 if acceleration is active otherwise 0.
  --   bit 1 is 1 if the contact sensor is open otherwise 0
  --   bit 2-7 is a 6 bit battery voltage value in tenths of a volt
  local batteryDivisor = 10
  local temperature = zb_rx.body.zcl_body.body_bytes:byte(1) | (zb_rx.body.zcl_body.body_bytes:byte(2) << 8)
  local status = zb_rx.body.zcl_body.body_bytes:byte(3)
  local acceleration = status & ACCELERATION_MASK
  local contact = (status & CONTACT_MASK) >> 1
  local battery = (status >> 2) / batteryDivisor
  multi_utils.handle_acceleration_report(device, acceleration)
  contact_handler(device, contact)
  battery_handler(device, battery, zb_rx)
  temperature_handler(device, temperature)
end

local function status_report_handler(driver, device, zb_rx)
  -- This is a custom cluster command for the kickstarter multi.  It contains 3 fields
  -- a 16-bit temp field, an 8-bit status field and an 8-bit battery voltage field (this field is battery voltage * 40).
  -- The status fields is further broken up into 2 bit values:
  --   bit 0 is 1 if acceleration is active otherwise 0.
  --   bit 1 is 1 if the contact sensor is open otherwise 0
  local batteryDivisor = 40
  local temperature = zb_rx.body.zcl_body.body_bytes:byte(1) | (zb_rx.body.zcl_body.body_bytes:byte(2) << 8)
  local status = zb_rx.body.zcl_body.body_bytes:byte(3)
  local acceleration = status & ACCELERATION_MASK
  local contact = (status & CONTACT_MASK) >> 1
  local battery = zb_rx.body.zcl_body.body_bytes:byte(4) / batteryDivisor
  multi_utils.handle_acceleration_report(device, acceleration)
  contact_handler(device, contact)
  battery_handler(device, battery, zb_rx)
  temperature_handler(device, temperature)
end


local function xyz_handler(driver, device, zb_rx)
  -- This is a custom cluster command for the kickstarter multi.
  -- It contains 3 2 byte signed integers which are X,Y,Z acceleration values that are used to define orientation.
  local x = multi_utils.convert_to_signedInt16(zb_rx.body.zcl_body.body_bytes:byte(1), zb_rx.body.zcl_body.body_bytes:byte(2))
  local y = multi_utils.convert_to_signedInt16(zb_rx.body.zcl_body.body_bytes:byte(3), zb_rx.body.zcl_body.body_bytes:byte(4))
  local z = multi_utils.convert_to_signedInt16(zb_rx.body.zcl_body.body_bytes:byte(5), zb_rx.body.zcl_body.body_bytes:byte(6))
  multi_utils.handle_three_axis_report(device, x, y, z)
end

local smartsense_multi = {
  NAME = "SmartSense Multi",
  zigbee_handlers = {
    cluster = {
      [SMARTSENSE_MULTI_CLUSTER] = {
        [SMARTSENSE_MULTI_ACC_CMD] = acceleration_handler,
        [SMARTSENSE_MULTI_XYZ_CMD] = xyz_handler,
        [SMARTSENSE_MULTI_STATUS_CMD] = status_handler,
        [SMARTSENSE_MULTI_STATUS_REPORT_CMD] = status_report_handler
      },
      [zcl_clusters.IASZone.ID] = {
        [zcl_clusters.IASZone.client.commands.ZoneStatusChangeNotification.ID] = zone_status_change_handler
      }
    },
    attr = {
      [zcl_clusters.IASZone.ID] = {
        [zcl_clusters.IASZone.attributes.ZoneStatus.ID] = zone_status_handler
      }
    }
  },
  can_handle = can_handle
}

return smartsense_multi
