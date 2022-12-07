local zcl_clusters = require "st.zigbee.zcl.clusters"
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local Basic = zcl_clusters.Basic
local PowerConfiguration = zcl_clusters.PowerConfiguration

local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"
local log = require "log"
local utils = require "st.utils"

local constants = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local zdo_messages = require "st.zigbee.zdo"

local button_utils = require "button_utils"

local supported_values = require "zigbee-multi-button.supported_values"

local SWITCH8_GROUP_CONFIGURE = "is_group_configured"
local SWITCH8_NUM_ENDPOINT = 0x04

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
  local ep_num = component_id:match("button(%d)")
  return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
end

local function endpoint_to_component(device, ep)
  local button_comp = string.format("button%d", ep)
  if device.profile.components[button_comp] ~= nil then
    return button_comp
  else
    return "main"
  end
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.1, 3.0)

  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)

  for ep = 1, device:component_count() do
    -- 
    --  calling get_component_id_for_endpoint
    --  to verify relationship ep / component
    --
    log.debug('### endpoint: ', ep)
    log.debug('### matches with:', device:get_component_id_for_endpoint(ep))
  end
end

local function handle_switch_onoff(driver, device, zb_rx)
  --local endpoint_id = device:component_to_endpoint(cmd.component)
  --device:send_to_component(cmd.component, req)
  log.debug("### handle_switch_onoff cmd: " .. utils.stringify_table(zb_rx, "cmd table", true))
  log.debug("### ep: " .. zb_rx.address_header.src_endpoint.value)

  --device:emit_component_event(zb_rx.address_header.src_endpoint.value, capabilities.button.button.pushed)
  button_utils.build_button_handler("button" .. zb_rx.address_header.src_endpoint.value,
    capabilities.button.button.pushed)


  button_utils.build_button_handler("button2",
    capabilities.button.button.pushed)

end

local function handle_set_level(driver, device, zb_rx)
  -- local endpoint_id = device:component_to_endpoint(cmd.component)
  -- local level = math.floor(cmd.args.level / 100.0 * 254)
  --local req = Level.server.commands.MoveToLevelWithOnOff(device, endpoint_id, level, cmd.args.rate or 0,
  --  0, 0)
  --device:send(req)
  log.debug("### handle_set_level cmd: " .. utils.stringify_table(zb_rx, "cmd table", true))
  log.debug("### ep: " .. zb_rx.address_header.src_endpoint.value)
  --button_utils.build_button_handler("button3", capabilities.button.button.held)
  button_utils.build_button_handler("button" .. zb_rx.address_header.src_endpoint.value,
    capabilities.button.button.held)

  button_utils.build_button_handler("button2",
    capabilities.button.button.held)
end

local function added_handler(self, device)
  for comp_name, comp in pairs(device.profile.components) do

    device:emit_component_event(comp, capabilities.button.supportedButtonValues({ "pushed", "held" }))

    if comp_name == "main" then
      device:emit_component_event(comp,
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
    else
      device:emit_component_event(comp,
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
    end
  end
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
end

local function do_configure(self, device)
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  --device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
  --device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))

  for endpoint = 1, SWITCH8_NUM_ENDPOINT do
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):
      to_endpoint(endpoint))
    device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):
      to_endpoint(endpoint))
  end
  if not self.datastore[SWITCH8_GROUP_CONFIGURE] then
    -- Configure adding hub to group once
    self:add_hub_to_zigbee_group(0xE901)
    self:add_hub_to_zigbee_group(0xE902)
    self:add_hub_to_zigbee_group(0xE903)
    self:add_hub_to_zigbee_group(0xE904)
    self.datastore[SWITCH8_GROUP_CONFIGURE] = true
  end
end ]]

local do_configuration = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  for endpoint = 1, SWITCH8_NUM_ENDPOINT do
    device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):to_endpoint(endpoint))
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(endpoint))
  end
  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))
  device:send(Basic.attributes.DeviceEnabled:write(device, true))
  log.debug("### self.datastore[SWITCH8_GROUP_CONFIGURE]: " ..
    utils.stringify_table(self.datastore[SWITCH8_GROUP_CONFIGURE], "cmd table", true))
  if not self.datastore[SWITCH8_GROUP_CONFIGURE] then
    -- Configure adding hub to group once
    self:add_hub_to_zigbee_group(0xE901)
    self:add_hub_to_zigbee_group(0xE902)
    self:add_hub_to_zigbee_group(0xE903)
    self:add_hub_to_zigbee_group(0xE904)
    self.datastore[SWITCH8_GROUP_CONFIGURE] = true
  end
  -- Read binding table
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR,
    constants.HUB.ENDPOINT,
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    constants.ZDO_PROFILE_ID,
    mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
  )
  local binding_table_req = mgmt_bind_req.MgmtBindRequest(0) -- Single argument of the start index to query the table
  local message_body = zdo_messages.ZdoMessageBody({
    zdo_body = binding_table_req
  })
  local binding_table_cmd = messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = message_body
  })
  device:send(binding_table_cmd)
end

local function attr_on_handler(driver, device, zb_rx)
  log.debug("### handle_set_level cmd: " .. utils.stringify_table(zb_rx, "cmd table", true))
  log.debug("### ep: " .. zb_rx.address_header.src_endpoint.value)
  button_utils.send_pushed_or_held_button_event_if_applicable(device,
    EP_BUTTON_ON_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value])
end

local function attr_off_handler(driver, device, zb_rx)
  log.debug("### handle_set_level cmd: " .. utils.stringify_table(zb_rx, "cmd table", true))
  log.debug("### ep: " .. zb_rx.address_header.src_endpoint.value)
  button_utils.send_pushed_or_held_button_event_if_applicable(device,
    EP_BUTTON_OFF_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value])
end

--[[ local function handle_set_level(driver, device, zb_rx)
  log.debug("### handle_set_level cmd: " .. utils.stringify_table(zb_rx, "cmd table", true))
  log.debug("### ep: " .. zb_rx.address_header.src_endpoint.value)
  --button_utils.build_button_handler("button3", capabilities.button.button.held)
  button_utils.build_button_handler("button" .. zb_rx.address_header.src_endpoint.value,
    capabilities.button.button.held)

end ]]

local function added_handler(self, device)
  log.debug("### device info start: ")
  local dev = self.device_api.get_device_info(device.id)
  log.debug(utils.stringify_table(dev, "dev table", true))
  log.debug("### device info end ")

  local config = supported_values.get_device_parameters(device)
  for _, component in pairs(device.profile.components) do
    local number_of_buttons = component.id == "main" and config.NUMBER_OF_BUTTONS or 1
    if config ~= nil then
      device:emit_component_event(component, capabilities.button.supportedButtonValues(config.SUPPORTED_BUTTON_VALUES),
        { visibility = { displayed = false } })
    else
      device:emit_component_event(component,
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false } }))
    end
    device:emit_component_event(component, capabilities.button.numberOfButtons({ value = number_of_buttons }))
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
end

local function component_to_endpoint(device, component_id)
  local ep_ini = device.fingerprinted_endpoint_id

  if component_id == "main" then
    return ep_ini
  else
    local ep_num = component_id:match("endpoint(%d)")
    if ep_num == "2" then
      return ep_ini + 1
    elseif ep_num == "3" then
      return ep_ini + 2
    elseif ep_num == "4" then
      return ep_ini + 3
    end
  end

  --[[ local ep_num = component_id:match("button(%d)")
  return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id ]]
end

local function endpoint_to_component(device, ep)
  local ep_ini = device.fingerprinted_endpoint_id

  if ep == ep_ini then
    return "main"
  else
    if ep == ep_ini + 1 then
      return "endpoint2"
    elseif ep == ep_ini + 2 then
      return "endpoint3"
    elseif ep == ep_ini + 3 then
      return "endpoint4"
    end
  end
  --[[ local button_comp = string.format("button%d", ep)
  if device.profile.components[button_comp] ~= nil then
    return button_comp
  else
    return "main"
  end ]]
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.1, 3.0)

  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)

  for ep = 1, device:component_count() do
    --
    --  calling get_component_id_for_endpoint
    --  to verify relationship ep / component
    --
    log.debug('### endpoint: ', ep)
    log.debug('### matches with:', device:get_component_id_for_endpoint(ep))
  end
end

local robb_wireless_8_control = {
  NAME = "ROBB Wireless 8 Remote Control",
  lifecycle_handlers = {
    init = device_init,
    --init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    added = added_handler,
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
