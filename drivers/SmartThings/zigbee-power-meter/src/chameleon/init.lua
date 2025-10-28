local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local log = require "log"

local TemperatureMeasurement = clusters.DeviceTemperatureConfiguration
local PowerConfiguration = clusters.PowerConfiguration

local ZIGBEE_FINGERPRINT = {
  {model = "CT101xxxx" }
}

-- temperature: 0.5C, humidity: 2%
local configuration = {
  {
    cluster = TemperatureMeasurement.ID,
    attribute = TemperatureMeasurement.attributes.CurrentTemperature.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = TemperatureMeasurement.attributes.CurrentTemperature.base_type,
    reportable_change = 50
  },
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
    reportable_change = 1
  }
}

local is_chameleon_ct_clamp = function(opts, driver, device)
  log.info("is_chameleon_ct_clamp")
  for _, fingerprint in ipairs(ZIGBEE_FINGERPRINT) do
      if device:get_model() == fingerprint.model then
         log.info("Yes it is a ct clamp")
         return true
      end
  end
  log.info("No it isnt a ct clamp")
  return false
end

local function battery_level_handler(driver, device, value, zb_rx)
  log.info("battery_level_handler")
  device:emit_event(capabilities.battery.battery(value.value))
end

local function device_init(driver, device)
  log.info("device_init")
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end

  local batt_level = device:get_latest_state("main", capabilities.battery.ID, capabilities.battery.battery
  .NAME) or nil
  if batt_level == nil then
    device:emit_event(capabilities.battery.battery.normal())
  end
end

local function added_handler(self, device)
  log.info("added_handler")
  device:emit_event(capabilities.temperatureMeasurement.temperature({ value = 0, unit = "C" }))
  device:emit_event(capabilities.battery.battery({value = 0, unit = "%" }))
end

local ct_clamp_battery_temperature_handler = {
  NAME = "ct_clamp_battery_temperature_handler",
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_level_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  can_handle = is_chameleon_ct_clamp
}

return ct_clamp_battery_temperature_handler
