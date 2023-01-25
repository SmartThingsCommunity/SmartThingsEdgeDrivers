local zcl_clusters = require "st.zigbee.zcl.clusters"
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff
local Groups = zcl_clusters.Groups
local PowerConfiguration = zcl_clusters.PowerConfiguration

local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"
local log = require "log"
local utils = require "st.utils"
local json = require("dkjson")

local constants = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local zdo_messages = require "st.zigbee.zdo"

local button_utils = require "button_utils"

local supported_values = require "zigbee-multi-button.supported_values"

local SWITCH8_NUM_ENDPOINT = 0x04
local ENTRIES_READ = "ENTRIES_READ"

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

local COMPONENT_MAP = { "main", "button1",  "button2",  "button3",  "button4",  "button5",  "button6",  "button7",  "button8" }

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

local function build_button_handler(MAPPING, pressed_type)
  return function(driver, device, zb_rx)
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

local do_configuration = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  for endpoint = 1, SWITCH8_NUM_ENDPOINT do
    device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui):to_endpoint(endpoint))
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(endpoint))
    device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1):to_endpoint(endpoint))
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

  device:send(Groups.server.commands.RemoveAllGroups(device))
end

local function zdo_binding_table_handler(driver, device, zb_rx)
  -- log.debug("### binding tabel: " .. utils.stringify_table(zb_rx, "binding table", true))
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      log.debug("### send add hub to zigbee group command")
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
      return
    end
  end

  local entries_read = device:get_field(ENTRIES_READ) or 0
  entries_read = entries_read + zb_rx.body.zdo_body.binding_table_list_count.value

  -- if the device still has binding table entries we haven't read, we need
  -- to go ask for them until we've read them all
  if entries_read <= zb_rx.body.zdo_body.total_binding_table_entry_count.value then
    device:set_field(ENTRIES_READ, entries_read)

    -- Read binding table
    local addr_header = messages.AddressHeader(
      constants.HUB.ADDR,
      constants.HUB.ENDPOINT,
      device:get_short_address(),
      device.fingerprinted_endpoint_id,
      constants.ZDO_PROFILE_ID,
      mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
    )
    local binding_table_req = mgmt_bind_req.MgmtBindRequest(entries_read) -- Single argument of the start index to query the table
    local message_body = zdo_messages.ZdoMessageBody({ zdo_body = binding_table_req })
    local binding_table_cmd = messages.ZigbeeMessageTx({ address_header = addr_header, body = message_body })
    device:send(binding_table_cmd)
  else
    log.debug("### table response fallback")
    driver:add_hub_to_zigbee_group(0x0000) -- fallback if no binding table entries found
    device:send(Groups.commands.AddGroup(device, 0x0000))
  end
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
  --[[ log.debug("### device info start: ")
  local dev = self.device_api.get_device_info(device.id)
  log.debug(utils.stringify_table(dev, "dev table", true))
  log.debug("### device info end ") ]]

  local config = supported_values.get_device_parameters(device)
  for _, component in pairs(device.profile.components) do
    local number_of_buttons = component.id == "main" and config.NUMBER_OF_BUTTONS or 1
    --[[ if config ~= nil then
      device:emit_component_event(component, capabilities.button.supportedButtonValues(config.SUPPORTED_BUTTON_VALUES),
        { visibility = { displayed = false } })
    else
      device:emit_component_event(component,
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false } }))
    end ]]

    --log.debug("### component: " .. utils.stringify_table(component, "component table", true))

    device:emit_component_event(component, capabilities.button.supportedButtonValues(config.SUPPORTED_BUTTON_VALUES),
      { visibility = { displayed = false } })

    device:emit_component_event(component, capabilities.button.numberOfButtons({ value = number_of_buttons }))
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
  device:send(Groups.server.commands.RemoveAllGroups(device))
end

local function component_to_endpoint(device, component_id)
  local ep_ini = device.fingerprinted_endpoint_id

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

  --[[ local ep_num = component_id:match("button(%d)")
  return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id ]]
end

local function endpoint_to_component(device, ep)
  local ep_ini = device.fingerprinted_endpoint_id

  if ep == ep_ini then
    return {"main", "button1", "button2" }
  else
    if ep == ep_ini + 1 then
      return {"button3", "button4"}
 --[[    elseif ep == ep_ini then
      return "button2"
    elseif ep == ep_ini + 1 then
      return "button3"
    elseif ep == ep_ini + 1 then
      return "button4" ]]
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

  local device_cloud = json.decode(driver.device_api.get_device_info(device.id))

  device_cloud.zigbee_endpoints = utils.merge({
    ["2"] = utils.merge({
      id = 2
    }, device_cloud.zigbee_endpoints["2"])
  }, device_cloud.zigbee_endpoints)
  device:load_updated_data(device_cloud)

  log.debug("### new device info start: ")
  local dev = driver.device_api.get_device_info(device.id)
  log.debug(utils.stringify_table(dev, "new dev table", true))
  log.debug("### new device info end ")

  for cp = 1, 4 do
    --
    --  calling get_component_id_for_endpoint
    --  to verify relationship ep / component
    --
    log.debug('### endpoint: ', cp)
    log.debug('### ep matches with:', device: get_component_id_for_endpoint(cp))
  end

  for key, value in ipairs(COMPONENT_MAP) do
    log.debug('### component: ', value)
    log.debug('### comp matches with:', device:get_endpoint_for_component_id(value))
  end
end

local robb_wireless_8_control = {
  NAME = "ROBB Wireless 8 Remote Control",
  supported_capabilities = {
    capabilities.button,
    capabilities.battery,
    capabilities.switch,
    capabilities.switchLevel,
  },
  lifecycle_handlers = {
    init = device_init,
    --init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    added = added_handler,
    doConfigure = do_configuration
  },
  zigbee_handlers = {
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    },
    cluster = {
      --[[ [Level.ID] = {
        [Level.server.commands.MoveWithOnOff.ID] = build_button_handler(BUTTON_CP_ON_ENDPOINT_MAP),
        [Level.server.commands.StopWithOnOff.ID] = build_button_handler(BUTTON_CP_OFF_ENDPOINT_MAP)
      }, ]]
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = build_button_handler(BUTTON_CP_OFF_ENDPOINT_MAP, capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = build_button_handler(BUTTON_CP_ON_ENDPOINT_MAP, capabilities.button.button.pushed)
      },
      [Groups.ID] = {

      }
    }
  },
  can_handle = can_handle
}

return robb_wireless_8_control
