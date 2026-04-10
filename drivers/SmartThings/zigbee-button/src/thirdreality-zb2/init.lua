local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"

local MULTISTATE_INPUT_CLUSTER_ID = 0x0012
local PRESENT_VALUE_ATTR_ID = 0x0055

local HELD   = 0x0000
local PUSHED = 0x0001
local DOUBLE = 0x0002

local COMPONENT_MAP = {
  [1] = "button1",
  [2] = "button2",
  [3] = "button3"
}

local function present_value_attr_handler(driver, device, value, zb_rx)
  local event

  if value.value == PUSHED then
    event = capabilities.button.button.pushed({ state_change = true })
  elseif value.value == DOUBLE then
    event = capabilities.button.button.double({ state_change = true })
  elseif value.value == HELD then
    event = capabilities.button.button.held({ state_change = true })
  end

  if not event then return end

  local ep = zb_rx.address_header.src_endpoint.value
  local component_id = COMPONENT_MAP[ep]

  if component_id and device.profile.components[component_id] then
    device:emit_component_event(device.profile.components[component_id], event)
  end
end

local function device_added(driver, device)
  local supported = { "pushed", "double", "held" }

  for ep, comp_id in pairs(COMPONENT_MAP) do
    local comp = device.profile.components[comp_id]
    if comp then
      device:emit_component_event(comp, capabilities.button.supportedButtonValues(supported, { visibility = { displayed = false } }))
      device:emit_component_event(comp, capabilities.button.numberOfButtons({ value = 1 }))
    end
  end
end

local thirdreality_3button_handler = {
  NAME = "ThirdReality Smart Button ZB2",
  lifecycle_handlers = {
    added = device_added
  },
  zigbee_handlers = {
    attr = {
      [MULTISTATE_INPUT_CLUSTER_ID] = {
        [PRESENT_VALUE_ATTR_ID] = present_value_attr_handler
      }
    }
  },
  can_handle = require("thirdreality-zb2.can_handle"),
}

return thirdreality_3button_handler
