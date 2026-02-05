-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local IASZone = zcl_clusters.IASZone
local CarbonMonoxideCluster = zcl_clusters.CarbonMonoxide
local carbonMonoxide = capabilities.carbonMonoxideDetector
local CarbonMonoxideEndpoint = 0x2E
local SmokeAlarmEndpoint = 0x23
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement
local TEMPERATURE_ENDPOINT = 0x26
local Basic = zcl_clusters.Basic
local alarm = capabilities.alarm
local smokeDetector = capabilities.smokeDetector
local IASWD = zcl_clusters.IASWD
local carbonMonoxideMeasurement = capabilities.carbonMonoxideMeasurement
local tamperAlert = capabilities.tamperAlert
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local alarm_command = {
  OFF = 0,
  SIREN = 1
}

local CONFIGURATIONS = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 30,
    maximum_interval = 300,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  },
  {
    cluster = TemperatureMeasurement.ID,
    attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
    minimum_interval = 60,
    maximum_interval = 600,
    data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
    reportable_change = 100
  },
  {
    cluster = CarbonMonoxideCluster.ID,
    attribute = CarbonMonoxideCluster.attributes.MeasuredValue.ID,
    minimum_interval = 10,
    maximum_interval = 600,
    data_type = data_types.SinglePrecisionFloat,
    reportable_change = 1.0
  }
}

local function device_added(driver, device)
  device:emit_event(alarm.alarm.off())

  if device:supports_capability(smokeDetector) then
    device:emit_event(smokeDetector.smoke.clear())
  end

  if device:supports_capability(carbonMonoxide) then
    device:emit_event(carbonMonoxide.carbonMonoxide.clear())
  end

  if device:supports_capability(tamperAlert) then
    device:emit_event(tamperAlert.tamper.clear())
  end

  if device:supports_capability(carbonMonoxideMeasurement) then
    device:emit_event(carbonMonoxideMeasurement.carbonMonoxideLevel({value = 0, unit = "ppm"}))
  end
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.1)(driver, device)
  if CONFIGURATIONS ~= nil then
    for _, attribute in ipairs(CONFIGURATIONS) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function generate_event_from_zone_status(driver, device, zone_status, zigbee_message)
  local endpoint = zigbee_message.address_header.src_endpoint.value
  if endpoint == SmokeAlarmEndpoint then
    if device:supports_capability(smokeDetector) then
      if zone_status:is_test_set() then
          device:emit_event(smokeDetector.smoke.tested())
      elseif zone_status:is_alarm1_set() then
        device:emit_event(smokeDetector.smoke.detected())
      else
        device.thread:call_with_delay(6, function ()
          device:emit_event(smokeDetector.smoke.clear())
        end)
      end
    end
  end
  if endpoint == CarbonMonoxideEndpoint then
    if device:supports_capability(carbonMonoxide) then
      if zone_status:is_test_set() then
        device:emit_event(carbonMonoxide.carbonMonoxide.tested())
      elseif zone_status:is_alarm1_set() then
        device:emit_event(carbonMonoxide.carbonMonoxide.detected())
      else
        device.thread:call_with_delay(6, function ()
          device:emit_event(carbonMonoxide.carbonMonoxide.clear())
        end)
      end
    end
  end
  if device:supports_capability(tamperAlert) then
    if zone_status:is_tamper_set() then
      device:emit_event(tamperAlert.tamper.detected())
    else
      device:emit_event(tamperAlert.tamper.clear())
    end
  end
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  local zone_status = zb_rx.body.zcl_body.zone_status
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function carbon_monoxide_measure_value_attr_handler(driver, device, attr_val, zb_rx)
  local voc_value = attr_val.value
  if voc_value <= 1 then
    voc_value = voc_value * 1000000
  end
  device:emit_event(carbonMonoxideMeasurement.carbonMonoxideLevel({value = voc_value, unit = "ppm"}))
end

local function do_refresh(driver, device)
  device:send(CarbonMonoxideCluster.attributes.MeasuredValue:read(device):to_endpoint(CarbonMonoxideEndpoint))
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device):to_endpoint(TEMPERATURE_ENDPOINT))
end

--[[ local function do_configure(driver, device)
  device:configure()

  device.thread:call_with_delay(5, function()
    do_refresh(driver, device)
  end)
end ]]

local frient_smoke_carbon_monoxide = {
  NAME = "Frient Smoke Carbon Monoxide",
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    refresh = do_refresh,
    --[[ configure = do_configure, ]]
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      },
      [CarbonMonoxideCluster.ID] = {
        [CarbonMonoxideCluster.attributes.MeasuredValue.ID] = carbon_monoxide_measure_value_attr_handler
      }
    }
  },
  can_handle = require("frient.can_handle"),
}

return frient_smoke_carbon_monoxide