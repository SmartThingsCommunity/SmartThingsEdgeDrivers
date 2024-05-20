--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--
--  ===============================================================================================
--  Up to date API references are available here:
--  https://developers.meethue.com/develop/hue-api-v2/
--
--  Improvements to be made:
--
--  ===============================================================================================
local cosock = require "cosock"
local log = require "log"

local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local json = require "st.json"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: table, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Discovery = require "disco"
local EventSource = require "lunchbox.sse.eventsource"
local Fields = require "fields"
local handlers = require "handlers"
local HueApi = require "hue.api"
local HueColorUtils = require "hue.cie_utils"
local lunchbox_util = require "lunchbox.util"
local utils = require "utils"

local syncCapabilityId = "samsungim.hueSyncMode"
local hueSyncMode = capabilities[syncCapabilityId]

local StrayDeviceMessageTypes = {
  FoundBridge = "FOUND_BRIDGE",
  NewStrayLight = "NEW_STRAY_LIGHT",
}

--- minimum colortemp value from Hue
local DEFAULT_MIREK = 153

-- "forward declare" some functions
local _initialize, bridge_added, light_added, init_light, init_bridge

local function safe_wrap_handler(handler)
  return function(driver, device, ...)
    if device == nil or (device and device.id == nil) then
      log.warn("Tried to handle capability command for device that has been deleted")
      return
    end
    local success, result = pcall(handler, driver, device, ...)
    if not success then
      log.error_with({ hub_logs = true }, string.format("Failed to invoke capability command handler. Reason: %s", result))
    end
    return result
  end
end

local refresh_handler = safe_wrap_handler(handlers.refresh_handler)
local switch_on_handler = safe_wrap_handler(handlers.switch_on_handler)
local switch_off_handler = safe_wrap_handler(handlers.switch_off_handler)
local switch_level_handler = safe_wrap_handler(handlers.switch_level_handler)
local set_color_handler = safe_wrap_handler(handlers.set_color_handler)
local set_hue_handler = safe_wrap_handler(handlers.set_hue_handler)
local set_saturation_handler = safe_wrap_handler(handlers.set_saturation_handler)
local set_color_temp_handler = safe_wrap_handler(handlers.set_color_temp_handler)

---@param light_device HueChildDevice
---@param light table
local function emit_light_status_events(light_device, light)
  if light_device ~= nil then
    if light.status then
      if light.status == "connected" then
        light_device.log.info_with({hub_logs=true}, "Light status event, marking device online")
        light_device:online()
        light_device:set_field(Fields.IS_ONLINE, true)
      elseif light.status == "connectivity_issue" then
        light_device.log.info_with({hub_logs=true}, "Light status event, marking device offline")
        light_device:set_field(Fields.IS_ONLINE, false)
        light_device:offline()
        return
      end
    end

    if light_device:get_field(Fields.IS_ONLINE) ~= true then
      return
    end

    if light.mode then
      light_device:emit_event(hueSyncMode.mode(light.mode))
    end

    if light.on and light.on.on then
      light_device:emit_event(capabilities.switch.switch.on())
    elseif light.on and not light.on.on then
      light_device:emit_event(capabilities.switch.switch.off())
    end

    if light.dimming then
      local adjusted_level = st_utils.round(st_utils.clamp_value(light.dimming.brightness, 1, 100))
      if utils.is_nan(adjusted_level) then
        light_device.log.warn(
          string.format(
            "Non numeric value %s computed for switchLevel Attribute Event, ignoring.",
            adjusted_level
          )
        )
      else
        light_device:emit_event(capabilities.switchLevel.level(adjusted_level))
      end
    end

    if light.color_temperature then
      local mirek = DEFAULT_MIREK
      if light.color_temperature.mirek_valid then
        mirek = light.color_temperature.mirek
      end
      local min = light_device:get_field(Fields.MIN_KELVIN) or HueApi.MIN_TEMP_KELVIN_WHITE_AMBIANCE
      local kelvin = math.floor(
        st_utils.clamp_value(handlers.mirek_to_kelvin(mirek), min, HueApi.MAX_TEMP_KELVIN)
      )
      if utils.is_nan(kelvin) then
        light_device.log.warn(
          string.format(
            "Non numeric value %s computed for colorTemperature Attribute Event, ignoring.",
            kelvin
          )
        )
      else
        light_device:emit_event(capabilities.colorTemperature.colorTemperature(kelvin))
      end
    end

    if light.color then
      light_device:set_field(Fields.GAMUT, light.color.gamut, { persist = true })
      local r, g, b = HueColorUtils.safe_xy_to_rgb(light.color.xy, light.color.gamut)
      local hue, sat, _ = st_utils.rgb_to_hsv(r, g, b)
      -- We sent a command where hue == 100 and wrapped the value to 0, reverse that here
      if light_device:get_field(Fields.WRAPPED_HUE) == true and (hue + .05 >= 1 or hue - .05 <= 0) then
        hue = 1
        light_device:set_field(Fields.WRAPPED_HUE, false)
      end

      local adjusted_hue = st_utils.clamp_value(st_utils.round(hue * 100), 0, 100)
      local adjusted_sat = st_utils.clamp_value(st_utils.round(sat * 100), 0, 100)

      if utils.is_nan(adjusted_hue) then
        light_device.log.warn(
          string.format(
            "Non numeric value %s computed for colorControl.hue Attribute Event, ignoring.",
            adjusted_hue
          )
        )
      else
        light_device:emit_event(capabilities.colorControl.hue(adjusted_hue))
      end

      if utils.is_nan(adjusted_sat) then
        light_device.log.warn(
          string.format(
            "Non numeric value %s computed for colorControl.saturation Attribute Event, ignoring.",
            adjusted_sat
          )
        )
      else
        light_device:emit_event(capabilities.colorControl.saturation(adjusted_sat))
      end
    end
  end
end

---@param driver HueDriver
---@param device HueBridgeDevice
local function migrate_bridge(driver, device)
  log.info_with({ hub_logs = true },
    string.format("Migrate Bridge for device %s", (device.label or device.id or "unknown device")))
  local api_key = device.data.username
  local ipv4 = device.data.ip
  local device_dni = device.device_network_id

  local known_macs = {}
  known_macs[ipv4] = device_dni

  log.info(
    string.format("Rediscovering bridge for migrated device %s", (device.label or device.id or "unknown device")))
  cosock.spawn(
    function()
      local bridge_found = false
      local backoff_generator = utils.backoff_builder(10, 0.1, 0.1)
      local sleep_time = 0.1
      while true do
        log.info(
          string.format(
            "[MigrateBridge] Scanning for Hue Bridge info for migrated device %s",
            (device.label or device.id or "unknown device")
          )
        )
        Discovery.search_for_bridges(driver, known_macs, function(hue_driver, bridge_ip, bridge_id)
          if bridge_id ~= device_dni then return end

          log.info(
            string.format(
              "[MigrateBridge] Matching Hue Bridge for migrated device %s found, querying configuration values",
              (device.label or device.id or "unknown device")
            )
          )

          local bridge_info = driver.datastore.bridge_netinfo[bridge_id]

          if not bridge_info then
            log.debug(string.format("Bridge info for %s not yet available", bridge_id))
            return
          end

          if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
            log.warn("Found bridge that does not support CLIP v2 API, ignoring")
            hue_driver.ignored_bridges[bridge_id] = true
            return
          end

          hue_driver.joined_bridges[bridge_id] = true
          Discovery.api_keys[bridge_id] = api_key

          local new_metadata = {
            profile = "hue-bridge",
            manufacturer = "Signify Netherlands B.V.",
            model = bridge_info.modelid or "BSB002",
            vendor_provided_label = (bridge_info.name or "Philips Hue Bridge"),
          }

          device:try_update_metadata(new_metadata)
          log.info_with({ hub_logs = true },
            string.format("Bridge %s Migrated, re-adding", (device.label or device.id or "unknown device")))
          log.debug(string.format(
            "Re-requesting added handler for %s after migrating", (device.label or device.id or "unknown device")
          ))
          bridge_added(hue_driver, device)
          log.debug(string.format(
            "Re-requesting init handler for %s after migrating", (device.label or device.id or "unknown device")
          ))
          init_bridge(hue_driver, device)
          bridge_found = true
        end)
        if bridge_found then return end

        if sleep_time < 10 then
          sleep_time = backoff_generator()
        end
        log.warn(
          string.format(
            "[MigrateBridge] Failed to find bridge info for device %s, waiting %s seconds then trying again",
            (device.label or device.id or "unknown device"),
            sleep_time
          )
        )
        cosock.socket.sleep(sleep_time)
      end
    end,
    string.format("bridge migration thread for %s", device.label)
  )
end

---@param driver HueDriver
---@param device HueBridgeDevice
local function spawn_bridge_add_api_key_task(driver, device)
  local device_bridge_id = device.device_network_id
  cosock.spawn(function()
    -- 30 seconds is the typical UX for waiting to hit the link button in the Hue ecosystem
    local timeout_time = cosock.socket.gettime() + 30

    -- we pre-declare these variables in the outer scope so that our gotos work.
    -- a sad day that we need these gotos.
    local api_key_response, err, api_key, bridge_info, bridge_ip, _
    repeat
      local time_remaining = math.max(0, timeout_time - cosock.socket.gettime())
      if time_remaining == 0 then
        local _log = device.log or log
        _log.error_with({ hub_logs = true },
          string.format(
            "Link button not pressed or API key not received for bridge \"%s\" after 30 seconds, sleeping then trying again in a few minutes.",
            device.label
          )
        )
        cosock.socket.sleep(120)                    -- two minutes
        timeout_time = cosock.socket.gettime() + 30 -- refresh timeout time
        goto continue
      end

      if not driver.datastore.bridge_netinfo[device_bridge_id] then
        goto continue
      end

      bridge_info = driver.datastore.bridge_netinfo[device_bridge_id]
      bridge_ip = bridge_info.ip

      api_key_response, err, _ = HueApi.request_api_key(
        bridge_ip,
        utils.labeled_socket_builder((device.label or device.device_network_id or device.id or "unknown bridge"))
      )

      if err ~= nil or not api_key_response then
        log.warn("Error while trying to request Bridge API Key: ", err)
        goto continue
      end

      for _, item in ipairs(api_key_response) do
        if item.error ~= nil then
          log.warn("Error paylod in bridge API key response: " .. item.error.description)
          goto continue
        end

        api_key = item.success.username
      end

      ::continue::
      -- don't hammer the bridge since we're waiting for the user to hit the link button
      if api_key == nil then cosock.socket.sleep(2) end
    until api_key ~= nil

    if not api_key then
      log.error_with({ hub_logs = true }, "Link button not pressed or API key not received for bridge " ..
        (device.label or device.device_network_id or device.id or "unknown"))
      return
    end

    Discovery.api_keys[device_bridge_id] = api_key
    _initialize(driver, device)
  end, "Hue Bridge Background Join Task")
end

local function update_bridge_fields_from_info(driver, bridge_info, bridge_device)
  local bridge_ip = bridge_info.ip
  local device_bridge_id = bridge_device.device_network_id

  if bridge_device:get_field(Fields._REFRESH_AFTER_INIT) == nil then
    bridge_device:set_field(Fields._REFRESH_AFTER_INIT, true, { persist = true })
  end

  bridge_device:set_field(Fields.DEVICE_TYPE, "bridge", { persist = true })
  bridge_device:set_field(Fields.MODEL_ID, bridge_info.modelid, { persist = true })
  bridge_device:set_field(Fields.BRIDGE_ID, device_bridge_id, { persist = true })
  bridge_device:set_field(Fields.BRIDGE_SW_VERSION, tonumber(bridge_info.swversion or "0", 10), { persist = true })

  if Discovery.api_keys[device_bridge_id] then
    bridge_device:set_field(HueApi.APPLICATION_KEY_HEADER, Discovery.api_keys[device_bridge_id], { persist = true })
    driver.api_key_to_bridge_id[Discovery.api_keys[device_bridge_id]] = device_bridge_id
  end
  bridge_device:set_field(Fields.IPV4, bridge_ip, { persist = true })
end

---@param driver HueDriver
---@param device HueBridgeDevice
bridge_added = function(driver, device)
  log.info_with({ hub_logs = true },
    string.format("Bridge Added for device %s", (device.label or device.id or "unknown device")))
  local device_bridge_id = device.device_network_id
  local bridge_info = driver.datastore.bridge_netinfo[device_bridge_id]

  if not bridge_info then
    local known_macs = {}
    cosock.spawn(
      function()
        local backoff_generator = utils.backoff_builder(10, 0.1, 0.1)
        local sleep_time = 0.1
        local bridge_found = false

        while true do
          log.info(
            string.format(
              "[BridgeAdded] Scanning the network for Hue Bridge matching device %s",
              (device.label or device.id or "unknown device")
            )
          )
          Discovery.search_for_bridges(driver, known_macs, function(driver, bridge_ip, bridge_id)
            if bridge_id ~= device_bridge_id then return end

            log.info(string.format(
              "[BridgeAdded] Found Hue Bridge on the network for %s, querying configuration values",
              (device.label or device.id or "unknown device")
            )
            )
            local bridge_info = driver.datastore.bridge_netinfo[bridge_id]

            if not bridge_info then
              log.debug(string.format("Bridge info for %s not yet available", bridge_id))
              return
            end

            if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
              log.warn("Found bridge that does not support CLIP v2 API, ignoring")
              driver.ignored_bridges[bridge_id] = true
              return
            end

            driver.joined_bridges[bridge_id] = true
            update_bridge_fields_from_info(driver, bridge_info, device)
            device:set_field(Fields._ADDED, true, { persist = true })
            bridge_found = true
          end)
          if bridge_found then return end

          if sleep_time < 10 then
            sleep_time = backoff_generator()
          end
          log.warn(
            string.format(
              "[BridgeAdded] Failed to find bridge info for device %s, waiting %s seconds then trying again",
              (device.label or device.id or "unknown device"),
              sleep_time
            )
          )
          cosock.socket.sleep(sleep_time)
        end
      end,
      "bridge added re-scan"
    )
  else
    update_bridge_fields_from_info(driver, bridge_info, device)
    device:set_field(Fields._ADDED, true, { persist = true })
  end

  if not Discovery.api_keys[device_bridge_id] then
    log.error_with({ hub_logs = true },
      string.format(
        "Received `added` lifecycle event for bridge %s with unknown API key, " ..
        "please press the Link Button on your Hue Bridge(s).",
        (device.label or device.device_network_id or device.id or "unknown bridge")
      )
    )
    -- we have to do a long poll here to give the user a chance to hit the link button on the
    -- hue bridge, so in this specific pathological case we start a new coroutine and complete
    -- the handling of the device add on a different task to free up the driver task
    spawn_bridge_add_api_key_task(driver, device)
    return
  end
end

---@param driver HueDriver
---@param device HueChildDevice
---@param parent_device_id nil|string
---@param hue_light_description nil|table
local function migrate_light(driver, device, parent_device_id, hue_light_description)
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
    bridge_device = driver:get_device_info(parent_device_id, false)
  end

  if not bridge_device then
    bridge_device = driver:get_device_by_dni(bridge_id)
  end

  local api_instance = (bridge_device and bridge_device:get_field(Fields.BRIDGE_API))
      or (bridge_device and Discovery.disco_api_instances[bridge_device.device_network_id])
  local light_resource = hue_light_description or
      Discovery.light_state_disco_cache[(device:get_field(Fields.RESOURCE_ID))]

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
    driver.stray_bulb_tx:send({
      type = StrayDeviceMessageTypes.NewStrayLight,
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

  log.info(string.format(
    "Migration to CLIPV2 for %s complete, going through onboarding flow again",
    (device.label or device.id or "unknown device")
  ))
  log.debug(string.format(
    "Re-requesting added handler for %s after migrating", (device.label or device.id or "unknown device")
  ))
  light_added(driver, device, bridge_device.id, light_resource.id)
  log.debug(string.format(
    "Re-requesting init handler for %s after migrating", (device.label or device.id or "unknown device")
  ))
  init_light(driver, device)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param parent_device_id nil|string
---@param resource_id nil|string
light_added = function(driver, device, parent_device_id, resource_id)
  log.info(
    string.format("Light Added for device %s", (device.label or device.id or "unknown device")))
  local child_key = device.parent_assigned_child_key
  local device_light_resource_id = resource_id or child_key

  local light_info_known = (Discovery.light_state_disco_cache[device_light_resource_id] ~= nil)
  if not light_info_known then
    log.info(
      string.format("Querying device info for parent of %s", (device.label or device.id or "unknown device")))
    local parent_bridge = driver:get_device_info(parent_device_id or device.parent_device_id or
      device:get_field(Fields.PARENT_DEVICE_ID))
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
      driver.stray_bulb_tx:send({
        type = StrayDeviceMessageTypes.NewStrayLight,
        driver = driver,
        device = device
      })
      return
    end

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
        Discovery.light_state_disco_cache[light.id] = {
          hue_provided_name = light.metadata.name,
          id = light.id,
          on = light.on,
          color = light.color,
          dimming = light.dimming,
          color_temperature = light.color_temperature,
          mode = light.mode,
          parent_device_id = parent_bridge.id,
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
    driver.stray_bulb_tx:send({
      type = StrayDeviceMessageTypes.NewStrayLight,
      driver = driver,
      device = device
    })
    return
  end

  local light_info = Discovery.light_state_disco_cache[device_light_resource_id]
  local minimum_dimming = 2

  if light_info.dimming and light_info.dimming.min_dim_level then minimum_dimming = light_info.dimming.min_dim_level end

  -- persistent fields
  device:set_field(Fields.DEVICE_TYPE, "light", { persist = true })
  if light_info.color ~= nil and light_info.color.gamut then
    device:set_field(Fields.GAMUT, light_info.color.gamut, { persist = true })
  end
  device:set_field(Fields.HUE_DEVICE_ID, light_info.hue_device_id, { persist = true })
  device:set_field(Fields.MIN_DIMMING, minimum_dimming, { persist = true })
  device:set_field(Fields.PARENT_DEVICE_ID, light_info.parent_device_id, { persist = true })
  device:set_field(Fields.RESOURCE_ID, device_light_resource_id, { persist = true })
  device:set_field(Fields._ADDED, true, { persist = true })
  device:set_field(Fields._REFRESH_AFTER_INIT, true, { persist = true })

  driver.light_id_to_device[device_light_resource_id] = device

  -- the refresh handler adds lights that don't have a fully initialized bridge to a queue.
  refresh_handler(driver, device)
end

local function do_bridge_network_init(driver, bridge_device, bridge_url, api_key)
  if not bridge_device:get_field(Fields.EVENT_SOURCE) then
    log.info_with({ hub_logs = true }, "Creating SSE EventSource for bridge " ..
      (bridge_device.label or bridge_device.device_network_id or bridge_device.id or "unknown bridge"))
    local url_table = lunchbox_util.force_url_table(bridge_url .. "/eventstream/clip/v2")
    local eventsource = EventSource.new(
      url_table,
      { [HueApi.APPLICATION_KEY_HEADER] = api_key },
      nil
    )

    eventsource.onopen = function(msg)
      log.info_with({ hub_logs = true },
        string.format("Event Source Connection for Hue Bridge \"%s\" established, marking online", bridge_device.label))
      bridge_device:online()

      local bridge_api = bridge_device:get_field(Fields.BRIDGE_API)
      cosock.spawn(function()
        -- We don't want to do a scan if we're already in a discovery loop,
        -- because the event source connection will open if a bridge is discovered
        -- and we'll effectively be scanning twice.
        -- Two scans that find the same device close together can emit events close enough
        -- together that the dedupe logic at the cloud layer will get bypassed and lead to
        -- duplicate device records.
        if not Discovery.discovery_active then
          Discovery.scan_bridge_and_update_devices(driver, bridge_device:get_field(Fields.BRIDGE_ID))
        end
        local child_device_map = {}
        local children = bridge_device:get_child_list()
        local _log = bridge_device.log or log
        _log.debug(string.format("Scanning connectivity of %s child devices", #children))
        for _, device_record in ipairs(children) do
          local hue_device_id = device_record:get_field(Fields.HUE_DEVICE_ID)
          if hue_device_id ~= nil then
            child_device_map[hue_device_id] = device_record
          end
        end

        local scanned = false
        local connectivity_status, rest_err

        while true do
          if scanned then break end
          connectivity_status, rest_err = bridge_api:get_connectivity_status()
          if rest_err ~= nil then
            log.error(string.format("Couldn't query Hue Bridge %s for zigbee connectivity status for child devices: %s",
              bridge_device.label, st_utils.stringify_table(rest_err, "Rest Error", true)))
            goto continue
          end

          if connectivity_status.errors and #connectivity_status.errors > 0 then
            log.error(
              string.format(
                "Hue Bridge %s replied with the following error message(s) " ..
                "when querying child device connectivity status:",
                bridge_device.label
              )
            )
            for idx, err in ipairs(connectivity_status.errors) do
              log.error(string.format("--- %s", st_utils.stringify_table(err, string.format("Error %s:", idx), true)))
            end
            goto continue
          end

          if connectivity_status.data and #connectivity_status.data > 0 then
            scanned = true
            for _, status in ipairs(connectivity_status.data) do
              local hue_device_id = (status.owner and status.owner.rid) or ""
              log.trace(string.format("Checking connectivity status for device resource id %s", hue_device_id))
              local child_device = child_device_map[hue_device_id]
              if child_device then
                if not child_device.id then
                  child_device_map[hue_device_id] = nil
                else
                  if status.status == "connected" then
                    child_device.log.info_with({hub_logs=true}, "Marking Online after SSE Reconnect")
                    child_device:online()
                    child_device:set_field(Fields.IS_ONLINE, true)
                  elseif status.status == "connectivity_issue" then
                    child_device.log.info_with({hub_logs=true}, "Marking Offline after SSE Reconnect")
                    child_device:set_field(Fields.IS_ONLINE, false)
                    child_device:offline()
                  end
                end
              end
            end
          end

          ::continue::
        end
      end, string.format("Hue Bridge %s Zigbee Scan Task", bridge_device.label))
    end

    eventsource.onerror = function()
      log.error_with({ hub_logs = true }, string.format("Hue Bridge \"%s\" Event Source Error", bridge_device.label))

      for _, device_record in ipairs(bridge_device:get_child_list()) do
        device_record:set_field(Fields.IS_ONLINE, false)
        device_record:offline()
      end

      bridge_device:offline()
    end

    eventsource.onmessage = function(msg)
      if msg and msg.data then
        local json_result = table.pack(pcall(json.decode, msg.data))
        local success = table.remove(json_result, 1)
        local events, err = table.unpack(json_result, 1, json_result.n)

        if not success then
          log.error_with({ hub_logs = true },
            "Couldn't decode JSON in SSE callback: " .. (events or "unexpected nil from pcall catch"))
          return
        end

        if err ~= nil then
          log.error_with({ hub_logs = true }, "JSON Parsing Error: " .. err)
          return
        end

        for _, event in ipairs(events) do
          if event.type == "update" then
            for _, update_data in ipairs(event.data) do
              --- for a regular message from a light doing something normal,
              --- you get the resource id of the light service for that device in
              --- the data field
              local light_resource_id = update_data.id
              if update_data.type == "zigbee_connectivity" and update_data.owner ~= nil then
                --- zigbee connectivity messages sometimes emit with the device as the owner
                light_resource_id = driver.device_rid_to_light_rid[update_data.owner.rid]
              end
              local light_device = driver.light_id_to_device[light_resource_id]
              if light_device ~= nil  and light_device.id ~= nil then
                driver.emit_light_status_events(light_device, update_data)
              end
            end
          elseif event.type == "delete" then
            for _, delete_data in ipairs(event.data) do
              if delete_data.type == "light" then
                local light_resource_id = delete_data.id
                local light_device = driver.light_id_to_device[light_resource_id]
                if light_device ~= nil and light_device.id ~= nil then
                  log.info(
                    string.format(
                      "Light device \"%s\" was deleted from hue bridge %s",
                      (light_device.label or light_device.id or "unknown device"),
                      (bridge_device.label or bridge_device.device_network_id or bridge_device.id or "unknown bridge")
                    )
                  )
                  light_device.log.trace("Attempting to delete Device UUID " .. tostring(light_device.id))
                  driver:do_hue_light_delete(light_device)
                end
              end
            end
          elseif event.type == "add" then
            for _, add_data in ipairs(event.data) do
              if add_data.type == "light" and add_data.owner and add_data.owner.rtype == "device" then
                log.info(
                  string.format(
                    "New light added to Hue Bridge \"%s\", light properties: \"%s\"",
                    bridge_device.label, json.encode(add_data)
                  )
                )

                cosock.spawn(function()
                  local hue_api = bridge_device:get_field(Fields.BRIDGE_API)
                  if hue_api == nil then
                    local _log = bridge_device.log or log
                    _log.warn("No Hue API instance available for new light event.")
                    return
                  end

                  local hue_device_rid = add_data.owner.rid
                  local rest_resp, rest_err = hue_api:get_device_by_id(hue_device_rid)

                  if rest_err ~= nil then
                    log.error(
                      string.format(
                         "Error getting device information for new light \"%s\" with device RID %s: %s",
                        add_data.metadata.name,
                        hue_device_rid,
                        st_utils.stringify_table(rest_err)
                      )
                    )
                    return
                  end

                  if rest_resp == nil then
                    log.error("REST Response while handling New Light Event unexpectedly nil without error message")
                    return
                  end

                  if rest_resp.errors and #rest_resp.errors > 0 then
                    for _, hue_error in ipairs(rest_resp.errors) do
                      log.error_with({ hub_logs = true }, "Error in Hue API response: " .. hue_error.description)
                    end
                    return
                  end

                  local new_device_info = nil
                  for _, hue_device in ipairs(rest_resp.data or {}) do
                    for _, svc_info in ipairs(hue_device.services or {}) do
                      if svc_info.rtype == "light" and svc_info.rid == add_data.id then
                        new_device_info = hue_device
                        break
                      end
                    end
                    if new_device_info ~= nil then break end
                  end

                  if new_device_info == nil then
                    log.warn("Couldn't get all device info for new light, unable to join. Try using Scan Nearby to find new Hue lights.")
                    return
                  end

                  log.info(
                    string.format(
                      "Adding light \"%s\"",
                      add_data.metadata.name
                    )
                  )

                  local profile_ref

                  if add_data.color then
                    if add_data.color_temperature then
                      profile_ref = "white-and-color-ambiance"
                    else
                      profile_ref = "legacy-color"
                    end
                  elseif add_data.color_temperature then
                    profile_ref = "white-ambiance" -- all color temp products support `white` (dimming)
                  elseif add_data.dimming then
                    profile_ref = "white"          -- `white` refers to dimmable and includes filament bulbs
                  else
                    log.warn(
                      string.format(
                        "Light resource [%s] does not seem to be A White/White-Ambiance/White-Color-Ambiance device, currently unsupported"
                        ,
                        add_data.id
                      )
                    )
                    return
                  end

                  local create_device_msg = {
                    type = "EDGE_CHILD",
                    label = add_data.metadata.name,
                    vendor_provided_label = new_device_info.product_data.product_name,
                    profile = profile_ref,
                    manufacturer = new_device_info.product_data.manufacturer_name,
                    model = new_device_info.product_data.model_id,
                    parent_device_id = bridge_device.id,
                    parent_assigned_child_key = add_data.id,
                  }

                  Discovery.light_state_disco_cache[add_data.id] = {
                    hue_provided_name = add_data.metadata.name,
                    id = add_data.id,
                    on = add_data.on,
                    color = add_data.color,
                    dimming = add_data.dimming,
                    color_temperature = add_data.color_temperature,
                    mode = add_data.mode,
                    parent_device_id = bridge_device.id,
                    hue_device_id = add_data.owner.rid,
                    hue_device_data = new_device_info
                  }

                  driver:try_create_device(create_device_msg)
                end, "New Device Event Task")
              end
            end
          end
        end
      end
    end

    bridge_device:set_field(Fields.EVENT_SOURCE, eventsource, { persist = false })
  end
  bridge_device:set_field(Fields._INIT, true, { persist = false })
  local ids_to_remove = {}
  for id, light_device in ipairs(driver._lights_pending_refresh) do
    local bridge_id = light_device.parent_device_id or bridge_device:get_field(Fields.PARENT_DEVICE_ID)
    if bridge_id == bridge_device.id then
      table.insert(ids_to_remove, id)
      refresh_handler(driver, light_device)
    end
  end
  for _, id in ipairs(ids_to_remove) do
    driver._lights_pending_refresh[id] = nil
  end
  driver.stray_bulb_tx:send({
    type = StrayDeviceMessageTypes.FoundBridge,
    driver = driver,
    device = bridge_device
  })
end

---@param driver HueDriver
---@param device HueBridgeDevice
init_bridge = function(driver, device)
  log.info(
    string.format("Init Bridge for device %s", (device.label or device.id or "unknown device")))
  local device_bridge_id = device:get_field(Fields.BRIDGE_ID)
  local bridge_manager = device:get_field(Fields.BRIDGE_API) or Discovery.disco_api_instances[device_bridge_id]

  local ip = device:get_field(Fields.IPV4)
  local api_key = device:get_field(HueApi.APPLICATION_KEY_HEADER)
  local bridge_url = "https://" .. ip

  if not Discovery.api_keys[device_bridge_id] then
    log.debug(string.format(
      "init_bridge for %s, caching API key", (device.label or device.id or "unknown device")
    ))
    Discovery.api_keys[device_bridge_id] = api_key
  end

  if not bridge_manager then
    log.debug(string.format(
      "init_bridge for %s, creating bridge manager", (device.label or device.id or "unknown device")
    ))
    bridge_manager = HueApi.new_bridge_manager(
      bridge_url,
      api_key,
      utils.labeled_socket_builder((device.label or device_bridge_id or device.id or "unknown bridge"))
    )
    Discovery.disco_api_instances[device_bridge_id] = bridge_manager
  end
  device:set_field(Fields.BRIDGE_API, bridge_manager, { persist = false })

  if not driver.api_key_to_bridge_id[api_key] then
    log.debug(string.format(
      "init_bridge for %s, mapping API key to Bridge DNI", (device.label or device.id or "unknown device")
    ))
    driver.api_key_to_bridge_id[api_key] = device_bridge_id
  end

  if not driver.joined_bridges[device_bridge_id] then
    log.debug(string.format(
      "init_bridge for %s, cacheing bridge info", (device.label or device.id or "unknown device")
    ))
    cosock.spawn(
      function()
        local bridge_info
        -- create a very slow backoff
        local backoff_generator = utils.backoff_builder(10, 0.1, 0.1)
        local sleep_time = 0.1
        while true do
          log.info(
            string.format(
              "[BridgeInit] Querying bridge %s for configuration values",
              (device.label or device.id or "unknown device")
            )
          )
          bridge_info = driver.datastore.bridge_netinfo[device_bridge_id]

          if not bridge_info then
            log.debug(string.format("Bridge info for %s not yet available", device_bridge_id))
            goto continue
          else
            if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
              log.warn("Found bridge that does not support CLIP v2 API, ignoring")
              driver.ignored_bridges[device_bridge_id] = true
              return
            end

            log.info(string.format("Bridge info for %s received, initializing network configuration", device_bridge_id))
            driver.joined_bridges[device_bridge_id] = true
            do_bridge_network_init(driver, device, bridge_url, api_key)
            return
          end

          ::continue::
          if sleep_time < 10 then
            sleep_time = backoff_generator()
          end
          log.warn(
            string.format(
              "[BridgeInit] Failed to find bridge info for device %s, waiting %s seconds then trying again",
              (device.label or device.id or "unknown device"),
              sleep_time
            )
          )
          cosock.socket.sleep(sleep_time)
        end
      end,
      "bridge init"
    )
  else
    do_bridge_network_init(driver, device, bridge_url, api_key)
  end
end

---@param driver HueDriver
---@param device HueChildDevice
init_light = function(driver, device)
  log.info(
    string.format("Init Light for device %s", (device.label or device.id or "unknown device")))
  local caps = device.profile.components.main.capabilities
  if caps.colorTemperature then
    if caps.colorControl then
      device:set_field(Fields.MIN_KELVIN, HueApi.MIN_TEMP_KELVIN_COLOR_AMBIANCE, { persist = true })
    else
      device:set_field(Fields.MIN_KELVIN, HueApi.MIN_TEMP_KELVIN_WHITE_AMBIANCE, { persist = true })
    end
  end
  local device_light_resource_id = device:get_field(Fields.RESOURCE_ID) or device.parent_assigned_child_key or
      device.device_network_id
  local hue_device_id = device:get_field(Fields.HUE_DEVICE_ID)
  if not driver.light_id_to_device[device_light_resource_id] then
    driver.light_id_to_device[device_light_resource_id] = device
  end
  if not driver.device_rid_to_light_rid[hue_device_id] then
    driver.device_rid_to_light_rid[hue_device_id] = device_light_resource_id
  end
  device:set_field(Fields._INIT, true, { persist = false })
  if device:get_field(Fields._REFRESH_AFTER_INIT) then
    refresh_handler(driver, device)
    device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  end
end

---@param driver HueDriver
---@param device HueDevice
local function device_init(driver, device)
  local device_type = device:get_field(Fields.DEVICE_TYPE)
  log.info(
    string.format("device_init for device %s, device_type: %s", (device.label or device.id or "unknown device"),
      device_type))
  if device_type == "bridge" then
    init_bridge(driver, device --[[@as HueBridgeDevice]])
  elseif device_type == "light" then
    init_light(driver, device --[[@as HueChildDevice]])
  end
end

---@param driver HueDriver
---@param device HueDevice
---@param parent_device_id nil|string
local function device_added(driver, device, _, _, parent_device_id)
  log.info(
    string.format("device_added for device %s", (device.label or device.id or "unknown device")))
  if utils.is_dth_bridge(device) then
    migrate_bridge(driver, device --[[@as HueBridgeDevice]])
  elseif utils.is_dth_light(device) then
    migrate_light(driver, device --[[@as HueChildDevice]], parent_device_id)
    -- Don't do a refresh if it's a migration
    device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  elseif utils.is_edge_bridge(device) then
    bridge_added(driver, device --[[@as HueBridgeDevice]])
  elseif utils.is_edge_light(device) then
    light_added(driver, device --[[@as HueChildDevice]], parent_device_id)
  else
    log.warn(
      st_utils.stringify_table(device,
        string.format("Device Added %s does not appear to be a bridge or bulb",
          device.label or device.id or "unknown device"), true)
    )
  end
end

---@param driver HueDriver
---@param device HueDevice
_initialize = function(driver, device, event, args, parent_device_id)
  local maybe_device = driver:get_device_by_dni(device.device_network_id)
  if not (
        maybe_device
        and maybe_device.id == device.id
      )
  then
    driver.datastore.dni_to_device_id[device.device_network_id] = device.id
  end

  log.info(
    string.format("_initialize handling event %s for device %s", event, (device.label or device.id or "unknown device")))
  if not device:get_field(Fields._ADDED) then
    log.debug(
      string.format(
        "_ADDED for device %s not set while _initialize is handling %s, performing added lifecycle operations",
        (device.label or device.id or "unknown device"), event))
    device_added(driver, device, event, args, parent_device_id)
  end

  if not device:get_field(Fields._INIT) then
    log.debug(
      string.format(
        "_INIT for device %s not set while _initialize is handling %s, performing device init lifecycle operations",
        (device.label or device.id or "unknown device"), event))
    device_init(driver, device)
  end
end

local disco = Discovery.discover
local added = safe_wrap_handler(_initialize)
local init = safe_wrap_handler(_initialize)

local stray_bulb_tx, stray_bulb_rx = cosock.channel.new()
stray_bulb_rx:settimeout(30)

cosock.spawn(function()
  local stray_lights = {}
  local stray_dni_to_rid = {}
  local found_bridges = {}
  local thread_local_driver = nil

  local process_strays = function(driver, strays, bridge_device_uuid)
    local dnis_to_remove = {}

    for light_dni, light_device in pairs(strays) do
      local light_rid = stray_dni_to_rid[light_dni]
      local cached_light_description = Discovery.light_state_disco_cache[light_rid]
      if cached_light_description then
        table.insert(dnis_to_remove, light_dni)
        migrate_light(driver, light_device, bridge_device_uuid, cached_light_description)
      end
    end

    for _, dni in ipairs(dnis_to_remove) do
      strays[dni] = nil
    end
  end

  while true do
    local msg, err = stray_bulb_rx:receive()
    if err and err ~= "timeout" then
      log.error_with({ hub_logs = true }, "Cosock Receive Error: ", err)
      goto continue
    end

    if err == "timeout" then
      if next(stray_lights) ~= nil and next(found_bridges) ~= nil and thread_local_driver ~= nil then
        log.info_with({ hub_logs = true },
          "No new stray lights received but some remain in queue, attempting to resolve remaining stray lights")
        for _, bridge in pairs(found_bridges) do
          stray_bulb_tx:send({
            type = StrayDeviceMessageTypes.FoundBridge,
            driver = thread_local_driver,
            device = bridge
          })
        end
      end
      goto continue
    end

    do
      local msg_device = msg.device
      thread_local_driver = msg.driver
      if msg.type == StrayDeviceMessageTypes.FoundBridge then
        local bridge_ip = msg_device:get_field(Fields.IPV4)
        local api_instance =
            msg_device:get_field(Fields.BRIDGE_API)
            or Discovery.disco_api_instances[msg_device.device_network_id]

        if not api_instance then
          api_instance = HueApi.new_bridge_manager(
            "https://" .. bridge_ip,
            msg_device:get_field(HueApi.APPLICATION_KEY_HEADER),
            utils.labeled_socket_builder((msg_device.label or msg_device.device_network_id or msg_device.id or "unknown bridge"))
          )
          Discovery.disco_api_instances[msg_device.device_network_id] = api_instance
        end

        found_bridges[msg_device.id] = msg.device
        local bridge_device_uuid = msg_device.id

        -- TODO: We can optimize around this by keeping track of whether or not this bridge
        -- needs to be scanned (maybe skip scanning if there are no stray lights?)
        --
        -- @doug.stephen@smartthings.com
        log.info(
          string.format(
            "Stray light handler notified of new bridge %s, scanning bridge",
            (msg.device.label or msg.device.device_network_id or msg.device.id or "unknown bridge")
          )
        )
        Discovery.search_bridge_for_supported_devices(thread_local_driver, msg_device:get_field(Fields.BRIDGE_ID), api_instance,
          function(hue_driver, svc_info, device_data)
            if not (svc_info.rid and svc_info.rtype and svc_info.rtype == "light") then return end

            local device_light_resource_id = svc_info.rid
            local light_resource, rest_err, _ = api_instance:get_light_by_id(device_light_resource_id)
            if rest_err ~= nil or not light_resource then
              log.error_with({ hub_logs = true }, string.format(
                "Error getting light info while processing new bridge %s",
                (msg_device.label or msg_device.id or "unknown device"), rest_err
              ))
              return
            end

            if light_resource.errors and #light_resource.errors > 0 then
              log.error_with({ hub_logs = true }, "Errors found in API response:")
              for idx, resource_err in ipairs(light_resource.errors) do
                log.error_with({ hub_logs = true }, string.format(
                  "Error Number %s in get_light_by_id response while onboarding bridge %s: %s",
                  idx,
                  (msg_device.label or msg_device.id or "unknown device"),
                  st_utils.stringify_table(resource_err)
                ))
              end
              return
            end

            if light_resource.data and #light_resource.data > 0 then
              for _, light in ipairs(light_resource.data) do
                local light_resource_description = {
                  hue_provided_name = device_data.metadata.name,
                  id = light.id,
                  on = light.on,
                  color = light.color,
                  dimming = light.dimming,
                  color_temperature = light.color_temperature,
                  mode = light.mode,
                  parent_device_id = bridge_device_uuid,
                  hue_device_id = light.owner.rid,
                  hue_device_data = device_data
                }
                if not Discovery.light_state_disco_cache[light.id] then
                  log.info(string.format("Caching previously unknown light service description for %s",
                    device_data.metadata.name))
                  Discovery.light_state_disco_cache[light.id] = light_resource_description
                end
              end
            end

            for stray_dni, stray_light in pairs(stray_lights) do
              local matching_v1_id = stray_light.data and stray_light.data.bulbId and
                  stray_light.data.bulbId == device_data.id_v1:gsub("/lights/", "")
              local matching_uuid = stray_light.parent_assigned_child_key == svc_info.rid or
                  stray_light.device_network_id == svc_info.rid

              if matching_v1_id or matching_uuid then
                local api_key_extracted = api_instance.headers["hue-application-key"]
                log.info_with({ hub_logs = true }, " ", (stray_light.label or stray_light.id or "unknown light"),
                  ", re-adding")
                log.info_with({ hub_logs = true }, string.format(
                  'Found Bridge for stray light %s, retrying onboarding flow.\n' ..
                  '\tMatching v1 id? %s\n' ..
                  '\tMatching uuid? %s\n' ..
                  '\tlight_device DNI: %s\n' ..
                  '\tlight_device Parent Assigned Key: %s\n' ..
                  '\tlight_device parent device id: %s\n' ..
                  '\tProvided bridge_device_id: %s\n' ..
                  '\tAPI key cached for given bridge_device_id? %s\n' ..
                  '\tCached bridge device for given API key: %s\n'
                  ,
                  stray_light.label,
                  matching_v1_id,
                  matching_uuid,
                  stray_light.device_network_id,
                  stray_light.parent_assigned_child_key,
                  stray_light.parent_device_id,
                  bridge_device_uuid,
                  (Discovery.api_keys[hue_driver:get_device_info(bridge_device_uuid).device_network_id] ~= nil),
                  hue_driver.api_key_to_bridge_id[api_key_extracted]
                ))
                stray_dni_to_rid[stray_dni] = svc_info.rid
                break
              end
            end
          end,
          "[process_strays]"
        )
        log.info(string.format(
          "Finished querying bridge %s for devices from stray light handler",
          (msg.device.label or msg.device.device_network_id or msg.device.id or "unknown bridge")
        )
        )
        process_strays(thread_local_driver, stray_lights, msg_device.id)
      elseif msg.type == StrayDeviceMessageTypes.NewStrayLight then
        stray_lights[msg_device.device_network_id] = msg_device

        local maybe_bridge_id =
            msg_device.parent_device_id or msg_device:get_field(Fields.PARENT_DEVICE_ID)
        local maybe_bridge = found_bridges[maybe_bridge_id]

        if maybe_bridge ~= nil then
          local bridge_ip = maybe_bridge:get_field(Fields.IPV4)
          local api_instance =
              maybe_bridge:get_field(Fields.BRIDGE_API)
              or Discovery.disco_api_instances[maybe_bridge.device_network_id]

          if not api_instance then
            api_instance = HueApi.new_bridge_manager(
              "https://" .. bridge_ip,
              maybe_bridge:get_field(HueApi.APPLICATION_KEY_HEADER),
              utils.labeled_socket_builder((maybe_bridge.label or maybe_bridge.device_network_id or maybe_bridge.id or "unknown bridge"))
            )
            Discovery.disco_api_instances[maybe_bridge.device_network_id] = api_instance
          end

          process_strays(thread_local_driver, stray_lights, maybe_bridge.id)
        end
      end
    end
    ::continue::
    if next(stray_lights) ~= nil then
      local stray_lights_pseudo_json = "{\"stray_bulbs\":["
      for dni, light in pairs(stray_lights) do
        stray_lights_pseudo_json = stray_lights_pseudo_json ..
            string.format(
              [[{"label":"%s","dni":"%s","device_id":"%s"},]],
              (light.label or light.id or "unknown light"),
              dni,
              light.id
            )
      end
      -- strip trailing comma and close array/root object
      stray_lights_pseudo_json = stray_lights_pseudo_json:sub(1, -2) .. "]}"
      log.info_with({ hub_logs = true },
        string.format("Stray light loop end, unprocessed lights: %s", stray_lights_pseudo_json))
    end
  end
end, "Stray Hue Bulb Resolution Task")


local function remove(driver, device)
  driver.datastore.dni_to_device_id[device.device_network_id] = nil
  if device:get_field(Fields.DEVICE_TYPE) == "bridge" then
    local api_instance = device:get_field(Fields.BRIDGE_API)
    if api_instance then
      api_instance:shutdown()
      device:set_field(Fields.BRIDGE_API, nil)
    end

    local event_source = device:get_field(Fields.EVENT_SOURCE)
    if event_source then
      event_source:close()
      device:set_field(Fields.EVENT_SOURCE, nil)
    end

    Discovery.api_keys[device.device_network_id] = nil
  end
end

local function supports_switch(hue_repr)
  return
      hue_repr.on ~= nil
      and type(hue_repr.on) == "table"
      and type(hue_repr.on.on) == "boolean"
end

local function supports_switch_level(hue_repr)
  return
      hue_repr.dimming ~= nil
      and type(hue_repr.dimming) == "table"
      and type(hue_repr.dimming.brightness) == "number"
end

local function supports_color_temp(hue_repr)
  return
      hue_repr.color_temperature ~= nil
      and type(hue_repr.color_temperature) == "table"
      and next(hue_repr.color_temperature) ~= nil
end

local function supports_color_control(hue_repr)
  return
      hue_repr.color ~= nil
      and type(hue_repr.color) == "table"
      and type(hue_repr.color.xy) == "table"
      and type(hue_repr.color.gamut) == "table"
end

local support_check_handlers = {
  [capabilities.switch.ID] = supports_switch,
  [capabilities.switchLevel.ID] = supports_switch_level,
  [capabilities.colorControl.ID] = supports_color_control,
  [capabilities.colorTemperature.ID] = supports_color_temp
}

--- @type HueDriver
local hue = Driver("hue",
  {
    discovery = disco,
    lifecycle_handlers = { added = added, init = init, removed = remove },
    capability_handlers = {
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
      },
      [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = switch_on_handler,
        [capabilities.switch.commands.off.NAME] = switch_off_handler,
      },
      [capabilities.switchLevel.ID] = {
        [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler,
      },
      [capabilities.colorControl.ID] = {
        [capabilities.colorControl.commands.setColor.NAME] = set_color_handler,
        [capabilities.colorControl.commands.setHue.NAME] = set_hue_handler,
        [capabilities.colorControl.commands.setSaturation.NAME] = set_saturation_handler,
      },
      [capabilities.colorTemperature.ID] = {
        [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temp_handler,
      },
    },
    ignored_bridges = {},
    joined_bridges = {},
    light_id_to_device = {},
    device_rid_to_light_rid = {},
    -- the only real way we have to know which bridge a bulb wants to use at migration time
    -- is by looking at the stored api key so we will make a map to look up bridge IDs with
    -- the API key as the map key.
    api_key_to_bridge_id = {},
    stray_bulb_tx = stray_bulb_tx,
    _lights_pending_refresh = {},
    emit_light_status_events = function(light_device, light_table)
      if light_device == nil or (light_device and light_device.id == nil) then
        log.warn("Tried to emit light status event for device that has been deleted")
        return
      end
      local success, result = pcall(emit_light_status_events, light_device, light_table)
      if not success then
        log.error_with({ hub_logs = true }, string.format("Failed to invoke emit light status handler. Reason: %s", result))
      end
      return result
    end,
    do_hue_light_delete = function(driver, device)
      if type(driver.try_delete_device) ~= "function" then
        local _log = device.log or log
        _log.warn("Requesting device delete on API version that doesn't support it. Marking device offline.")
        device:offline()
        return
      end

      driver:try_delete_device(device.id)
    end,
    check_hue_repr_for_capability_support = function(hue_repr, capability_id)
      local handler = support_check_handlers[capability_id]
      if type(handler) == "function" then
        return handler(hue_repr)
      else
        return false
      end
    end,
    update_bridge_netinfo = function(self, bridge_id, bridge_info)
      if self.joined_bridges[bridge_id] then
        local bridge_device = self:get_device_by_dni(bridge_id)
        if not bridge_device then
          log.warn_with({ hub_logs = true },
            string.format(
              "Couldn't locate bridge device for joined bridge with DNI %s",
              bridge_id
            )
          )
          return
        end

        if bridge_info.ip ~= bridge_device:get_field(Fields.IPV4) then
          update_bridge_fields_from_info(self, bridge_info, bridge_device)
          local maybe_api_client = bridge_device:get_field(Fields.BRIDGE_API)
          local maybe_api_key = bridge_device:get_field(HueApi.APPLICATION_KEY_HEADER) or Discovery.api_keys[bridge_id]
          local maybe_event_source = bridge_device:get_field(Fields.EVENT_SOURCE)
          local bridge_url = "https://" .. bridge_info.ip

          if maybe_api_key then
            if maybe_api_client then
              maybe_api_client:update_connection(bridge_url, maybe_api_key)
            end

            if maybe_event_source then
              maybe_event_source:close()
              bridge_device:set_field(Fields.EVENT_SOURCE, nil)
              do_bridge_network_init(self, bridge_device, bridge_url, maybe_api_key)
            end
          end
        end
      end
    end,
    get_device_by_dni = function(self, dni, force_refresh)
      local device_uuid = self.datastore.dni_to_device_id[dni]
      if not device_uuid then return nil end
      return self:get_device_info(device_uuid, force_refresh)
    end
  }
)

if hue.datastore["bridge_netinfo"] == nil then
  hue.datastore["bridge_netinfo"] = {}
end

if hue.datastore["dni_to_device_id"] == nil then
  hue.datastore["dni_to_device_id"] = {}
end


if hue.datastore["api_keys"] == nil then
  hue.datastore["api_keys"] = {}
end

Discovery.api_keys = setmetatable({}, {
  __newindex = function (self, k, v)
    assert(
      type(v) == "string" or type(v) == "nil",
      string.format("Attempted to store value of type %s in application_key table which expects \"string\" types",
        type(v)
      )
    )
    hue.datastore.api_keys[k] = v
    hue.datastore:save()
  end,
  __index = function(self, k)
    return hue.datastore.api_keys[k]
  end
})

-- Kick off a scan right away to attempt to populate some information
hue:call_with_delay(3, Discovery.do_mdns_scan, "Philips Hue mDNS Initial Scan")

-- re-scan every minute
local MDNS_SCAN_INTERVAL_SECONDS = 600
hue:call_on_schedule(MDNS_SCAN_INTERVAL_SECONDS, Discovery.do_mdns_scan, "Philips Hue mDNS Scan Task")

log.info("Starting Hue driver")
hue:run()
log.warn("Hue driver exiting")
