local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local device_lib = require "st.device"

local cubeAction = capabilities["stse.cubeAction"]
local cubeFace = capabilities["stse.cubeFace"]

local COMPONENT_TO_ENDPOINT_MAP_BUTTON = "__component_to_endpoint_map_button"
local DEFERRED_CONFIGURE = "__DEFERRED_CONFIGURE"
local DOING_CONFIGURE = "__DOING_CONFIGURE"
local INITIAL_PRESS_ONLY = "__initial_press_only" -- for devices that support MS (MomentarySwitch), but not MSR (MomentarySwitchRelease)

-- after 3 seconds of cubeAction, to automatically change the action status of Plugin UI or Device Card to noAction
local CUBEACTION_TIMER = "__cubeAction_timer"
local CUBEACTION_TIME = 3

local function is_aqara_cube(opts, driver, device)
  -- device.label is a value that can be changed by the user,
  -- so it is changed to read only value(device.manufacturer_info.product_name).
  local name = string.format("%s", device.manufacturer_info.product_name)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
    string.find(name, "Aqara Cube T1 Pro") then
      return true
  end
  return false
end

local callback_timer = function(device)
  return function()
    device:emit_event(cubeAction.cubeAction("noAction"))
  end
end

local function reset_thread(device)
  local timer = device:get_field(CUBEACTION_TIMER)
  if timer then
    device.thread:cancel_timer(timer)
    device:set_field(CUBEACTION_TIMER, nil)
  end
  device:set_field(CUBEACTION_TIMER, device.thread:call_with_delay(CUBEACTION_TIME, callback_timer(device)))
end

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, persist)
  device:set_field(string.format("%s_%d", field, endpoint), value, {persist = persist})
end

-- The endpoints of each face may increase sequentially, but may increase as in [250, 251, 2, 3, 4, 5]
-- and the current device:get_endpoints function is valid only for the former so, adds this function.
local function get_reordered_endpoints(driver, device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    local MS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    -- find the default/main endpoint, the device with the lowest EP that supports MS
    table.sort(MS)
    if MS[6] < (MS[1] + 150) then
      -- When the endpoints of each face increase sequentially
      -- The lowest EP is the main endpoint
      -- as a workaround, it is assumed that the first endpoint number and the last endpoint number are not larger than 150.
      return MS
    else
      -- When the endpoints of each face do not increase sequentially... [250, 251, 2, 3, 4, 5] 250 is the main endpoint.
      -- For the situation where a node following these mechanisms has exhausted all available 65535 endpoint addresses for exposed entities,
      -- it MAY wrap around to the lowest unused endpoint address (refter to Matter Core Spec 9.2.4. Dynamic Endpoint Allocation)
      local ept1 = {}   -- First consecutive end points
      local ept2 = {}   -- Second consecutive end points
      local idx1 = 1
      local idx2 = 1
      local flag = 0
      local previous = 0
      for _, ep in ipairs(MS) do
        if idx1 == 1 then
          ept1[idx1] = ep
        else
          if flag == 0
            and ep <= (previous + 15) then
            -- the endpoint number does not always increase by 1
            -- as a workaround, assume that the next endpoint number is not greater than 15
            ept1[idx1] = ep
          else
            ept2[idx2] = ep
            idx2 = idx2 + 1
            if flag ~= 1 then
              flag = 1
            end
          end
        end
        idx1 = idx1 + 1
        previous = ep
      end

      local start = #ept2 + 1
      idx1 = 1
      idx2 = start
      for i=start, 6 do
        ept2[idx2] = ept1[idx1]
        idx1 = idx1 + 1
        idx2 = idx2 + 1
      end
      return ept2
    end
  end
end

local function endpoint_to_component(device, endpoint)
  return "main"
end

-- This is called either on add for parent/child devices, or after the device profile changes for components
local function configure_buttons(device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    local MS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    device.log.debug(#MS.." momentary switch endpoints")
    for _, ep in ipairs(MS) do
      -- device only supports momentary switch, no release events
      device.log.debug("configuring for press event only")
      set_field_for_endpoint(device, INITIAL_PRESS_ONLY, ep, true, true)
    end
  end
end

local function device_added(driver, device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    local MS = get_reordered_endpoints(driver, device)
    local main_endpoint = device.MATTER_DEFAULT_ENDPOINT
    if #MS > 0 then
      main_endpoint = MS[1] -- the endpoint matching to the non-child device
      if MS[1] == 0 then main_endpoint = MS[2] end -- we shouldn't hit this, but just in case
    end
    device.log.debug("main button endpoint is "..main_endpoint)

    -- At the moment, we're taking it for granted that all momentary switches only have 2 positions
    local current_component_number = 1
    local component_map = {}
    for _, ep in ipairs(MS) do -- for each momentary switch endpoint (including main)
      device.log.debug("Configuring endpoint "..ep)
      -- build the mapping of endpoints to components
      component_map[string.format("%d", current_component_number)] = ep
      current_component_number = current_component_number + 1
    end

    device:set_field(COMPONENT_TO_ENDPOINT_MAP_BUTTON, component_map, {persist = true})
    device:try_update_metadata({profile = "cube-t1-pro"})
    device:set_field(DEFERRED_CONFIGURE, true)
  end
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id
    and device:get_field(DEFERRED_CONFIGURE)
    and device.network_type ~= device_lib.NETWORK_TYPE_CHILD then

    -- At the time of device_added, there is an error that the corresponding capability cannot be found
    -- because the profile has not been changed from the generic profile of fingerprint to the Aqara Cube.
    reset_thread(device)
    device:emit_event(cubeFace.cubeFace("face1Up"))

    device:set_field(DEFERRED_CONFIGURE, nil)

    -- In the current test framework, the values of device.profile.id and args.old_st_store.profile.id are always the same,
    -- so the test coverage cannot be increased. This is why I added DOING_CONFIGURE flag.
    device:set_field(DOING_CONFIGURE, true)
  end

  if device:get_field(DOING_CONFIGURE) then
    -- profile has changed, and we deferred setting up our buttons, so do that now
    configure_buttons(device)
    device:set_field(DOING_CONFIGURE, nil)
  end
end

local function device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    device:subscribe()
    device:set_endpoint_to_component_fn(endpoint_to_component)

    -- to read the capability again when the driver is updated with a new capability.
    device_added(driver, device)
  end
end

local function initial_press_event_handler(driver, device, ib, response)
  if get_field_for_endpoint(device, INITIAL_PRESS_ONLY, ib.endpoint_id) then
    local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP_BUTTON) or {}
    local face = 1
    for component, ep in pairs(map) do
      if map[component] == ib.endpoint_id then
        face = component
        break
      end
    end

    reset_thread(device)
    device:emit_event(cubeAction.cubeAction(string.format("flipToSide%d", face)))
    device:emit_event(cubeFace.cubeFace(string.format("face%dUp", face)))
  end
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local aqara_cube_handler = {
  NAME = "Aqara Cube Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed
  },
  matter_handlers = {
    attr = {
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler
      }
    },
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = initial_press_event_handler
      }
    },
  },
  can_handle = is_aqara_cube
}

return aqara_cube_handler

