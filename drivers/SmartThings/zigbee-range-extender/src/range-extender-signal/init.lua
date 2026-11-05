-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local Basic = (require "st.zigbee.zcl.clusters").Basic

local function refresh_signal_strength(driver, device)
  -- The reply carries the hub's received-message RSSI and LQI.
  device:send(Basic.attributes.ZCLVersion:read(device))
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    refresh_signal_strength(driver, device)
  end
end

local function signal_strength_handler(driver, device, value, zb_rx)
  -- A device can change profiles while this sub-driver is loaded.
  if not device:supports_capability(capabilities.signalStrength, "main") then
    return
  end

  if zb_rx.lqi ~= nil and zb_rx.lqi.value ~= nil then
    device:emit_event(capabilities.signalStrength.lqi(zb_rx.lqi.value))
  end
  if zb_rx.rssi ~= nil and zb_rx.rssi.value ~= nil then
    device:emit_event(capabilities.signalStrength.rssi({ value = zb_rx.rssi.value, unit = "dBm" }))
  end
end

return {
  NAME = "Range Extender Signal Strength",
  lifecycle_handlers = {
    infoChanged = info_changed,
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.ZCLVersion.ID] = signal_strength_handler,
      },
    },
  },
  can_handle = require("range-extender-signal.can_handle"),
}
