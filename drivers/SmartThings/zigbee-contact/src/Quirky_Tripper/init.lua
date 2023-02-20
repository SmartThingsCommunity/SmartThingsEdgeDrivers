local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
--local battery_defaults = require "battery-voltage"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local bind_request_resp = require "st.zigbee.zdo.bind_request_response"

local FINGERPRINTS = {
  { mfr = "Sercomm Corp.", model = "Tripper" }
}
--- Try adding this battery handler and see what happens
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
local CONFIGURATIONS = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
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

local is_tripper_products = function(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(opts,driver, device)
  ---battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)
  battery_defaults.battery_voltage(opts,driver,device)
  device:send(clusters.PowerConfiguration.attributes.BatteryVoltage:read(device))
end

  for _, attribute in ipairs(CONFIGURATIONS) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local tripper_contact_handler = {
  NAME = "Tripper Contact Handler",
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = is_tripper_products
}

return tripper_contact_handler
