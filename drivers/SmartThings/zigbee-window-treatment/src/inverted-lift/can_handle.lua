-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function invert_lift_percentage_can_handle(opts, driver, device, ...)
  local somfy_can_handle = require("inverted-lift.somfy.can_handle")
  local yoolax_can_handle = require("inverted-lift.yoolax.can_handle")
  local rooms_beautiful_can_handle = require("inverted-lift.rooms-beautiful.can_handle")
  local vimar_can_handle = require("inverted-lift.vimar.can_handle")
  if somfy_can_handle(opts, driver, device)
    or yoolax_can_handle(opts, driver, device)
    or rooms_beautiful_can_handle(opts, driver, device)
    or vimar_can_handle(opts, driver, device)
    or device:get_manufacturer() == "IKEA of Sweden"
    or device:get_manufacturer() == "Smartwings"
    or device:get_manufacturer() == "Insta GmbH"
  then
    return true, require("inverted-lift")
  end
  return false
end

return invert_lift_percentage_can_handle
