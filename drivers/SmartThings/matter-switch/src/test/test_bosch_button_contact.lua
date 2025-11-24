-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.generated.zap_clusters"
local button_attr = capabilities.button.button
local uint32 = require "st.matter.data_types.Uint32"

local mock_device = test.mock_device.build_test_matter_device({
  label = "Bosch_Button_Contact_Sensor",
  profile = t_utils.get_profile_definition("contact-button-battery.yml"),
  manufacturer_info = {
    vendor_id = 0x1209,
    product_id = 0x3015
  },
  endpoints = {
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
        {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0015, device_type_revision = 1} -- CONTACT SENSOR
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {
            cluster_id = clusters.Switch.ID,
            feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
                    clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
                    clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
            cluster_type = "SERVER",
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- GENERIC SWITCH
      }
    }
  }
})

local CLUSTER_SUBSCRIBE_LIST = {
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.ShortRelease,
    clusters.Switch.server.events.MultiPressComplete,
    clusters.PowerSource.server.attributes.BatPercentRemaining,
    clusters.BooleanState.attributes.StateValue
}

local function test_init()
    test.disable_startup_messages()
    test.mock_device.add_test_device(mock_device)

    local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
    for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
        if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
    end

    test.socket.matter:__expect_send({mock_device.id, subscribe_request})
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.matter:__expect_send({mock_device.id, subscribe_request})
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.matter:__expect_send({mock_device.id, clusters.PowerSource.attributes.AttributeList:read()})
    test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, 2)})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", button_attr.pushed()))
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Ensure doConfigure and the following handling works as expected",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.attributes.MultiPressMax:build_test_report_data(mock_device, 2, 2)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed", "double", "held"}, {visibility = {displayed = false}}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 6, {uint32(0x0C)})})
    mock_device:expect_metadata_update({ profile = "contact-button-battery" })
  end
)


test.register_coroutine_test(
  "Handle single press sequence for a multi press on multi button",
  function ()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 2, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, 2, {previous_position = 0}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device, 2, {new_position = 0, total_number_of_presses_counted = 1, previous_position = 0}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", button_attr.pushed({state_change = true})))
  end
)

test.register_message_test(
  "Handle release after long press", {
      {
          channel = "matter",
          direction = "receive",
          message = {
              mock_device.id,
              clusters.Switch.events.InitialPress:build_test_event_report(
                      mock_device, 2, {new_position = 1}
              )
          }
      },
      {
          channel = "matter",
          direction = "receive",
          message = {
              mock_device.id,
              clusters.Switch.events.LongPress:build_test_event_report(
                      mock_device, 2, {new_position = 1}
              ),
          }
      },
      {
          channel = "capability",
          direction = "send",
          message = mock_device:generate_test_message("main", capabilities.button.button.held({state_change=true}))
      },
      {
          channel = "matter",
          direction = "receive",
          message = {
              mock_device.id,
              clusters.Switch.events.LongRelease:build_test_event_report(
                      mock_device, 2, {previous_position = 1}
              )
          }
      },
  }
)

test.register_message_test(
  "Receiving a max press attribute of 2 should emit correct event", {
      {
          channel = "matter",
          direction = "receive",
          message = {
              mock_device.id,
              clusters.Switch.attributes.MultiPressMax:build_test_report_data(
                      mock_device, 1, 2
              )
          },
      },
      {
          channel = "capability",
          direction = "send",
          message = mock_device:generate_test_message("main",
                  capabilities.button.supportedButtonValues({"pushed", "double"}, {visibility = {displayed = false}}))
      },
  }
)

test.register_message_test(
  "Handle double press", {
      {
          channel = "matter",
          direction = "receive",
          message = {
              mock_device.id,
              clusters.Switch.events.InitialPress:build_test_event_report(
                      mock_device, 2, {new_position = 1}
              )
          }
      },
      {
          channel = "matter",
          direction = "receive",
          message = {
              mock_device.id,
              clusters.Switch.events.MultiPressComplete:build_test_event_report(
                      mock_device, 2, {new_position = 1, total_number_of_presses_counted = 2, previous_position = 0}
              )
          }
      },
      {
          channel = "capability",
          direction = "send",
          message = mock_device:generate_test_message("main", capabilities.button.button.double({state_change=true}))
      },
  }
)

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

test.register_message_test(
  "Boolean state reports should generate correct messages", {
      {
          channel = "matter",
          direction = "receive",
          message = {
              mock_device.id,
              clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device, 1, false)
          }
      },
      {
          channel = "capability",
          direction = "send",
          message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
          channel = "matter",
          direction = "receive",
          message = {
              mock_device.id,
              clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device, 1, true)
          }
      },
      {
          channel = "capability",
          direction = "send",
          message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
  }
)

test.run_registered_tests()
