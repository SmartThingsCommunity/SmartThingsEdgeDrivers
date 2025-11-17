-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- The only reason we need this is because of supported_capabilities on the driver template
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local configurationMap = require "configurations"
local CONFIGURE_REPORTING_RESPONSE_ID = 0x07
local SIMPLE_METERING_ID = 0x0702
local ELECTRICAL_MEASUREMENT_ID = 0x0B04
local version = require "version"

local lazy_handler
if version.api >= 15 then
  lazy_handler = require "st.utils.lazy_handler"
else
  lazy_handler = require
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("switch(%d)")
  return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

local device_init = function(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)

  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end

  local ias_zone_config_method = configurationMap.get_ias_zone_config_method(device)
  if ias_zone_config_method ~= nil then
    device:set_ias_zone_config_method(ias_zone_config_method)
  end
  local device_lib = require "st.device"
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    local find_child = require "lifecycle_handlers.find_child"
    device:set_find_child(find_child)
  end
end

local lazy_load_if_possible = require "lazy_load_subdriver"

local zigbee_switch_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorControl,
    capabilities.colorTemperature,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.motionSensor,
    capabilities.illuminanceMeasurement,
  },
  sub_drivers = {
    lazy_load_if_possible("non_zigbee_devices"),
    lazy_load_if_possible("hanssem"),
    lazy_load_if_possible("aqara"),
    lazy_load_if_possible("aqara-light"),
    lazy_load_if_possible("ezex"),
    lazy_load_if_possible("rexense"),
    lazy_load_if_possible("sinope"),
    lazy_load_if_possible("sinope-dimmer"),
    lazy_load_if_possible("zigbee-dimmer-power-energy"),
    lazy_load_if_possible("zigbee-metering-plug-power-consumption-report"),
    lazy_load_if_possible("jasco"),
    lazy_load_if_possible("multi-switch-no-master"),
    lazy_load_if_possible("zigbee-dual-metering-switch"),
    lazy_load_if_possible("rgb-bulb"),
    lazy_load_if_possible("zigbee-dimming-light"),
    lazy_load_if_possible("white-color-temp-bulb"),
    lazy_load_if_possible("rgbw-bulb"),
    (version.api < 16) and lazy_load_if_possible("zll-dimmer-bulb") or nil,
    lazy_load_if_possible("ikea-xy-color-bulb"),
    lazy_load_if_possible("zll-polling"),
    lazy_load_if_possible("zigbee-switch-power"),
    lazy_load_if_possible("ge-link-bulb"),
    lazy_load_if_possible("bad_on_off_data_type"),
    lazy_load_if_possible("robb"),
    lazy_load_if_possible("wallhero"),
    lazy_load_if_possible("inovelli"), -- Combined driver for both VZM31-SN and VZM32-SN
    lazy_load_if_possible("laisiao"),
    lazy_load_if_possible("tuya-multi"),
    lazy_load_if_possible("frient")
  },
  zigbee_handlers = {
    global = {
      [SIMPLE_METERING_ID] = {
        [CONFIGURE_REPORTING_RESPONSE_ID] = configurationMap.handle_reporting_config_response
      },
     [ELECTRICAL_MEASUREMENT_ID] = {
        [CONFIGURE_REPORTING_RESPONSE_ID] = configurationMap.handle_reporting_config_response
      }
    }
  },
  current_config_version = 1,
  lifecycle_handlers = {
    init = configurationMap.power_reconfig_wrapper(device_init),
    added = lazy_handler("lifecycle_handlers.device_added"),
    infoChanged = lazy_handler("lifecycle_handlers.info_changed"),
    doConfigure = lazy_handler("lifecycle_handlers.do_configure"),
  },
  health_check = false,
}
defaults.register_for_default_handlers(zigbee_switch_driver_template,
  zigbee_switch_driver_template.supported_capabilities,
  {native_capability_cmds_enabled = true, native_capability_attrs_enabled = true}
)
local zigbee_switch = ZigbeeDriver("zigbee_switch", zigbee_switch_driver_template)
zigbee_switch:run()
