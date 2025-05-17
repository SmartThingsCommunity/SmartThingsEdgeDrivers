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

local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local IasZoneType = require "st.zigbee.generated.types.IasZoneType"
local device_management = require "st.zigbee.device_management"
local PowerConfiguration = clusters.PowerConfiguration

local CONTACT_SWITCH = IasZoneType.CONTACT_SWITCH
local MOTION_SENSOR = IasZoneType.MOTION_SENSOR
local WATER_SENSOR = IasZoneType.WATER_SENSOR

local ZIGBEE_GENERIC_SENSOR_PROFILE = "generic-sensor"
local ZIGBEE_GENERIC_CONTACT_SENSOR_PROFILE = "generic-contact-sensor"
local ZIGBEE_GENERIC_MOTION_SENSOR_PROFILE = "generic-motion-sensor"
local ZIGBEE_GENERIC_WATERLEAK_SENSOR_PROFILE = "generic-waterleak-sensor"
local ZIGBEE_GENERIC_MOTION_ILLUMINANCE_PROFILE = "generic-motion-illuminance"

local ZONETYPE = "ZoneType"
local IASZone = clusters.IASZone

-- ask device to upload its zone type
local device_added = function(self, device)
  device:send(IASZone.attributes.ZoneType:read(device))
end

-- configure reporting for IASZone cluster
local do_configure = function(self, device)
  device:configure()
  device:send(device_management.build_bind_request(device, IASZone.ID, self.environment_info.hub_zigbee_eui))
  device:send(IASZone.attributes.ZoneStatus:configure_reporting(device, 30, 300, 1))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:send(IASZone.attributes.ZoneStatus:read(device))
  end
end

-- update profile with different zone type
local function update_profile(device, zone_type)
  local profile = ZIGBEE_GENERIC_SENSOR_PROFILE
  if zone_type == CONTACT_SWITCH then
    profile = ZIGBEE_GENERIC_CONTACT_SENSOR_PROFILE
  elseif zone_type == WATER_SENSOR then
    profile = ZIGBEE_GENERIC_WATERLEAK_SENSOR_PROFILE
  elseif zone_type == MOTION_SENSOR then
    profile = ZIGBEE_GENERIC_MOTION_SENSOR_PROFILE
    for _, ep in ipairs(device.zigbee_endpoints) do
      if device:supports_server_cluster(clusters.IlluminanceMeasurement.ID, ep.id) then
        profile = ZIGBEE_GENERIC_MOTION_ILLUMINANCE_PROFILE
      end
    end
  end
  device:try_update_metadata({profile = profile})
end

-- read zone type and update profile
local ias_zone_type_attr_handler = function (driver, device, attr_val)
  device:set_field(ZONETYPE, attr_val.value)
  update_profile(device, attr_val.value)
end

local zigbee_generic_sensor_template = {
  supported_capabilities = {
    capabilities.battery,
    capabilities.firmwareUpdate,
    capabilities.refresh
  },
  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneType.ID] = ias_zone_type_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  sub_drivers = {
    require("contact"),
    require("motion"),
    require("waterleak"),
    require("motion-illuminance")
  },
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE
}

defaults.register_for_default_handlers(zigbee_generic_sensor_template, zigbee_generic_sensor_template.supported_capabilities)
local zigbee_sensor = ZigbeeDriver("zigbee-sensor", zigbee_generic_sensor_template)
zigbee_sensor:run()