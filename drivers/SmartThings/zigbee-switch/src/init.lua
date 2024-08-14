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
local configurationMap = require "configurations"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local preferences = require "preferences"

local Groups = clusters.Groups
local log = require "log"
local zigbee_zcl = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local zigbee_constants = require "st.zigbee.constants"
local generic_body = require "st.zigbee.generic_body"
local utils = require "st.utils"
GROUP_ID = 0x1234


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

local function send_on_to_group(device, group_id)
  log.info(string.format("Sending On command to group 0x%04X", group_id)) 
  tx_msg = clusters.OnOff.server.commands.On(device)
  tx_msg.address_header.dest_addr.value = group_id
  tx_msg.address_header.dest_endpoint.value = 0xFF
  tx_msg.tx_options.value = 0x01
  device:send(tx_msg)
end

local function send_off_to_group(device, group_id)
  log.info(string.format("Sending Off command to group 0x%04X", group_id)) 
  tx_msg = clusters.OnOff.server.commands.Off(device)
  tx_msg.address_header.dest_addr.value = group_id
  tx_msg.address_header.dest_endpoint.value = 0xFF
  tx_msg.tx_options.value = 0x01
  device:send(tx_msg)
end

local function add_to_group(device, group_id)
  log.info(string.format("Adding device to group 0x%04X", group_id))
  device:send(Groups.server.commands.AddGroup(device, group_id))
end

local function add_to_group_response(self, device, value, zb_rx)
  log.info(string.format("add_to_group_response value=%s zb_rx=%s", value, zb_rx))
end

local function get_group_membership(device)
  log.info(string.format("Getting group membership"))
  device:send(Groups.server.commands.GetGroupMembership(device, {}))
end

local function get_group_membership_response(self, device, zb_rx)
  zcl_body = zb_rx.body.zcl_body
  log.info(string.format("get_group_membership_response: %s", utils.stringify_table(zcl_body)))
  
  already_in_group = false
  for _, group_entry in ipairs(zcl_body.group_list_list) do
    if group_entry.value == GROUP_ID then
      log.info("Already in group")
      already_in_group = true
      break
    end
  end

  if not already_in_group then
    log.info("Not already in group")
    add_to_group(device, GROUP_ID)
  end
  --send_on_to_group(device, GROUP_ID)
  --send_off_to_group(device, GROUP_ID)
end


local do_configure = function(self, device)
  device:refresh()
  device:configure()

  -- Additional one time configuration
  if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
    -- Divisor and multipler for EnergyMeter
    device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
    device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
    -- Divisor and multipler for PowerMeter
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

local device_init = function(self, device)
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

  get_group_membership(device)
end

local function handle_switch_on(driver, device, cmd)
  send_on_to_group(device, GROUP_ID)
end

local function handle_switch_off(driver, device, cmd)
  send_off_to_group(device, GROUP_ID)
end

local zigbee_switch_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorControl,
    capabilities.colorTemperature,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.motionSensor,
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
    lazy_load_if_possible("wallhero")
  },
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [Groups.ID] = {
        [Groups.client.commands.AddGroupResponse.ID] = add_to_group_response,
        [Groups.client.commands.GetGroupMembershipResponse.ID] = get_group_membership_response
      },
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
  }
}


defaults.register_for_default_handlers(zigbee_switch_driver_template,
  zigbee_switch_driver_template.supported_capabilities,  {native_capability_cmds_enabled = false})
local zigbee_switch = ZigbeeDriver("zigbee_switch_with_groups", zigbee_switch_driver_template)
zigbee_switch:run()
