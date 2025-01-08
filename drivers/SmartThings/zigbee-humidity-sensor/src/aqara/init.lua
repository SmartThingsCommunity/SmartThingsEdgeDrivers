local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"

local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity
local PowerConfiguration = clusters.PowerConfiguration

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.sensor_ht.agl02" }
}

-- temperature: 0.5C, humidity: 2%
local configuration = {
  {
    cluster = TemperatureMeasurement.ID,
    attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
    minimum_interval = 3600,
    maximum_interval = 7200,
    data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
    reportable_change = 50
  },
  {
    cluster = RelativeHumidity.ID,
    attribute = RelativeHumidity.attributes.MeasuredValue.ID,
    minimum_interval = 3600,
    maximum_interval = 7200,
    data_type = RelativeHumidity.attributes.MeasuredValue.base_type,
    reportable_change = 200
  },
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
    reportable_change = 1
  }
}

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function battery_level_handler(driver, device, value, zb_rx)
  local voltage = value.value
  local batteryLevel = "normal"
  if voltage <= 25 then
    batteryLevel = "critical"
  elseif voltage < 28 then
    batteryLevel = "warning"
  end
  device:emit_event(capabilities.batteryLevel.battery(batteryLevel))
end

local function device_init(driver, device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end

  local batt_level = device:get_latest_state("main", capabilities.batteryLevel.ID, capabilities.batteryLevel.battery
  .NAME) or nil
  if batt_level == nil then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  end
end

local function added_handler(self, device)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))
  device:emit_event(capabilities.temperatureMeasurement.temperature({ value = 0, unit = "C" }))
  device:emit_event(capabilities.relativeHumidityMeasurement.humidity(0))
  device:emit_event(capabilities.batteryLevel.battery("normal"))
end

local aqara_humidity_handler = {
  NAME = "Aqara Humidity Handler",
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_level_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  can_handle = is_aqara_products
}

return aqara_humidity_handler
