local capabilities = require "st.capabilities"
local log = require "log"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Discovery = require "disco"
local Fields = require "fields"
local StrayDeviceHelper = require "stray_device_helper"

local utils = require "utils"

---@class LightMigrationHandler
local LightMigrationHandler = {}

---@param driver HueDriver
---@param device HueChildDevice
---@param lifecycle_handlers LifecycleHandlers
---@param parent_device_id string?
---@param hue_light_description HueLightInfo?
function LightMigrationHandler.migrate(driver, device, lifecycle_handlers, parent_device_id, hue_light_description)
  local api_key = device.data.username
  local v1_id = device.data.bulbId
  local bridge_id = driver.api_key_to_bridge_id[api_key]

  log.info_with({ hub_logs = true },
    string.format("Migrate Light for device %s with v1_id %s and bridge_id %s",
      (device.label or device.id or "unknown device"), v1_id, (bridge_id or "<not yet known>")
    )
  )

  local bridge_device = nil
  if parent_device_id ~= nil then
    bridge_device = utils.get_hue_bridge_for_device(driver, device, parent_device_id)
  end

  if not bridge_device then
    bridge_device = driver:get_device_by_dni(bridge_id)
  end

  ---@type PhilipsHueApi
  local api_instance = (bridge_device and bridge_device:get_field(Fields.BRIDGE_API))
      or (bridge_device and Discovery.disco_api_instances[bridge_device.device_network_id])
  local light_resource = hue_light_description or
      Discovery.device_state_disco_cache[utils.get_hue_rid(device) or v1_id] --[[@as HueLightInfo]]

  if not (api_instance and bridge_device and bridge_device:get_field(Fields._INIT)
        and driver.joined_bridges[bridge_id] and light_resource) then
    local bridge_dni = "not available"
    if bridge_device then bridge_dni = bridge_device.device_network_id end
    log.warn(string.format(
      'Attempting to migrate "stray" bulb before Hue Bridge network connection is fully established\n' ..
      '(bridge not added or light resource not identified).\n' ..
      '\tBulb Label: %s\n' ..
      '\tBulb DTH API KEY: %s\n' ..
      '\tBulb DTH v1_id: %s\n' ..
      '\tBulb DNI: %s\n' ..
      '\tBulb Parent Assigned Key: %s\n' ..
      '\tMaybe Bridge Id: %s\n' ..
      '\t`bridge_device` nil? %s\n' ..
      '\tBridge marked as joined? %s\n' ..
      '\tBridge Device DNI: %s',
      (device.label),
      api_key,
      v1_id,
      device.device_network_id,
      device.parent_assigned_child_key,
      bridge_id,
      (bridge_device == nil),
      driver.joined_bridges[bridge_id],
      bridge_dni
    ))
    device:set_field(Fields.RETRY_MIGRATION, true, { persist = false })
    driver.stray_device_tx:send({
      type = StrayDeviceHelper.MessageTypes.NewStrayDevice,
      driver = driver,
      device = device
    })
    return
  end

  log.info(
    string.format("Found parent bridge %s for migrated light %s, beginning update and onboard"
    , (bridge_device.label or bridge_device.device_network_id or bridge_device.id or "unknown bridge device")
    , (device.label or device.id or "unknown light device")
    )
  )

  local mismatches = {}
  local bridge_support = {}
  local profile_support = {}
  for _, cap in ipairs({
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorTemperature,
    capabilities.colorControl
  }) do
    local payload = {}
    if cap.ID == capabilities.switch.ID then
      payload = light_resource.on
    elseif cap.ID == capabilities.switchLevel.ID then
      payload = light_resource.dimming
    elseif cap.ID == capabilities.colorControl.ID then
      payload = light_resource.color
    elseif cap.ID == capabilities.colorTemperature.ID then
      payload = light_resource.color_temperature
    end

    local profile_supports = device:supports_capability_by_id(cap.ID, nil)
    local bridge_supports = driver.check_hue_repr_for_capability_support(light_resource, cap.ID)

    bridge_support[cap.NAME] = {
      supports = bridge_supports,
      payload = payload
    }
    profile_support[cap.NAME] = profile_supports

    if bridge_supports ~= profile_supports then
      table.insert(mismatches, cap.NAME)
    end
  end

  local dbg_table = {
    _mismatches = mismatches,
    _name = {
      device_label = (device.label or device.id or "unknown label"),
      hue_name = (light_resource.hue_provided_name or "no name given")
    },
    bridge_supports = bridge_support,
    profile_supports = profile_support
  }

  device.log.info_with({ hub_logs = true }, st_utils.stringify_table(
    dbg_table,
    "Comparing profile-reported capabilities to bridge reported representation",
    false
  ))

  local new_metadata = {
    manufacturer = light_resource.hue_device_data.product_data.manufacturer_name,
    model = light_resource.hue_device_data.product_data.model_id,
    vendor_provided_label = light_resource.hue_device_data.product_data.product_name,
  }
  device:try_update_metadata(new_metadata)
  device:set_field(Fields.RETRY_MIGRATION, false, { persist = false })

  log.info(string.format(
    "Migration to CLIPV2 for %s complete, going through onboarding flow again",
    (device.label or device.id or "unknown device")
  ))
  log.debug(string.format(
    "Re-requesting added handler for %s after migrating", (device.label or device.id or "unknown device")
  ))
  lifecycle_handlers.device_added(driver, device, bridge_device.id, light_resource.id)
  log.debug(string.format(
    "Re-requesting init handler for %s after migrating", (device.label or device.id or "unknown device")
  ))
  lifecycle_handlers.device_init(driver, device)
end

return LightMigrationHandler
