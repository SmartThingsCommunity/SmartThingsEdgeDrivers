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
local Discovery = require "disco"
local EventSource = require "lunchbox.sse.eventsource"
local Fields = require "hue.fields"
local handlers = require "handlers"
local HueApi = require "hue.api"
local HueColorUtils = require "hue.cie_utils"
local log = require "log"
local lunchbox_util = require "lunchbox.util"
local utils = require "utils"

local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local json = require "st.json"
local st_utils = require "st.utils"

local syncCapabilityId = "samsungim.hueSyncMode"
local hueSyncMode = capabilities[syncCapabilityId]

local StrayDeviceMessageTypes = {
  FoundBridge = "FOUND_BRIDGE",
  NewStrayLight = "NEW_STRAY_LIGHT",
}

--- minimum colortemp value from Hue
local DEFAULT_MIREK = 153

-- "forward declare" some functions
local bridge_added, light_added, _initialize

---@param light_device HueChildDevice
---@param light table
local function emit_light_status_events(light_device, light)
  if light_device ~= nil then
    if light.status then
      if light.status == "connected" then
        light_device:online()
      elseif light.status == "connectivity_issue" then
        light_device:offline()
        return
      end
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
      local adjusted_level = st_utils.clamp_value(light.dimming.brightness, 1, 100)
      light_device:emit_event(capabilities.switchLevel.level(st_utils.round(adjusted_level)))
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
      light_device:emit_event(capabilities.colorTemperature.colorTemperature(kelvin))
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

      light_device:emit_event(capabilities.colorControl.hue(st_utils.round(hue * 100)))
      light_device:emit_event(capabilities.colorControl.saturation(st_utils.round(sat * 100)))
    end
  end
end

---@param driver HueDriver
---@param device HueBridgeDevice
local function migrate_bridge(driver, device)
  local api_key = device.data.username
  local ipv4 = device.data.ip
  local device_dni = device.device_network_id

  local known_macs = {}
  known_macs[ipv4] = device_dni

  Discovery.search_for_bridges(driver, known_macs, function(hue_driver, bridge_ip, bridge_id)
    if bridge_id ~= device_dni then return end

    local bridge_info, err, _ = HueApi.get_bridge_info(bridge_ip)
    if err ~= nil or not bridge_info then
      log.error("Error querying bridge info: ", err)
      return
    end

    if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
      log.warn("Found bridge that does not support CLIP v2 API, ignoring")
      hue_driver.ignored_bridges[bridge_id] = true
      return
    end

    bridge_info.ip = bridge_ip

    hue_driver.joined_bridges[bridge_id] = bridge_info
    Discovery.api_keys[bridge_id] = api_key

    local new_metadata = {
      profile = "hue-bridge",
      manufacturer = "Signify Netherlands B.V.",
      model = bridge_info.modelid or "BSB002",
      vendor_provided_label = (bridge_info.name or "Philips Hue Bridge"),
    }

    device:try_update_metadata(new_metadata)
    log.trace("Bridge Migrated, re-adding")
    bridge_added(hue_driver, device)
  end)

  if not driver.joined_bridges[device_dni] then
    log.error_with({ hub_logs = true },
      string.format(
        "Attempted to migrate DTH Hue Bridge %s to Edge Driver but could not find a compatible bridge on the network"
        ,
        device.label))
  end
end

---@param driver HueDriver
---@param device HueBridgeDevice
local function spawn_bridge_add_api_key_task(driver, device)
  local device_bridge_id = device.device_network_id
  cosock.spawn(function()
    -- 30 seconds is the typical UX for waiting to hit the link button in the Hue ecosystem
    local timeout_time = cosock.socket.gettime() + 30
    local bridge_info = driver.joined_bridges[device_bridge_id]
    local bridge_ip = bridge_info.ip

    -- we pre-declare these variables in the outer scope so that our gotos work.
    -- a sad day that we need these gotos.
    local api_key_response, err, api_key, _
    repeat
      local time_remaining = math.max(0, timeout_time - cosock.socket.gettime())
      if time_remaining == 0 then
        log.error(
          string.format(
            "Link button not pressed or API key not received for bridge \"%s\" after 30 seconds, sleeping then trying again in a few minutes.",
            device.label
          )
        )
        cosock.socket.sleep(120)                    -- two minutes
        timeout_time = cosock.socket.gettime() + 30 -- refresh timeout time
        goto continue
      end

      api_key_response, err, _ = HueApi.request_api_key(bridge_ip)

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
      log.error("Link button not pressed or API key not received for bridge " .. device.label)
      return
    end

    Discovery.api_keys[device_bridge_id] = api_key
    _initialize(driver, device)
  end, "Hue Bridge Background Join Task")
end

---@param driver HueDriver
---@param device HueBridgeDevice
bridge_added = function(driver, device)
  local device_bridge_id = device.device_network_id

  if not driver.joined_bridges[device_bridge_id] then
    local known_macs = {}
    Discovery.search_for_bridges(driver, known_macs, function(driver, bridge_ip, bridge_id)
      if bridge_id ~= device_bridge_id then return end

      local bridge_info, err, _ = HueApi.get_bridge_info(bridge_ip)
      if err ~= nil or not bridge_info then
        log.error("Error querying bridge info: ", err)
        return
      end

      if tonumber(bridge_info.swversion or "0", 10) < HueApi.MIN_CLIP_V2_SWVERSION then
        log.warn("Found bridge that does not support CLIP v2 API, ignoring")
        driver.ignored_bridges[bridge_id] = true
        return
      end

      bridge_info.ip = bridge_ip
      driver.joined_bridges[bridge_id] = bridge_info
    end)
  end

  -- still haven't found the bridge, we're finished
  if not driver.joined_bridges[device_bridge_id] then return end

  local bridge_info = driver.joined_bridges[device_bridge_id]

  if not Discovery.api_keys[device_bridge_id] then
    log.error(
      "Received `added` lifecycle event for bridge with unknown API key, " ..
      "please press the Link Button on your Hue Bridge(s)."
    )
    -- we have to do a long poll here to give the user a chance to hit the link button on the
    -- hue bridge, so in this specific pathological case we start a new coroutine and complete
    -- the handling of the device add on a different task to free up the driver task
    spawn_bridge_add_api_key_task(driver, device)
    return
  end

  local bridge_ip = bridge_info.ip
  if device:get_field(Fields._REFRESH_AFTER_INIT) == nil then
    device:set_field(Fields._REFRESH_AFTER_INIT, true, { persist = true })
  end
  device:set_field(Fields.DEVICE_TYPE, "bridge", { persist = true })
  device:set_field(Fields.IPV4, bridge_ip, { persist = true })
  device:set_field(Fields.MODEL_ID, bridge_info.modelid, { persist = true })
  device:set_field(Fields.BRIDGE_ID, device_bridge_id, { persist = true })
  device:set_field(Fields.BRIDGE_SW_VERSION, tonumber(bridge_info.swversion or "0", 10), { persist = true })
  device:set_field(Fields.API_KEY, Discovery.api_keys[device_bridge_id], { persist = true })
  device:set_field(Fields._ADDED, true, { persist = true })
  driver.api_key_to_bridge_id[Discovery.api_keys[device_bridge_id]] = device_bridge_id
end

---@param driver HueDriver
---@param device HueChildDevice
---@param parent_device_id nil|string
local function migrate_light(driver, device, parent_device_id)
  local api_key = device.data.username
  local v1_id = device.data.bulbId

  local bridge_id = driver.api_key_to_bridge_id[api_key]

  local known_dni_to_device_map = {}
  for _, device in ipairs(driver:get_devices()) do
    local dni = device.device_network_id or device.parent_assigned_child_key
    known_dni_to_device_map[dni] = device
  end

  local bridge_device = known_dni_to_device_map[bridge_id or ""]

  if not (bridge_device and driver.joined_bridges[bridge_id] and (Discovery.api_keys[bridge_id] or api_key)) then
    log.warn("Found \"stray\" bulb without associated Hue Bridge. Waiting to see if a bridge becomes available.")
    driver.stray_bulb_tx:send({
      type = StrayDeviceMessageTypes.NewStrayLight,
      driver = driver,
      device = device
    })
    return
  end

  local bridge_ip = driver.joined_bridges[bridge_id].ip
  local api_instance = HueApi.new_bridge_manager("https://" .. bridge_ip, (Discovery.api_keys[bridge_id] or api_key))

  Discovery.search_bridge_for_supported_devices(driver, api_instance,
    function(hue_driver, svc_info, device_data)
      if not (svc_info.rid and svc_info.rtype and svc_info.rtype == "light") then return end
      if not device_data.id_v1 or device_data.id_v1:gsub("/lights/", "") ~= v1_id then return end

      local resource_id = svc_info.rid
      local light_resource, err, _ = api_instance:get_light_by_id(resource_id)
      if err ~= nil or not light_resource then
        log.error("Error getting light info: ", err)
        return
      end

      if light_resource.errors and #light_resource.errors > 0 then
        log.error("Errors found in API response:")
        for idx, err in ipairs(light_resource.errors) do
          log.error(st_utils.stringify_table(err, "Error " .. idx, true))
        end
        return
      end

      for _, light in ipairs(light_resource.data or {}) do
        local profile_ref

        if light.color then
          profile_ref =
          "white-and-color-ambiance"     -- all color light products support `white` (dimming) and `ambiance` (color temp)
        elseif light.color_temperature then
          profile_ref = "white-ambiance" -- all color temp products support `white` (dimming)
        elseif light.dimming then
          profile_ref = "white"          -- `white` refers to dimmable and includes filament bulbs
        else
          log.warn(
            string.format(
              "Light resource [%s] does not seem to be A White/White-Ambiance/White-Color-Ambiance device, currently unsupported"
              ,
              svc_info.rid
            )
          )
          return
        end
        local updated_parent_id = parent_device_id or known_dni_to_device_map[bridge_id].id
        local new_metadata = {
          profile = profile_ref,
          manufacturer = device_data.product_data.manufacturer_name,
          model = device_data.product_data.model_id,
          vendor_provided_label = device_data.product_data.product_name,
        }
        device:try_update_metadata(new_metadata)

        Discovery.light_state_disco_cache[light.id] = {
          on = light.on,
          color = light.color,
          dimming = light.dimming,
          color_temp = light.color_temperature,
          mode = light.mode,
          parent_device_id = updated_parent_id,
          hue_device_id = light.owner.rid
        }

        light_added(driver, device, updated_parent_id, resource_id)
      end
    end)
end

---@param driver HueDriver
---@param device HueChildDevice
---@param parent_device_id nil|string
---@param resource_id nil|string
light_added = function(driver, device, parent_device_id, resource_id)
  local child_key = device.parent_assigned_child_key
  local device_light_resource_id = resource_id or child_key

  if not Discovery.light_state_disco_cache[device_light_resource_id] then
    local parent_bridge = driver:get_device_info(parent_device_id or device.parent_device_id or
      device:get_field(Fields.PARENT_DEVICE_ID))
    if not parent_bridge then
      log.error(string.format(
        "Device added with parent UUID of %s but could not find a device with that UUID in the driver"
        , (device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID))))
      return
    end

    local key = parent_bridge:get_field(Fields.API_KEY)
    local bridge_ip = parent_bridge:get_field(Fields.IPV4)
    local bridge_id = parent_bridge:get_field(Fields.BRIDGE_ID)
    if not (Discovery.api_keys[bridge_id or {}] or key) then
      log.warn("Found \"stray\" bulb without associated Hue Bridge. Waiting to see if a bridge becomes available.")
      driver.stray_bulb_tx:send({
        type = StrayDeviceMessageTypes.NewStrayLight,
        driver = driver,
        device = device
      })
      return
    end

    local api_instance = Discovery.disco_api_instances[bridge_id] or
        HueApi.new_bridge_manager("https://" .. bridge_ip, (Discovery.api_keys[bridge_id] or key))

    local light_resource, err, _ = api_instance:get_light_by_id(device_light_resource_id)
    if err ~= nil or not light_resource then
      log.error("Error getting light info: ", error)
      return
    end

    if light_resource.errors and #light_resource.errors > 0 then
      log.error("Errors found in API response:")
      for idx, err in ipairs(light_resource.errors) do
        log.error(st_utils.stringify_table(err, "Error " .. idx, true))
      end
      return
    end

    for _, light in ipairs(light_resource.data or {}) do
      Discovery.light_state_disco_cache[light.id] = {
        on = light.on,
        color = light.color,
        dimming = light.dimming,
        color_temp = light.color_temperature,
        mode = light.mode,
        parent_device_id = parent_bridge.id,
        hue_device_id = light.owner.rid
      }
    end
  end

  -- still unable to get information about the bulb over REST API, bailing
  if not Discovery.light_state_disco_cache[device_light_resource_id] then return end

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

  driver.light_id_to_device[device_light_resource_id] = device
  -- the refresh handler adds lights that don't have a fully initialized bridge to a queue.
  handlers.refresh_handler(driver, device)
end

---@param driver HueDriver
---@param device HueBridgeDevice
local function init_bridge(driver, device)
  local device_bridge_id = device:get_field(Fields.BRIDGE_ID)
  local bridge_manager = device:get_field(Fields.BRIDGE_API) or Discovery.disco_api_instances[device_bridge_id]

  local ip = device:get_field(Fields.IPV4)
  local api_key = device:get_field(Fields.API_KEY)
  local bridge_url = "https://" .. ip

  if not bridge_manager then
    bridge_manager = HueApi.new_bridge_manager(bridge_url, api_key)
  end

  device:set_field(Fields.BRIDGE_API, bridge_manager, { persist = false })

  if not device:get_field(Fields.EVENT_SOURCE) then
    log.trace("Creating SSE EventSource for bridge " .. device.label)
    device:offline()
    local url_table = lunchbox_util.force_url_table(bridge_url .. "/eventstream/clip/v2")
    local eventsource = EventSource.new(
      url_table,
      { [HueApi.APPLICATION_KEY_HEADER] = api_key },
      nil
    )

    eventsource.onopen = function(msg)
      log.debug(string.format("Event Source Connection for Hue Bridge \"%s\" established, marking online", device.label))
      device:online()
    end

    eventsource.onerror = function()
      log.error(string.format("Hue Bridge \"%s\" Event Source Error", device.label))
      device:offline()
    end

    eventsource.onmessage = function(msg)
      if msg and msg.data then
        local success, events = pcall(json.decode, msg.data)

        if not success then
          log.error("Couldn't decode JSON in SSE callback: " .. events)
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
              if light_device ~= nil then
                driver.emit_light_status_events(light_device, update_data)
              end
            end
          elseif event.type == "delete" then
            for _, delete_data in ipairs(event.data) do
              if delete_data.type == "light" then
                local light_resource_id = delete_data.id
                local light_device = driver.light_id_to_device[light_resource_id]
                if light_device ~= nil then
                  log.info("Light device \"%s\" was deleted from hue bridge")
                  light_device:offline()
                end
              end
            end
          elseif event.type == "add" then
            for _, add_data in ipairs(event.data) do
              if add_data.type == "light" then
                log.info(
                  string.format(
                    "New light added to Hue Bridge \"%s\": \"%s\", " ..
                    "re-run discovery to join new lights to SmartThings",
                    device.label, st_utils.stringify_table(add_data, nil, false)
                  )
                )
              end
            end
          end
        end
      end
    end

    device:set_field(Fields.EVENT_SOURCE, eventsource, { persist = false })
  end
  device:set_field(Fields._INIT, true, { persist = false })
  local ids_to_remove = {}
  for id, light_device in ipairs(driver._lights_pending_refresh) do
    local bridge_id = light_device.parent_device_id or device:get_field(Fields.PARENT_DEVICE_ID)
    if bridge_id == device.id then
      table.insert(ids_to_remove, id)
      handlers.refresh_handler(driver, light_device)
    end
  end
  for _, id in ipairs(ids_to_remove) do
    driver._lights_pending_refresh[id] = nil
  end
  driver.stray_bulb_tx:send({
    type = StrayDeviceMessageTypes.FoundBridge,
    driver = driver,
    device = device
  })
end

---@param driver HueDriver
---@param device HueChildDevice
local function init_light(driver, device)
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
    handlers.refresh_handler(driver, device)
    device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  end
end

---@param driver HueDriver
---@param device HueDevice
local function device_init(driver, device)
  local device_type = device:get_field(Fields.DEVICE_TYPE)
  if device_type == "bridge" then
    init_bridge(driver, device)
  elseif device_type == "light" then
    init_light(driver, device)
  end
end

---@param driver HueDriver
---@param device HueDevice
---@param parent_device_id nil|string
local function device_added(driver, device, _, _, parent_device_id)
  if utils.is_dth_bridge(device) then
    migrate_bridge(driver, device)
  elseif utils.is_dth_light(device) then
    migrate_light(driver, device, parent_device_id)
    -- Don't do a refresh if it's a migration
    device:set_field(Fields._REFRESH_AFTER_INIT, false, { persist = true })
  elseif utils.is_edge_bridge(device) then
    bridge_added(driver, device)
  elseif utils.is_edge_light(device) then
    light_added(driver, device, parent_device_id)
  else
    log.warn(string.format("Device Added %s does not appear to be a bridge or bulb", device.label))
  end
end

---@param driver HueDriver
---@param device HueDevice
_initialize = function(driver, device, event, args, parent_device_id)
  if not device:get_field(Fields._ADDED) then
    device_added(driver, device, event, args, parent_device_id)
  end

  if not device:get_field(Fields._INIT) then
    device_init(driver, device)
  end
end

local stray_bulb_tx, stray_bulb_rx = cosock.channel.new()
cosock.spawn(function()
  local function process_strays(driver, api_instance, strays, bridge_device_id)
    local dnis_to_remove = {}

    Discovery.search_bridge_for_supported_devices(driver, api_instance, function(hue_driver, svc_info, device_data)
      if not (svc_info.rid and svc_info.rtype and svc_info.rtype == "light") then return end

      for light_dni, light_device in pairs(strays) do
        local matching_v1_id = light_device.data and light_device.data.bulbId and
            light_device.data.bulbId == device_data.id_v1:gsub("/lights/", "")
        local matching_uuid = light_device.device_network_id == svc_info.rid or
            light_device.device_network_id == svc_info.rid

        if matching_v1_id or matching_uuid then
          log.trace("Found Bridge for stray light ", light_device.label, ", re-adding")
          table.insert(dnis_to_remove, light_dni)
          _initialize(hue_driver, light_device, nil, nil, bridge_device_id)
        end
      end
    end)

    for _, dni in ipairs(dnis_to_remove) do
      strays[dni] = nil
    end
  end

  local stray_lights = {}
  local found_bridges = {}

  while true do
    local msg, err = stray_bulb_rx:receive()
    if err then
      log.error("Cosock Receive Error: ", err)
      goto continue
    end

    local msg_device, driver = msg.device, msg.driver
    if msg.type == StrayDeviceMessageTypes.FoundBridge then
      local bridge_ip = msg_device:get_field(Fields.IPV4)
      local api_instance =
          msg_device:get_field(Fields.BRIDGE_API) or
          HueApi.new_bridge_manager("https://" .. bridge_ip, msg_device:get_field(Fields.API_KEY))

      found_bridges[msg_device.id] = msg.device
      process_strays(driver, api_instance, stray_lights, msg_device.id)
    elseif msg.type == StrayDeviceMessageTypes.NewStrayLight then
      stray_lights[msg_device.device_network_id] = msg_device

      local maybe_bridge_id =
          msg_device.parent_device_id or msg_device:get_field(Fields.PARENT_DEVICE_ID)
      local maybe_bridge = found_bridges[maybe_bridge_id]

      if maybe_bridge ~= nil then
        local bridge_ip = maybe_bridge:get_field(Fields.IPV4)
        local api_instance =
            maybe_bridge:get_field(Fields.BRIDGE_API) or
            HueApi.new_bridge_manager("https://" .. bridge_ip, msg_device:get_field(Fields.API_KEY))
        process_strays(driver, api_instance, stray_lights, maybe_bridge.id)
      end
    end
    ::continue::
  end
end, "Stray Hue Bulb Resolution Task")

--- @type HueDriver
local hue = Driver("hue",
  {
    discovery = Discovery.discover,
    lifecycle_handlers = { added = _initialize, init = _initialize },
    capability_handlers = {
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = handlers.refresh_handler
      },
      [capabilities.switch.ID] = {
        [capabilities.switch.commands.on.NAME] = handlers.switch_on_handler,
        [capabilities.switch.commands.off.NAME] = handlers.switch_off_handler,
      },
      [capabilities.switchLevel.ID] = {
        [capabilities.switchLevel.commands.setLevel.NAME] = handlers.switch_level_handler,
      },
      [capabilities.colorControl.ID] = {
        [capabilities.colorControl.commands.setColor.NAME] = handlers.set_color_handler,
      },
      [capabilities.colorTemperature.ID] = {
        [capabilities.colorTemperature.commands.setColorTemperature.NAME] = handlers.set_color_temp_handler,
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
    emit_light_status_events = emit_light_status_events
  }
)

log.info("Starting Hue driver")
hue:run()
log.warn("Hue driver exiting")
