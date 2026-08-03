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

local function configure_profile(device)
  local update_metadata_request = require "sensor_utils.update_metadata_request"

  local updated_component_to_endpoint_map = {}
  local updated_metadata = update_metadata_request.init()
  for _, ep in ipairs(device.endpoints) do
    -- >2 since EP0 is the root node, EP1 is a permanent Presence Sensor, and EP2 is a permanent Light Sensor
    if ep.endpoint_id > 2 then
      local component_id = string.format("sensor%d", ep.endpoint_id - 2) -- ex. sensor1, sensor2, etc. for EP3, EP4, etc.
      updated_component_to_endpoint_map[component_id] = ep.endpoint_id
      updated_metadata:add_capabilities_to_component(component_id, { capabilities.presenceSensor.ID })
    end
  end
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, updated_component_to_endpoint_map, { persist = true })
  device:try_update_metadata(updated_metadata:add_profile("aqara-fp400"):format())
end


local Fp400LifecycleHandlers = {}

function Fp400LifecycleHandlers.do_configure(driver, device)
  configure_profile(device)
end

function Fp400LifecycleHandlers.driver_switched(driver, device)
  configure_profile(device)
  device:try_update_metadata({provisioning_state = "PROVISIONED"})
end

function Fp400LifecycleHandlers.info_changed(driver, device, event, args)
  if not sensor_utils.deep_equals(args.old_st_store.endpoints, device.endpoints) then
    configure_profile(device)
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
