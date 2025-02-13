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

local capabilities = require "st.capabilities"
local routerState = capabilities["smilevirtual57983.routerState"]
test.add_package_capability("routerState.yml")
local routerName = capabilities["smilevirtual57983.routerName"]
test.add_package_capability("routerName.yml")
local threadVersion = capabilities["smilevirtual57983.threadVersion"]
test.add_package_capability("threadVersion.yml")

local clusters = require "st.matter.clusters"
clusters.ThreadBorderRouterManagement = require "ThreadBorderRouterManagement"
clusters.WifiNetworkMangement = require "WiFiNetworkManagement"

local mock_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("thread-border-router.yml"),
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
    clusters.ThreadBorderRouterManagement.attributes.BorderRouterName,
    clusters.ThreadBorderRouterManagement.attributes.InterfaceEnabled,
    clusters.ThreadBorderRouterManagement.attributes.ThreadVersion,
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
            mock_device:generate_test_message("main", threadVersion.threadVersion({ value = "1.2.0" }))
        )
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.ThreadVersion:build_test_report_data(
                mock_device, 1, 4
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", threadVersion.threadVersion({ value = "1.3.0" }))
        )
        test.socket.matter:__queue_receive({
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.ThreadVersion:build_test_report_data(
                mock_device, 1, 5
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message("main", threadVersion.threadVersion({ value = "1.4.0" }))
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
  "InterfaceEnabled should correctly display on or off",
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
        message = mock_device:generate_test_message("main", routerState.state.enabled())
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
        message = mock_device:generate_test_message("main", routerState.state.off())
      }
  }
)

test.register_message_test(
  "RouterName should correctly display the given name",
  {
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.BorderRouterName:build_test_report_data(mock_device, 1, "john foo._mescop._udp")
        }
    },
    {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", routerName.name({ value = "john foo"}))
    },
    {
        channel = "matter",
        direction = "receive",
        message = {
            mock_device.id,
            clusters.ThreadBorderRouterManagement.attributes.BorderRouterName:build_test_report_data(mock_device, 1, "jane bar._mescop._udp")
        }
    },
    {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", routerName.name({ value = "jane bar"}))
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
        message = mock_device:generate_test_message("main", routerName.name({ value = "john foo no suffix"}))
    },
  }
)

test.run_registered_tests()
