local device_management = require "st.zigbee.device_management"

local zcl_clusters = require "st.zigbee.zcl.clusters"
local Basic = zcl_clusters.Basic
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local capabilities = require "st.capabilities"

--[[
The ROBB Wireless Remote Control has 4 or 8 buttons. They are arranged in two columns:

All buttons on the left side support 'pressed' (OnOff > ON) and 'up_hold' (Level > MoveStepMode.UP).
All buttons on the right side support 'pressed' (OnOff > OFF) and 'down_hold' (Level > MoveStepMode.DOWN).

Each button-row represents one endpoint. The 8x remote control has four endpoints, the 4x remote control has two.
That means each endpoint has two buttons.
--]]

local ROBB_MFR_STRING = "ROBB smarrt"
local WIRELESS_REMOTE_FINGERPRINTS = {
  ["ROB_200-008-0"] = {
    endpoints = 2,
    buttons = 4
  },
  ["ROB_200-007-0"] = {
    endpoints = 4,
    buttons = 8
  }
}

local function can_handle(opts, driver, device, ...)
  if device:get_manufacturer() == ROBB_MFR_STRING and WIRELESS_REMOTE_FINGERPRINTS[device:get_model()] then
    return true
  else
    return false
  end
end

local button_push_handler = function(addF)
  return function(driver, device, zb_rx)
    local additional_fields = { state_change = true }
    local ep = zb_rx.address_header.src_endpoint.value

    -- Fetch correct button name
    local offset = 0
    if addF == true then
      offset = 0xF0
    end

    local event = capabilities.button.button.pushed(additional_fields)
    device:emit_event_for_endpoint(ep + offset, event)
    device:emit_event(event)
  end
end

local function button_hold_handler(driver, device, zb_rx)
  local pressed_type
  local additional_fields = { state_change = true }
  local ep = zb_rx.address_header.src_endpoint.value

  local offset = 0

  -- Handle MoveStepMode.UP
  if zcl_clusters.Level.types.MoveStepMode.UP == zb_rx.body.zcl_body.move_mode.value then
    pressed_type = "up_hold"
  -- Handle MoveStepMode.DOWN
  else
    offset = 0xF0
    pressed_type = "down_hold"
  end

  local event = capabilities.button.button[pressed_type](additional_fields)
  device:emit_event_for_endpoint(ep + offset, event)
  device:emit_event(event)
end

local do_configuration = function(driver, device)
  -- Get the right number of endpoints
  local endpoints = WIRELESS_REMOTE_FINGERPRINTS[device:get_model()].endpoints

  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, driver.environment_info.hub_zigbee_eui), 1)
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))

  for endpoint = 1, endpoints do
    device:send(device_management.build_bind_request(device, Level.ID, driver.environment_info.hub_zigbee_eui, endpoint))
    device:send(device_management.build_bind_request(device, OnOff.ID, driver.environment_info.hub_zigbee_eui, endpoint))
  end

  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))

  device:send(Basic.attributes.DeviceEnabled:write(device, true))
  if not device:get_field('is_group_configured') then
    -- Configure adding hub to group once
    driver:add_hub_to_zigbee_group(0xE902)
    -- Add two more groups if it is the 8x wall switch
    if endpoints == 4 then
      driver:add_hub_to_zigbee_group(0xE903)
      driver:add_hub_to_zigbee_group(0xE904)
    end

    device:set_field('is_group_configured', true, { persist = true })
  end
end

local function added_handler(self, device)
  local supported_button_values
  local number_of_buttons
  local comp_id

  for _, comp in pairs(device.profile.components) do
    comp_id = comp.id

    -- Special handeling of ON buttons (left column)
    if comp_id == "button1" or comp_id == "button3" or comp_id == "button5" or comp_id == "button7" then
      supported_button_values = { "pushed", "up_hold" }
      number_of_buttons = 1
    -- Special handling of OFF buttons (right column)
    elseif comp_id == "button2" or comp_id == "button4" or comp_id == "button6" or comp_id == "button8" then
      supported_button_values = { "pushed", "down_hold" }
      number_of_buttons = 1
    -- Handling of main button capability
    elseif comp_id == "main" then
      supported_button_values = { "pushed", "up_hold", "down_hold" }
      number_of_buttons = WIRELESS_REMOTE_FINGERPRINTS[device:get_model()].buttons
    end

    device:emit_component_event(comp,
      capabilities.button.supportedButtonValues(supported_button_values, { visibility = { displayed = false } }))
    device:emit_component_event(comp,
      capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = false } }))
  end
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  device:emit_event(capabilities.battery.battery(math.floor(value.value / 2.0 + 0.5)))
end

-- Map endpoints to component
local function endpoint_to_component(device, ep)
  local EP_MAP = {
    [0x01] = "button1",
    [0x02] = "button3",
    [0x03] = "button5",
    [0x04] = "button7",
    [0xF1] = "button2",
    [0xF2] = "button4",
    [0xF3] = "button6",
    [0xF4] = "button8"
  }

  if EP_MAP[ep] ~= nil then
    return EP_MAP[ep]
  else
    return "main"
  end
end

local function device_init(driver, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local robb_wireless_control = {
  NAME = "ROBB Wireless Remote Control",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler,
    doConfigure = do_configuration
  },
  zigbee_handlers = {
    cluster = {
      [Level.ID] = {
        [Level.server.commands.MoveWithOnOff.ID] = button_hold_handler,
      },
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = button_push_handler(true),
        [OnOff.server.commands.On.ID] = button_push_handler(false)
      }
    },
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      }
    }
  },
  can_handle = can_handle
}

return robb_wireless_control
