local capabilities = require "st.capabilities"
local log = require "log"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Discovery = require "disco"
local Fields = require "fields"
local HueDeviceTypes = require "hue_device_types"
local StrayDeviceHelper = require "stray_device_helper"

local button_disco = require "disco.button"
local hue_multi_service_device_utils = require "utils.hue_multi_service_device_utils"
local utils = require "utils"

---@class ButtonLifecycleHandlers
local ButtonLifecycleHandlers = {}

---@param driver HueDriver
---@param device HueChildDevice
---@param parent_device_id string?
---@param resource_id string?
function ButtonLifecycleHandlers.added(driver, device, parent_device_id, resource_id)
  log.info(
    string.format("Button Added for device %s", (device.label or device.id or "unknown device")))
  local device_button_resource_id = resource_id or utils.get_hue_rid(device)
  if not device_button_resource_id then
    log.error(
      string.format(
        "Could not determine the Hue Resource ID for added button %s",
        (device and device.label) or "unknown button"
      )
    )
    return
  end

  local button_info = Discovery.device_state_disco_cache[device_button_resource_id]
  if not button_info then
    log.error(
      string.format(
        "Expected button info to be cached, sending button %s to stray resolver",
        (device and device.label) or "unknown button"
      )
    )
    driver.stray_device_tx:send({
      type = StrayDeviceHelper.MessageTypes.NewStrayDevice,
      driver = driver,
      device = device
    })
    return
  end

  local button_rid_to_index_map = {}
  if button_info.button then
    driver.hue_identifier_to_device_record[button_info.id] = device
    button_rid_to_index_map[button_info.id] = 1
  end

  if button_info.num_buttons then
    for var = 1, button_info.num_buttons do
      local button_key = string.format("button%s", var)
      local button_id_key = string.format("%s_id", button_key)
      local button = button_info[button_key]
      local button_id = button_info[button_id_key]

      if button and button_id then
        driver.hue_identifier_to_device_record[button_id] = device
        button_rid_to_index_map[button_id] = var

        local supported_button_values = utils.get_supported_button_values(button.event_values)
        local component
        if var == 1 then
          component = "main"
        else
          component = button_key
        end
        device.profile.components[component]:emit_event(
          capabilities.button.supportedButtonValues(
            supported_button_values,
            { visibility = { displayed = false } }
          )
        )
      end
    end
  end

  if button_info.power_id then
    driver.hue_identifier_to_device_record[button_info.power_id] = device
  end

  log.debug(st_utils.stringify_table(button_rid_to_index_map, "button index map", true))
  device:set_field(Fields.BUTTON_INDEX_MAP, button_rid_to_index_map, { persist = true })
  device:set_field(Fields.DEVICE_TYPE, HueDeviceTypes.BUTTON, { persist = true })
  device:set_field(Fields.HUE_DEVICE_ID, button_info.hue_device_id, { persist = true })
  device:set_field(Fields.PARENT_DEVICE_ID, button_info.parent_device_id, { persist = true })
  device:set_field(Fields.RESOURCE_ID, device_button_resource_id, { persist = true })
  device:set_field(Fields._ADDED, true, { persist = true })
  device:set_field(Fields._REFRESH_AFTER_INIT, true, { persist = true })

  driver.hue_identifier_to_device_record[device_button_resource_id] = device
end

---@param driver HueDriver
---@param device HueChildDevice
function ButtonLifecycleHandlers.init(driver, device)
  log.info(
    string.format("Init Button for device %s", (device and device.label or device.id or "unknown button")))
  device:set_field(Fields.IS_MULTI_SERVICE, true, { persist = true })
  local device_button_resource_id =
      utils.get_hue_rid(device) or
      device.device_network_id

  log.debug("resource id " .. tostring(device_button_resource_id))

  local hue_device_id = device:get_field(Fields.HUE_DEVICE_ID)
  if not driver.hue_identifier_to_device_record[device_button_resource_id] then
    driver.hue_identifier_to_device_record[device_button_resource_id] = device
  end
  local button_info, err
  button_info = Discovery.device_state_disco_cache[device_button_resource_id]
  if not button_info then
    log.debug("no button info")
    local parent_bridge = utils.get_hue_bridge_for_device(
      driver, device, device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
    )
    local api_instance = (parent_bridge and parent_bridge:get_field(Fields.BRIDGE_API))

    if parent_bridge and api_instance then
      button_info, err = button_disco.update_state_for_all_device_services(
        driver,
        api_instance,
        hue_device_id,
        parent_bridge.device_network_id,
        Discovery.device_state_disco_cache
      )
      if err then
        log.error(
          st_utils.stringify_table(
            err,
            string.format(
              "Error populating initial state for button %s",
              (device and device.label) or "unknown button"
            ),
            true
          )
        )
      end
    end
  end
  if not button_info then
    log.warn(string.format("Button %s parent bridge not ready, queuing refresh", device and device.label))
    driver._devices_pending_refresh[device.id] = device
  else
    hue_multi_service_device_utils.update_multi_service_device_maps(
      driver, device, hue_device_id, button_info, HueDeviceTypes.BUTTON
    )
  end
  device:set_field(Fields._INIT, true, { persist = false })
  if device:get_field(Fields._REFRESH_AFTER_INIT) then
    driver:inject_capability_command(device, {
      capability = capabilities.refresh.ID,
      command = capabilities.refresh.commands.refresh.NAME,
      args = {}
    })
    device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  end
end

return ButtonLifecycleHandlers
