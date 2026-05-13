-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local excluded_devices = {
  FIBARO_DOOR_WINDOW = {
    mfrs = 0x010F
  },
  AEOTEC_AERQ_8 = {
    mfrs = 0x0371,
    product_ids = 0x0039
  },
  AEOTEC_DOOR_WINDOW_SENSOR_8 = {
    mfrs = 0x0371,
    product_ids = 0x0037
  },
  AEOTEC_WATER_SENSOR_8 = {
    mfrs = 0x0371,
    product_ids = 0x0038
  },
}

local function can_handle_tamper_event(opts, driver, zw_device, cmd, ...)
  -- check only for relevant tamper event first
  if not(opts.dispatcher_class == "ZwaveDispatcher" and
    cmd ~= nil and
    cmd.cmd_class ~= nil and
    cmd.cmd_class == cc.NOTIFICATION and
    cmd.cmd_id == Notification.REPORT and
    cmd.args.notification_type == Notification.notification_type.HOME_SECURITY and
    (cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED or
    cmd.args.event == Notification.event.home_security.TAMPERING_PRODUCT_MOVED)) then
    return false
  end

  -- check exclusion list: if device matches any entry, skip auto-clear
  for _, excluded_device in pairs(excluded_devices) do
    local mfrs          = excluded_device.mfrs
    local product_types = excluded_device.product_types or nil
    local product_ids   = excluded_device.product_ids   or nil

    if mfrs ~= nil then
      if zw_device:id_match(
          mfrs,
          product_types,
          product_ids
        ) then
        return false
      end
    end
  end
end

return can_handle_tamper_event