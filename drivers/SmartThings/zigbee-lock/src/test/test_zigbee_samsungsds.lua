-- Copyright 2022 SmartThings
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

-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local DoorLock = clusters.DoorLock

local DoorLockState = DoorLock.attributes.LockState
local OperationEventCode = DoorLock.types.OperationEventCode

local SAMSUNG_SDS_MFR_SPECIFIC_COMMAND = 0x1F
local SAMSUNG_SDS_MFR_CODE = 0x0003

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("lock-without-codes.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "SAMSUNG SDS",
          model = "",
          server_clusters = {0x0000, 0x0001, 0x0003, 0x0004, 0x0005, 0x0009, 0x0101 }
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.unlocked()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
    test.wait_for_events()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, DoorLock.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        DoorLock.attributes.LockState:configure_reporting(mock_device, 0, 3600, 0)
      }
    )

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
    "Lock status reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.LockState:build_test_attr_report(mock_device,
                                                                                         DoorLockState.LOCKED) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked())
      }
    }
)

test.register_message_test(
    "Lock status reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.LockState:build_test_attr_report(mock_device,
                                                                                         DoorLockState.UNLOCKED) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked())
      }
    }
)

test.register_message_test(
    "Not Fully Locked status reporting should not be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.LockState:build_test_attr_report(mock_device,
                                                                                         DoorLockState.NOT_FULLY_LOCKED) }
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0000,
                        OperationEventCode.LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          capabilities.lock.lock.locked({ data = { codeId = "0", codeName = "Code 0", method = "keypad"} })
        )
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0000,
                        OperationEventCode.UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          capabilities.lock.lock.unlocked({ data = { codeId = "0", codeName = "Code 0", method = "keypad"} })
        )
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0000,
                        OperationEventCode.ONE_TOUCH_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          capabilities.lock.lock.locked({ data = { codeId = "0", codeName = "Code 0", method = "keypad"} })
        )
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0000,
                        OperationEventCode.KEY_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          capabilities.lock.lock.locked({ data = { codeId = "0", codeName = "Code 0", method = "keypad"} })
        )
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0000,
                        OperationEventCode.KEY_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          capabilities.lock.lock.unlocked({ data = { codeId = "0", codeName = "Code 0", method = "keypad"} })
        )
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0000,
                        OperationEventCode.AUTO_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          capabilities.lock.lock.locked({ data = { codeId = "0", codeName = "Code 0", method = "keypad"} })
        )
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0000,
                        OperationEventCode.MANUAL_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          capabilities.lock.lock.locked({data = { codeId = "0", codeName = "Code 0", method = "keypad"} })
        )
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0000,
                        OperationEventCode.MANUAL_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
          capabilities.lock.lock.unlocked({ data = { codeId = "0", codeName = "Code 0", method = "keypad"} })
        )
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0001,
                        OperationEventCode.LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "command" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0001,
                        OperationEventCode.UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "command" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0001,
                        OperationEventCode.ONE_TOUCH_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "command" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0001,
                        OperationEventCode.KEY_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "command" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0001,
                        OperationEventCode.KEY_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "command" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0001,
                        OperationEventCode.AUTO_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "auto" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0001,
                        OperationEventCode.MANUAL_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "command" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0001,
                        OperationEventCode.MANUAL_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "command" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0002,
                        OperationEventCode.LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "manual" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0002,
                        OperationEventCode.UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "manual" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0002,
                        OperationEventCode.ONE_TOUCH_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "manual" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0002,
                        OperationEventCode.KEY_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "manual" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0002,
                        OperationEventCode.KEY_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "manual" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0002,
                        OperationEventCode.AUTO_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "auto" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0002,
                        OperationEventCode.MANUAL_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "manual" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0002,
                        OperationEventCode.MANUAL_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "manual" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0003,
                        OperationEventCode.LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "rfid" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0003,
                        OperationEventCode.UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "rfid" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0003,
                        OperationEventCode.ONE_TOUCH_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "rfid" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0003,
                        OperationEventCode.KEY_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "rfid" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0003,
                        OperationEventCode.KEY_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "rfid" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0003,
                        OperationEventCode.AUTO_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "auto" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0003,
                        OperationEventCode.MANUAL_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "rfid" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0003,
                        OperationEventCode.MANUAL_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "rfid" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0004,
                        OperationEventCode.LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "fingerprint" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0004,
                        OperationEventCode.UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "fingerprint" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0004,
                        OperationEventCode.ONE_TOUCH_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "fingerprint" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0004,
                        OperationEventCode.KEY_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "fingerprint" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0004,
                        OperationEventCode.KEY_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "fingerprint" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0004,
                        OperationEventCode.AUTO_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "auto" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0004,
                        OperationEventCode.MANUAL_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "fingerprint" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0004,
                        OperationEventCode.MANUAL_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "fingerprint" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0005,
                        OperationEventCode.LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "bluetooth" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0005,
                        OperationEventCode.UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "bluetooth" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0005,
                        OperationEventCode.ONE_TOUCH_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "bluetooth" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0005,
                        OperationEventCode.KEY_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "bluetooth" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0005,
                        OperationEventCode.KEY_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "bluetooth" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0005,
                        OperationEventCode.AUTO_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "auto" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0005,
                        OperationEventCode.MANUAL_LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "bluetooth" } }))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x0005,
                        OperationEventCode.MANUAL_UNLOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({ data = { method = "bluetooth" } }))
      }
    }
)

test.register_coroutine_test(
    "Battery Voltage test cases",
    function()
      local battery_test_map = {
          [63] = 100,
          [60] = 100,
          [56] = 80,
          [48] = 40,
          [45] = 25,
          [40] = 0,
          [38] = 0
      }
      for voltage, batt_perc in pairs(battery_test_map) do
        test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
        test.wait_for_events()
      end
    end
)

test.register_message_test(
  "manufacture specific command on DoorLock cluster (\x00\x00) should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, DoorLock.ID, SAMSUNG_SDS_MFR_SPECIFIC_COMMAND, SAMSUNG_SDS_MFR_CODE, "  ")
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked())
    },
  }
)

test.register_message_test(
  "manufacture specific command on DoorLock cluster (\x01\x00) should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        zigbee_test_utils.build_custom_command_id(mock_device, DoorLock.ID, SAMSUNG_SDS_MFR_SPECIFIC_COMMAND, SAMSUNG_SDS_MFR_CODE, " ")
      }
    }
  }
)

test.register_coroutine_test(
    "Handle Unlock cmd",
    function()
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "lock", component = "main", command = "unlock", args = {} }
          }
      )
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_tx_custom_command_id(mock_device, DoorLock.ID, SAMSUNG_SDS_MFR_SPECIFIC_COMMAND, SAMSUNG_SDS_MFR_CODE, "1235")
      })
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Handle Lock cmd",
    function()
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "lock", component = "main", command = "lock", args = {} }
          }
      )
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Device added function handler",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.unlocked()))
      test.wait_for_events()
    end
)

test.run_registered_tests()
