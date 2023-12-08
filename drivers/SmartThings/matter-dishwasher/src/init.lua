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

local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local log = require "log"
local utils = require "st.utils"

local temperatureLevelId = "spacewonder52282.temperatureLevel"
local temperatureLevel = capabilities[temperatureLevelId]
local dishwasherModeId = "spacewonder52282.dishwasherMode"
local dishwasherMode = capabilities[dishwasherModeId]
local operationalStateId = "spacewonder52282.operationalState1"
local operationalState = capabilities[operationalStateId]

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function temperatureControl_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("temperatureControl_attr_handler: %s", ib.data.value))

  local current_mode=math.floor(ib.data.value)
  if current_mode==0 then
    device:emit_event_for_endpoint(ib.endpoint_id, temperatureLevel.temperatureLevel.temperatureLevel1())
  elseif current_mode==1 then
    device:emit_event_for_endpoint(ib.endpoint_id, temperatureLevel.temperatureLevel.temperatureLevel2())
  elseif current_mode==2 then
    device:emit_event_for_endpoint(ib.endpoint_id, temperatureLevel.temperatureLevel.temperatureLevel3())
  elseif current_mode==3 then
    device:emit_event_for_endpoint(ib.endpoint_id, temperatureLevel.temperatureLevel.temperatureLevel4())
  elseif current_mode==4 then
    device:emit_event_for_endpoint(ib.endpoint_id, temperatureLevel.temperatureLevel.temperatureLevel5())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, temperatureLevel.temperatureLevel.temperatureLevel1())
  end
end

local function dishwasher_supported_modes_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("dishwasher_supported_modes_attr_handler supportedModes: %s", ib.data.value))
end

local function dishwasher_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("dishwasher_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode=math.floor(ib.data.value)
  if current_mode==0 then
    device:emit_event_for_endpoint(ib.endpoint_id, dishwasherMode.dishwasherMode.normal())
  elseif current_mode==1 then
    device:emit_event_for_endpoint(ib.endpoint_id, dishwasherMode.dishwasherMode.heavy())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, dishwasherMode.dishwasherMode.light())
  end
end

local function operational_state_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("operational_state_attr_handler operationalState: %s", ib.data.value))

  if ib.data.value == clusters.OperationalState.types.OperationalStateEnum.STOPPED then
    device:emit_event_for_endpoint(ib.endpoint_id, operationalState.operationalState.stopped())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.RUNNING then
    device:emit_event_for_endpoint(ib.endpoint_id, operationalState.operationalState.running())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.PAUSED then
    device:emit_event_for_endpoint(ib.endpoint_id, operationalState.operationalState.paused())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, operationalState.operationalState.error())
  end
end

-- Capability Handlers --
local function handle_switch_on(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local function handle_temperature(driver, device, cmd)
  log.info_with({ hub_logs = true },
  string.format("handle_temperature: %s", cmd.args.level))

  if cmd.args.level==temperatureLevel.temperatureLevel.temperatureLevel1.NAME then
    device:send(clusters.TemperatureControl.commands.SetTemperature(device, 1, nil, 0))
  elseif cmd.args.level==temperatureLevel.temperatureLevel.temperatureLevel2.NAME then
    device:send(clusters.TemperatureControl.commands.SetTemperature(device, 1, nil, 1))
  elseif cmd.args.level==temperatureLevel.temperatureLevel.temperatureLevel3.NAME then
    device:send(clusters.TemperatureControl.commands.SetTemperature(device, 1, nil, 2))
  elseif cmd.args.level==temperatureLevel.temperatureLevel.temperatureLevel4.NAME then
    device:send(clusters.TemperatureControl.commands.SetTemperature(device, 1, nil, 3))
  elseif cmd.args.level==temperatureLevel.temperatureLevel.temperatureLevel5.NAME then
    device:send(clusters.TemperatureControl.commands.SetTemperature(device, 1, nil, 4))
  else
    device:send(clusters.TemperatureControl.commands.SetTemperature(device, 1, nil, 0))
  end
end

local function handle_dishwasher_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
  string.format("handle_dishwasher_mode currentMode: %s", cmd.args.mode))

  if cmd.args.mode==dishwasherMode.dishwasherMode.normal.NAME then
    device:send(clusters.DishwasherMode.commands.ChangeToMode(device, 1, 0))
  elseif cmd.args.mode==dishwasherMode.dishwasherMode.heavy.NAME then
    device:send(clusters.DishwasherMode.commands.ChangeToMode(device, 1, 1))
  elseif cmd.args.mode==dishwasherMode.dishwasherMode.light.NAME then
    device:send(clusters.DishwasherMode.commands.ChangeToMode(device, 1, 2))
  else
    device:send(clusters.DishwasherMode.commands.ChangeToMode(device, 1, 0))
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.SelectedTemperatureLevel.ID] = temperatureControl_attr_handler,
      },
      [clusters.DishwasherMode.ID] = {
        [clusters.DishwasherMode.attributes.SupportedModes.ID] = dishwasher_supported_modes_attr_handler,
        [clusters.DishwasherMode.attributes.CurrentMode.ID] = dishwasher_mode_attr_handler,
      },
      [clusters.OperationalState.ID] = {
        [clusters.OperationalState.attributes.OperationalState.ID] = operational_state_attr_handler,
      },
    }
  },
  subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [temperatureLevelId] = {
      clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
      clusters.TemperatureControl.attributes.SupportedTemperatureLevels,
    },
    [dishwasherModeId] = {
      clusters.DishwasherMode.attributes.SupportedModes,
      clusters.DishwasherMode.attributes.CurrentMode,
    },
    [operationalStateId] = {
      clusters.OperationalState.attributes.OperationalState,
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [temperatureLevelId] = {
      [temperatureLevel.commands.setTemperature.NAME] = handle_temperature,
    },
    [dishwasherModeId] = {
      [dishwasherMode.commands.setDishwasherMode.NAME] = handle_dishwasher_mode,
    },
  },
}

local matter_driver = MatterDriver("matter-dishwasher", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
