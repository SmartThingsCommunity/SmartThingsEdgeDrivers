local test = require "integration_test"
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

test.add_package_capability("cookTime.yml")
test.add_package_capability("fanMode.yml")

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
      }))
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
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({ "Grill", "Pre Heat" }))
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