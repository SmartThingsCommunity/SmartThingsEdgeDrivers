local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.generated.zap_clusters"
local button_attr = capabilities.button.button

local child_profile = t_utils.get_profile_definition("switch-binary.yml")

--mock the actual device
local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("light-binary.yml"),
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
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
  }
})

local mock_children = {}
for _, endpoint in ipairs(mock_device.endpoints) do
  if endpoint.endpoint_id > 1 then
    local child_data = {
      profile = child_profile,
      device_network_id = string.format("%s:%02X", mock_device.id, endpoint.endpoint_id),
      parent_device_id = mock_device.id,
      parent_assigned_child_key = string.format("%02X", endpoint.endpoint_id)
    }
    mock_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data)
  end
end

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
  clusters.OnOff.attributes.OnOff,
}

local function test_init()
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  for _, child in pairs(mock_children) do
    test.mock_device.add_test_device(child)
  end

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "switch-binary",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = "02"
  })

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 3",
    profile = "switch-binary",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = "03"
  })
end

test.set_test_init_function(test_init)

test.register_message_test(
  "On command to component switch should send the appropriate commands",
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
  "On command to component switch should send the appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 2, true)
      }
    },
		{
			channel = "capability",
			direction = "send",
			message = mock_children[2]:generate_test_message("main", capabilities.switch.switch.on())
		}
  }
)

test.register_message_test(
  "On command to component switch should send the appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, 3, true)
      }
    },
		{
			channel = "capability",
			direction = "send",
			message = mock_children[3]:generate_test_message("main", capabilities.switch.switch.on())
		}
  }
)

-- run the tests
test.run_registered_tests()
