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

local APPLICATION_ENDPOINT = 1

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("laundry-dryer-tn-tl.yml"),
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
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
        },
        { cluster_id = clusters.LaundryWasherMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.OperationalState.ID,   cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x007C, device_type_revision = 1 } -- LaundryDryer
      }
    }
  }
})

local mock_device_washer = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("laundry-washer-tn-tl.yml"),
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
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
        },
        { cluster_id = clusters.LaundryWasherMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.OperationalState.ID,   cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x0073, device_type_revision = 1 } -- LaundryWasher
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LaundryWasherMode.attributes.CurrentMode,
    clusters.LaundryWasherMode.attributes.SupportedModes,
    clusters.OperationalState.attributes.OperationalState,
    clusters.OperationalState.attributes.OperationalError,
    clusters.OperationalState.attributes.AcceptedCommandList,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  local subscribe_request_washer = cluster_subscribe_list[1]:subscribe(mock_device_washer)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request_washer:merge(cluster:subscribe(mock_device_washer))
    end
  end
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.socket.matter:__expect_send({ mock_device_washer.id, subscribe_request_washer })
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_washer)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_washer.id, "added" })
  test.set_rpc_version(5)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Off command should send appropriate commands",
  -- we do not test "on" command, as laundry devices are supposed to have offOnly feature.
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.Off(mock_device, APPLICATION_ENDPOINT)
      }
    }
  }
)

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
  "Laundry Washer Suppoerted Modes must be registered and Laundry Washer Mode command should send appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LaundryWasherMode.attributes.SupportedModes:build_test_report_data(mock_device, APPLICATION_ENDPOINT,
          {
            clusters.LaundryWasherMode.types.ModeOptionStruct({ ["label"] = "Quick", ["mode"] = 0, ["mode_tags"] = {} }),
            clusters.LaundryWasherMode.types.ModeOptionStruct({ ["label"] = "Super Dry", ["mode"] = 1, ["mode_tags"] = {} })
          }
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({"Quick", "Super Dry"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedArguments({"Quick", "Super Dry"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "main", command = "setMode", args = {"Quick"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.LaundryWasherMode.server.commands.ChangeToMode(mock_device, APPLICATION_ENDPOINT, 0) --0 is the index where Quick is stored.
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "main", command = "setMode", args = {"Super Dry"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.LaundryWasherMode.server.commands.ChangeToMode(mock_device, APPLICATION_ENDPOINT, 1) --1 is the index where Super Dry is stored.
      }
    }
  }
)

local utf1 = require "st.matter.data_types.UTF8String1"

test.register_message_test(
  "TemperatureControl Supported Levels must be registered and setTemperatureLevel level command should send appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.SupportedTemperatureLevels:build_test_report_data(mock_device, APPLICATION_ENDPOINT, {utf1("Level 1"), utf1("Level 2"), utf1("Level 3")})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureLevel.supportedTemperatureLevels({"Level 1", "Level 2", "Level 3"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureLevel", component = "main", command = "setTemperatureLevel", args = {"Level 1"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.server.commands.SetTemperature(mock_device, APPLICATION_ENDPOINT, nil, 0) --0 is the index where Level1 is stored.
      }
    },
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for laundry dryer",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device, APPLICATION_ENDPOINT, 3000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device, APPLICATION_ENDPOINT, 7000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device, APPLICATION_ENDPOINT, 6000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=30.0,maximum=70.0, step = 0.1}, unit = "C"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 60.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {40.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device, APPLICATION_ENDPOINT, 40 * 100, nil)
      }
    },
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for laundry dryer, temp bounds out of range and temp setpoint converted from F to C",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device, APPLICATION_ENDPOINT, 0)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device, APPLICATION_ENDPOINT, 10000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device, APPLICATION_ENDPOINT, 5000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=27.0,maximum=80.0, step = 0.1}, unit = "C"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 50.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {104.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device, APPLICATION_ENDPOINT, 40 * 100, nil)
      }
    },
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for laundry washer",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 1500)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 5000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 4000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=15.0,maximum=50.0, step = 0.1}, unit = "C"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 40.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_washer.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {25.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device_washer, APPLICATION_ENDPOINT, 25 * 100, nil)
      }
    },
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for laundry washer, temp bounds out of range and temp setpoint converted from F to C",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 0)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 10000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 3000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=13.0,maximum=55.0, step = 0.1}, unit = "C"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 30.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_washer.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {122.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device_washer, APPLICATION_ENDPOINT, 50 * 100, nil)
      }
    },
  }
)

test.run_registered_tests()
