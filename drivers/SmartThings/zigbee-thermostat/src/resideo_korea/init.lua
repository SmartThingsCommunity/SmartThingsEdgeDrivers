-- Copyright 2023 SmartThings
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
local device_lib = require "st.device"
local device_management = require "st.zigbee.device_management"

-- Zigbee Spec Utils
local clusters = require "st.zigbee.zcl.clusters"
local Thermostat = clusters.Thermostat
local ThermostatSystemMode = Thermostat.attributes.SystemMode

local capabilities = require "st.capabilities"
local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState

local do_refresh = function(self, device)
  local attributes = {Thermostat.attributes.OccupiedHeatingSetpoint, Thermostat.attributes.LocalTemperature,
                      Thermostat.attributes.ControlSequenceOfOperation, Thermostat.attributes.ThermostatRunningState,
                      Thermostat.attributes.SystemMode}
  for _, attribute in pairs(attributes) do
    if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
      -- SmartThings Hub has a issue with setting parent endpoint
      device:send(attribute:read(device):to_endpoint(0x01))
    else
      device:send(attribute:read(device))
    end
  end
end

local do_configure = function(self, device)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    for endpoint = 1, 6 do
      device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui,
        endpoint))
    end
  end
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(device, 20, 300, 100))
  device:send(Thermostat.attributes.LocalTemperature:configure_reporting(device, 20, 300, 100))
  device:send(Thermostat.attributes.ThermostatRunningState:configure_reporting(device, 20, 300))
  device:send(Thermostat.attributes.SystemMode:configure_reporting(device, 20, 300))

  do_refresh(self, device)
end

local SUPPORTED_THERMOSTAT_MODES = {ThermostatMode.thermostatMode.away.NAME, ThermostatMode.thermostatMode.heat.NAME}

local supported_thermostat_modes_handler = function(driver, device, supported_modes, zb_rx)
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    ThermostatMode.supportedThermostatModes(SUPPORTED_THERMOSTAT_MODES, {
      visibility = {
        displayed = false
      }
    }))
end

local thermostat_operating_state_handler = function(driver, device, operating_state, zb_rx)
  if (operating_state:is_heat_second_stage_on_set() or operating_state:is_heat_on_set()) then
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      ThermostatOperatingState.thermostatOperatingState.heating())
  elseif (operating_state:is_cool_second_stage_on_set() or operating_state:is_cool_on_set()) then
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      ThermostatOperatingState.thermostatOperatingState.cooling())
  elseif (operating_state:is_fan_on_set()) then
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      ThermostatOperatingState.thermostatOperatingState.fan_only())
  else
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      ThermostatOperatingState.thermostatOperatingState.idle())
  end
end

local function thermostat_occupied_heating_setpoint_handler(driver, device, value, zb_rx)
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    capabilities.thermostatHeatingSetpoint.heatingSetpoint({
      value = value.value / 100.0,
      unit = "C"
    }))
end

local set_thermostat_mode = function(driver, device, command)
  if command.args.mode == ThermostatMode.thermostatMode.off.NAME or command.args.mode ==
    ThermostatMode.thermostatMode.away.NAME then
    device:send_to_component(command.component, Thermostat.attributes.SystemMode:write(device, ThermostatSystemMode.OFF))
    device.thread:call_with_delay(1, function(d)
      device:send_to_component(command.component, Thermostat.attributes.SystemMode:read(device))
    end)
  elseif command.args.mode == ThermostatMode.thermostatMode.auto.NAME or command.args.mode ==
    ThermostatMode.thermostatMode.heat.NAME then
    device:send_to_component(command.component,
      Thermostat.attributes.SystemMode:write(device, ThermostatSystemMode.HEAT))
    device.thread:call_with_delay(1, function(d)
      device:send_to_component(command.component, Thermostat.attributes.SystemMode:read(device))
    end)
  end
end

local thermostat_mode_setter = function(mode_name)
  return function(driver, device, command)
    return set_thermostat_mode(driver, device, {
      component = command.component,
      args = {
        mode = mode_name
      }
    })
  end
end

local thermostat_mode_handler = function(driver, device, thermostat_mode, zb_rx)
  if thermostat_mode.value == ThermostatSystemMode.OFF then
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, ThermostatMode.thermostatMode.away())
  else
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, ThermostatMode.thermostatMode.heat())
  end
end

local function added(driver, device, event)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    for i = 2, 6, 1 do
      local name = string.format("Room %d", i - 1)
      local metadata = {
        type = "EDGE_CHILD",
        label = name,
        profile = "thermostat-resideo-dt300st-m000",
        parent_device_id = device.id,
        parent_assigned_child_key = string.format("%02X", i),
        vendor_provided_label = name
      }
      driver:try_create_device(metadata)
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function init(driver, device, event)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local resideo_thermostat = {
  NAME = "Resideo Thermostat Handler",
  lifecycle_handlers = {
    init = init,
    added = added,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [Thermostat.ID] = {
        [Thermostat.attributes.ControlSequenceOfOperation.ID] = supported_thermostat_modes_handler,
        [Thermostat.attributes.ThermostatRunningState.ID] = thermostat_operating_state_handler,
        [Thermostat.attributes.SystemMode.ID] = thermostat_mode_handler,
        [Thermostat.attributes.OccupiedHeatingSetpoint.ID] = thermostat_occupied_heating_setpoint_handler
      }
    }
  },
  capability_handlers = {
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
      [ThermostatMode.commands.auto.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.heat.NAME),
      [ThermostatMode.commands.off.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.off.NAME),
      [ThermostatMode.commands.heat.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.heat.NAME)
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Resideo Korea" and device:get_model() == "DT300ST-M000"
  end
}

return resideo_thermostat
