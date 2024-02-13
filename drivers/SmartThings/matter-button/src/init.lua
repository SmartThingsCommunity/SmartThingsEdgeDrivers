local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.generated.zap_clusters"
local MatterDriver = require "st.matter.driver"
local lua_socket = require "socket"
local device_lib = require "st.device"

local START_BUTTON_PRESS = "__start_button_press"
local TIMEOUT_THRESHOLD = 10 --arbitrary timeout
local HELD_THRESHOLD = 1
-- this is the number of buttons for which we have a static profile already made
local STATIC_PROFILE_SUPPORTED = {2, 4, 6, 8}

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local DEFERRED_CONFIGURE = "__DEFERRED_CONFIGURE"

-- Some switches will send a MultiPressComplete event as part of a long press sequence. Normally the driver will create a
-- button capability event on receipt of MultiPressComplete, but in this case that would result in an extra event because
-- the "held" capability event is generated when the LongPress event is received. The IGNORE_NEXT_MPC flag is used
-- to tell the driver to ignore MultiPressComplete if it is received after a long press to avoid this extra event.
local IGNORE_NEXT_MPC = "__ignore_next_mpc"

-- These are essentially storing the supported features of a given endpoint
-- TODO: add an is_feature_supported_for_endpoint function to matter.device that takes an endpoint
local EMULATE_HELD = "__emulate_held" -- for non-MSR (MomentarySwitchRelease) devices we can emulate this on the software side
local SUPPORTS_MULTI_PRESS = "__multi_button" -- for MSM devices (MomentarySwitchMultiPress), create an event on receipt of MultiPressComplete
local INITIAL_PRESS_ONLY = "__initial_press_only" -- for devices that support MS (MomentarySwitch), but not MSR (MomentarySwitchRelease)

local HUE_MANUFACTURER_ID = 0x100B

--helper function to create list of multi press values
local function create_multi_list(size, supportsHeld)
  local list = {"pushed", "double"}
  if supportsHeld then table.insert(list, "held") end
  for i=3, size do
    table.insert(list, string.format("pushed_%dx", i))
  end
  return list
end

local function contains(array, value)
  for _, element in ipairs(array) do
    if element == value then
      return true
    end
  end
  return false
end

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, persist)
  device:set_field(string.format("%s_%d", field, endpoint), value, {persist = persist})
end

local function init_press(device, endpoint)
  set_field_for_endpoint(device, START_BUTTON_PRESS, endpoint, lua_socket.gettime(), false)
end

local function emulate_held_event(device, ep)
  local now = lua_socket.gettime()
  local press_init = get_field_for_endpoint(device, START_BUTTON_PRESS, ep) or now -- if we don't have an init time, assume instant release
  if (now - press_init) < TIMEOUT_THRESHOLD then
    if (now - press_init) > HELD_THRESHOLD then
      device:emit_event_for_endpoint(ep, capabilities.button.button.held({state_change = true}))
    else
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = true}))
    end
  end
  set_field_for_endpoint(device, START_BUTTON_PRESS, ep, nil, false)
end

--end of helper functions
--------------------------------------------------------------------------
local function find_default_endpoint(device, component)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(clusters.Switch.ID)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      res = v
      break
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function endpoint_to_component(device, endpoint)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, ep in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function component_to_endpoint(device, component_name)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component_name] then
    return map[component_name]
  end
  return find_default_endpoint(device)
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    device:subscribe()
    device:set_find_child(find_child)
    device:set_endpoint_to_component_fn(endpoint_to_component)
    device:set_component_to_endpoint_fn(component_to_endpoint)
  end
end

-- This is called either on add for parent/child devices, or after the device profile changes for components
local function configure_buttons(device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    local MS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    local MSR = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE})
    device.log.debug(#MSR.." momentary switch release endpoints")
    local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
    device.log.debug(#MSL.." momentary switch long press endpoints")
    local MSM = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS})
    device.log.debug(#MSM.." momentary switch multi press endpoints")
    for _, ep in ipairs(MS) do
      local supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
      -- this ordering is important, as MSL & MSM devices must also support MSR
      if contains(MSM, ep) then
        -- ask the device to tell us its max number of presses
        device.log.debug("sending multi press max read")
        device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep))
        set_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ep, true, true)
        supportedButtonValues_event = nil -- deferred until max press handler
      elseif contains(MSL, ep) then
        device.log.debug("configuring for long press device")
      elseif contains(MSR, ep) then
        device.log.debug("configuring for emulated held")
        set_field_for_endpoint(device, EMULATE_HELD, ep, true, true)
      else -- device only supports momentary switch, no release events
        device.log.debug("configuring for press event only")
        supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})
        set_field_for_endpoint(device, INITIAL_PRESS_ONLY, ep, true, true)
      end

      if supportedButtonValues_event then
        device:emit_event_for_endpoint(ep, supportedButtonValues_event)
      end
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = false}))
    end
  end
end

local function device_added(driver, device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    local MS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    device.log.debug(#MS.." momentary switch endpoints")
    -- local LS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.LATCHING_SWITCH})

    -- find the default/main endpoint, the device with the lowest EP that supports MS
    table.sort(MS)
    local main_endpoint = device.MATTER_DEFAULT_ENDPOINT
    if #MS > 0 then
      main_endpoint = MS[1] -- the endpoint matching to the non-child device
      if MS[1] == 0 then main_endpoint = MS[2] end -- we shouldn't hit this, but just in case
    end
    device.log.debug("main button endpoint is "..main_endpoint)

    local battery_support = false
    if device.manufacturer_info.vendor_id ~= HUE_MANUFACTURER_ID and
            #device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}) > 0 then
      battery_support = true
    end

    local new_profile = nil
    -- We have a static profile that will work for this number of buttons
    if contains(STATIC_PROFILE_SUPPORTED, #MS) then
      if battery_support then
        new_profile = string.format("%d-button-battery", #MS)
      else
        new_profile = string.format("%d-button", #MS)
      end
    elseif not battery_support then
      -- a battery-less button/remote (either single or will use parent/child)
      new_profile = "button"
    end

    if new_profile then device:try_update_metadata({profile = new_profile}) end

    -- At the moment, we're taking it for granted that all momentary switches only have 2 positions
    -- TODO: flesh this out for NumberOfPositions > 2
    local current_component_number = 2
    local component_map = {}
    local component_map_used = false
    for _, ep in ipairs(MS) do -- for each momentary switch endpoint (including main)
      device.log.debug("Configuring endpoint "..ep)
      -- build the mapping of endpoints to components if we have a static profile (multi-component)
      if contains(STATIC_PROFILE_SUPPORTED, #MS) then
        if ep ~= main_endpoint then
          component_map[string.format("button%d", current_component_number)] = ep
          current_component_number = current_component_number + 1
        else
          component_map["main"] = ep
        end
        component_map_used = true
      else -- use parent/child
        if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
          local name = string.format("%s %d", device.label, current_component_number)
          driver:try_create_device(
            {
              type = "EDGE_CHILD",
              label = name,
              profile = "button",
              parent_device_id = device.id,
              parent_assigned_child_key = string.format("%02X", ep),
              vendor_provided_label = name
            }
          )
          current_component_number = current_component_number + 1
        end
      end
    end

    if component_map_used then
      device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
    end

    if new_profile then
      device:set_field(DEFERRED_CONFIGURE, true)
    else
      configure_buttons(device)
    end

    -- TODO: Solution for latching switches
    -- for _, ep in ipairs(LS) do
    --   local name = string.format("%s %d", device.label, ep)
    --   local child = driver:try_create_device(
    --     {
    --       type = "EDGE_CHILD",
    --       label = name,
    --       profile = "child-button",
    --       parent_device_id = device.id,
    --       parent_assigned_child_key = string.format("%02X", ep),
    --       vendor_provided_label = name
    --     }
    --   )
    --   -- Latching switches are switches that don't return to an idle position after being pressed.
    --   -- In that sense, they can be all sorts of things, like dials or radio buttons. This means
    --   -- they can have any number of states > 2. However, due to the current nature of our capabilities
    --   -- our ability to support the full range of options here is limited, so we will stick with
    --   -- up/down rocker switches (kind of).
    --   child:emit_event(capabilities.button.supportedButtonValues({"up","down"}, {visibility = {displayed = false}}))
    -- end

  end
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id
    and device:get_field(DEFERRED_CONFIGURE)
    and device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    -- profile has changed, and we deferred setting up our buttons, so do that now
    configure_buttons(device)
    device:set_field(DEFERRED_CONFIGURE, nil)
  end
end

--end of lifecyle handlers
----------------------------------------------------------------------------

-- initial press
local function initial_press_event_handler(driver, device, ib, response)
  if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Receipt of an InitialPress event means we do not want to ignore the next MultiPressComplete event
    -- or else we would potentially not create the expected button capability event
    set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, nil)
  else
    if get_field_for_endpoint(device, INITIAL_PRESS_ONLY, ib.endpoint_id) then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
    elseif get_field_for_endpoint(device, EMULATE_HELD, ib.endpoint_id) then
      -- if our button doesn't differentiate between short and long holds, do it in code by keeping track of the press down time
      init_press(device, ib.endpoint_id)
    end
  end
end

-- if the device distinguishes a long press event, it will always be a "held"
-- there's also a "long release" event, but this event is required to come first
local function long_press_event_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.held({state_change = true}))
  if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Ignore the next MultiPressComplete event if it is sent as part of this "long press" event sequence
    set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, true)
  end
end

-- short release event handler
local function short_release_event_handler(driver, device, ib, response)
  if not get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    if get_field_for_endpoint(device, EMULATE_HELD, ib.endpoint_id) then
      emulate_held_event(device, ib.endpoint_id)
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
    end
  end
end

-- multi-press complete
local function multi_press_complete_event_handler(driver, device, ib, response)
  -- in the case of multiple button presses
  -- emit number of times, multiple presses have been completed
  if ib.data and get_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id) ~= true then
    local press_value = ib.data.elements.total_number_of_presses_counted.value
    --capability only supports up to 6 presses
    if press_value < 7 then
      local button_event = capabilities.button.button.pushed({state_change = true})
      if press_value == 2 then
        button_event = capabilities.button.button.double({state_change = true})
      elseif press_value > 2 then
        button_event = capabilities.button.button(string.format("pushed_%dx", press_value), {state_change = true})
      end

      device:emit_event_for_endpoint(ib.endpoint_id, button_event)
    else
      log.info(string.format("Number of presses (%d) not supported by capability", press_value))
    end
  end
  set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, nil)
end

--end of event handlers
---------------------------------------------------------------------------
local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

--need to find out max number of times a button can be pressed
local function max_press_handler(driver, device, ib, response)
  local max = ib.data.value or 1 --get max number of presses
  device.log.debug("Device supports "..max.." presses")
  -- capability only supports up to 6 presses
  if max > 6 then
    log.info("Device supports more than 6 presses")
    max = 6
  end
  local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
  local supportsHeld = contains(MSL, ib.endpoint_id)
  local values = create_multi_list(max, supportsHeld)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.supportedButtonValues(values, {visibility = {displayed = false}}))
end


-- end of attribute handlers
-- ------------------------------------------------------------------------
local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = info_changed
  },
  matter_handlers = {
    attr = {
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler
      },
      [clusters.Switch.ID] = {
        [clusters.Switch.attributes.MultiPressMax.ID] = max_press_handler,
      }
    },
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = initial_press_event_handler,
        [clusters.Switch.events.LongPress.ID] = long_press_event_handler,
        [clusters.Switch.events.ShortRelease.ID] = short_release_event_handler,
        [clusters.Switch.events.MultiPressComplete.ID] = multi_press_complete_event_handler,
      }
    },
  },
  subscribed_attributes = {
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining,
    },
  },
  subscribed_events = {
    [capabilities.button.ID] = {
      clusters.Switch.events.InitialPress,
      clusters.Switch.events.LongPress,
      clusters.Switch.events.ShortRelease,
      clusters.Switch.events.MultiPressComplete
    }
  },
}

local matter_driver = MatterDriver("matter-button", matter_driver_template)
matter_driver:run()
