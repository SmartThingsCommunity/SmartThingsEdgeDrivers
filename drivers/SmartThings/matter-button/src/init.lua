local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.generated.zap_clusters"
local MatterDriver = require "st.matter.driver"
local lua_socket = require "socket"

--button state machine states
local BUTTON_STATE_MAP = {
  WAIT = 1,
  PRESSED = 2,
  HELD_COMPLETE = 3,
}
local STATE = "state"
-- singlepress, multipress, latching switch
local BUTTON_TYPE = "__button_type" --should get set when device is added
local BUTTON_TYPE_MAP = {
  SINGLE_PRESS = 1,
  MULTI_PRESS = 2,
  LATCH_SWITCH = 3
}
local MAX_PRESS = "__max_press"
local BUTTON_X_PRESS_TIME = "button_%d_pressed_time"
local TIMEOUT_THRESHOLD = 50 --arbitrary timeout


--helper function to create liste of multi press values
local function create_multi_list(size)
  local list = {"pushed", "held", "double"}
  if size > 2 then
    for i=3, size do
      table.insert(list, string.format("pushed_%dx", i))
    end
  end
  return list
end

--helper functions for button timing
--button_number is which button was pressed?
local function init_press(device, button_number)
  device:set_field(string.format(BUTTON_X_PRESS_TIME, button_number or 0), lua_socket.gettime())
end

--helper function for pseudo state machine
local function next_button_state(device, next_state, button_number)
  local press_time = device:get_field(string.format(BUTTON_X_PRESS_TIME, button_number or 0))
  local time_diff = lua_socket.gettime() - press_time
  local state = device:get_field(STATE)
  if state == nil then
    state = BUTTON_STATE_MAP.WAIT
  end

  local set_state
  if time_diff < TIMEOUT_THRESHOLD then
    if next_state == BUTTON_STATE_MAP.PRESSED and state == BUTTON_STATE_MAP.WAIT then
      set_state = BUTTON_STATE_MAP.PRESSED
    elseif next_state == BUTTON_STATE_MAP.HELD_COMPLETE and state == BUTTON_STATE_MAP.PRESSED then
      set_state = BUTTON_STATE_MAP.HELD_COMPLETE
    else
      set_state = BUTTON_STATE_MAP.WAIT
    end
  else
    set_state = BUTTON_STATE_MAP.WAIT
  end
  device:set_field(STATE, set_state)
end

--emit the proper events
local function button_event(device, ib,  multi_press)
  local state = device:get_field(STATE)
  local button_type = device:get_field(BUTTON_TYPE)
  if button_type == nil then
    if multi_press > 0 then
      button_type = BUTTON_TYPE_MAP.MULTI_PRESS
    else
      button_type = BUTTON_TYPE_MAP.SINGLE_PRESS
    end
  end

  if button_type ~= BUTTON_TYPE_MAP.LATCH_SWITCH then
    local event
    if button_type == BUTTON_TYPE_MAP.SINGLE_PRESS then
      if state == BUTTON_STATE_MAP.HELD_COMPLETE then
        event = capabilities.button.button.held({state_change = true})
      elseif state == BUTTON_STATE_MAP.PRESSED then
        event = capabilities.button.button.pushed({state_change = true})
      end
    elseif button_type == BUTTON_TYPE_MAP.MULTI_PRESS then
      if state == BUTTON_STATE_MAP.HELD_COMPLETE then
        if multi_press == 2 then
          event = capabilities.button.button.double({state_change = true})
        else
          event = capabilities.button.button(string.format("pushed_%dx", multi_press))
        end
      end
    end
    if event ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, event)
    end
  end
end

--end of helper functions
--------------------------------------------------------------------------
local function device_init(driver, device)
  device:subscribe()
end

local function device_added(driver, device)
  local MS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  local MSR = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE})
  local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
  local MSM = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS})

  if #MS > 0 then
    if #MSL < 1 and #MSM < 1 then
      device:set_field(BUTTON_TYPE, BUTTON_TYPE_MAP.SINGLE_PRESS) --singlepress
      device:emit_event(capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})) --supported values

    elseif #MSR > 0 and #MSL > 0 and #MSM < 1 then
      device:set_field(BUTTON_TYPE, BUTTON_TYPE_MAP.SINGLE_PRESS) --singlepress
      device:emit_event(capabilities.button.supportedButtonValues({"pushed", "held"},{visibility = {displayed = false}})) --supported values

    elseif #MSM > 0 then
      device:set_field(BUTTON_TYPE, BUTTON_TYPE_MAP.MULTI_PRESS) -- multipress

      --send read MultiPressMax attribute request
      local req = clusters.Switch.attributes.MultiPressMax:read(device)
      device:send(req)

    end
    device:emit_event(capabilities.button.button.pushed({state_change = false})) --button is not pressed yet

  else
    --it is a latching switch
    device:set_field(BUTTON_TYPE, BUTTON_TYPE_MAP.LATCH_SWITCH) -- latching switch
    device:emit_event(capabilities.button.supportedButtonValues({"up","down"}, {visibility = {displayed = false}}))
  end
  device:set_field(STATE, BUTTON_STATE_MAP.WAIT) --set wait state

  device:emit_event(capabilities.button.numberOfButtons({value=1}, {visibility = {displayed = false}})) --number of buttons

end

--end of lifecyle handlers
----------------------------------------------------------------------------

-- initial press
local function initial_event_handler(driver, device, ib, response)
  --button 0 has been pressed
  init_press(device, 0)
  -- move to PRESSED state
  next_button_state(device, BUTTON_STATE_MAP.PRESSED, 0) -- 0 is for multipress
  button_event(device, ib, 0)
end

local function long_event_handler(driver, device, ib, response)
  -- long press, button is being held
  -- move to HELD state
  next_button_state(device, BUTTON_STATE_MAP.HELD_COMPLETE, 0)

  --0 is for multpress
  button_event(device, ib, 0)
end

-- release event handler
local function release_event_handler(driver, device, ib, response)
  -- button has been released
  -- move to WAIT state
  next_button_state(device, BUTTON_STATE_MAP.WAIT, 0)
  button_event(device, ib, 0)

end


-- multi-press complete
local function multi_event_handler(driver, device, ib, response)
  -- in the case of multiple button presses
  -- emit number of times, multiple presses have been completed
  if ib.data then
    local press_value = ib.data.elements.total_number_of_presses_counted.value
    --capability only supports up to 6 presses
    if press_value < 7 then
      next_button_state(device, BUTTON_STATE_MAP.HELD_COMPLETE, 0)
      button_event(device, ib, press_value)
      next_button_state(device, BUTTON_STATE_MAP.WAIT, 0)
    else
      log.info("Number of presses not supported by capability")
    end
  end
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
  if ib.data.value then
    local MAX = ib.data.value or 1 --get max number of presses
    -- capability only supports up to 6 presses
    if MAX < 7 then
      local values = create_multi_list(MAX)
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.supportedButtonValues(values, {visibility = {displayed = false}}))
      device:set_field(MAX_PRESS, MAX)
    else
      log.info("Number of presses not supported by capability")
    end
  end
end

--needed for latching switch
local function current_pos_handler(driver, device, ib, response)
  local button_type = device:get_field(BUTTON_TYPE)
  if ib.data.value and button_type == BUTTON_TYPE_MAP.LATCH_SWITCH then
    if ib.data.value == 1 then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.up({state_change = true})) --off
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.down({state_change = true})) --on
    end
  end
end

-- end of attribute handlers
-- ------------------------------------------------------------------------
local matter_driver_template = {
  lifecycle_handlers = {init = device_init, added = device_added},
  matter_handlers = {
    attr = {
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler
      },
      [clusters.Switch.ID] = {
        [clusters.Switch.attributes.MultiPressMax.ID] = max_press_handler,
        [clusters.Switch.attributes.CurrentPosition.ID] = current_pos_handler,
        --number of positions attribute? for switches with more than two positions
      }
    },
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = initial_event_handler,
        [clusters.Switch.events.LongPress.ID] = long_event_handler,
        [clusters.Switch.events.ShortRelease.ID] = release_event_handler,
        [clusters.Switch.events.LongRelease.ID] = release_event_handler,
        [clusters.Switch.events.MultiPressComplete.ID] = multi_event_handler,
      }
    },
  },
  subscribed_attributes = {
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining,
    },
    [capabilities.button.ID] = {
      clusters.Switch.attributes.MultiPressMax,
      clusters.Switch.attributes.CurrentPosition
    }
  },
  subscribed_events = {
    [capabilities.button.ID] = {
      clusters.Switch.events.InitialPress,
      clusters.Switch.events.LongPress,
      clusters.Switch.events.ShortRelease,
      clusters.Switch.events.LongRelease,
      clusters.Switch.events.MultiPressComplete
    }
  },
}

local matter_driver = MatterDriver("matter-button", matter_driver_template)
matter_driver:run()
