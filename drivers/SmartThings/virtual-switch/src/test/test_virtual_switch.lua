-- Mock out globals
local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local mock_simple_device = test.mock_device.build_test_generic_device(
    {
      profile = t_utils.get_profile_definition("virtual-dimmer-switch.yml"),
      preferences = { ["certifiedpreferences.forceStateChange"] = true },
    }
)

local mock_device_no_prefs = test.mock_device.build_test_generic_device(
    {
      profile = t_utils.get_profile_definition("virtual-dimmer-switch.yml"),
    }
)

local function test_init()
  test.mock_device.add_test_device(mock_simple_device)
  test.mock_device.add_test_device(mock_device_no_prefs)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Reported level should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 83, 0 } }}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.switchLevel.level(83, {state_change=true}))
      },
     {
      channel = "capability",
      direction = "send",
      message = mock_simple_device:generate_test_message("main", capabilities.switch.switch.on())
     }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switch", component = "main", command = "on", args = {}}}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.switch.switch.on({state_change=true}))
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device_no_prefs.id, { capability = "switch", component = "main", command = "on", args = {}}}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device_no_prefs:generate_test_message("main", capabilities.switch.switch.on({state_change=true}))
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: off",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switch", component = "main", command = "off", args = {}}}

      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.switch.switch.off({state_change=true}))
      }
    }
)

test.register_message_test(
    "Reported off for 0",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 0, 0 } }}
      },
      {
       channel = "capability",
       direction = "send",
       message = mock_simple_device:generate_test_message("main", capabilities.switch.switch.off({state_change=true}))
      }
    }
)


test.register_message_test(
    "Reported on and level for 100",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_simple_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 100, 0 }, {state_change=true}}}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main", capabilities.switchLevel.level(100, {state_change=true}))
      },
      {
       channel = "capability",
       direction = "send",
       message = mock_simple_device:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_coroutine_test(
  "State change should not be true when forceStateChange is false",
  function()
    test.socket.device_lifecycle():__queue_receive({mock_simple_device.id, "init"})
    test.socket.device_lifecycle():__queue_receive(mock_simple_device:generate_info_changed(
        {
            preferences = {
              ["certifiedpreferences.forceStateChange"] = false
            }
        }
    ))
    test.wait_for_events()
    test.socket.capability:__queue_receive({ mock_simple_device.id,
      { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.capability:__expect_send(mock_simple_device:generate_test_message("main", capabilities.switch.switch.on()))
  end
)

test.run_registered_tests()
