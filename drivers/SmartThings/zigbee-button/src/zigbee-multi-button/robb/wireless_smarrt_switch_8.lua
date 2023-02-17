local device_management = require "st.zigbee.device_management"

local zcl_clusters = require "st.zigbee.zcl.clusters"
local Basic = zcl_clusters.Basic
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local Groups = zcl_clusters.Groups
local PowerConfiguration = zcl_clusters.PowerConfiguration

local log = require "log"
local utils = require "st.utils"
local json = require("dkjson")

local capabilities = require "st.capabilities"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local SWITCH8_GROUP_CONFIGURE = "is_group_configured"
local SWITCH8_NUM_ENDPOINT = 0x04

local BUTTON_CP_ON_ENDPOINT_MAP = {
  [1] = "button1",
  [2] = "button3",
  [3] = "button5",
  [4] = "button7"
}

local BUTTON_CP_OFF_ENDPOINT_MAP = {
  [1] = "button2",
  [2] = "button4",
  [3] = "button6",
  [4] = "button8"
}

local WIRELESS_REMOTE_FINGERPRINTS = {
  { mfr = "ROBB smarrt", model = "ROB_200-007-0" }
}

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(WIRELESS_REMOTE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

--[[ local function component_to_endpoint(device, component_id)
  local ep_ini = device.fingerprinted_endpoint_id

  log.debug("### component_to_endpoint")

  if component_id == "main" then
    return ep_ini
  else
    local ep_num = component_id:match("button(%d)")
    if ep_num == "1" then
      return ep_ini
    elseif ep_num == "2" then
      return ep_ini
    elseif ep_num == "3" then
      return ep_ini + 1
    elseif ep_num == "4" then
      return ep_ini + 1
    end
  end

  local ep_num = component_id:match("button(%d)")
  return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
end ]]

--[[ local function endpoint_to_component(device, ep)
  local ep_ini = device.fingerprinted_endpoint_id

  log.debug("### endpoint_to_component")

  if ep == ep_ini then
    return { "main", "button1", "button2" }
  else
    if ep == ep_ini + 1 then
      return { "button3", "button4" }
         elseif ep == ep_ini then
      return "button2"
    elseif ep == ep_ini + 1 then
      return "button3"
    elseif ep == ep_ini + 1 then
      return "button4"
    end
  end
end ]]

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("button(%d)")
  return { ep_num and tonumber(ep_num) }
end

local function endpoint_to_component(device, ep)
  local button_comp = string.format("button%d", ep)
  if device.profile.components[button_comp] ~= nil then
    return button_comp
  else
    return "main"
  end
end

local function build_button_handler(MAPPING, pressed_type)
  return function(driver, device, zb_rx)
    --local bytes = zb_rx.body

    log.debug('### zbrx:' .. utils.stringify_table(zb_rx, 'body', true))
    --[[ local button_num = bytes:byte(2) + 1
    local button_name = "button" .. button_num
    log.debug('### button_name:' .. button_name)]]

    local additional_fields = {
      state_change = true
    }
    local event = pressed_type(additional_fields)
    local button_name = MAPPING[zb_rx.address_header.src_endpoint.value]
    local comp = device.profile.components[button_name]
    if comp ~= nil then
      device:emit_component_event(comp, event)
    else
      log.warn("Attempted to emit button event for unknown button: " .. button_name)
    end
  end
end

local device_init = function(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)

  --[[ log.debug("### new device info start: ")
  local dev = driver.device_api.get_device_info(device.id)
  log.debug(utils.stringify_table(dev, "new dev table", true))
  log.debug("### new device info end ") ]]

  battery_defaults.build_linear_voltage_init(2.1, 3.0)
end

local do_configuration = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))

  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):to_endpoint(0x01))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(0x01))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):to_endpoint(0x02))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(0x02))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):to_endpoint(0x03))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(0x03))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):to_endpoint(0x04))
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(0x04))
  
  --device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1):to_endpoint(endpoint))
  --[[ device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  for endpoint = 1, SWITCH8_NUM_ENDPOINT do
    device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):to_endpoint(endpoint))
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(endpoint))
  end
  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))

  device:send(Basic.attributes.DeviceEnabled:write(device, true))
  if not self.datastore[SWITCH8_GROUP_CONFIGURE] then
    -- Configure adding hub to group once
    self:add_hub_to_zigbee_group(0x0D01)
    self:add_hub_to_zigbee_group(0x0D02)
    self:add_hub_to_zigbee_group(0x0D03)
    self:add_hub_to_zigbee_group(0x0D04)
    self.datastore[SWITCH8_GROUP_CONFIGURE] = true
  end ]]
end

local robb_wireless_8_control = {
  NAME = "ROBB Wireless 8 Remote Control",
  supported_capabilities = {
    capabilities.battery,
    capabilities.switch,
  },
  lifecycle_handlers = {
    init = device_init,
    -- init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    -- added = added_handler,
    doConfigure = do_configuration
  },
  zigbee_handlers = {
    cluster = {
      --[[ [Level.ID] = {
        [Level.server.commands.MoveWithOnOff.ID] = build_button_handler(BUTTON_CP_ON_ENDPOINT_MAP),
        [Level.server.commands.StopWithOnOff.ID] = build_button_handler(BUTTON_CP_OFF_ENDPOINT_MAP)
      }, ]]
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = build_button_handler(BUTTON_CP_OFF_ENDPOINT_MAP,
          capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = build_button_handler(BUTTON_CP_ON_ENDPOINT_MAP, capabilities.button.button.pushed)
      }
    }
  },
  can_handle = can_handle
}

return robb_wireless_8_control
