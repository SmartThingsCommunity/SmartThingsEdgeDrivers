-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local sensor_utils = require "sensor_utils.utils"

local COMPONENT_TO_ENDPOINT_MAP = "__COMPONENT_TO_ENDPOINT_MAP"

local function endpoint_to_component(device, endpoint_id)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component_id, ep_id in pairs(map) do
    if ep_id == endpoint_id then return component_id end
  end
  return "main"
end

local function match_profile(device)
  local enabled_optional_component_capabilities = {}
  local component_to_endpoint_map = {}
  for _, ep in ipairs(device.endpoints) do
    -- since EP0 is the root node, EP1 is a permanent Presence Sensor, and EP2 is a permanent Light Sensor
    if ep.endpoint_id > 2 then
        component_to_endpoint_map[string.format("sensor%d", ep.endpoint_id - 2)] = ep.endpoint_id
      -- ex. sensor1, sensor2, etc. for EP3, EP4, etc.
      table.insert(enabled_optional_component_capabilities,{ string.format("sensor%d", ep.endpoint_id - 2), { capabilities.presenceSensor.ID } })
    end
  end
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_to_endpoint_map, { persist = true })
  device:try_update_metadata({profile = "aqara-fp400", optional_component_capabilities = enabled_optional_component_capabilities })
end


local Fp400LifecycleHandlers = {}

function Fp400LifecycleHandlers.do_configure(driver, device)
  match_profile(device)
end

function Fp400LifecycleHandlers.driver_switched(driver, device)
  match_profile(device)
  device:try_update_metadata({provisioning_state = "PROVISIONED"})
end

function Fp400LifecycleHandlers.info_changed(driver, device, event, args)
  if not sensor_utils.deep_equals(args.old_st_store.endpoints, device.endpoints) then
    match_profile(device)
    device:subscribe()
  end
end

function Fp400LifecycleHandlers.device_init(driver, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:subscribe()
end

local aqara_fp400_handler = {
  NAME = "aqara-fp400",
  lifecycle_handlers = {
    doConfigure = Fp400LifecycleHandlers.do_configure,
    driverSwitched = Fp400LifecycleHandlers.driver_switched,
    infoChanged = Fp400LifecycleHandlers.info_changed,
    init = Fp400LifecycleHandlers.device_init,
  },
  can_handle = require("sub_drivers.aqara_fp400.can_handle"),
}

return aqara_fp400_handler
