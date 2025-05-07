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

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

clusters.RvcCleanMode = require "RvcCleanMode"
clusters.RvcOperationalState = require "RvcOperationalState"
clusters.RvcRunMode = require "RvcRunMode"
clusters.OperationalState = require "OperationalState"

local APPLICATION_ENDPOINT = 10

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("rvc-clean-mode.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = APPLICATION_ENDPOINT,
      clusters = {
        {cluster_id = clusters.RvcRunMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RvcCleanMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RvcOperationalState.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0074, device_type_revision = 1} -- Robot Vacuum Cleaner
      }
    }
  }
})

local function test_init()
  local subscribed_attributes = {
    [capabilities.mode.ID] = {
        clusters.RvcRunMode.attributes.SupportedModes,
        clusters.RvcRunMode.attributes.CurrentMode,
        clusters.RvcCleanMode.attributes.SupportedModes,
        clusters.RvcCleanMode.attributes.CurrentMode,
    },
    [capabilities.robotCleanerOperatingState.ID] = {
        clusters.RvcOperationalState.attributes.OperationalState,
        clusters.RvcOperationalState.attributes.OperationalError,
    },
  }
  local subscribe_request = nil
  for _, attributes in pairs(subscribed_attributes) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device)
      else
        subscribe_request:merge(attribute:subscribe(mock_device))
      end
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
end
test.set_test_init_function(test_init)

local modeTagStruct = require "RvcRunMode.types.ModeTagStruct"

local IDLE_MODE     = { label = "Idle Mode",     mode = 0, mode_tags = { modeTagStruct({ mfg_code = 0x1E1E, value = 16384 }) } }
local CLEANING_MODE = { label = "Cleaning Mode", mode = 2, mode_tags = { modeTagStruct({ mfg_code = 0x1E1E, value = 16385 }) } }
local MAPPING_MODE  = { label = "Mapping Mode",  mode = 4, mode_tags = { modeTagStruct({ mfg_code = 0x1E1E, value = 16386 }) } }

local RUN_MODES = {
  MAPPING_MODE,
  IDLE_MODE,
  CLEANING_MODE,
}

local RUN_MODE_LABELS = { RUN_MODES[1].label, RUN_MODES[2].label, RUN_MODES[3].label }

local CLEAN_MODE_1 = { label = "Clean Mode 1", mode = 0, mode_tags = { modeTagStruct({ mfg_code = 0x1E1E, value = 1 }) } }
local CLEAN_MODE_2 = { label = "Clean Mode 2", mode = 1, mode_tags = { modeTagStruct({ mfg_code = 0x1E1E, value = 2 }) } }

local CLEAN_MODES = {
  CLEAN_MODE_2,
  CLEAN_MODE_1,
}

local CLEAN_MODE_LABELS = { CLEAN_MODES[1].label, CLEAN_MODES[2].label }

local function supported_run_mode_init()
  test.socket.matter:__queue_receive({
    mock_device.id,
    clusters.RvcRunMode.attributes.SupportedModes:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
      {
        clusters.RvcRunMode.types.ModeOptionStruct(RUN_MODES[1]),
        clusters.RvcRunMode.types.ModeOptionStruct(RUN_MODES[2]),
        clusters.RvcRunMode.types.ModeOptionStruct(RUN_MODES[3]),
      }
    )
  })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "runMode",
      capabilities.mode.supportedModes(RUN_MODE_LABELS, { visibility = { displayed = false } })
    )
  )
end

local function supported_clean_mode_init()
  test.socket.matter:__queue_receive({
    mock_device.id,
    clusters.RvcCleanMode.attributes.SupportedModes:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
      {
        clusters.RvcCleanMode.types.ModeOptionStruct(CLEAN_MODES[1]),
        clusters.RvcCleanMode.types.ModeOptionStruct(CLEAN_MODES[2]),
      }
    )
  })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "cleanMode",
      capabilities.mode.supportedModes(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "cleanMode",
      capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
    )
  )
end

local function operating_state_init()
  test.socket.matter:__queue_receive({
    mock_device.id,
    clusters.RvcOperationalState.attributes.OperationalState:build_test_report_data(
      mock_device,
      APPLICATION_ENDPOINT,
      clusters.OperationalState.types.OperationalStateEnum.STOPPED
    )
  })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main",
      capabilities.robotCleanerOperatingState.operatingState.stopped()
    )
  )
end

test.register_coroutine_test(
  "On changing the run mode to a mode with an IDLE tag, supportedArgument must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    operating_state_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        IDLE_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = IDLE_MODE.label})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments(RUN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "On changing the run mode to a mode with an CLEANING tag, supportedArgument must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    operating_state_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        CLEANING_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = CLEANING_MODE.label})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments({ IDLE_MODE.label }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "On changing the run mode to a mode with an MAPPING tag, supportedArgument must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    operating_state_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        MAPPING_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = MAPPING_MODE.label})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments({ IDLE_MODE.label }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "On changing the clean mode, mode must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    operating_state_init()
    for _, cleanMode in ipairs(CLEAN_MODES) do
      test.socket.matter:__queue_receive({
        mock_device.id,
        clusters.RvcCleanMode.attributes.CurrentMode:build_test_report_data(
          mock_device,
          APPLICATION_ENDPOINT,
          cleanMode.mode
        )
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "cleanMode",
          capabilities.mode.mode({value = cleanMode.label})
        )
      )
    end
  end
)

test.register_coroutine_test(
  "On changing the rvc run mode, appropriate RvcRunMode command must be sent to the device", function()
    supported_run_mode_init()
    test.wait_for_events()
    for _, runMode in ipairs(RUN_MODES) do
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "mode", component = "runMode", command = "setMode", args = { runMode.label } }
      })
      test.socket.matter:__expect_send({
        mock_device.id,
        clusters.RvcRunMode.server.commands.ChangeToMode(mock_device, APPLICATION_ENDPOINT, runMode.mode)
      })
    end
  end
)

test.register_coroutine_test(
  "On changing the rvc clean mode, appropriate RvcCleanMode command must be sent to the device", function()
    supported_clean_mode_init()
    test.wait_for_events()
    for _, cleanMode in ipairs(CLEAN_MODES) do
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "mode", component = "cleanMode", command = "setMode", args = { cleanMode.label } }
      })
      test.socket.matter:__expect_send({
        mock_device.id,
        clusters.RvcCleanMode.server.commands.ChangeToMode(mock_device, APPLICATION_ENDPOINT, cleanMode.mode)
      })
    end
  end
)

test.register_coroutine_test(
  "On changing the operatinalState to RUNNING, robotCleanerOperatingState must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        IDLE_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = IDLE_MODE.label})
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalState:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        clusters.OperationalState.types.OperationalStateEnum.RUNNING
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.running()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments({ IDLE_MODE.label }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "On changing the operatinalState to PAUSED, robotCleanerOperatingState must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        IDLE_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = IDLE_MODE.label})
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalState:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        clusters.OperationalState.types.OperationalStateEnum.PAUSED
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.paused()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments(RUN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "On changing the operatinalState to SEEKING_CHARGER, robotCleanerOperatingState must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        IDLE_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = IDLE_MODE.label})
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalState:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        clusters.RvcOperationalState.types.OperationalStateEnum.SEEKING_CHARGER
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.seekingCharger()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments({ IDLE_MODE.label }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "On changing the operatinalState to CHARGING, robotCleanerOperatingState must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        IDLE_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = IDLE_MODE.label})
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalState:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        clusters.RvcOperationalState.types.OperationalStateEnum.CHARGING
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.charging()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments(RUN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "On changing the operatinalState to DOCKED, robotCleanerOperatingState must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        IDLE_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = IDLE_MODE.label})
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalState:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        clusters.RvcOperationalState.types.OperationalStateEnum.DOCKED
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.docked()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments(RUN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments(CLEAN_MODE_LABELS, { visibility = { displayed = false } })
      )
    )
  end
)

test.register_coroutine_test(
  "On changing the OperationalError, robotCleanerOperatingState must be set to the appropriate value", function()
    supported_run_mode_init()
    supported_clean_mode_init()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        IDLE_MODE.mode
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.mode({value = IDLE_MODE.label})
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalState:build_test_report_data(
        mock_device,
        APPLICATION_ENDPOINT,
        clusters.OperationalState.types.OperationalStateEnum.ERROR
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "runMode",
        capabilities.mode.supportedArguments({}, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "cleanMode",
        capabilities.mode.supportedArguments({}, { visibility = { displayed = false } })
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_START_OR_RESUME,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.unableToStartOrResume()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_COMPLETE_OPERATION,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.unableToCompleteOperation()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.OperationalState.types.ErrorStateEnum.COMMAND_INVALID_IN_STATE,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.commandInvalidInState()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.RvcOperationalState.types.ErrorStateEnum.FAILED_TO_FIND_CHARGING_DOCK,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.failedToFindChargingDock()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.RvcOperationalState.types.ErrorStateEnum.STUCK,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.stuck()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.RvcOperationalState.types.ErrorStateEnum.DUST_BIN_MISSING,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.dustBinMissing()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.RvcOperationalState.types.ErrorStateEnum.DUST_BIN_FULL,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.dustBinFull()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.RvcOperationalState.types.ErrorStateEnum.WATER_TANK_EMPTY,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.waterTankEmpty()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.RvcOperationalState.types.ErrorStateEnum.WATER_TANK_MISSING,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.waterTankMissing()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.RvcOperationalState.types.ErrorStateEnum.WATER_TANK_LID_OPEN,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.waterTankLidOpen()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.RvcOperationalState.server.attributes.OperationalError:build_test_report_data(
        mock_device, APPLICATION_ENDPOINT,
        {
          error_state_id = clusters.RvcOperationalState.types.ErrorStateEnum.MOP_CLEANING_PAD_MISSING,
          error_state_label = "",
          error_state_details = ""
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.robotCleanerOperatingState.operatingState.mopCleaningPadMissing()
      )
    )
  end
)

test.run_registered_tests()