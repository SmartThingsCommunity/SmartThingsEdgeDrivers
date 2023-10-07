local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.generated.zap_clusters"

--mock the actual device
local mock_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("button-profile.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = 0,
          cluster_type = "SERVER"
        },
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"}
      },
    },
  },
}
)

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
  clusters.PowerSource.server.attributes.BatPercentRemaining,
  clusters.Switch.server.events.InitialPress,
  clusters.Switch.server.events.LongPress,
  clusters.Switch.server.events.ShortRelease,
  clusters.Switch.server.events.LongRelease,
  clusters.Switch.server.events.MultiPressComplete,
  clusters.Switch.server.attributes.MultiPressMax,
  clusters.Switch.server.attributes.CurrentPosition
}

local function test_init()
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)


test.register_coroutine_test(
  "Handle on position", function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({"up", "down"}, {visibility = {displayed = false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({value = 1}, {visibility = {displayed = false}})
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.Switch.attributes.CurrentPosition:build_test_report_data(
          mock_device, 1, 1
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.button.up({state_change = true})
      )
    )

    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Handle on command", function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.supportedButtonValues({"up", "down"}, {visibility = {displayed = false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.numberOfButtons({value = 1}, {visibility = {displayed = false}})
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.Switch.attributes.CurrentPosition:build_test_report_data(
          mock_device, 1, 0
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.button.button.down({state_change = true})
      )
    )

    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Handle received BatPercentRemaining from device.", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 1, 150
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150/2.0+0.5))
      )
    )
    test.wait_for_events()
  end
)

-- run the tests
test.run_registered_tests()
