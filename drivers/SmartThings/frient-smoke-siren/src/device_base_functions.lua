local capabilities                                   = require "st.capabilities"
local battery_defaults                               = require "st.zigbee.defaults.battery_defaults"
local cluster_base                                   = require "st.zigbee.cluster_base"
local zcl_clusters                                   = require "st.zigbee.zcl.clusters"
local log                                            = require "log"

local PowerConfiguration                             = zcl_clusters.PowerConfiguration
local IASZone                                        = zcl_clusters.IASZone
local IASWD                                          = zcl_clusters.IASWD
local TemperatureMeasurement                         = zcl_clusters.TemperatureMeasurement
local Basic                                          = zcl_clusters.Basic

local FRIENT_DEVICE_FINGERPRINTS                     = require "device_config"

local BASE_FUNCTIONS                                 = {}

-- Constants
BASE_FUNCTIONS.DEVELCO_MANUFACTURER_CODE             = 0x1015
BASE_FUNCTIONS.DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR = 0x8000

BASE_FUNCTIONS.SIREN_ENDIAN                          = "siren_endian"
BASE_FUNCTIONS.PRIMARY_SW_VERSION                    = "primary_sw_version"

BASE_FUNCTIONS.ALARM_COMMAND                         = "alarmCommand"
BASE_FUNCTIONS.ALARM_LAST_DURATION                   = "lastDuration"
BASE_FUNCTIONS.ALARM_MAX_DURATION                    = "maxDuration"

BASE_FUNCTIONS.ALARM_DEFAULT_MAX_DURATION            = 240

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
function BASE_FUNCTIONS.added(driver, device)
  for _, fingerprint in ipairs(FRIENT_DEVICE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      if device:supports_capability(capabilities.tamperAlert) then
        device:emit_event(capabilities.tamperAlert.tamper.clear())
      end
      if device:supports_capability(capabilities.smokeDetector) then
        device:emit_event(capabilities.smokeDetector.smoke.clear())
      end
      if device:supports_capability(capabilities.temperatureAlarm) then
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
      end
      if device:supports_capability(capabilities.waterSensor) then
        device:emit_event(capabilities.waterSensor.water.dry())
      end
      if device:supports_capability(capabilities.switch) then
        device:emit_event(capabilities.switch.switch.off())
      end
      if device:supports_capability(capabilities.alarm) then
        device:emit_event(capabilities.alarm.alarm.off())
        device:set_field(BASE_FUNCTIONS.ALARM_MAX_DURATION, BASE_FUNCTIONS.ALARM_DEFAULT_MAX_DURATION, { persist = true })
      end

      device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, BASE_FUNCTIONS.DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, BASE_FUNCTIONS.DEVELCO_MANUFACTURER_CODE)) -- Read the firmware version
    end
  end
end

function BASE_FUNCTIONS.init(driver, device)
  for _, fingerprint in ipairs(FRIENT_DEVICE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      if device:supports_capability(capabilities.battery) then
        battery_defaults.build_linear_voltage_init(2.3, 3.0)(driver, device)
      end
    end
  end
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
function BASE_FUNCTIONS.do_refresh(driver, device)
  for _, fingerprint in ipairs(FRIENT_DEVICE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      if fingerprint.ENDPOINT_TAMPER then
        device:send(IASZone.attributes.ZoneStatus:read(device):to_endpoint(fingerprint.ENDPOINT_TAMPER))
      end
      if fingerprint.ENDPOINT_TEMPERATURE then
        device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device):to_endpoint(fingerprint.ENDPOINT_TEMPERATURE))
      end
      if device:supports_capability(capabilities.battery) then
        device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
      end

      -- Check if we have the software version
      local sw_version = device:get_field(BASE_FUNCTIONS.PRIMARY_SW_VERSION)
      if ((sw_version == nil) or (sw_version == "")) then
        log.warn("Refresh: Firmware version not detected, checking software version")
        device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, BASE_FUNCTIONS.DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, BASE_FUNCTIONS.DEVELCO_MANUFACTURER_CODE))
      else
        log.trace("Refresh: Firmware version: 0x" .. sw_version)
      end
    end
  end
end

--- @param driver ZigbeeDriver The current driver running containing necessary context for execution
--- @param device st.zigbee.Device The device this message was received from containing identifying information
--- @param event string The lifecycle event name
--- @param args table Table containing information relevant to the lifecycle event
function BASE_FUNCTIONS.do_configure(driver, device, event, args)
  device:configure()
  for _, fingerprint in ipairs(FRIENT_DEVICE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      if fingerprint.ENDPOINT_SIREN then
        device:set_field(BASE_FUNCTIONS.ALARM_MAX_DURATION, device.preferences.warningDuration == nil and BASE_FUNCTIONS.ALARM_DEFAULT_MAX_DURATION or device.preferences.warningDuration, { persist = true })
        device:send(IASWD.attributes.MaxDuration:write(device, device.preferences.warningDuration == nil and BASE_FUNCTIONS.ALARM_DEFAULT_MAX_DURATION or device.preferences.warningDuration):to_endpoint(fingerprint.ENDPOINT_SIREN))
      end
    end
  end
end

return BASE_FUNCTIONS
