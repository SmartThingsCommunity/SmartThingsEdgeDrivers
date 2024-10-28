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
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local log = require "log"

local EVSE_EP = 1
local ELECTRICAL_SENSOR_EP = 2
local DEVICE_ENERGY_MANAGEMENT_DEVICE_EP = 3

clusters.EnergyEvse = require "EnergyEvse"
clusters.EnergyEvseMode = require "EnergyEvseMode"
clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
clusters.DeviceEnergyManagementMode = require "DeviceEnergyManagementMode"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("evse-power-meas-energy-mgmt-mode.yml"),
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
      endpoint_id = EVSE_EP,
      clusters = {
        { cluster_id = clusters.EnergyEvse.ID,     cluster_type = "SERVER" },
        { cluster_id = clusters.EnergyEvseMode.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x050C, device_type_revision = 1 } -- EVSE
      }
    },
    {
      endpoint_id = ELECTRICAL_SENSOR_EP,
      clusters = {
        { cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 } -- Electrical Sensor
      }
    },
    {
      endpoint_id = DEVICE_ENERGY_MANAGEMENT_DEVICE_EP,
      clusters = {
        { cluster_id = clusters.DeviceEnergyManagementMode.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x050D, device_type_revision = 1 } -- Device Energy Management
      }
    },
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.EnergyEvse.attributes.State,
    clusters.EnergyEvse.attributes.SupplyState,
    clusters.EnergyEvse.attributes.FaultState,
    clusters.EnergyEvse.attributes.ChargingEnabledUntil,
    clusters.EnergyEvse.attributes.MinimumChargeCurrent,
    clusters.EnergyEvse.attributes.MaximumChargeCurrent,
    clusters.EnergyEvse.attributes.SessionDuration,
    clusters.EnergyEvse.attributes.SessionEnergyCharged,
    clusters.ElectricalPowerMeasurement.attributes.PowerMode,
    clusters.EnergyEvseMode.attributes.SupportedModes,
    clusters.EnergyEvseMode.attributes.CurrentMode,
    clusters.DeviceEnergyManagementMode.attributes.CurrentMode,
    clusters.DeviceEnergyManagementMode.attributes.SupportedModes,
  }
  log.info("In test init", os.time())
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
  capabilities.evseChargingSession.targetEndTime("1970-01-01T00:00:00Z")))
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Assert component to endpoint map",
  function()
    local component_to_endpoint_map = mock_device:get_field("__component_to_endpoint_map")
    assert(component_to_endpoint_map["electricalSensor"] == ELECTRICAL_SENSOR_EP, "Electrical Sensor Endpoint must be 2")
    assert(component_to_endpoint_map["deviceEnergyManagement"] == DEVICE_ENERGY_MANAGEMENT_DEVICE_EP,
      "Device Energy Management Endpoint must be 3")
  end
)

test.register_message_test(
  "EnergyEvse Supply State must trigger appropriate evseState supplystate capability event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.SupplyState:build_test_report_data(mock_device, EVSE_EP,
          clusters.EnergyEvse.attributes.SupplyState.CHARGING_ENABLED)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseState.supplyState.chargingEnabled())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseChargingSession.chargingState.charging({state_change = true}))
    }
  }
)

test.register_message_test(
  "EnergyEvse State must trigger appropriate evseState EvseState capability event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.SupplyState:build_test_report_data(mock_device, EVSE_EP,
          clusters.EnergyEvse.attributes.SupplyState.CHARGING_ENABLED)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseState.supplyState.chargingEnabled())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseChargingSession.chargingState.charging({state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.State:build_test_report_data(mock_device, EVSE_EP,
          clusters.EnergyEvse.attributes.State.PLUGGED_IN_DEMAND)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseState.state.pluggedInDemand())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseChargingSession.chargingState.charging({state_change = true}))
    },
  }
)

test.register_message_test(
  "EnergyEvse Fault State must trigger appropriate evseState faultState capability event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.FaultState:build_test_report_data(mock_device, EVSE_EP,
          clusters.EnergyEvse.attributes.FaultState.GROUND_FAULT)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseState.faultState.groundFault())
    }
  }
)

test.register_message_test(
  "EnergyEvse ChargingEnabledUntil in epoch must trigger appropriate evseChargingSession targetEndTime capability event in iso8601 format", --1724399242 in epoch to 2024-08-23T07:47:22Z in iso8601
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.ChargingEnabledUntil:build_test_report_data(mock_device, EVSE_EP, 1724399242)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseChargingSession.targetEndTime("2024-08-23T07:47:22Z"))
    }
  }
)

test.register_message_test(
  "EnergyEvse MinimumChargeCurrent constraint must trigger appropriate evseChargingSession minCurrent capability event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.MinimumChargeCurrent:build_test_report_data(mock_device, EVSE_EP, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseChargingSession.minCurrent(0))
    }
  }
)

test.register_message_test(
  "EnergyEvse MaximumChargeCurrent constraint must trigger appropriate evseChargingSession maxCurrent capability event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.MaximumChargeCurrent:build_test_report_data(mock_device, EVSE_EP, 10000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseChargingSession.maxCurrent(10000))
    }
  }
)

test.register_message_test(
  "EnergyEvse SessionDuration must trigger appropriate evseChargingSession sessionTime capability event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.SessionDuration:build_test_report_data(mock_device, EVSE_EP, 9000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseChargingSession.sessionTime(9000))
    }
  }
)

test.register_message_test(
  "EnergyEvse SessionEnergyCharged must trigger appropriate evseChargingSession energyDelivered capability event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvse.attributes.SessionEnergyCharged:build_test_report_data(mock_device, EVSE_EP, 900000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.evseChargingSession.energyDelivered(900000))
    }
  }
)

test.register_message_test(
  "ElectricalPowerMeasurement PowerMode must trigger appropriate powerSource capability event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ElectricalPowerMeasurement.attributes.PowerMode:build_test_report_data(mock_device, ELECTRICAL_SENSOR_EP,
          clusters.ElectricalPowerMeasurement.attributes.PowerMode.AC)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("electricalSensor",
        capabilities.powerSource.powerSource.mains())
    }
  }
)

test.register_message_test(
  "EnergyEvseMode SupportedModes must be registered.\n2.CurrentMode must trigger approriate mode capability event.\n3.Command to setMode should trigger appropriate changeToMode matter command",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvseMode.attributes.SupportedModes:build_test_report_data(mock_device, EVSE_EP, {
          clusters.EnergyEvseMode.types.ModeOptionStruct({
            ["label"] = "Auto-Scheduled",
            ["mode"] = 0,
            ["mode_tags"] = {
              clusters.EnergyEvseMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 0 })
            }
          }),
          clusters.EnergyEvseMode.types.ModeOptionStruct({
            ["label"] = "Manual",
            ["mode"] = 1,
            ["mode_tags"] = {
              clusters.EnergyEvseMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 1 })
            }
          })
        })
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.mode.supportedModes({ "Auto-Scheduled", "Manual" }, { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.mode.supportedArguments({ "Auto-Scheduled", "Manual" }, { visibility = { displayed = false } }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.EnergyEvseMode.attributes.CurrentMode:build_test_report_data(mock_device, EVSE_EP, 1) --1 is the index for Manual EnergyEvse mode
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.mode.mode("Manual"))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "main", command = "setMode", args = { "Auto-Scheduled" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.EnergyEvseMode.commands.ChangeToMode(mock_device, EVSE_EP, 0) --Index is Auto-Scheduled
      }
    }
  }
)

test.register_message_test(
  "DeviceEnergyManagementMode SupportedModes must be registered.\n2.CurrentMode must trigger approriate mode capability event.\n3.Command to setMode should trigger appropriate changeToMode matter command",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DeviceEnergyManagementMode.attributes.SupportedModes:build_test_report_data(mock_device,
          DEVICE_ENERGY_MANAGEMENT_DEVICE_EP, {
          clusters.DeviceEnergyManagementMode.types.ModeOptionStruct({
            ["label"] = "Grid Energy Management",
            ["mode"] = 0,
            ["mode_tags"] = {
              clusters.DeviceEnergyManagementMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 0 })
            }
          }),
          clusters.DeviceEnergyManagementMode.types.ModeOptionStruct({
            ["label"] = "Home Energy Management",
            ["mode"] = 1,
            ["mode_tags"] = {
              clusters.DeviceEnergyManagementMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 1 })
            }
          }),
          clusters.DeviceEnergyManagementMode.types.ModeOptionStruct({
            ["label"] = "Full Energy Management",
            ["mode"] = 2,
            ["mode_tags"] = {
              clusters.DeviceEnergyManagementMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 2 })
            }
          })
        })
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("deviceEnergyManagement",
        capabilities.mode.supportedModes(
        { "Grid Energy Management", "Home Energy Management", "Full Energy Management" },
          { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("deviceEnergyManagement",
        capabilities.mode.supportedArguments(
        { "Grid Energy Management", "Home Energy Management", "Full Energy Management" },
          { visibility = { displayed = false } }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DeviceEnergyManagementMode.attributes.CurrentMode:build_test_report_data(mock_device,
          DEVICE_ENERGY_MANAGEMENT_DEVICE_EP, 1)                                                                                              --1 is the index for Home Energy Management mode
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("deviceEnergyManagement",
        capabilities.mode.mode("Home Energy Management"))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "deviceEnergyManagement", command = "setMode", args = { "Full Energy Management" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.DeviceEnergyManagementMode.commands.ChangeToMode(mock_device, DEVICE_ENERGY_MANAGEMENT_DEVICE_EP, 2) --Index is Full Energy Management
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "deviceEnergyManagement", command = "setMode", args = { "Grid Energy Management" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.DeviceEnergyManagementMode.commands.ChangeToMode(mock_device, DEVICE_ENERGY_MANAGEMENT_DEVICE_EP, 0) --Index is Grid Energy Management
      }
    }
  }
)

--TODO: Include tests for evseChargingSession capability commands. This is anyhow tested with EVSE virtual device app.

test.run_registered_tests()
