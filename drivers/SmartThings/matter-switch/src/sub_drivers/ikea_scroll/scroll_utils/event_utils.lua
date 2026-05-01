-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_utils = require "st.utils"
local clusters = require "st.matter.clusters"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"

local IkeaScrollEventUtils = {}


function IkeaScrollEventUtils.requeue_clear_scroll_state(device)
  -- cancel any previously queued clear state actions to prevent unintended clears
  if device:get_field(scroll_fields.CLEAR_STATE_TIMER) then
    device.thread:cancel_timer(device:get_field(scroll_fields.CLEAR_STATE_TIMER))
  end
  local new_timer = device.thread:call_with_delay(scroll_fields.CLEAR_STATE_DELAY_S, function()
    device:set_field(scroll_fields.GLOBAL_ROTATE_AMOUNT_STATE, 0)
  end)
  device:set_field(scroll_fields.CLEAR_STATE_TIMER, new_timer)
end

function IkeaScrollEventUtils.is_valid_scroll_amount(device, scroll_amount)
  local global_rotate_amount_state = device:get_field(scroll_fields.GLOBAL_ROTATE_AMOUNT_STATE) or 0
  local is_rotate_amount_state_at_bounds = (scroll_amount < 0 and global_rotate_amount_state <= -100) or (scroll_amount > 0 and global_rotate_amount_state >= 100)
  if is_rotate_amount_state_at_bounds then
    return false
  end

  device:set_field(scroll_fields.GLOBAL_ROTATE_AMOUNT_STATE, st_utils.clamp_value(global_rotate_amount_state + scroll_amount, -100, 100))
  IkeaScrollEventUtils.requeue_clear_scroll_state(device)
  return true
end

-- inspect all info blocks to find the last one that is not an InitialPress event. We will
-- only try to emit a rotateAmount event if the current info block being handled is that last one.
function IkeaScrollEventUtils.is_last_valid_info_block(cur_info_block_event_id, cur_info_block_value, info_blocks)
  local last_valid_emission_idx = #info_blocks
  -- Ignore all InitialPress events in a multi-response block
  while (last_valid_emission_idx > 1) and (info_blocks[last_valid_emission_idx].info_block.event_id == clusters.Switch.events.InitialPress.ID) do
    last_valid_emission_idx = last_valid_emission_idx - 1
  end

  -- Because the info block does not include the unique_key Matter defined event number, this
  -- logic is a best guess at matching the current info block to the last valid info block.
  local emission_ib = info_blocks[last_valid_emission_idx].info_block
  if emission_ib.event_id ~= cur_info_block_event_id then
    return false
  elseif emission_ib.event_id == clusters.Switch.events.MultiPressComplete.ID then
    local last_valid_ib_value = emission_ib.data.elements and emission_ib.data.elements.total_number_of_presses_counted.value or 0
    return last_valid_ib_value == cur_info_block_value
  elseif emission_ib.event_id == clusters.Switch.events.MultiPressOngoing.ID then
    local last_valid_ib_value = emission_ib.data.elements and emission_ib.data.elements.current_number_of_presses_counted.value or 0
    return last_valid_ib_value == cur_info_block_value
  elseif last_valid_emission_idx == 1 then -- aka, all ib's are InitialPress
    return true
  end

  return false
end

function IkeaScrollEventUtils.aggregate_scroll_amount_for_info_blocks(device, info_blocks)
  local total_presses = 0
  local presses_in_current_chain = 0
  for _, ib in ipairs(info_blocks) do
    if ib.info_block.event_id == clusters.Switch.events.MultiPressOngoing.ID then
      presses_in_current_chain = ib.info_block.data.elements and ib.info_block.data.elements.current_number_of_presses_counted.value or 0
    elseif ib.info_block.event_id == clusters.Switch.events.MultiPressComplete.ID then
      total_presses = total_presses + (ib.info_block.data.elements and ib.info_block.data.elements.total_number_of_presses_counted.value or 0)
      presses_in_current_chain = 0
    end
  end
  total_presses = total_presses + presses_in_current_chain -- aggregate any presses to the total from the current chain
  return { total_presses = total_presses, presses_in_current_chain = presses_in_current_chain }
end

function IkeaScrollEventUtils.rotate_amount_scaling_helper(device, endpoint_id, scroll_amount)
  local scale_factor = 1.0 -- the default scale factor is 1.0, i.e none
  local component = device:endpoint_to_component(endpoint_id)
  if component == "main" then
    scale_factor = scroll_fields.KNOB_SENSITIVITY_FACTORS[device.preferences.knobSensitivityGroup1] or 1.0
  elseif component == "group2" then
    scale_factor = scroll_fields.KNOB_SENSITIVITY_FACTORS[device.preferences.knobSensitivityGroup2] or 1.0
  elseif component == "group3" then
    scale_factor = scroll_fields.KNOB_SENSITIVITY_FACTORS[device.preferences.knobSensitivityGroup3] or 1.0
  end
  local scaled_scroll_amount = st_utils.clamp_value(math.floor(scroll_amount * scale_factor), -100, 100)
  return scaled_scroll_amount
end

return IkeaScrollEventUtils
