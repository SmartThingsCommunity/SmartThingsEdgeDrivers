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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("air-purifier.yml"),
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
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
        endpoint_id = 1,
        clusters = {
          {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER"},
        }
      }
  }
})

local cluster_subscribe_list = {
  clusters.FanControl.attributes.FanModeSequence,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.PercentCurrent,
  clusters.HepaFilterMonitoring.attributes.ChangeIndication,
  clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
}

local function test_init()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
	"On/Off command should send the appropriate FanMode commands",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "switch", component = "main", command = "on", args = { } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.attributes.FanMode.LOW)
			}
		},
    {
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "switch", component = "main", command = "off", args = { } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.attributes.FanMode.OFF)
			}
		}
	}
)

test.register_message_test(
	"Test on/off attribute handler",
	{
		{
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 1, true)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
	}
)

test.register_message_test(
	"setAirPurifierFanMode command should send the appropriate commands",
	{
		{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "airPurifierFanMode", component = "main", command = "setAirPurifierFanMode", args = { "low" } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.attributes.FanMode.LOW)
			}
		},
    {
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "airPurifierFanMode", component = "main", command = "setAirPurifierFanMode", args = { "sleep" } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.attributes.FanMode.LOW)
			}
		},
    {
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "airPurifierFanMode", component = "main", command = "setAirPurifierFanMode", args = { "auto" } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.attributes.FanMode.AUTO)
			}
		}
	}
)

test.register_message_test(
	"FanModeSequence send the appropriate commands",
	{
		{
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, 0)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.supportedAirPurifierFanModes({
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }))
		},
    {
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, 1)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.supportedAirPurifierFanModes({
        capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
        capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
      }))
		},
	}
)

test.register_message_test(
	"Test fan speed commands",
	{
		{
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.PercentCurrent:build_test_report_data(mock_device, 1, 10)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.fanSpeedPercent.percent(10))
		},
    	{
			channel = "capability",
			direction = "receive",
			message = {
				mock_device.id,
				{ capability = "fanSpeedPercent", component = "main", command = "setPercent", args = { 50 } }
			}
		},
		{
			channel = "matter",
			direction = "send",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.PercentSetting:write(mock_device, 1, 50)
			}
		}
	}
)

test.register_message_test(
	"Test fan mode handler",
	{
		{
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.OFF)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
		},
    {
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.LOW)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.airPurifierFanMode.low())
		},
    {
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.HIGH)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.airPurifierFanMode.airPurifierFanMode.high())
		},
	}
)

test.register_message_test(
	"Test filter status for HEPA and Activated Carbon filters",
	{
		{
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.HepaFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.HepaFilterMonitoring.attributes.ChangeIndication.OK)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("HEPA-Filter", capabilities.filterStatus.filterStatus.normal())
		},
    {
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.HepaFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.HepaFilterMonitoring.attributes.ChangeIndication.CRITICAL)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("HEPA-Filter", capabilities.filterStatus.filterStatus.replace())
		},
    {
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.OK)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("Activated-Carbon-Filter", capabilities.filterStatus.filterStatus.normal())
		},
    {
			channel = "matter",
			direction = "receive",
			message = {
				mock_device.id,
				clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.CRITICAL)
			}
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("Activated-Carbon-Filter", capabilities.filterStatus.filterStatus.replace())
		},
	}
)

test.run_registered_tests()
