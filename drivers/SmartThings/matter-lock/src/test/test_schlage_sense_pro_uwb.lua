-- Copyright 2026 SmartThings, Inc.
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
local cluster_base = require "st.matter.cluster_base"
local data_types = require "st.matter.data_types"
local constants = require "schlage-sense-pro.constants"
local can_handle = require "schlage-sense-pro.can_handle"

local lockUwbApproachSettings = constants.get_lock_uwb_approach_settings_capability()
local lockUwbModeSettings = constants.get_lock_uwb_mode_settings_capability()

local enabled_optional_capabilities = {
  {
    "main",
    {
      constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS,
      constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS,
    }
  }
}

local mock_schlage_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition(
    "lock-modular-uwb-settings.yml",
    { enabled_optional_capabilities = enabled_optional_capabilities }
  ),
  manufacturer_info = {
    vendor_id = constants.SCHLAGE_VENDOR_ID,
    product_id = constants.SCHLAGE_SENSE_PRO_PRODUCT_ID,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.BasicInformation.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.DoorLock.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0,
        },
        {
          cluster_id = constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
        }
      },
      device_types = {
        { device_type_id = 0x000A, device_type_revision = 1 } -- Door Lock
      }
    }
  }
})

local DoorLockFeatureMapAttr = { ID = 0xFFFC, cluster = clusters.DoorLock.ID }

local function test_init()
  test.socket.capability:__load_capability_definition(
    constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS,
    1,
    constants.APPROACH_CAP_JSON
  )
  test.socket.capability:__load_capability_definition(
    constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS,
    1,
    constants.MODE_CAP_JSON
  )

  local subscribe_request = clusters.DoorLock.attributes.LockState:subscribe(mock_schlage_device)
  subscribe_request:merge(clusters.DoorLock.attributes.OperatingMode:subscribe(mock_schlage_device))
  subscribe_request:merge(cluster_base.subscribe(mock_schlage_device, nil, DoorLockFeatureMapAttr.cluster, DoorLockFeatureMapAttr.ID))
  subscribe_request:merge(clusters.DoorLock.events.LockOperation:subscribe(mock_schlage_device))
  subscribe_request:merge(clusters.DoorLock.events.DoorLockAlarm:subscribe(mock_schlage_device))

  test.mock_device.add_test_device(mock_schlage_device)
  test.socket.matter:__expect_send({ mock_schlage_device.id, subscribe_request })
end
test.set_test_init_function(test_init)

-------------------------------------------------------------------------------------
-- Subdriver Matching Tests
-------------------------------------------------------------------------------------

test.register_coroutine_test(
  "can_handle matches Schlage Sense Pro and rejects other devices",
  function()
    local matched, subdriver = can_handle(nil, nil, mock_schlage_device)
    assert(matched == true, "Expected can_handle to return true for Schlage Sense Pro")
    assert(subdriver ~= nil, "Expected subdriver table to be returned")
    assert(subdriver.NAME == "schlage-sense-pro", "Expected subdriver NAME to be schlage-sense-pro")

    local other_device = test.mock_device.build_test_matter_device({
      profile = t_utils.get_profile_definition("lock-modular.yml"),
      manufacturer_info = {
        vendor_id = 0x115F,
        product_id = 0x2802,
      }
    })
    local other_matched = can_handle(nil, nil, other_device)
    assert(other_matched == false, "Expected can_handle to return false for non-Schlage device")
  end
)

-------------------------------------------------------------------------------------
-- Capability Command Tests (Cloud/App -> Device)
-------------------------------------------------------------------------------------

test.register_message_test(
  "Handle lockUwbApproachSettings setApproachDirection('frontOnly')",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_schlage_device.id,
        {
          capability = constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS,
          component = "main",
          command = "setApproachDirection",
          args = { "frontOnly" }
        }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_schlage_device.id,
        cluster_base.write(
          mock_schlage_device,
          1,
          constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          constants.ATTR_FIELD_OF_VIEW_ID,
          nil,
          data_types.validate_or_build_type(3, data_types.Uint8)
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_schlage_device:generate_test_message(
        "main",
        lockUwbApproachSettings.approachDirection("frontOnly")
      )
    }
  }
)

test.register_message_test(
  "Handle lockUwbApproachSettings setApproachDirection('frontLeftRight')",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_schlage_device.id,
        {
          capability = constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS,
          component = "main",
          command = "setApproachDirection",
          args = { "frontLeftRight" }
        }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_schlage_device.id,
        cluster_base.write(
          mock_schlage_device,
          1,
          constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          constants.ATTR_FIELD_OF_VIEW_ID,
          nil,
          data_types.validate_or_build_type(0, data_types.Uint8)
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_schlage_device:generate_test_message(
        "main",
        lockUwbApproachSettings.approachDirection("frontLeftRight")
      )
    }
  }
)

test.register_message_test(
  "Handle lockUwbModeSettings setIntentMode('unlockOnArrival')",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_schlage_device.id,
        {
          capability = constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS,
          component = "main",
          command = "setIntentMode",
          args = { "unlockOnArrival" }
        }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_schlage_device.id,
        cluster_base.write(
          mock_schlage_device,
          1,
          constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          constants.ATTR_INTENT_MODE_ID,
          nil,
          data_types.validate_or_build_type(1, data_types.Uint8)
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_schlage_device:generate_test_message(
        "main",
        lockUwbModeSettings.intentMode("unlockOnArrival")
      )
    }
  }
)

test.register_message_test(
  "Handle lockUwbModeSettings setIntentMode('unlockOnInteraction')",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_schlage_device.id,
        {
          capability = constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS,
          component = "main",
          command = "setIntentMode",
          args = { "unlockOnInteraction" }
        }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_schlage_device.id,
        cluster_base.write(
          mock_schlage_device,
          1,
          constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          constants.ATTR_INTENT_MODE_ID,
          nil,
          data_types.validate_or_build_type(2, data_types.Uint8)
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_schlage_device:generate_test_message(
        "main",
        lockUwbModeSettings.intentMode("unlockOnInteraction")
      )
    }
  }
)

-------------------------------------------------------------------------------------
-- Matter Attribute Report Tests (Device -> Hub)
-------------------------------------------------------------------------------------

test.register_message_test(
  "Handle Field of View attribute report from device (raw=2 -> frontRight)",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_schlage_device.id,
        cluster_base.build_test_report_data(
          mock_schlage_device,
          1,
          constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          constants.ATTR_FIELD_OF_VIEW_ID,
          data_types.Uint8(2)
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_schlage_device:generate_test_message(
        "main",
        lockUwbApproachSettings.approachDirection("frontRight")
      )
    }
  }
)

test.register_message_test(
  "Handle Intent Mode attribute report from device (raw=0 -> unlockOnApproach)",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_schlage_device.id,
        cluster_base.build_test_report_data(
          mock_schlage_device,
          1,
          constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          constants.ATTR_INTENT_MODE_ID,
          data_types.Uint8(0)
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_schlage_device:generate_test_message(
        "main",
        lockUwbModeSettings.intentMode("unlockOnApproach")
      )
    }
  }
)

-------------------------------------------------------------------------------------
-- Refresh Command Tests
-------------------------------------------------------------------------------------

test.register_message_test(
  "Handle refresh command queries both standard lock state and UWB settings",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_schlage_device.id,
        {
          capability = capabilities.refresh.ID,
          component = "main",
          command = "refresh",
          args = {}
        }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_schlage_device.id,
        clusters.DoorLock.attributes.LockState:read(mock_schlage_device)
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_schlage_device.id,
        cluster_base.read(
          mock_schlage_device,
          1,
          constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          constants.ATTR_FIELD_OF_VIEW_ID,
          nil
        )
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_schlage_device.id,
        cluster_base.read(
          mock_schlage_device,
          1,
          constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
          constants.ATTR_INTENT_MODE_ID,
          nil
        )
      }
    }
  }
)

-------------------------------------------------------------------------------------
-- Lifecycle Event Tests
-------------------------------------------------------------------------------------

test.register_coroutine_test(
  "Handle doConfigure lifecycle event for Schlage Sense Pro UWB lock",
  function()
    mock_schlage_device:expect_metadata_update({
      profile = "lock-modular-uwb-settings",
      optional_component_capabilities = {
        {
          "main",
          {
            constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS,
            constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS,
          }
        }
      }
    })
    mock_schlage_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ mock_schlage_device.id, "doConfigure" })
    test.socket.capability:__expect_send(
      mock_schlage_device:generate_test_message(
        "main",
        lockUwbApproachSettings.supportedApproachDirections(
          constants.SUPPORTED_APPROACH_DIRECTIONS, { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_schlage_device:generate_test_message(
        "main",
        lockUwbModeSettings.supportedIntentModes(
          constants.SUPPORTED_INTENT_MODES, { visibility = { displayed = false } }
        )
      )
    )
    test.socket.matter:__expect_send({
      mock_schlage_device.id,
      cluster_base.read(
        mock_schlage_device,
        1,
        constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
        constants.ATTR_FIELD_OF_VIEW_ID,
        nil
      )
    })
    test.socket.matter:__expect_send({
      mock_schlage_device.id,
      cluster_base.read(
        mock_schlage_device,
        1,
        constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
        constants.ATTR_INTENT_MODE_ID,
        nil
      )
    })
    test.socket.capability:__expect_send(
      mock_schlage_device:generate_test_message(
        "main",
        capabilities.lock.supportedLockValues(
          { "locked", "unlocked", "not fully locked" },
          { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_schlage_device:generate_test_message(
        "main",
        capabilities.lock.supportedLockCommands(
          { "lock", "unlock" },
          { visibility = { displayed = false } }
        )
      )
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Handle driverSwitched lifecycle event for Schlage Sense Pro UWB lock",
  function()
    mock_schlage_device:expect_metadata_update({
      profile = "lock-modular-uwb-settings",
      optional_component_capabilities = {
        {
          "main",
          {
            constants.CAPABILITY_LOCK_UWB_APPROACH_SETTINGS,
            constants.CAPABILITY_LOCK_UWB_MODE_SETTINGS,
          }
        }
      }
    })
    mock_schlage_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.device_lifecycle:__queue_receive({ mock_schlage_device.id, "driverSwitched" })
    test.socket.capability:__expect_send(
      mock_schlage_device:generate_test_message(
        "main",
        lockUwbApproachSettings.supportedApproachDirections(
          constants.SUPPORTED_APPROACH_DIRECTIONS, { visibility = { displayed = false } }
        )
      )
    )
    test.socket.capability:__expect_send(
      mock_schlage_device:generate_test_message(
        "main",
        lockUwbModeSettings.supportedIntentModes(
          constants.SUPPORTED_INTENT_MODES, { visibility = { displayed = false } }
        )
      )
    )
    test.socket.matter:__expect_send({
      mock_schlage_device.id,
      cluster_base.read(
        mock_schlage_device,
        1,
        constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
        constants.ATTR_FIELD_OF_VIEW_ID,
        nil
      )
    })
    test.socket.matter:__expect_send({
      mock_schlage_device.id,
      cluster_base.read(
        mock_schlage_device,
        1,
        constants.SCHLAGE_UWB_CUSTOM_CLUSTER_ID,
        constants.ATTR_INTENT_MODE_ID,
        nil
      )
    })
    test.wait_for_events()
  end
)

test.run_registered_tests()
