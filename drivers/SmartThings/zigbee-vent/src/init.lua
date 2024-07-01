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
local device_management = require "st.zigbee.device_management"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"

local temperature_measurement_defaults = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP"
}

local KEEN_PRESSURE_ATTRIBUTE = 0x0020
local KEEN_MFG_CODE = 0x115B

local function pressure_report_handler(driver, device, value, zb_rx)
  local kPa = math.floor(value.value / (10 * 1000)) -- reports are in deciPascals
  device:emit_event(capabilities.atmosphericPressureMeasurement.atmosphericPressure({value = kPa, unit = "kPa"}))
end

local function battery_report_handler(driver, device, value, zb_rx)
  if (value.value >= 0 and value.value <= 100) then
    -- keen vent reports battery as a raw percent rather than 2x
    device:emit_event(capabilities.battery.battery(value.value))
  end
end

local function level_report_handler(driver, device, value, zb_rx)
  local level = math.floor((value.value / 254.0 * 100) + 0.5)
  device:emit_event(capabilities.switchLevel.level(level))

  if (level > 0) then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function set_level_handler(driver, device, command)
  device:send(clusters.Level.commands.MoveToLevelWithOnOff(device, math.floor(command.args.level * 0xFE / 100), 0xFFFF))

  driver:call_with_delay(1, function (d) device:send(clusters.Level.attributes.CurrentLevel:read(device)) end)
end

local function switch_on_handler(driver, device, command)
  local last_level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME)
  if (last_level == nil or last_level == 0) then last_level = 100 end
  last_level =  math.floor(last_level * 0xFE / 100)
  device:send(clusters.Level.commands.MoveToLevelWithOnOff(device, last_level, 0xFFFF))
end

local temperature_measurement_min_max_attr_handler = function(minOrMax)
  return function(driver, device, value, zb_rx)
    local raw_temp = value.value
    local celc_temp = raw_temp / 100.0
    local temp_scale = "C"

    device:set_field(string.format("%s", minOrMax), celc_temp)

    local min = device:get_field(temperature_measurement_defaults.MIN_TEMP)
    local max = device:get_field(temperature_measurement_defaults.MAX_TEMP)

    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = temp_scale }))
        device:set_field(temperature_measurement_defaults.MIN_TEMP, nil)
        device:set_field(temperature_measurement_defaults.MAX_TEMP, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end

local function refresh_handler(driver, device, command)
  device:send(clusters.Level.attributes.CurrentLevel:read(device))
  device:send(clusters.OnOff.attributes.OnOff:read(device))
  device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(clusters.TemperatureMeasurement.attributes.MinMeasuredValue:read(device))
  device:send(clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:read(device))
  device:send(clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))

  local pressure_read = cluster_base.read_manufacturer_specific_attribute(device, clusters.PressureMeasurement.ID, KEEN_PRESSURE_ATTRIBUTE, KEEN_MFG_CODE)
  device:send(pressure_read)
end


local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, clusters.TemperatureMeasurement.ID, self.environment_info.hub_zigbee_eui))
  device:send(clusters.TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 300, 1))

  device:send(device_management.build_bind_request(device, clusters.OnOff.ID, self.environment_info.hub_zigbee_eui))
  device:send(clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, 300, 1))

  device:send(device_management.build_bind_request(device, clusters.PressureMeasurement.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, clusters.Level.ID, self.environment_info.hub_zigbee_eui))

  device:send(device_management.build_bind_request(device, clusters.PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 60, 21600, 1))
end

local zigbee_vent_driver = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.temperatureMeasurement,
    capabilities.atmosphericPressureMeasurement,
    capabilities.battery,
    capabilities.refresh
  },
  zigbee_handlers = {
    attr = {
      [clusters.PressureMeasurement.ID] = {
        [KEEN_PRESSURE_ATTRIBUTE] = pressure_report_handler
      },
      [clusters.PowerConfiguration.ID] = {
        [clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_report_handler
      },
      [clusters.Level.ID] = {
        [clusters.Level.attributes.CurrentLevel.ID] = level_report_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MIN_TEMP),
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temperature_measurement_min_max_attr_handler(temperature_measurement_defaults.MAX_TEMP),
      }
    }
  },
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = set_level_handler
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = refresh_handler
  }
}

defaults.register_for_default_handlers(zigbee_vent_driver, zigbee_vent_driver.supported_capabilities)
local driver = ZigbeeDriver("zigbee-vent", zigbee_vent_driver)
driver:run()
