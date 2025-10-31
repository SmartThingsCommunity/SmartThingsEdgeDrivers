-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local switch_utils = require "switch_utils.utils"
local button_cfg = require "switch_utils.device_configuration".ButtonCfg
local scroll_utils = require "sub_drivers.ikea_scroll.scroll_utils.utils"
local scroll_cfg = require "sub_drivers.ikea_scroll.scroll_utils.device_configuration"

local IkeaScrollLifecycleHandlers = {}

-- prevent main driver device_added handling from running
function IkeaScrollLifecycleHandlers.device_added(driver, device)
end

function IkeaScrollLifecycleHandlers.device_init(driver, device)
  device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
  device:extend_device("subscribe", scroll_utils.subscribe)
  device:subscribe()
end

function IkeaScrollLifecycleHandlers.do_configure(driver, device)
  scroll_cfg.match_profile(driver, device)
end

function IkeaScrollLifecycleHandlers.driver_switched(driver, device)
  scroll_cfg.match_profile(driver, device)
end

function IkeaScrollLifecycleHandlers.info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    button_cfg.configure_buttons(device)
    device:subscribe()
  end
end


-- DEVICE TEMPLATE --

local ikea_scroll_handler = {
  NAME = "Ikea Scroll Handler",
  lifecycle_handlers = {
    added = IkeaScrollLifecycleHandlers.device_added,
    doConfigure = IkeaScrollLifecycleHandlers.do_configure,
    driverSwitched = IkeaScrollLifecycleHandlers.driver_switched,
    infoChanged = IkeaScrollLifecycleHandlers.info_changed,
    init = IkeaScrollLifecycleHandlers.device_init,
  },
  can_handle = scroll_utils.is_ikea_scroll
}

return ikea_scroll_handler
