-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local version = require "version"

if version.api < 20 then
  clusters.ClosureControl = require "embedded_clusters.ClosureControl"
  clusters.ClosureDimension = require "embedded_clusters.ClosureDimension"
end

local fields = require "sub_drivers.closure.closure_utils.fields"
local closure_utils = require "sub_drivers.closure.closure_utils.utils"

local ClosureAttrHandlers = {}

function ClosureAttrHandlers.main_state_attr_handler(driver, device, ib, response)
  if ib.data.value == nil then return end
  closure_utils.set_closure_control_state(device, ib.endpoint_id, { main = ib.data.value })
  closure_utils.emit_closure_control_capability(device, ib.endpoint_id)
end

function ClosureAttrHandlers.overall_current_state_attr_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  clusters.ClosureControl.types.OverallCurrentStateStruct:augment_type(ib.data)
  for _, v in pairs(ib.data.elements or {}) do
    if v.field_id == 0 then
      local current = v.value
      closure_utils.set_closure_control_state(device, ib.endpoint_id, { current = current })
      closure_utils.emit_closure_control_capability(device, ib.endpoint_id)
      break
    end
  end
end

function ClosureAttrHandlers.overall_target_state_attr_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  clusters.ClosureControl.types.OverallTargetStateStruct:augment_type(ib.data)
  for _, v in pairs(ib.data.elements or {}) do
    if v.field_id == 0 then
      local target = v.value
      closure_utils.set_closure_control_state(device, ib.endpoint_id, { target = target })
      closure_utils.emit_closure_control_capability(device, ib.endpoint_id)
      break
    end
  end
end

function ClosureAttrHandlers.closure_dimension_current_state_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  clusters.ClosureDimension.types.DimensionStateStruct:augment_type(ib.data)
  local pos_field = ib.data.elements.position
  if not pos_field or pos_field.value == nil then return end
  local level = math.floor(pos_field.value / 100)
  if device:supports_capability_by_id(capabilities.doorControl.ID) then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.level.level(level))
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(level))
  end
end

function ClosureAttrHandlers.tag_list_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local tag_value
  for _, v in ipairs(ib.data.elements) do
    local tag = v.elements
    if tag and tag.namespace_id and tag.namespace_id.value == 0x44 then
      tag_value = tag.tag and tag.tag.value
      break
    end
  end

  local closure_tag_map = {
    [0] = fields.closure_tag_list.COVERING,
    [1] = fields.closure_tag_list.WINDOW,
    [2] = fields.closure_tag_list.BARRIER,
    [3] = fields.closure_tag_list.CABINET,
    [4] = fields.closure_tag_list.GATE,
    [5] = fields.closure_tag_list.GARAGE_DOOR,
    [6] = fields.closure_tag_list.DOOR,
  }

  local closure_tag = fields.closure_tag_list.NA
  if tag_value ~= nil and closure_tag_map[tag_value] ~= nil then
    closure_tag = closure_tag_map[tag_value]
  end

  device:set_field(fields.CLOSURE_TAG, closure_tag, {persist = true})
  closure_utils.match_profile(device)
end

function ClosureAttrHandlers.power_source_attribute_list_handler(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements) do
    if attr.value == 0x0C then  -- BatPercentRemaining
      device:set_field(fields.CLOSURE_BATTERY_SUPPORT, fields.battery_support.BATTERY_PERCENTAGE, {persist = true})
      closure_utils.match_profile(device)
      return
    elseif attr.value == 0x0E then  -- BatChargeLevel
      device:set_field(fields.CLOSURE_BATTERY_SUPPORT, fields.battery_support.BATTERY_LEVEL, {persist = true})
      closure_utils.match_profile(device)
      return
    end
  end
  -- No battery attribute found
  device:set_field(fields.CLOSURE_BATTERY_SUPPORT, fields.battery_support.NO_BATTERY, {persist = true})
  closure_utils.match_profile(device)
end

return ClosureAttrHandlers
