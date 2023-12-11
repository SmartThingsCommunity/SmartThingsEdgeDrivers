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

local robotCleanerOperationalStateId = "spacewonder52282.robotCleanerOperationalState2"
local robotCleanerOperationalState = capabilities[robotCleanerOperationalStateId]

local rvc_run_mode_supported_mode = "RvcRunMode.SupportedMode"
local rvc_clean_mode_supported_mode = "RvcCleanMode.SupportedMode"

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function rvc_run_mode_supported_mode_attr_handler(driver, device, ib, response)
  local supportedModes = {}
  for _, mode in ipairs(ib.data.value) do
    table.insert(supportedModes, mode.label)
  end
  device:set_field(rvc_run_mode_supported_mode, supportedModes, {persist = true})
  local component = device.profile.components["runMode"]
  device:emit_component_event(component, capabilities.mode.supportedModes(supportedModes))
end

local function rvc_run_mode_current_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("rvc_run_mode_current_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode = math.floor(ib.data.value)
  local supportedModes = device:get_field(rvc_run_mode_supported_mode)
  for _, mode in ipairs(supportedModes) do
    if mode.mode == current_mode then
      local component = device.profile.components["runMode"]
      device:emit_component_event(component, capabilities.mode.mode(mode.label))
      break
    end
  end
end

local function rvc_clean_mode_supported_mode_attr_handler(driver, device, ib, response)
  local supportedModes = {}
  for _, mode in ipairs(ib.data.value) do
    table.insert(supportedModes, mode.label)
  end
  device:set_field(rvc_clean_mode_supported_mode, supportedModes, {persist = true})
  local component = device.profile.components["cleanMode"]
  device:emit_component_event(component, capabilities.mode.supportedModes(supportedModes))
end

local function rvc_clean_mode_current_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("rvc_clean_mode_current_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode = math.floor(ib.data.value)
  local supportedModes = device:get_field(rvc_clean_mode_supported_mode)
  for _, mode in ipairs(supportedModes) do
    if mode.mode == current_mode then
      local component = device.profile.components["cleanMode"]
      device:emit_component_event(component, capabilities.mode.mode(mode.label))
      break
    end
  end
end

local function rvc_operational_state_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("rvc_operational_state_attr_handler operationalState: %s", ib.data.value))

  if ib.data.value == clusters.OperationalState.types.OperationalStateEnum.STOPPED then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerOperationalState.robotCleanerOperationalState.stopped())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.RUNNING then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerOperationalState.robotCleanerOperationalState.running())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.PAUSED then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerOperationalState.robotCleanerOperationalState.paused())
  elseif ib.data.value == clusters.OperationalState.types.OperationalStateEnum.ERROR then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerOperationalState.robotCleanerOperationalState.error())
  elseif ib.data.value == clusters.RvcOperationalState.types.OperationalStateEnum.SEEKING_CHARGER then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerOperationalState.robotCleanerOperationalState.seekingcharger())
  elseif ib.data.value == clusters.RvcOperationalState.types.OperationalStateEnum.CHARGING then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerOperationalState.robotCleanerOperationalState.charging())
  elseif ib.data.value == clusters.RvcOperationalState.types.OperationalStateEnum.DOCKED then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerOperationalState.robotCleanerOperationalState.docked())
  end
end

-- Capability Handlers --
local function handle_robot_cleaner_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_robot_cleaner_mode component: %s, mode: %s", cmd.component, cmd.args.mode))

  if cmd.component == "runMode" then
    local supportedModes = device:get_field(rvc_run_mode_supported_mode)
    for i, mode in ipairs(supportedModes) do
      if cmd.args.mode == mode.mode then
        device:send(clusters.RvcRunMode.commands.ChangeToMode(device, 1, i - 1))
        return
      end
    end
  elseif cmd.component == "cleanMode" then
    local supportedModes = device:get_field(rvc_clean_mode_supported_mode)
    for i, mode in ipairs(supportedModes) do
      if cmd.args.mode == mode.mode then
        device:send(clusters.RvcCleanMode.commands.ChangeToMode(device, 1, i - 1))
        return
      end
    end
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.RvcRunMode.ID] = {
        [clusters.RvcRunMode.attributes.SupportedModes.ID] = rvc_run_mode_supported_mode_attr_handler,
        [clusters.RvcRunMode.attributes.CurrentMode.ID] = rvc_run_mode_current_mode_attr_handler,
      },
      [clusters.RvcCleanMode.ID] = {
        [clusters.RvcCleanMode.attributes.SupportedModes.ID] = rvc_clean_mode_supported_mode_attr_handler,
        [clusters.RvcCleanMode.attributes.CurrentMode.ID] = rvc_clean_mode_current_mode_attr_handler,
      },
      [clusters.RvcOperationalState.ID] = {
        [clusters.RvcOperationalState.attributes.OperationalState.ID] = rvc_operational_state_attr_handler,
      },
    }
  },
  subscribed_attributes = {
    [capabilities.mode.ID] = {
      clusters.RvcRunMode.attributes.SupportedModes,
      clusters.RvcRunMode.attributes.CurrentMode,
      clusters.RvcCleanMode.attributes.SupportedModes,
      clusters.RvcCleanMode.attributes.CurrentMode,
    },
    [robotCleanerOperationalStateId] = {
      clusters.RvcOperationalState.attributes.OperationalState,
    },
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_robot_cleaner_mode,
    },
  },
}

local matter_driver = MatterDriver("matter-rvc", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
