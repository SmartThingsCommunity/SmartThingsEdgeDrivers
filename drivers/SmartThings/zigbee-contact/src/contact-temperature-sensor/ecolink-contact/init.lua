-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local PollControl = clusters.PollControl

local CHECK_IN_INTERVAL = 0x00001C20
local SHORT_POLL_INTERVAL = 0x0200
local LONG_POLL_INTERVAL = 0xB1040000
local FAST_POLL_TIMEOUT = 0x0028



local function do_configure(driver, device)
  device:configure()
  device:send(device_management.build_bind_request(device, PollControl.ID, driver.environment_info.hub_zigbee_eui))
  device:refresh()
  device:send(PollControl.attributes.CheckInInterval:write(device, CHECK_IN_INTERVAL))
  device:send(PollControl.commands.SetShortPollInterval(device, SHORT_POLL_INTERVAL))
  device:send(PollControl.attributes.FastPollTimeout:write(device, FAST_POLL_TIMEOUT))
  device:send(PollControl.commands.SetLongPollInterval(device, LONG_POLL_INTERVAL))
end

local ecolink_sensor = {
  NAME = "Ecolink Contact Temperature",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = require("contact-temperature-sensor.ecolink-contact.can_handle"),
}

return ecolink_sensor
