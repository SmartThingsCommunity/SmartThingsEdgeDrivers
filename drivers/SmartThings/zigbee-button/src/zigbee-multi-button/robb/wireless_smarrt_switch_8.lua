local device_management = require "st.zigbee.device_management"

local zcl_clusters = require "st.zigbee.zcl.clusters"
local Basic = zcl_clusters.Basic
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local Groups = zcl_clusters.Groups
local PowerConfiguration = zcl_clusters.PowerConfiguration

local log = require "log"
local utils = require "st.utils"

local capabilities = require "st.capabilities"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local button_utils = require "button_utils"

local SWITCH8_GROUP_CONFIGURE = "is_group_configured"
local SWITCH8_NUM_ENDPOINT = 0x04

local WIRELESS_REMOTE_FINGERPRINTS = {
  { mfr = "ROBB smarrt", model = "ROB_200-007-0" },
  { mfr = "ROBB smarrt", model = "ROB_200-008-0" }
}

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(WIRELESS_REMOTE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end


local function component_to_endpoint(device, component_id)
  log.debug('### component_id:' .. component_id)
  local ep_num = component_id:match("button(%d)")
  return { ep_num and tonumber(ep_num) }
end

local function endpoint_to_component(device, ep)
  log.debug('### ep:' .. ep)
  local button_comp = string.format("button%d", ep)
  if device.profile.components[button_comp] ~= nil then
    return button_comp
  else
    return "main"
  end
end


local device_init = function(driver, device)
  --[[ device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component) ]]

  battery_defaults.build_linear_voltage_init(2.1, 3.0)
end

local do_configuration = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  for endpoint = 1,SWITCH8_NUM_ENDPOINT do
    device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):to_endpoint(
      endpoint))
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(
      endpoint))
  end

  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))

  device:send(Basic.attributes.DeviceEnabled:write(device, true))
  if not self.datastore[SWITCH8_GROUP_CONFIGURE] then
    -- Configure adding hub to group once
    self:add_hub_to_zigbee_group(0xE902)
    self:add_hub_to_zigbee_group(0xE903)
    self:add_hub_to_zigbee_group(0xE904)
    self.datastore[SWITCH8_GROUP_CONFIGURE] = true
  end
end



local EP_BUTTON_ON_COMPONENT_MAP = {
  [0x01] = 1,
  [0x02] = 3,
  [0x03] = 5,
  [0x04] = 7
}

local EP_BUTTON_OFF_COMPONENT_MAP = {
  [0x01] = 2,
  [0x02] = 4,
  [0x03] = 6,
  [0x04] = 8
}

local function attr_on_handler(driver, device, zb_rx)
  button_utils.send_pushed_or_held_button_event_if_applicable(device,
    EP_BUTTON_ON_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value])
end

local function attr_off_handler(driver, device, zb_rx)
  button_utils.send_pushed_or_held_button_event_if_applicable(device,
    EP_BUTTON_OFF_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value])
end

local robb_wireless_8_control = {
  NAME = "ROBB Wireless 8 Remote Control",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configuration
  },
  zigbee_handlers = {
    cluster = {
      [Level.ID] = {
        [Level.server.commands.MoveWithOnOff.ID] = attr_on_handler,
        [Level.server.commands.StopWithOnOff.ID] = attr_off_handler
      },
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = attr_off_handler,
        [OnOff.server.commands.On.ID] = attr_on_handler
      }
    }
  },
  can_handle = can_handle
}

return robb_wireless_8_control
