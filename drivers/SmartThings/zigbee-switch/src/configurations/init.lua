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


local CONFIGURATION_VERSION_KEY = "_configuration_version"
local CONFIGURATION_ATTEMPTED = "_reconfiguration_attempted"

local configurations = {}

configurations.check_and_reconfig_devices = function(driver)
  local clusters = require "st.zigbee.zcl.clusters"
  local capabilities = require "st.capabilities"
  local instantaneous_demand_configuration = {
    cluster = clusters.SimpleMetering.ID,
    attribute = clusters.SimpleMetering.attributes.InstantaneousDemand.ID,
    minimum_interval = 5,
    maximum_interval = 3600,
    data_type = clusters.SimpleMetering.attributes.InstantaneousDemand.base_type,
    reportable_change = 5
  }
  local active_power_configuration = {
    cluster = clusters.ElectricalMeasurement.ID,
    attribute = clusters.ElectricalMeasurement.attributes.ActivePower.ID,
    minimum_interval = 5,
    maximum_interval = 3600,
    data_type = clusters.ElectricalMeasurement.attributes.ActivePower.base_type,
    reportable_change = 5
  }

  for device_id, device in pairs(driver.device_cache) do
    local config_version = device:get_field(CONFIGURATION_VERSION_KEY)
    if config_version == nil or config_version < driver.current_config_version then
      if device:supports_capability(capabilities.powerMeter) then
        if device:supports_server_cluster(clusters.ElectricalMeasurement.ID) then
          -- Increase minimum reporting interval to 5 seconds
          device:send(clusters.ElectricalMeasurement.attributes.ActivePower:configure_reporting(device, 5, 600, 5))
          device:add_configured_attribute(active_power_configuration)
        end
        if device:supports_server_cluster(clusters.SimpleMetering.ID) then
          -- Increase minimum reporting interval to 5 seconds
          device:send(clusters.SimpleMetering.attributes.InstantaneousDemand:configure_reporting(device, 5, 600, 5))
          device:add_configured_attribute(instantaneous_demand_configuration)
        end
      end
      device:set_field(CONFIGURATION_ATTEMPTED, true, {persist = true})
    end
  end
  driver._reconfig_timer = nil
end

configurations.handle_reporting_config_response = function(driver, device, zb_mess)
  local Status = require "st.zigbee.generated.types.ZclStatus"
  local clusters = require "st.zigbee.zcl.clusters"
  local device_def = require "st.device"

  local dev = device
  local find_child_fn = device:get_field(device_def.FIND_CHILD_KEY)
  if find_child_fn ~= nil then
    local child = find_child_fn(device, zb_mess.address_header.src_endpoint.value)
    if child ~= nil then
      dev = child
    end
  end
  if dev:get_field(CONFIGURATION_ATTEMPTED) == true then
    if zb_mess.body.zcl_body.global_status ~= nil and zb_mess.body.zcl_body.global_status.value == Status.SUCCESS then
      dev:set_field(CONFIGURATION_VERSION_KEY, driver.current_config_version, {persist = true})
    elseif zb_mess.body.zcl_body.config_records ~= nil then
      local config_records = zb_mess.body.zcl_body.config_records
      for _, record in ipairs(config_records) do
        if zb_mess.address_header.cluster.value == clusters.SimpleMetering.ID then
          if record.attr_id.value == clusters.SimpleMetering.attributes.InstantaneousDemand.ID
            and record.status.value == Status.SUCCESS then
            dev:set_field(CONFIGURATION_VERSION_KEY, driver.current_config_version, {persist = true})
          end
        elseif zb_mess.address_header.cluster.value == clusters.ElectricalMeasurement.ID then
          if record.attr_id.value == clusters.ElectricalMeasurement.attributes.ActivePower.ID
            and record.status.value == Status.SUCCESS then
            dev:set_field(CONFIGURATION_VERSION_KEY, driver.current_config_version, {persist = true})
          end
        end

      end
    end
  end
end

configurations.power_reconfig_wrapper = function(orig_function)
  local new_init = function(driver, device)
    local config_version = device:get_field(CONFIGURATION_VERSION_KEY)
    if config_version == nil or config_version < driver.current_config_version then
      if driver._reconfig_timer == nil then
        driver._reconfig_timer = driver:call_with_delay(5*60, configurations.check_and_reconfig_devices, "reconfig_power_devices")
      end
    end
    orig_function(driver, device)
  end
  return new_init
end

configurations.get_device_configuration = function(zigbee_device)
  local devices = require "configurations.devices"
  for _, device in pairs(devices) do
    for _, fingerprint in pairs(device.FINGERPRINTS) do
      if zigbee_device:get_manufacturer() == fingerprint.mfr and zigbee_device:get_model() == fingerprint.model then
        return device.CONFIGURATION
      end
    end
  end
  return nil
end

configurations.get_ias_zone_config_method = function(zigbee_device)
  local devices = require "configurations.devices"
  for _, device in pairs(devices) do
    for _, fingerprint in pairs(device.FINGERPRINTS) do
      if zigbee_device:get_manufacturer() == fingerprint.mfr and zigbee_device:get_model() == fingerprint.model then
        return device.IAS_ZONE_CONFIG_METHOD
      end
    end
  end
  return nil
end

return configurations
