-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local SINOPE_SWITCH_CLUSTER = 0xFF01
local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE = 0x0052
local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE = 0x0053

local function info_changed(driver, device, event, args)
  -- handle ledIntensity preference setting
  if (args.old_st_store.preferences.ledIntensity ~= device.preferences.ledIntensity) then
    local ledIntensity = device.preferences.ledIntensity

    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(ledIntensity, data_types.Uint8, "payload")))
    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(ledIntensity, data_types.Uint8, "payload")))

  end
end

local zigbee_sinope_switch = {
  NAME = "Zigbee Sinope switch",
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = require("sinope.can_handle"),
}

return zigbee_sinope_switch
