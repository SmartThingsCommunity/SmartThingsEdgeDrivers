local log = require "log"
local capabilities = require "st.capabilities"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Consts = require "consts"
local Discovery = require "disco"
local Fields = require "fields"
local HueApi = require "hue.api"
local HueDeviceTypes = require "hue_device_types"
local StrayDeviceHelper = require "stray_device_helper"

local utils = require "utils"

---@class LightLifecycleHandlers
local LightLifecycleHandlers = {}

---@param driver HueDriver
---@param device HueChildDevice
---@param parent_device_id nil|string
---@param resource_id nil|string
function LightLifecycleHandlers.added(driver, device, parent_device_id, resource_id)
  log.info(
    string.format("Light Added for device %s", (device.label or device.id or "unknown device")))
  local device_light_resource_id = resource_id or utils.get_hue_rid(device)
  if not device_light_resource_id then
    log.error(
      string.format(
        "Could not determine the Hue Resource ID for added light %s",
        (device and device.label) or "unknown light"
      )
    )
    return
  end

  local light_info_known = (Discovery.device_state_disco_cache[device_light_resource_id] ~= nil)
  if not light_info_known then
    log.info(
      string.format("Querying device info for parent of %s", (device.label or device.id or "unknown device")))
    local parent_bridge = utils.get_hue_bridge_for_device(driver, device, parent_device_id)
    if not parent_bridge then
      log.error_with({ hub_logs = true }, string.format(
        "Device %s added with parent UUID of %s but could not find a device with that UUID in the driver",
        (device.label or device.id or "unknown device"),
        (device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID))))
      return
    end

    log.info(
      string.format(
        "Found parent bridge device %s info for %s",
        (parent_bridge.label or parent_bridge.device_network_id or parent_bridge.id or "unknown bridge"),
        (device.label or device.id or "unknown device")
      )
    )

    local key = parent_bridge:get_field(HueApi.APPLICATION_KEY_HEADER)
    local bridge_ip = parent_bridge:get_field(Fields.IPV4)
    local bridge_id = parent_bridge:get_field(Fields.BRIDGE_ID)
    if not (Discovery.api_keys[bridge_id or {}] or key) then
      log.warn(
        "Found \"stray\" bulb without associated Hue Bridge. Waiting to see if a bridge becomes available.")
      driver.stray_device_tx:send({
        type = StrayDeviceHelper.MessageTypes.NewStrayDevice,
        driver = driver,
        device = device
      })
      return
    end

    ---@type PhilipsHueApi
    local api_instance =
        parent_bridge:get_field(Fields.BRIDGE_API) or Discovery.disco_api_instances[bridge_id]

    if not api_instance then
      api_instance = HueApi.new_bridge_manager(
        "https://" .. bridge_ip,
        (parent_bridge:get_field(HueApi.APPLICATION_KEY_HEADER) or Discovery.api_keys[bridge_id] or key),
        utils.labeled_socket_builder(
          (parent_bridge.label or bridge_id or parent_bridge.id or "unknown bridge")
        )
      )
      Discovery.disco_api_instances[parent_bridge.device_network_id] = api_instance
    end

    local light_resource, err, _ = api_instance:get_light_by_id(device_light_resource_id)
    if err ~= nil or not light_resource then
      log.error_with({ hub_logs = true }, "Error getting light info: ", error)
      return
    end

    if light_resource.errors and #light_resource.errors > 0 then
      log.error_with({ hub_logs = true }, "Errors found in API response:")
      for idx, err in ipairs(light_resource.errors) do
        log.error_with({ hub_logs = true }, st_utils.stringify_table(err, "Error " .. idx, true))
      end
      return
    end

    for _, light in ipairs(light_resource.data or {}) do
      if device_light_resource_id == light.id then
        Discovery.device_state_disco_cache[light.id] = {
          hue_provided_name = light.metadata.name,
          id = light.id,
          on = light.on,
          color = light.color,
          dimming = light.dimming,
          color_temperature = light.color_temperature,
          mode = light.mode,
          parent_device_id = parent_device_id or device.parent_device_id,
          hue_device_id = light.owner.rid,
          hue_device_data = {
            product_data = {
              manufacturer_name = device.manufacturer,
              model_id = device.model,
              product_name = device.vendor_provided_label
            }
          }
        }
        light_info_known = true
        break
      end
    end
  end

  -- still unable to get information about the bulb over REST API, bailing
  if not light_info_known then
    log.warn(string.format(
      "Couldn't get light info for %s, marking as \"stray\"", (device.label or device.id or "unknown device")
    ))
    driver.stray_device_tx:send({
      type = StrayDeviceHelper.MessageTypes.NewStrayDevice,
      driver = driver,
      device = device
    })
    return
  end

  ---@type HueLightInfo
  local light_info = Discovery.device_state_disco_cache[device_light_resource_id]

  -- Remembering that mirek are reciprocal to kelvin, note the following:
  --  ** Minimum Mirek -> _Maximum_ Kelvin
  --  ** Maximum Mirek -> _Minimum_ Kelvin
  --
  -- Not necessarily obvious/intuitive, but easy enough to validate with the math:
  --
  -- Given that `kelvin = 1000000 / mirek`, and `mirek = 1000000 / kelvin`, pick
  -- one of our minimum consts: `Consts.MIN_TEMP_KELVIN_COLOR_AMBIANCE = 2000`
  --
  -- `floor(1000000 / 2000) = 500` and 500 is the max mirek we see on almost all Hue lights.
  -- Similarly:
  -- `floor(1000000 / 6500) = 153`, which is the minimum we see from the API for color control lights.
  if light_info.color_temperature and light_info.color_temperature.mirek_schema then
    local caps = device.profile.components.main.capabilities
    if caps.colorTemperature then
      local min_ct_kelvin, max_ct_kelvin = nil, nil
      if type(light_info.color_temperature.mirek_schema.mirek_maximum) == "number" then
        min_ct_kelvin = math.floor(utils.mirek_to_kelvin(light_info.color_temperature.mirek_schema.mirek_maximum))
      end
      if type(light_info.color_temperature.mirek_schema.mirek_minimum) == "number" then
        max_ct_kelvin = math.floor(utils.mirek_to_kelvin(light_info.color_temperature.mirek_schema.mirek_minimum))
      end
      if not min_ct_kelvin then
        if caps.colorControl then
          min_ct_kelvin = Consts.MIN_TEMP_KELVIN_COLOR_AMBIANCE
        else
          min_ct_kelvin = Consts.MIN_TEMP_KELVIN_WHITE_AMBIANCE
        end
      end
      if not max_ct_kelvin then
        max_ct_kelvin = Consts.MAX_TEMP_KELVIN
      end
      device:set_field(Fields.MIN_KELVIN, min_ct_kelvin, { persist = true })
      device:set_field(Fields.MAX_KELVIN, max_ct_kelvin, { persist = true })
    end
  end

  -- persistent fields
  device:set_field(Fields.DEVICE_TYPE, "light", { persist = true })
  if light_info.color ~= nil and light_info.color.gamut then
    device:set_field(Fields.GAMUT, light_info.color.gamut, { persist = true })
  end
  device:set_field(Fields.HUE_DEVICE_ID, light_info.hue_device_id, { persist = true })
  device:set_field(Fields.PARENT_DEVICE_ID, light_info.parent_device_id, { persist = true })
  device:set_field(Fields.RESOURCE_ID, device_light_resource_id, { persist = true })
  device:set_field(Fields._ADDED, true, { persist = true })
  device:set_field(Fields._REFRESH_AFTER_INIT, true, { persist = true })

  driver.hue_identifier_to_device_record[device_light_resource_id] = device

  -- the refresh handler adds lights that don't have a fully initialized bridge to a queue.
  driver:inject_capability_command(device, {
    capability = capabilities.refresh.ID,
    command = capabilities.refresh.commands.refresh.NAME,
    args = {}
  })
end

---@param driver HueDriver
---@param device HueChildDevice
function LightLifecycleHandlers.init(driver, device)
  log.info(
    string.format("Init Light for device %s", (device.label or device.id or "unknown device")))

  local device_light_resource_id =
      utils.get_hue_rid(device) or
      device.device_network_id

  local hue_device_id = device:get_field(Fields.HUE_DEVICE_ID)
  if not driver.hue_identifier_to_device_record[device_light_resource_id] then
    driver.hue_identifier_to_device_record[device_light_resource_id] = device
  end
  local svc_rids_for_device = driver.services_for_device_rid[hue_device_id] or {}
  if not svc_rids_for_device[device_light_resource_id] then
    svc_rids_for_device[device_light_resource_id] = HueDeviceTypes.LIGHT
  end
  device:set_field(Fields._INIT, true, { persist = false })
  device:emit_event(capabilities.switchLevel.levelRange({ minimum = 1, maximum = 100 }))

  if device:get_field(Fields._REFRESH_AFTER_INIT) then
    driver:inject_capability_command(device, {
      capability = capabilities.refresh.ID,
      command = capabilities.refresh.commands.refresh.NAME,
      args = {}
    })
    device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  end
  driver:check_waiting_grandchildren_for_device(device)
end

return LightLifecycleHandlers
