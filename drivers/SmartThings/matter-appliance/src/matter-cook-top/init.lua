-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.matter.clusters"
local common_utils = require "common-utils"
local embedded_cluster_utils = require "embedded-cluster-utils"
local version = require "version"

if version.api < 10 then
  clusters.TemperatureControl = require "TemperatureControl"
end

local COOK_SURFACE_DEVICE_TYPE_ID = 0x0077

local function table_contains(tab, val)
  for _, tab_val in ipairs(tab) do
    if tab_val == val then
      return true
    end
  end
  return false
end

local function device_added(driver, device)
  local cook_surface_endpoints = common_utils.get_endpoints_for_dt(device, COOK_SURFACE_DEVICE_TYPE_ID)
  local componentToEndpointMap = {
    ["cookSurfaceOne"] = cook_surface_endpoints[1],
    ["cookSurfaceTwo"] = cook_surface_endpoints[2]
  }
  device:set_field(common_utils.COMPONENT_TO_ENDPOINT_MAP, componentToEndpointMap, { persist = true })
end

local function do_configure(driver, device)
  local cook_surface_endpoints = common_utils.get_endpoints_for_dt(device, COOK_SURFACE_DEVICE_TYPE_ID)

  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID,
    { feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL })

  local profile_name
  if #cook_surface_endpoints > 0 then
    profile_name = "cook-surface-one"
    if table_contains(tl_eps, cook_surface_endpoints[1]) then
      profile_name = profile_name .. "-tl"
    end

    -- we only support up to two cook surfaces
    if #cook_surface_endpoints > 1 then
      profile_name = profile_name .. "-cook-surface-two"
      if table_contains(tl_eps, cook_surface_endpoints[2]) then
        profile_name = profile_name .. "-tl"
      end
    end
  end

  if profile_name then
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({ profile = profile_name })
  end
end


-- Matter Handlers --
local matter_cook_top_handler = {
  NAME = "matter-cook-top",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = require("matter-cook-top.can_handle"),
}

return matter_cook_top_handler
