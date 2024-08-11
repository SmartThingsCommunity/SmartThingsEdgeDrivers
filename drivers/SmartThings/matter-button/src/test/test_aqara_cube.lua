local test = require "integration_test"
local capabilities = require "st.capabilities"
test.add_package_capability("cubeAction.yaml")
test.add_package_capability("cubeFace.yaml")
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.generated.zap_clusters"

local cubeAction = capabilities["stse.cubeAction"]
local cubeFace = capabilities["stse.cubeFace"]

--mock the actual device
local mock_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("cube-t1-pro.yml"),
    manufacturer_info = {vendor_id = 0x115f, product_id = 0x0000},
    endpoints = 
    {
      {
        endpoint_id = 1,
        clusters =
        {
          {
            cluster_id = clusters.Switch.ID,
            feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
            cluster_type = "SERVER"
          },
          {
            cluster_id = clusters.PowerSource.ID,
            cluster_type = "SERVER",
            feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY
          }
        },
      },
    },
  }
)

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
  clusters.PowerSource.server.attributes.BatPercentRemaining,
  -- In order to add InitialPress, button capability must be added. 
  -- In this case, the rest of the button events must also be added.
--  clusters.Switch.server.events.InitialPress,
--  clusters.Switch.server.events.LongPress,
--  clusters.Switch.server.events.ShortRelease,
--  clusters.Switch.server.events.MultiPressComplete,
}

local function test_init()
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
end

test.set_test_init_function(test_init)

--[[
-- custom capability cannot be supported by the test framework.
-- Error Message :
--   capability was not sent expected message:
--   {"00000000-1111-2222-3333-000000000001", {attribute_id="cubeAction", capability_id="stse.cubeAction", component_id="main", state={value="noAction"}}}
test.register_message_test(
  "Handle single press sequence for cubeAction", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 1, {new_position = 1}  --move to position 1?
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", cubeAction.cubeAction({value = "noAction"}, {state_change = true})) --should send initial press
    }
  }
)

test.register_message_test(
  "Handle single press sequence for cubeFace", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, 1, {new_position = 1}  --move to position 1?
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", cubeFace.cubeFace({value = "face1Up"}, {state_change = true})) --should send initial press
    }
  }
)
--]]

test.register_message_test(
  "Handle received BatPercentRemaining from device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 1, 150
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
      ),
    },
  }
)
-- run the tests
test.run_registered_tests()
