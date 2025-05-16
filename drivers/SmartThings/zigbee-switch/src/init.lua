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
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local globals = require "st.zigbee.zcl.global_commands"
local configurationMap = require "configurations"
local SimpleMetering = clusters.SimpleMetering
local preferences = require "preferences"
local device_lib = require "st.device"

local function lazy_load_if_possible(sub_driver_name)
  -- gets the current lua libs api version
  local version = require "version"

  -- version 9 will include the lazy loading functions
  if version.api >= 9 then
    return ZigbeeDriver.lazy_load_sub_driver(require(sub_driver_name))
  else
    return require(sub_driver_name)
  end

end

local function info_changed(self, device, event, args)
  preferences.update_preferences(self, device, args)
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  -- Additional one time configuration
  if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
    -- Divisor and multipler for EnergyMeter
    device:send(SimpleMetering.attributes.Divisor:read(device))
    device:send(SimpleMetering.attributes.Multiplier:read(device))
  end
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

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local device_init = function(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)

  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end

  local ias_zone_config_method = configurationMap.get_ias_zone_config_method(device)
  if ias_zone_config_method ~= nil then
    device:set_ias_zone_config_method(ias_zone_config_method)
  end
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local function is_mcd_device(device)
  local components = device.profile.components
  if type(components) == "table" then
    local component_count = 0
    for _, component in pairs(components) do
        component_count = component_count + 1
    end
    return component_count >= 2
  end
end

local function device_added(driver, device, event)
  local main_endpoint = device:get_endpoint(clusters.OnOff.ID)
  if is_mcd_device(device) == false and device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    for _, ep in ipairs(device.zigbee_endpoints) do
      if ep.id ~= main_endpoint then
        if device:supports_server_cluster(clusters.OnOff.ID, ep.id) then
          device:set_find_child(find_child)
          if find_child(device, ep.id) == nil then
            local name = string.format("%s %d", device.label, ep.id)
            local child_profile = "basic-switch"
            driver:try_create_device(
              {
                type = "EDGE_CHILD",
                label = name,
                profile = child_profile,
                parent_device_id = device.id,
                parent_assigned_child_key = string.format("%02X", ep.id),
                vendor_provided_label = name
              }
            )
          end
        end
      end
    end
  end
end

--- DEFAULT reporting configuration
-- local active_power_configuration = {
--   cluster = zcl_clusters.ElectricalMeasurement.ID,
--   attribute = zcl_clusters.ElectricalMeasurement.attributes.ActivePower.ID,
--   minimum_interval = 1,
--   maximum_interval = 3600,
--   data_type = zcl_clusters.ElectricalMeasurement.attributes.ActivePower.base_type,
--   reportable_change = 5
-- }
local ActivePower = clusters.ElectricalMeasurement.attributes.ActivePower
local log = require "log"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local read_configuration = require "st.zigbee.zcl.global_commands.read_reporting_configuration"
local data_types = require "st.zigbee.data_types"
local zb_const = require "st.zigbee.constants"
local function driver_switch(driver, device)
  log.info_with({hub_logs = true}, "Driver switch handler starting")
  -- read reporting configuration
  local data = read_configuration.ReadReportingConfiguration({
    read_configuration.ReadReportingConfigurationAttributeRecord(0, ActivePower.ID)
  })
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(read_configuration.ReadReportingConfiguration.ID)
  })
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    0x01,
    zb_const.HA_PROFILE_ID,
    clusters.ElectricalMeasurement.ID
  )
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = data
  })
  local read_config_message = messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
  local configure_msg = ActivePower:configure_reporting(device, 15, 600, 15)

  log.info_with({hub_logs = true}, "Driver switch handler reading previous Active Power configuration")
  device:send(read_config_message)
  -- delay and then reconfigure
  device.thread:call_with_delay(2, function()
    log.info_with({hub_logs = true}, "Driver switch handler changing Active Power configuration")
    device:send(configure_msg)
  end)
  -- delay and then read configurations
  device.thread:call_with_delay(4, function()
    log.info_with({hub_logs = true}, "Driver switch handler reading new Active Power configuration")
    -- read reporting configuration
    local data = read_configuration.ReadReportingConfiguration({
      read_configuration.ReadReportingConfigurationAttributeRecord(0, ActivePower.ID)
    })
    local zclh = zcl_messages.ZclHeader({
      cmd = data_types.ZCLCommandId(read_configuration.ReadReportingConfiguration.ID)
    })
    local addrh = messages.AddressHeader(
      zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT,
      device:get_short_address(),
      0x01,
      zb_const.HA_PROFILE_ID,
      clusters.ElectricalMeasurement.ID
    )
    local message_body = zcl_messages.ZclMessageBody({
      zcl_header = zclh,
      zcl_body = data
    })
    local read_config_message = messages.ZigbeeMessageTx({
      address_header = addrh,
      body = message_body
    })
    device:send(read_config_message)
  end)
end

local zigbee_switch_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorControl,
    capabilities.colorTemperature,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.motionSensor
  },
  sub_drivers = {
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
    lazy_load_if_possible("zll-dimmer-bulb"),
    lazy_load_if_possible("zigbee-switch-power"),
    lazy_load_if_possible("ge-link-bulb"),
    lazy_load_if_possible("bad_on_off_data_type"),
    lazy_load_if_possible("robb"),
    lazy_load_if_possible("wallhero"),
    lazy_load_if_possible("inovelli-vzm31-sn"),
    lazy_load_if_possible("laisiao"),
    lazy_load_if_possible("tuya-multi")
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed,
    doConfigure = do_configure,
    driverSwitched = driver_switch,
  }
}
defaults.register_for_default_handlers(zigbee_switch_driver_template,
  zigbee_switch_driver_template.supported_capabilities,
  {native_capability_cmds_enabled = true, native_capability_attrs_enabled = true}
)
local zigbee_switch = ZigbeeDriver("zigbee_switch", zigbee_switch_driver_template)
zigbee_switch:run()
