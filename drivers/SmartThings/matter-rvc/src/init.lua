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

local robotCleanerCleaningModeId = "spacewonder52282.robotCleanerCleaningMode"
local robotCleanerCleaningMode = capabilities[robotCleanerCleaningModeId]
local robotCleanerOperationalStateId = "spacewonder52282.robotCleanerOperationalState2"
local robotCleanerOperationalState = capabilities[robotCleanerOperationalStateId]

local rvc_run_mode_supported_mode = "RvcRunMode.SupportedMode"
local rvc_clean_mode_supported_mode = "RvcCleanMode.SupportedMode"

local RVC_RUN_MODE_MAP = {
  [0x4000] = capabilities.robotCleanerMovement.robotCleanerMovement.idle,
  [0x4001] = capabilities.robotCleanerMovement.robotCleanerMovement.cleaning,
}

local RVC_CLEAN_MODE_MAP = {
  [0x4000] = robotCleanerCleaningMode.robotCleanerCleaningMode.deepClean,
  [0x4001] = robotCleanerCleaningMode.robotCleanerCleaningMode.vaccum,
  [0x4002] = robotCleanerCleaningMode.robotCleanerCleaningMode.mop,
}

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function rvc_run_mode_supported_mode_attr_handler(driver, device, ib, response)
  device:set_field(rvc_run_mode_supported_mode, ib.data.value, {persist = true})
end

local function rvc_run_mode_current_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("run_current_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode=math.floor(ib.data.value)
  if current_mode==1 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerMovement.robotCleanerMovement.cleaning())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.robotCleanerMovement.robotCleanerMovement.idle())
  end
end

local function rvc_clean_mode_supported_mode_attr_handler(driver, device, ib, response)
  device:set_field(rvc_clean_mode_supported_mode, ib.data.value, {persist = true})
end

local function rvc_clean_mode_current_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("rvc_clean_mode_current_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode=math.floor(ib.data.value)
  if current_mode==0 then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerCleaningMode.robotCleanerCleaningMode.deepClean())
  elseif current_mode==1 then
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerCleaningMode.robotCleanerCleaningMode.vaccum())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, robotCleanerCleaningMode.robotCleanerCleaningMode.mop())
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
local function handle_robot_cleaner_movement(driver, device, cmd)
  log.info_with({ hub_logs = true },
  string.format("handle_robot_cleaner_movement currentMode: %s", cmd.args.mode))

  if cmd.args.mode==capabilities.robotCleanerMovement.robotCleanerMovement.cleaning.NAME then
      device:send(clusters.RvcRunMode.commands.ChangeToMode(device, 1, 1))
  else
      device:send(clusters.RvcRunMode.commands.ChangeToMode(device, 1, 0))
  end
end

local function handle_robot_cleaner_cleaning_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
  string.format("handle_robot_cleaner_cleaning_mode currentMode: %s", cmd.args.mode))

  if cmd.args.mode==robotCleanerCleaningMode.robotCleanerCleaningMode.deepClean.NAME then
    device:send(clusters.RvcCleanMode.commands.ChangeToMode(device, 1, 0))
  elseif cmd.args.mode==robotCleanerCleaningMode.robotCleanerCleaningMode.vaccum.NAME then
    device:send(clusters.RvcCleanMode.commands.ChangeToMode(device, 1, 1))
  else
    device:send(clusters.RvcCleanMode.commands.ChangeToMode(device, 1, 2))
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
    [capabilities.robotCleanerMovement.ID] = {
      clusters.RvcRunMode.attributes.SupportedModes,
      clusters.RvcRunMode.attributes.CurrentMode,
    },
    [robotCleanerCleaningModeId] = {
      clusters.RvcCleanMode.attributes.SupportedModes,
      clusters.RvcCleanMode.attributes.CurrentMode,
    },
    [robotCleanerOperationalStateId] = {
      clusters.RvcOperationalState.attributes.OperationalState,
    },
  },
  capability_handlers = {
    [capabilities.robotCleanerMovement.ID] = {
      [capabilities.robotCleanerMovement.commands.setRobotCleanerMovement.NAME] = handle_robot_cleaner_movement,
    },
    [robotCleanerCleaningModeId] = {
      [robotCleanerCleaningMode.commands.setRobotCleanerCleaningMode.NAME] = handle_robot_cleaner_cleaning_mode,
    },
  },
}

local matter_driver = MatterDriver("matter-rvc", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
