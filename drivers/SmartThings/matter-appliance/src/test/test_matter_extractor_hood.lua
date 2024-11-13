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
  profile = t_utils.get_profile_definition("extractor-hood-hepa-ac-wind.yml"),
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
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = clusters.FanControl.types.FanControlFeature.WIND},
      },
      device_types = {
        {device_type_id = 0x007A, device_type_revision = 1} -- Extractor Hood
      }
    }
  }
})

local function test_init()
  local subscribed_attributes = {
    [capabilities.fanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.fanSpeedPercent.ID] = {
      clusters.FanControl.attributes.PercentCurrent
    },
    [capabilities.windMode.ID] = {
      clusters.FanControl.attributes.WindSupport,
      clusters.FanControl.attributes.WindSetting
    },
    [capabilities.filterState.ID] = {
      clusters.HepaFilterMonitoring.attributes.Condition,
      clusters.ActivatedCarbonFilterMonitoring.attributes.Condition
    },
    [capabilities.filterStatus.ID] = {
      clusters.HepaFilterMonitoring.attributes.ChangeIndication,
      clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
    }
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
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Test fan percent",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.server.attributes.PercentCurrent:build_test_report_data(mock_device, 1, 10)
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
  "Test fan mode matter handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.types.FanModeEnum.OFF)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("off"))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.types.FanModeEnum.LOW)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("low"))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.types.FanModeEnum.MEDIUM)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("medium"))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.types.FanModeEnum.HIGH)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("high"))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.types.FanModeEnum.AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.fanMode("auto"))
    }
  }
)

test.register_message_test(
  "Test fan mode capability handler",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanMode", component = "main", command = "setFanMode", args = { capabilities.fanMode.fanMode.off.NAME } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.types.FanModeEnum.OFF)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanMode", component = "main", command = "setFanMode", args = { capabilities.fanMode.fanMode.low.NAME } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.types.FanModeEnum.LOW)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanMode", component = "main", command = "setFanMode", args = { capabilities.fanMode.fanMode.medium.NAME } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.types.FanModeEnum.MEDIUM)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanMode", component = "main", command = "setFanMode", args = { capabilities.fanMode.fanMode.high.NAME } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.types.FanModeEnum.HIGH)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanMode", component = "main", command = "setFanMode", args = { capabilities.fanMode.fanMode.auto.NAME } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:write(mock_device, 1, clusters.FanControl.types.FanModeEnum.AUTO)
      }
    }
  }
)
test.register_message_test(
  "Test setting fan mode sequence",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.supportedFanModes({
        capabilities.fanMode.fanMode.off.NAME,
        capabilities.fanMode.fanMode.low.NAME,
        capabilities.fanMode.fanMode.medium.NAME,
        capabilities.fanMode.fanMode.high.NAME
      }, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.supportedFanModes({
        capabilities.fanMode.fanMode.off.NAME,
        capabilities.fanMode.fanMode.low.NAME,
        capabilities.fanMode.fanMode.high.NAME
      }, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.supportedFanModes({
        capabilities.fanMode.fanMode.off.NAME,
        capabilities.fanMode.fanMode.low.NAME,
        capabilities.fanMode.fanMode.medium.NAME,
        capabilities.fanMode.fanMode.high.NAME,
        capabilities.fanMode.fanMode.auto.NAME
      }, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.supportedFanModes({
        capabilities.fanMode.fanMode.off.NAME,
        capabilities.fanMode.fanMode.low.NAME,
        capabilities.fanMode.fanMode.high.NAME,
        capabilities.fanMode.fanMode.auto.NAME
      }, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanModeSequence.OFF_HIGH_AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.supportedFanModes({
        capabilities.fanMode.fanMode.off.NAME,
        capabilities.fanMode.fanMode.high.NAME,
        capabilities.fanMode.fanMode.auto.NAME
      }, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanModeSequence:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanModeSequence.OFF_HIGH)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanMode.supportedFanModes({
        capabilities.fanMode.fanMode.off.NAME,
        capabilities.fanMode.fanMode.high.NAME
      }, {visibility={displayed=false}}))
    }
  }
)

test.register_message_test(
  "Test wind mode matter handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSupport:build_test_report_data(mock_device, 1, 0x02) -- NoWind and NaturalWind
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windMode.supportedWindModes({
        capabilities.windMode.windMode.noWind.NAME,
        capabilities.windMode.windMode.naturalWind.NAME
      }, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:build_test_report_data(mock_device, 1, clusters.FanControl.types.WindSettingMask.NATURAL_WIND)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windMode.windMode.naturalWind())
    }
  }
)

test.register_message_test(
  "Test wind mode capability handler",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "windMode", component = "main", command = "setWindMode", args = { "sleepWind" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:write(mock_device, 1, clusters.FanControl.types.WindSettingMask.SLEEP_WIND)
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "windMode", component = "main", command = "setWindMode", args = { "naturalWind" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:write(mock_device, 1, clusters.FanControl.types.WindSettingMask.NATURAL_WIND)
      }
    }
  }
)

test.register_message_test(
  "Test HEPA filter handlers",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.HepaFilterMonitoring.attributes.Condition:build_test_report_data(mock_device, 1, 3)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("hepaFilter", capabilities.filterState.filterLifeRemaining(3))
    },
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
      message = mock_device:generate_test_message("hepaFilter", capabilities.filterStatus.filterStatus.normal())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.HepaFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.HepaFilterMonitoring.attributes.ChangeIndication.WARNING)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("hepaFilter", capabilities.filterStatus.filterStatus.normal())
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
      message = mock_device:generate_test_message("hepaFilter", capabilities.filterStatus.filterStatus.replace())
    },
  }
)

test.register_message_test(
  "Test Activated Carbon filter handlers",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ActivatedCarbonFilterMonitoring.attributes.Condition:build_test_report_data(mock_device, 1, 5)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("activatedCarbonFilter", capabilities.filterState.filterLifeRemaining(5))
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
      message = mock_device:generate_test_message("activatedCarbonFilter", capabilities.filterStatus.filterStatus.normal())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication:build_test_report_data(mock_device, 1, clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.WARNING)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("activatedCarbonFilter", capabilities.filterStatus.filterStatus.normal())
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
      message = mock_device:generate_test_message("activatedCarbonFilter", capabilities.filterStatus.filterStatus.replace())
    },
  }
)

test.run_registered_tests()
