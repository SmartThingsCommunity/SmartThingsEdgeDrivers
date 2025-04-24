-- Copyright 2025 SmartThings
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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Meter = (require "st.zwave.CommandClass.Meter")({version=4})
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local t_utils = require "integration_test.utils"

local AEOTEC_MFR_ID = 0x0371
local AEOTEC_METER_PROD_TYPE = 0x0003
local AEOTEC_METER_PROD_ID = 0x0033

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local aeotec_meter_endpoints = {
  {
    command_classes = {
      {value = zw.METER}
    }
  }
}

local HEM8_DEVICES = {
  {
    profile = 'aeotec-home-energy-meter-gen8-1-phase-con',
    name = 'Aeotec Home Energy Meter 8 Consumption',
    endpoints = { 1, 3 }
  },
  {
    profile = 'aeotec-home-energy-meter-gen8-1-phase-pro',
    name = 'Aeotec Home Energy Meter 8 Production',
    child_key = 'pro',
    endpoints = { 2, 4 }
  },
  {
    profile = 'aeotec-home-energy-meter-gen8-sald-con',
    name = 'Aeotec Home Energy Meter 8 Settled Consumption',
    child_key = 'sald-con',
    endpoints = { 5 }
  },
  {
    profile = 'aeotec-home-energy-meter-gen8-sald-pro',
    name = 'Aeotec Home Energy Meter 8 Settled Production',
    child_key = 'sald-pro',
    endpoints = { 6 }
  }
}

local mock_parent = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition(HEM8_DEVICES[1].profile .. '.yml'),
  zwave_endpoints = aeotec_meter_endpoints,
  zwave_manufacturer_id = AEOTEC_MFR_ID,
  zwave_product_type = AEOTEC_METER_PROD_TYPE,
  zwave_product_id = AEOTEC_METER_PROD_ID
})

local mock_child_prod = test.mock_device.build_test_child_device({
    profile = t_utils.get_profile_definition(HEM8_DEVICES[2].profile .. '.yml'),
    parent_device_id = mock_parent.id,
    parent_assigned_child_key = HEM8_DEVICES[2].child_key
})

local mock_child_sald_con = test.mock_device.build_test_child_device({
    profile = t_utils.get_profile_definition(HEM8_DEVICES[3].profile .. '.yml'),
    parent_device_id = mock_parent.id,
    parent_assigned_child_key = HEM8_DEVICES[3].child_key
})

local mock_child_sald_prod = test.mock_device.build_test_child_device({
    profile = t_utils.get_profile_definition(HEM8_DEVICES[4].profile .. '.yml'),
    parent_device_id = mock_parent.id,
    parent_assigned_child_key = HEM8_DEVICES[4].child_key
})

local function test_init()
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child_prod)
  test.mock_device.add_test_device(mock_child_sald_con)
  test.mock_device.add_test_device(mock_child_sald_prod)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Added lifecycle event should create children for parent device",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_parent.id, "added" })

    for _, child in ipairs(HEM8_DEVICES) do
        if(child["child_key"]) then
          mock_parent:expect_device_create(
            {
                type = "EDGE_CHILD",
                label = child.name,
                profile = child.profile,
                parent_device_id = mock_parent.id,
                parent_assigned_child_key = child.child_key
            }
          )
        end
    end
    -- Refresh
    for _, device in ipairs(HEM8_DEVICES) do
      for _, endpoint in ipairs(device.endpoints) do
        test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({scale = Meter.scale.electric_meter.WATTS}, {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { endpoint }
            })
          )
        )
        test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}, {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { endpoint }
            })
          )
        )
      end
    end
  end
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_parent.id, "doConfigure" })

    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_parent,
      Configuration:Set({parameter_number = 111, size = 4, configuration_value = 300})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_parent,
      Configuration:Set({parameter_number = 112, size = 4, configuration_value = 300})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_parent,
      Configuration:Set({parameter_number = 113, size = 4, configuration_value = 300})
    ))
    mock_parent:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Power meter report should be handled",
  function()
    for _, device in ipairs(HEM8_DEVICES) do
      for _, endpoint in ipairs(device.endpoints) do
        local component = "main"
        if endpoint ~= 3 and endpoint ~= 4 and endpoint ~= 5 and endpoint ~= 6 then
        component = string.format("clamp%d", endpoint)
        end
        test.socket.zwave:__queue_receive({
          mock_parent.id,
          Meter:Report({
            scale = Meter.scale.electric_meter.WATTS,
            meter_value = 27
          }, {
            encap = zw.ENCAP.AUTO,
            src_channel = endpoint,
            dst_channels = {0}
          })
        })
        if(device["child_key"]) then
          if(device["child_key"] == "pro") then
            test.socket.capability:__expect_send(
                mock_child_prod:generate_test_message(component, capabilities.powerMeter.power({ value = 27, unit = "W" }))
            )
          elseif (device["child_key"] == "sald-pro") then
            test.socket.capability:__expect_send(
                mock_child_sald_prod:generate_test_message(component, capabilities.powerMeter.power({ value = 27, unit = "W" }))
            )
          elseif (device["child_key"] == "sald-con") then
            test.socket.capability:__expect_send(
                mock_child_sald_con:generate_test_message(component, capabilities.powerMeter.power({ value = 27, unit = "W" }))
            )
          end
        else
          test.socket.capability:__expect_send(
            mock_parent:generate_test_message(component, capabilities.powerMeter.power({ value = 27, unit = "W" }))
          )
        end
      end
    end
  end
)

test.register_coroutine_test(
  "Energy meter report should be handled",
  function()
    for _, device in ipairs(HEM8_DEVICES) do
      for _, endpoint in ipairs(device.endpoints) do
        local component = "main"
        if endpoint ~= 3 and endpoint ~= 4 and endpoint ~= 5 and endpoint ~= 6 then
              component = string.format("clamp%d", endpoint)
        end
        test.socket.zwave:__queue_receive({
          mock_parent.id,
          Meter:Report({
            scale = Meter.scale.electric_meter.KILOWATT_HOURS,
            meter_value = 5
          }, {
            encap = zw.ENCAP.AUTO,
            src_channel = endpoint,
            dst_channels = {0}
          })
        })
        if(device["child_key"]) then
          if(device["child_key"] == "pro") then
            test.socket.capability:__expect_send(
                mock_child_prod:generate_test_message(component, capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
            )
          elseif (device["child_key"] == "sald-pro") then
            test.socket.capability:__expect_send(
                mock_child_sald_prod:generate_test_message(component, capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
            )
          elseif (device["child_key"] == "sald-con") then
            test.socket.capability:__expect_send(
                mock_child_sald_con:generate_test_message(component, capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
            )
          end
        else
          test.socket.capability:__expect_send(
            mock_parent:generate_test_message(component, capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
          )
        end
      end
    end
  end
)

test.register_coroutine_test(
  "Report consumption and power consumption report after 15 minutes", function()
    -- set time to trigger power consumption report
    local current_time = os.time() - 60 * 20
    mock_child_sald_con:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zwave:__queue_receive(
      {
        mock_child_sald_con.id,
        zw_test_utils.zwave_test_build_receive_command(Meter:Report(
          {
            scale = Meter.scale.electric_meter.KILOWATT_HOURS,
            meter_value = 5
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 5,
            dst_channels = {0}
          }
        ))
      }
    )

    test.socket.capability:__expect_send(
      mock_child_sald_con:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    )

    test.socket.capability:__expect_send(
      mock_child_sald_con:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 5000 }))
    )
  end
)

test.register_coroutine_test(
  "Handle preference: thresholdCheck (parameter 3) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            thresholdCheck = 0
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 3,
          configuration_value = 0,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: imWThresholdTotal (parameter 4) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            imWThresholdTotal = 3500
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 4,
          configuration_value = 3500,
          size = 2
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: imWThresholdPhaseA (parameter 5) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            imWThresholdPhaseA = 3500
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 5,
          configuration_value = 3500,
          size = 2
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: exWThresholdTotal (parameter 8) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            exWThresholdTotal = 3500
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 8,
          configuration_value = 3500,
          size = 2
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: exWThresholdPhaseA (parameter 9) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            exWThresholdPhaseA = 3500
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 9,
          configuration_value = 3500,
          size = 2
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: imtWPctThresholdTotal (parameter 12) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            imtWPctThresholdTotal = 50
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 12,
          configuration_value = 50,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: imWPctThresholdPhaseA (parameter 13) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            imWPctThresholdPhaseA = 50
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 13,
          configuration_value = 50,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: exWPctThresholdTotal (parameter 16) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            exWPctThresholdTotal = 50
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 16,
          configuration_value = 50,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: exWPctThresholdPhaseA (parameter 17) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            exWPctThresholdPhaseA = 50
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 17,
          configuration_value = 50,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoRootDeviceReport (parameter 32) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
            autoRootDeviceReport = 1
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 32,
          configuration_value = 1,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: defaultReport (parameter 100) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          defaultReport = 1
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 100,
          configuration_value = 1,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoReportImp1 (parameter 101) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          autoReportImp1 = 300
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 101,
          configuration_value = 300,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoReportImp2 (parameter 102) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          autoReportImp2 = 2021161
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 102,
          configuration_value = 2021161,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoReportImp3 (parameter 103) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          autoReportImp3 = 40423221
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 103,
          configuration_value = 40423221,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoReportExp1 (parameter 104) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          autoReportExp1 = 505290
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 104,
          configuration_value = 505290,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoReportExp2 (parameter 105) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          autoReportExp2 = 2021161
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 105,
          configuration_value = 2021161,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoReportExp3 (parameter 106) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          autoReportExp3 = 40423221
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 106,
          configuration_value = 40423221,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: defaultTime (parameter 110) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          defaultTime = 1
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 110,
          configuration_value = 1,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoTimeImp1 (parameter 111) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_parent:generate_info_changed({
        preferences = {
          autoTimeImp1 = 300
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 111,
          configuration_value = 300,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoTimeImp2 (parameter 112) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_parent:generate_info_changed({
        preferences = {
          autoTimeImp2 = 7200
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 112,
          configuration_value = 7200,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoTimeImp3 (parameter 113) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
        mock_parent:generate_info_changed({
        preferences = {
          autoTimeImp3 = 7200
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 113,
          configuration_value = 7200,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoTimeExp1 (parameter 114) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_parent:generate_info_changed({
        preferences = {
          autoTimeExp1 = 300
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 114,
          configuration_value = 300,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoTimeExp2 (parameter 115) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_parent:generate_info_changed({
        preferences = {
          autoTimeExp2 = 3600
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 115,
          configuration_value = 3600,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: autoTimeExp3 (parameter 116) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_parent:generate_info_changed({
        preferences = {
          autoTimeExp3 = 3600
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 116,
          configuration_value = 3600,
          size = 4
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Handle preference: lockConfig (parameter 252) in infoChanged",
  function()
    test.socket.device_lifecycle:__queue_receive(
      mock_parent:generate_info_changed({
        preferences = {
          lockConfig = 1
        }
      })
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_parent,
        Configuration:Set({
          parameter_number = 252,
          configuration_value = 1,
          size = 1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Refresh sends commands to all components including base device",
  function()
    -- refresh commands for zwave devices do not have guaranteed ordering
    test.socket.zwave:__set_channel_ordering("relaxed")

    for _, device in ipairs(HEM8_DEVICES) do
      for _, endpoint in ipairs(device.endpoints) do
        test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({scale = Meter.scale.electric_meter.WATTS}, {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { endpoint }
            })
          )
        )

        test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}, {
              encap = zw.ENCAP.AUTO,
              src_channel = 0,
              dst_channels = { endpoint }
            })
          )
        )
      end
    end

    test.socket.capability:__queue_receive({
      mock_parent.id,
      { capability = "refresh", component = "main", command = "refresh", args = { } }
    })
  end
)

test.run_registered_tests()