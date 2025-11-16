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

local test = require "integration_test"
local capabilities = require "st.capabilities"
local json = require "dkjson"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local constants = require "st.zwave.constants"

local SAMSUNG_MANUFACTURER_ID = 0x022E
local SAMSUNG_PRODUCT_TYPE = 0x0001
local SAMSUNG_PRODUCT_ID = 0x0001

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-lock.yml"),
    zwave_manufacturer_id = SAMSUNG_MANUFACTURER_ID,
    zwave_product_type = SAMSUNG_PRODUCT_TYPE,
    zwave_product_id = SAMSUNG_PRODUCT_ID
  }
)

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function init_code_slot(slot_number, name, device)
  local lock_codes = device.persistent_store[constants.LOCK_CODES]
  if lock_codes == nil then
    lock_codes = {}
    device.persistent_store[constants.LOCK_CODES] = lock_codes
  end
  lock_codes[tostring(slot_number)] = name
end

test.register_coroutine_test(
  "When the device is added an unlocked event should be sent",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.lock.lock.unlocked())
    )
    test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.lockCodes.lockCodes(json.encode({["0"] = "Master Code"}), { visibility = { displayed = false } }))
    )
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Setting a user code name should be handled",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "setCode", args = { 1, "1234", "test" } } })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        UserCode:Set({user_identifier = 1, user_code = "1234", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS})
      )
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.NEW_USER_CODE_ADDED,
        event_parameter = "" }
      )
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        UserCode:Get({user_identifier = 1})
      )
    )
    test.socket.zwave:__queue_receive({
      mock_device.id,
      UserCode:Report({
        user_identifier = 1,
        user_code = "1234",
        user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
      })
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode({["1"] = "test"}), { visibility = { displayed = false } })
    ))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.codeChanged("1 set", { data = { codeName = "test"}, state_change = true  }))
    )
  end
)

test.register_coroutine_test(
  "Notification about correctly added code should be handled",
  function()
    mock_device.persistent_store["_code_state"] = {["setName2"] = "Code 2"}
    test.socket.zwave:__queue_receive({ mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.NEW_USER_CODE_NOT_ADDED_DUE_TO_DUPLICATE_CODE
      })
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("2 failed", { state_change = true })))
  end
)

test.register_coroutine_test(
  "Notification about duplicated code should be handled",
  function()
    mock_device.persistent_store["_code_state"] = {["setName2"] = "Code 2"}
    test.socket.zwave:__queue_receive({ mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.NEW_USER_CODE_NOT_ADDED_DUE_TO_DUPLICATE_CODE
      })
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged(2 .. " failed", { state_change = true })))
  end
)

test.register_coroutine_test(
  "All user codes should be reported as deleted upon changing Master Code",
  function()
    init_code_slot(0, "Master Code", mock_device)
    init_code_slot(1, "Code 1", mock_device)
    init_code_slot(2, "Code 2", mock_device)
    init_code_slot(3, "Code 3", mock_device)
    test.socket.zwave:__queue_receive({
      mock_device.id,
      Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION,
        event_parameter = "" }
      )
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCodes.codeChanged("0 set", { data = { codeName = "Master Code"}, state_change = true })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCodes.codeChanged("1 deleted", { data = { codeName = "Code 1"}, state_change = true })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCodes.codeChanged("2 deleted", { data = { codeName = "Code 2"}, state_change = true })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lockCodes.codeChanged("3 deleted", { data = { codeName = "Code 3"}, state_change = true })
      )
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode({["0"] = "Master Code"} ), { visibility = { displayed = false } })
    ))
  end
)

test.run_registered_tests()
