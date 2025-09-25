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
local t_utils = require "integration_test.utils"
local data_types = require "st.matter.data_types"
local capabilities = require "st.capabilities"

local clusters = require "st.matter.clusters"
clusters.ThreadBorderRouterManagement = require "ThreadBorderRouterManagement"
clusters.WifiNetworkMangement = require "WiFiNetworkManagement"

local mock_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("network-infrastructure-manager.yml"),
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
            {device_type_id = 0x0016, device_type_revision = 1,} -- RootNode
        }
      },
      {
        endpoint_id = 1,
        clusters = {
            {cluster_id = clusters.ThreadBorderRouterManagement.ID, cluster_type = "SERVER", feature_map = 0},
            {cluster_id = clusters.WifiNetworkMangement.ID, cluster_type = "SERVER", feature_map = 0},
        },
        device_types = {
            {device_type_id = 0x0090, device_type_revision = 1,} -- Network Infrastructure Manager
        }
      }
    }
})

local cluster_subscribe_list = {
    clusters.ThreadBorderRouterManagement.attributes.ActiveDatasetTimestamp,
    clusters.ThreadBorderRouterManagement.attributes.BorderRouterName,
    clusters.ThreadBorderRouterManagement.attributes.InterfaceEnabled,
    clusters.ThreadBorderRouterManagement.attributes.ThreadVersion,
    clusters.WifiNetworkMangement.attributes.Ssid,
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

test.register_coroutine_test(
    "ThreadVersion should display the correct stringified version",
    function()
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.ThreadVersion:build_test_report_data(
                mock_device, 1, 3
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadBorderRouter.threadVersion({ value = "1.2.0" }))
        )
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.ThreadVersion:build_test_report_data(
                mock_device, 1, 4
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadBorderRouter.threadVersion({ value = "1.3.0" }))
        )
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.ThreadVersion:build_test_report_data(
                mock_device, 1, 5
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadBorderRouter.threadVersion({ value = "1.4.0" }))
        )
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.ThreadVersion:build_test_report_data(
                mock_device, 1, 6
            )
        })
    end
)

test.register_message_test(
  "InterfaceEnabled should correctly display enabled or disabled",
  {
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.InterfaceEnabled:build_test_report_data(mock_device, 1, true)
        }
    },
    {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.threadBorderRouter.threadInterfaceState("enabled"))
    },
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.InterfaceEnabled:build_test_report_data(mock_device, 1, false)
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.threadBorderRouter.threadInterfaceState("disabled"))
      }
  }
)

test.register_message_test(
  "BorderRouterName should correctly display the given name",
  {
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.BorderRouterName:build_test_report_data(mock_device, 1, "john foo._meshcop._udp")
        }
    },
    {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.threadBorderRouter.borderRouterName({ value = "john foo"}))
    },
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.BorderRouterName:build_test_report_data(mock_device, 1, "jane bar._meshcop._udp")
        }
    },
    {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.threadBorderRouter.borderRouterName({ value = "jane bar"}))
    },
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.BorderRouterName:build_test_report_data(mock_device, 1, "john foo no suffix")
        }
    },
    {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.threadBorderRouter.borderRouterName({ value = "john foo no suffix"}))
    },
  }
)

test.register_message_test(
  "wifiInformation capability should correctly display the Ssid",
  {
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.WifiNetworkMangement.attributes.Ssid:build_test_report_data(mock_device, 1, "test name for ssid!")
        }
    },
    {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.wifiInformation.ssid({ value = "test name for ssid!" }))
    }
  }
)

test.register_message_test(
  "Null-valued ssid (TLV 0x14) should correctly fail",
  {
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.WifiNetworkMangement.attributes.Ssid:build_test_report_data(mock_device, 1, string.char(data_types.Null.ID))
        }
    }
  }
)

test.register_message_test(
  "Ssid inputs using non-UTF8 encoding should not display an Ssid",
  {
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.WifiNetworkMangement.attributes.Ssid:build_test_report_data(mock_device, 1, string.char(0xC0)) --  0xC0 never appears in utf8
        }
    }
  }
)

local hex_dataset = [[
0E 08 00 00 68 87 D0 B2 00 00 00 03 00 00 18 35
06 00 04 00 1F FF C0 02 08 25 31 25 A9 B2 16 7F
35 07 08 FD 6E D1 57 02 B4 CD BF 05 10 33 AF 36
F8 13 8E 8F F9 50 6D 67 22 9B FD F2 40 03 0D 53
54 2D 35 30 33 32 30 30 31 31 39 36 01 02 D9 78
04 10 E2 29 D8 2A 84 B2 7D A1 AC 8D D8 71 64 AC
66 7F 0C 04 02 A0 FF F8
]]

local serializable_hex_dataset = hex_dataset:gsub("%s+", ""):gsub("..", function(cc)
    return string.char(tonumber(cc, 16))
end)

test.register_coroutine_test(
    "Thread DatasetResponse parsing should emit the correct capability events on an ActiveDatasetTimestamp update. Else, nothing should happen",
    function()
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.server.attributes.ActiveDatasetTimestamp:build_test_report_data(
                mock_device,
                1,
                1
            )
        })
        test.socket.matter:__expect_send({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.server.commands.GetActiveDatasetRequest(mock_device, 1),
        })
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.client.commands.DatasetResponse:build_test_command_response(
                mock_device,
                1,
                serializable_hex_dataset
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.channel({ value = 24 }))
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.extendedPanId({ value = "253125a9b2167f35" }))
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.networkKey({ value = "33af36f8138e8ff9506d67229bfdf240" }))
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.networkName({ value = "ST-5032001196" }))
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.panId({ value = 55672 }))
        )
        test.wait_for_events()

        -- after some amount of time, a device init occurs or we re-subscribe for other reasons.
        -- Since no change to the ActiveDatasetTimestamp has occurred, no re-read should occur
        test.socket.matter:__queue_receive({
                mock_device.id,
                clusters.ThreadBorderRouterManagement.server.attributes.ActiveDatasetTimestamp:build_test_report_data(
                    mock_device,
                    1,
                    1
                )
        })
        test.wait_for_events()

        -- after some more amount of time, a device init occurs or we re-subscribe for other reasons.
        -- This time, their ActiveDatasetTimestamp has updated, so we should re-read the operational dataset.
        test.socket.matter:__queue_receive({
                mock_device.id,
                clusters.ThreadBorderRouterManagement.server.attributes.ActiveDatasetTimestamp:build_test_report_data(
                    mock_device,
                    1,
                    2
                )
        })
        test.socket.matter:__expect_send({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.server.commands.GetActiveDatasetRequest(mock_device, 1),
        })
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.client.commands.DatasetResponse:build_test_command_response(
                mock_device,
                1,
                serializable_hex_dataset
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.channel({ value = 24 }))
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.extendedPanId({ value = "253125a9b2167f35" }))
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.networkKey({ value = "33af36f8138e8ff9506d67229bfdf240" }))
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.networkName({ value = "ST-5032001196" }))
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", capabilities.threadNetwork.panId({ value = 55672 }))
        )
        end
)

test.run_registered_tests()
