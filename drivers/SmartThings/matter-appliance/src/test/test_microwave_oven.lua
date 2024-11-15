-- Copyright 2024 SmartThings
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
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

clusters.OperationalState = require "OperationalState"
clusters.MicrowaveOvenControl = require "MicrowaveOvenControl"
clusters.MicrowaveOvenMode = require "MicrowaveOvenMode"

local APPLICATION_ENDPOINT = 1

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("microwave-oven.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        { cluster_id = clusters.OperationalState.ID,     cluster_type = "SERVER" },
        { cluster_id = clusters.MicrowaveOvenControl.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.MicrowaveOvenMode.ID,    cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0079, device_type_revision = 1 } -- Microwave Oven
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.OperationalState.attributes.OperationalState,
    clusters.OperationalState.attributes.OperationalError,
    clusters.OperationalState.attributes.AcceptedCommandList,
    clusters.MicrowaveOvenMode.attributes.SupportedModes,
    clusters.MicrowaveOvenMode.attributes.CurrentMode,
    clusters.MicrowaveOvenControl.attributes.MaxCookTime,
    clusters.MicrowaveOvenControl.attributes.CookTime
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.socket.matter:__expect_send({ mock_device.id, clusters.MicrowaveOvenControl.attributes.MaxCookTime:read(
    mock_device, APPLICATION_ENDPOINT) })
  test.mock_device.add_test_device(mock_device)
end

local function init_supported_microwave_oven_modes()
  test.socket.matter:__queue_receive({
    mock_device.id,
    clusters.MicrowaveOvenMode.attributes.SupportedModes:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
      {
        clusters.MicrowaveOvenMode.types.ModeOptionStruct({
          ["label"] = "Grill",
          ["mode"] = 0,
          ["mode_tags"] = {
            clusters.MicrowaveOvenMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 0 })
          }
        }),
        clusters.MicrowaveOvenMode.types.ModeOptionStruct({
          ["label"] = "Pre Heat",
          ["mode"] = 1,
          ["mode_tags"] = {
            clusters.MicrowaveOvenMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 1 })
          }
        })
      }
    )
  })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.mode.supportedModes({ "Grill", "Pre Heat" }, {visibility={displayed=false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.mode.supportedArguments({ "Grill", "Pre Heat" }, {visibility={displayed=false}})))
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Setting operationalState command to 'start' should send appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "operationalState", component = "main", command = "start", args = {} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.server.commands.Start(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalState:read(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:read(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalState:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.OperationalStateEnum.RUNNING)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.operationalState.operationalState.running())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({},{visibility={displayed=false}}))
      -- Prevent user from changing modes in between an operation.
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedArguments({},{visibility={displayed=false}}))
      -- Prevent user from changing modes in between an operation.
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.ErrorStateStruct({
            ["error_state_id"] = clusters.OperationalState.types.ErrorStateEnum.NO_ERROR,
            ["error_state_label"] = "",
            ["error_state_details"] = ""
          }))
      }
    }, -- on receiving NO ERROR we don't do anything.
  }
)

test.register_message_test(
  "Setting operationalState command to 'stop' should send appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "operationalState", component = "main", command = "stop", args = {} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.server.commands.Stop(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalState:read(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:read(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalState:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.OperationalStateEnum.STOPPED)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.operationalState.operationalState.stopped())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({ "Grill", "Pre Heat" },{visibility={displayed=false}}))
      --When operation is stopped, enable mode options for user to choose.
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedArguments({ "Grill", "Pre Heat" },{visibility={displayed=false}}))
      --When operation is stopped, enable mode options for user to choose.
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.ErrorStateStruct({
            ["error_state_id"] = clusters.OperationalState.types.ErrorStateEnum.NO_ERROR,
            ["error_state_label"] = "",
            ["error_state_details"] = ""
          }))
      }
    }, -- on receiving NO ERROR we don't do anything.
  },
  {
    test_init = function()
      test_init()
      init_supported_microwave_oven_modes()
    end
  }
)

test.register_message_test(
  "Setting operationalState command to 'pause' should send appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "operationalState", component = "main", command = "pause", args = {} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.server.commands.Pause(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalState:read(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:read(mock_device, APPLICATION_ENDPOINT)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalState:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.OperationalStateEnum.PAUSED)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.operationalState.operationalState.paused())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({},{visibility={displayed=false}}))
      -- Prevent user from changing modes in between an operation.
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedArguments({},{visibility={displayed=false}}))
      -- Prevent user from changing modes in between an operation.
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.ErrorStateStruct({
            ["error_state_id"] = clusters.OperationalState.types.ErrorStateEnum.NO_ERROR,
            ["error_state_label"] = "",
            ["error_state_details"] = ""
          }))
      }
    }, -- on receiving NO ERROR we don't do anything.
  }
)

test.register_message_test(
  "On receiving OperationalError, the appropriate operationalState event must be emitted",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.ErrorStateStruct({
            ["error_state_id"] = clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_START_OR_RESUME,
            ["error_state_label"] = "",
            ["error_state_details"] = ""
          }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.operationalState.operationalState.unableToStartOrResume())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({},{visibility={displayed=false}}))
      -- Prevent user from changing mode in event of error.
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedArguments({},{visibility={displayed=false}}))
      -- Prevent user from changing mode in event of error.
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.ErrorStateStruct({
            ["error_state_id"] = clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_COMPLETE_OPERATION,
            ["error_state_label"] = "",
            ["error_state_details"] = ""
          }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.operationalState.operationalState.unableToCompleteOperation())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({},{visibility={displayed=false}}))
      -- Prevent user from changing mode in event of error.
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedArguments({},{visibility={displayed=false}}))
      -- Prevent user from changing mode in event of error.
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.ErrorStateStruct({
            ["error_state_id"] = clusters.OperationalState.types.ErrorStateEnum.COMMAND_INVALID_IN_STATE,
            ["error_state_label"] = "",
            ["error_state_details"] = ""
          }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.operationalState.operationalState.commandInvalidInCurrentState())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({},{visibility={displayed=false}}))
      -- Prevent user from changing mode in event of error.
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedArguments({},{visibility={displayed=false}}))
      -- Prevent user from changing mode in event of error.
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.attributes.OperationalError:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          clusters.OperationalState.types.ErrorStateStruct({
            ["error_state_id"] = clusters.OperationalState.types.ErrorStateEnum.NO_ERROR,
            ["error_state_label"] = "",
            ["error_state_details"] = ""
          }))
      }
    }, -- on receiving NO ERROR we don't do anything.
  }
)

test.register_message_test(
  "The cookTimeRange value should be set on receiving MaxCookTime",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.MicrowaveOvenControl.attributes.MaxCookTime:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          900)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.cookTime.cookTimeRange({
        minimum = 1, --minimum should be 1.
        maximum = 900
      },{visibility={displayed=false}}))
    },
  }
)

test.register_message_test(
  "This test case checks for the following events:\n1. Report cookTime value of 30 seconds.\n2. MicrowaveOven supportedModes must be registered.\n3. Setting oven mode and cookTime should send appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.MicrowaveOvenControl.attributes.CookTime:build_test_report_data(mock_device, APPLICATION_ENDPOINT, 30)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.cookTime.cookTime(30))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.MicrowaveOvenMode.attributes.SupportedModes:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          {
            clusters.MicrowaveOvenMode.types.ModeOptionStruct({
              ["label"] = "Grill",
              ["mode"] = 0,
              ["mode_tags"] = {
                clusters.MicrowaveOvenMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 0 })
              }
            }),
            clusters.MicrowaveOvenMode.types.ModeOptionStruct({
              ["label"] = "Pre Heat",
              ["mode"] = 1,
              ["mode_tags"] = {
                clusters.MicrowaveOvenMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 1 })
              }
            })
          }
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({ "Grill", "Pre Heat" }, {visibility={displayed=false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedArguments({ "Grill", "Pre Heat" }, {visibility={displayed=false}}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "main", command = "setMode", args = { "Grill" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.MicrowaveOvenControl.commands.SetCookingParameters(mock_device, APPLICATION_ENDPOINT,
          0, --Index where Grill is stored
          30) --30 since that was the last received cookTime.
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "cookTime", component = "main", command = "setCookTime", args = { 300 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.MicrowaveOvenControl.commands.SetCookingParameters(mock_device, APPLICATION_ENDPOINT,
          0, --> Grill, as this was the last set microwave oven mode.
          300)
      }
    },
  }
)

test.run_registered_tests()
