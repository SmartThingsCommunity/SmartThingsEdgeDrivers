local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local function zdo_binding_table_handler(driver, device, zb_rx)
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
      return
    end
  end
  driver:add_hub_to_zigbee_group(0x0000) -- fallback if no binding table entries found
  device:send(Groups.commands.AddGroup(device, 0x0000))
end

-- Map left column buttons to endpoints
local EP_BUTTON_ON_COMPONENT_MAP = {
  [0x01] = "button1",
  [0x02] = "button3",
  [0x03] = "button5",
  [0x04] = "button7"
}

-- Map right column buttons to endpoints
local EP_BUTTON_OFF_COMPONENT_MAP = {
  [0x01] = "button2",
  [0x02] = "button4",
  [0x03] = "button6",
  [0x04] = "button8"
}

local build_button_handler = function(driver, device, zb_rx)
    local button_name
    local additional_fields = { state_change = true }

    -- Fetch correct button name 
    if zb_rx.body.zcl_header.cmd.value == 0x01 then
      button_name = EP_BUTTON_ON_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value]
    else
      button_name = EP_BUTTON_OFF_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value]
    end

    local event = capabilities.button.button.pushed(additional_fields)
    local comp = device.profile.components[button_name]
    -- Emit events
    if comp ~= nil then
      device:emit_component_event(comp, event)
      if button_name ~= "main" then
        device:emit_event(event)
      end
    end
end

local function hold_handler(driver, device, zb_rx)
  local button_name
  local pressed_type
  local additional_fields = { state_change = true }

  -- Handle MoveStepMode.UP
  if zcl_clusters.Level.types.MoveStepMode.UP == zb_rx.body.zcl_body.move_mode.value then
    button_name = EP_BUTTON_ON_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value]
    pressed_type = "up_hold"
  -- Handle MoveStepMode.DOWN
  else
    button_name = EP_BUTTON_OFF_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value]
    pressed_type = "down_hold"
  end

  local event = capabilities.button.button[pressed_type](additional_fields)
  local comp = device.profile.components[button_name]
  -- Emit events
  if comp ~= nil then
    device:emit_component_event(comp, event)
    device:emit_event(event)
  end
end

local do_configuration = function(driver, device) 
  local has8Btns = device:get_model() == "ROB_200-007-0"
  -- Get the right number of endpoints
  local endpoints = has8Btns and SWITCH8_NUM_ENDPOINT or SWITCH4_NUM_ENDPOINT
  
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, driver.environment_info.hub_zigbee_eui))
  
  for endpoint = 1, endpoints do
    device:send(device_management.build_bind_request(device, Level.ID, driver.environment_info.hub_zigbee_eui, endpoint))
    device:send(device_management.build_bind_request(device, OnOff.ID, driver.environment_info.hub_zigbee_eui, endpoint))
  end

  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))

  device:send(Basic.attributes.DeviceEnabled:write(device, true))
  if not driver.datastore[SWITCH_GROUP_CONFIGURE] then
    -- Configure adding hub to group once
    driver:add_hub_to_zigbee_group(0xE902)
    -- Add two more groups if it is the 8x wall switch
    if has8Btns then
      driver:add_hub_to_zigbee_group(0xE903)
      driver:add_hub_to_zigbee_group(0xE904)
    end

    driver.datastore[SWITCH_GROUP_CONFIGURE] = true
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
    -- Special handeling of OFF buttons (right column)
    elseif comp_id == "button2" or comp_id == "button4" or comp_id == "button6" or comp_id == "button8" then
      supported_button_values = { "pushed", "down_hold" }
      number_of_buttons = 1
    -- Handling of main button capability
    elseif comp_id == "main" then
      supported_button_values = { "pushed", "up_hold", "down_hold" }
      number_of_buttons = device:get_model() == "ROB_200-007-0" and SWITCH8_NUM_BUTTONS or SWITCH4_NUM_BUTTONS
    end

    device:emit_component_event(comp,
      capabilities.button.supportedButtonValues(supported_button_values, { visibility = { displayed = false } }))
    device:emit_component_event(comp,
      capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = false } }))
  end
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
end

local robb_wireless_control = {
  NAME = "ROBB Wireless Remote Control",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    added = added_handler,
    doConfigure = do_configuration
  },
  zigbee_handlers = {
    cluster = {
      [Level.ID] = {
        [Level.server.commands.MoveWithOnOff.ID] = hold_handler,
      },
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = build_button_handler,
        [OnOff.server.commands.On.ID] = build_button_handler
      }
    }
  },
  can_handle = can_handle
}

return robb
