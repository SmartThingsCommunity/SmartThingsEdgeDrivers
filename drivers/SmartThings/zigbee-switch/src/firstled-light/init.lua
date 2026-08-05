-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local PRIVATE_CLUSTER_ID = 0xFC00

local preference_map = {
  ["outputMode"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = 0x0000,
    data_type = data_types.Uint8
  },
  ["powerOnMode"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = 0x0001,
    data_type = data_types.Uint8
  },
  ["ledDriveCurrent"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = 0x0002,
    data_type = data_types.Uint16
  },
  ["dimTransitionTime"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = 0x0003,
    data_type = data_types.Uint16
  },
  ["colorTempTransitionTime"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = 0x0004,
    data_type = data_types.Uint16
  }
}

local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  if preferences ~= nil then
    for id, attr in pairs(preference_map) do
      local old_value = old_preferences[id]
      local value = preferences[id]
      if value ~= nil and value ~= old_value then
        value = tonumber(value)
        device:send(cluster_base.write_attribute(device,
          data_types.ClusterId(attr.cluster_id),
          data_types.AttributeId(attr.attribute_id),
          data_types.validate_or_build_type(value, attr.data_type, "payload")))
      end
    end
  end
end

local firstled_light_handlers = {
  NAME = "firstled-light handlers",
  lifecycle_handlers = {
    infoChanged = device_info_changed
  },
  can_handle = require("firstled-light.can_handle")
}

return firstled_light_handlers
