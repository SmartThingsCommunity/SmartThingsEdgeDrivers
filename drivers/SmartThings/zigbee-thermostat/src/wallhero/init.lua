-- Copyright 2026 SmartThings
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
local log = require "log"
local socket = require "cosock.socket"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local Scenes = zcl_clusters.Scenes
local OnOff = zcl_clusters.OnOff
local FanControl = zcl_clusters.FanControl
local Thermostat = zcl_clusters.Thermostat
local ThermostatMode  = capabilities.thermostatMode
local FanMode  = capabilities.fanMode

local function scenes_cluster_handler(driver, device, zb_rx)
  local additional_fields = {
    state_change = true
  }

  local ep = zb_rx.address_header.src_endpoint.value-3
  local button_name = "button" .. ep
  local event = capabilities.button.button.pushed(additional_fields)
  local comp = device.profile.components[button_name]
  if comp ~= nil then
    device:emit_component_event(comp, event)
  else
    log.warn("Attempted to emit button event for unknown button: " .. button_name)
  end
end

local function on_off_attr_handler(driver, device, value, zb_rx)
  local attr = capabilities.switch.switch
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, value.value and attr.on() or attr.off())
end

local function on_handler(driver, device, command)
  device:send_to_component(command.component, OnOff.server.commands.On(device))
end

local function off_handler(driver, device, command)
  device:send_to_component(command.component, OnOff.server.commands.Off(device))
end

local function caps_temperatureSetpoint_handler(driver, device, command)
  local temperature = tonumber(command.args.setpoint)*100
  device:send_to_component(command.component, Thermostat.attributes.OccupiedCoolingSetpoint:write(device,temperature))
end

local SUPPORTED_FAN_MODES = {
  { "auto", "high", "medium", "low"},
}

local FAN_MODE_TO_ZIGBEE = {
  ["auto"]   = 0x05,
  ["low"]    = 0x01,
  ["medium"] = 0x02,
  ["high"]   = 0x03
}

local ZIGBEE_TO_FAN_MODES = {
  [1]      =  "low" ,
  [2]      =  "medium" ,
  [3]      =  "high" ,
  [5]      =  "auto"
}

local function fan_mode_attr_handler(driver, device, value, zb_rx)
  local ep = zb_rx.address_header.src_endpoint.value
  local str = ZIGBEE_TO_FAN_MODES[value.value]
  if ep == 1  then
    device:emit_component_event(device.profile.components.main,FanMode.fanMode({ value = str }))
  elseif ep == 2 then
    device:emit_component_event(device.profile.components.fan,FanMode.fanMode({ value = str }))
  end
end

local function setFanMode_handler(driver, device, command)
  local value = FAN_MODE_TO_ZIGBEE[command.args.fanMode]
  device:send_to_component(command.component, FanControl.attributes.FanMode:write(device, value))
end

local function thermostat_attr_occupiedCoolingSetpoint_handler(driver, device, value, zb_rx)
  local ep = zb_rx.address_header.src_endpoint.value
  if ep == 1  then
    local temp = value.value/100
    device:emit_component_event(device.profile.components.main,capabilities.temperatureSetpoint.temperatureSetpoint({value = temp, unit = "C"}))
  end
end

local function do_refresh(driver, device)
  device:send_to_component("main", OnOff.attributes.OnOff:read(device))
  device:send_to_component("main", Thermostat.attributes.LocalTemperature:read(device))
  device:send_to_component("main", Thermostat.attributes.OccupiedCoolingSetpoint:read(device))
  socket.sleep(1)--Avoid wireless congestion and packet loss
  device:send_to_component("main", Thermostat.attributes.SystemMode:read(device))
  device:send_to_component("main", FanControl.attributes.FanMode:read(device))
  socket.sleep(1)
  device:send_to_component("fan", OnOff.attributes.OnOff:read(device))
  device:send_to_component("fan", FanControl.attributes.FanMode:read(device))
  socket.sleep(1)
  device:send_to_component("heat", OnOff.attributes.OnOff:read(device))
  device:send_to_component("heat", Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
end

local function added_handler(driver, device)
  device:emit_component_event(device.profile.components.main,ThermostatMode.supportedThermostatModes({"cool", "dryair", "fanonly", "heat"}, { visibility = { displayed = false } }))
  device:emit_component_event(device.profile.components.main,FanMode.supportedFanModes( SUPPORTED_FAN_MODES[1] , { visibility = { displayed = false }}))
  device:emit_component_event(device.profile.components.fan,FanMode.supportedFanModes( SUPPORTED_FAN_MODES[1] , { visibility = { displayed = false }}))

  device:emit_component_event(device.profile.components.main,capabilities.temperatureSetpoint.temperatureSetpointRange({ value = { minimum = 16.00, maximum = 32.00 }, unit = "C" }))
  device:emit_component_event(device.profile.components.heat,capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = 16.00, maximum = 32.00 }, unit = "C" }))

  device:emit_component_event(device.profile.components.main,capabilities.switch.switch.off())
  device:emit_component_event(device.profile.components.heat,capabilities.switch.switch.off())
  device:emit_component_event(device.profile.components.fan,capabilities.switch.switch.off())

  device:emit_component_event(device.profile.components.main,ThermostatMode.thermostatMode.cool())
  device:emit_component_event(device.profile.components.main,FanMode.fanMode.auto())
  device:emit_component_event(device.profile.components.fan,FanMode.fanMode.auto())
  device:emit_component_event(device.profile.components.main,capabilities.temperatureSetpoint.temperatureSetpoint({value = 26, unit = "C"}))
  device:emit_component_event(device.profile.components.heat,capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 26, unit = "C"}))

  for _, component in pairs(device.profile.components) do
    if component.id ~= "main" and component.id ~= "heat" and component.id ~= "fan" then
    device:emit_component_event(component,
      capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } }))
    device:emit_component_event(component,
      capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
    -- Without this time delay, the state of some buttons cannot be updated
    socket.sleep(1)
    end
  end
  do_refresh(driver, device)
end

local function component_to_endpoint(device, component_id)
  local ep_num
  if component_id == "main" then
    ep_num = 1
  elseif component_id == "fan" then
    ep_num = 2
  elseif component_id == "heat" then
    ep_num = 3
  end
  return ep_num or device.fingerprinted_endpoint_id
end

local function endpoint_to_component(device, ep)
  if ep > 3 then
    ep = ep - 3
    local button_comp = string.format("button%d+", ep)
    if device.profile.components[button_comp] ~= nil then
      return button_comp
    else
      return "button1"
    end
  else
    if ep == 1 then
      return "main"
    elseif ep == 2 then
      return "fan"
    else
      return "heat"
    end
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local wallhero_thermostat_3in1 = {
  NAME = "Wall Hero thermostat 3in1",
  supported_capabilities = {
    capabilities.switch,
  capabilities.temperatureSetpoint
  },
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  health_check = false,
  zigbee_handlers = {
    cluster = {
      [Scenes.ID] = {
        [Scenes.server.commands.RecallScene.ID] = scenes_cluster_handler,
      }
    },
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = on_off_attr_handler
      },
      [FanControl.ID] = {
        [FanControl.attributes.FanMode.ID] = fan_mode_attr_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.OccupiedCoolingSetpoint.ID] = thermostat_attr_occupiedCoolingSetpoint_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_handler,
      [capabilities.switch.commands.off.NAME] = off_handler
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = caps_temperatureSetpoint_handler
    },
    [capabilities.fanMode.ID] = {
      [capabilities.fanMode.commands.setFanMode.NAME] = setFanMode_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },

  can_handle = require("wallhero.can_handle")
}

return wallhero_thermostat_3in1
