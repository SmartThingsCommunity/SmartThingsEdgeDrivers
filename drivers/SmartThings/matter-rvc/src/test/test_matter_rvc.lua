-- Copyright 2023 SmartThings
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

clusters.RvcCleanMode = require "RvcCleanMode"
clusters.RvcOperationalState = require "RvcOperationalState"
clusters.RvcRunMode = require "RvcRunMode"
clusters.OperationalState = require "OperationalState"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("rvc-clean-mode.yml"),
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
        {cluster_id = clusters.RvcRunMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RvcCleanMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RvcOperationalState.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0074, device_type_revision = 1} -- Robot Vacuum Cleaner
      }
    }
  }
})

local function test_init()
  local subscribed_attributes = {
    [capabilities.mode.ID] = {
        clusters.RvcRunMode.attributes.SupportedModes,
        clusters.RvcRunMode.attributes.CurrentMode,
        clusters.RvcCleanMode.attributes.SupportedModes,
        clusters.RvcCleanMode.attributes.CurrentMode,
    },
    [capabilities.robotCleanerOperatingState.ID] = {
        clusters.RvcOperationalState.attributes.OperationalState,
        clusters.RvcOperationalState.attributes.OperationalError,
    },
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











local expect_reload_all_codes_messages = function(dev)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.lockCodes.lockCodes(
        json.encode({}), {visibility = {displayed = false}}
      )
    )
  )
  test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
  test.mock_time.advance_time(5)
  local credential = types.DlCredential({credential_type = types.DlCredentialType.PIN, credential_index = 1})
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.scanCodes("Scanning")
    )
  )
  test.socket.matter:__expect_send(
    {dev.id, DoorLock.server.commands.GetCredentialStatus(dev, 10, credential)}
  )
  test.wait_for_events()

  local next_credential_index = 2
  test.socket.matter:__queue_receive(
    {
      dev.id,
      DoorLock.client.commands.GetCredentialStatusResponse:build_test_command_response(
        dev, 10, -- endpoint
        true, --credential exists
        1,  --user_index
        nil, --creator fabric index
        nil, --last modified fabric index
        next_credential_index
      ),
    }
  )
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes
        .codeChanged("1 set", {data = {codeName = "Code 1"}, state_change = true})
    )
  )
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.lockCodes(
        json.encode({["1"] = "Code 1"}), {visibility = {displayed = false}}
      )
    )
  )
  local credential1 = types.DlCredential(
                      {
    credential_type = DoorLock.types.DlCredentialType.PIN,
    credential_index = next_credential_index,
  })
  test.socket.matter:__expect_send(
    {dev.id, DoorLock.server.commands.GetCredentialStatus(dev, 10, credential1)}
  )
  test.wait_for_events()

  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes
        .codeChanged("2 set", {data = {codeName = "Code 2"}, state_change = true})
    )
  )
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.lockCodes(
        json.encode({["1"] = "Code 1", ["2"] = "Code 2"}), {visibility = {displayed = false}}
      )
    )
  )

  test.socket.matter:__queue_receive(
    {
      dev.id,
      DoorLock.client.commands.GetCredentialStatusResponse:build_test_command_response(
        dev, 10, -- endpoint
        true, --credential exists
        1,    --user_index
        nil,  --creator fabric index
        nil,  --last modified fabric index
        nil   --next credential index
      ),
    }
  )

  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.scanCodes("Complete", {visibility = {displayed = false}})
    )
  )
  test.socket.capability:__expect_send(
    dev:generate_test_message(
      "main", capabilities.lockCodes.lockCodes(
        json.encode({["1"] = "Code 1", ["2"] = "Code 2"}),
          {visibility = {displayed = false}}
      )
    )
  )
end













test.register_message_test(
  "Operational state should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcOperationalState.server.attributes.OperationalState:build_test_report_data(mock_device, 1, clusters.OperationalState.types.OperationalStateEnum.STOPPED)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.robotCleanerOperatingState.operatingState.stopped())
    }
  }
)

test.run_registered_tests()