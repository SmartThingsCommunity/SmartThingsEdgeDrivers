local capabilities = require "st.capabilities"

local MULTISTATE_INPUT_ATTR = 0x0012
local PRESENT_VALUE = 0x0055

local HELD = 0x0000
local PUSHED = 0x0001
local DOUBLE = 0x0002

local function present_value_attr_handler(driver, device, value, zb_rx)
  local event
  local additional_fields = {
    state_change = true
  }
  if value.value == PUSHED then
    event = capabilities.button.button.pushed(additional_fields)
    device:emit_event(event)
  elseif value.value == DOUBLE then
    event = capabilities.button.button.double(additional_fields)
    device:emit_event(event)
  elseif value.value == HELD then
    event = capabilities.button.button.held(additional_fields)
    device:emit_event(event)
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.button.supportedButtonValues({ "pushed", "double", "held" }, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
end

local thirdreality_device_handler = {
  NAME = "ThirdReality Smart Button",
  lifecycle_handlers = {
    added = device_added
  },
  zigbee_handlers = {
    attr = {
      [MULTISTATE_INPUT_ATTR] = {
        [PRESENT_VALUE] = present_value_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Third Reality, Inc" and device:get_model() == "3RSB22BZ"
  end
}

return thirdreality_device_handler
