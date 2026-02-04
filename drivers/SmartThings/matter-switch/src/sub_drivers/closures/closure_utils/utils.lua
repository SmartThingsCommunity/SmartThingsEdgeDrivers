-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local fields = require "switch_utils.fields"
local im = require "st.matter.interaction_model"
local switch_utils = require "switch_utils.utils"

clusters.ClosureControl = require "embedded_clusters.ClosureControl"

local ClosureUtils = {}

function ClosureUtils.subscribe(device)
  local closure_subscribed_attributes = {
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining,
    },
    [capabilities.batteryLevel.ID] = {
      clusters.PowerSource.attributes.BatChargeLevel,
    },
    [capabilities.doorControl.ID] = {
      clusters.ClosureControl.attributes.MainState,
      clusters.ClosureControl.attributes.OverallCurrentState,
      clusters.ClosureControl.attributes.OverallTargetState
    },
    [capabilities.windowShade.ID] = {
      clusters.WindowCovering.attributes.OperationalStatus
    },
    [capabilities.windowShadeLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths
    },
    [capabilities.windowShadeTiltLevel.ID] = {
      clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths
    }
  }

  -- if the device is a closure rather than window covering, substitute the appropriate attributes
  if #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.CLOSURE) > 0 then
    closure_subscribed_attributes[capabilities.windowShade.ID] = {
      clusters.ClosureControl.attributes.MainState,
      clusters.ClosureControl.attributes.OverallCurrentState,
      clusters.ClosureControl.attributes.OverallTargetState
    }
  end

  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  local devices_seen, capabilities_seen, attributes_seen, events_seen = {}, {}, {}, {}

  for _, endpoint_info in ipairs(device.endpoints) do
    local checked_device = switch_utils.find_child(device, endpoint_info.endpoint_id) or device
    if not devices_seen[checked_device.id] then
      switch_utils.populate_subscribe_request_for_device(
        checked_device, subscribe_request, capabilities_seen, attributes_seen, events_seen, closure_subscribed_attributes, {}
      )
      devices_seen[checked_device.id] = true
    end
  end

  -- The refresh capability command handler in the lua libs uses this key to determine which attributes to read. Note
  -- that only attributes_seen needs to be saved here, and not events_seen, since the refresh handler only checks
  -- attributes and not events.
  device:set_field(fields.SUBSCRIBED_ATTRIBUTES_KEY, attributes_seen)

  -- If the type of battery support has not yet been determined, add the PowerSource AttributeList to the list of
  -- subscribed attributes in order to determine which if any battery capability should be used.
  if device:get_field(fields.profiling_data.BATTERY_SUPPORT) == nil then
    local ib = im.InteractionInfoBlock(nil, clusters.PowerSource.ID, clusters.PowerSource.attributes.AttributeList.ID)
    subscribe_request:with_info_block(ib)
  end

  -- For devices supporting ClosureControl, add the Descriptor cluster's TagList to the list of subscribed
  -- attributes in order to determine the closure type
  if #device:get_endpoints(clusters.ClosureControl.ID) > 0 then
    local ib = im.InteractionInfoBlock(nil, clusters.Descriptor.ID, clusters.Descriptor.attributes.TagList.ID)
    subscribe_request:with_info_block(ib)
  end

  if #subscribe_request.info_blocks > 0 then
    device:send(subscribe_request)
  end
end

return ClosureUtils
