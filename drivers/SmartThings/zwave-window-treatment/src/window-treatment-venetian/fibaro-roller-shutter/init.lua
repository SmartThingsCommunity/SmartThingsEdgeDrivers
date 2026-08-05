-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


--- @type st.zwave.CommandClass
local cc = (require "st.zwave.CommandClass")
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})


-- configuration parameters
local CALIBRATION_CONFIGURATION = 150
local OPERATING_MODE_CONFIGURATION = 151

-- fieldnames
local CALIBRATION = "calibration"

-- calibration statuses
local CLB_NOT_STARTED = "not_started"
local CLB_DONE = "done"
local CLB_PENDING = "pending"


local function configuration_report(driver, device, cmd)
  local parameter_number = cmd.args.parameter_number
  local configuration_value = cmd.args.configuration_value

  if parameter_number == CALIBRATION_CONFIGURATION then
    local calibration_status
    if configuration_value == 0 then
      calibration_status = CLB_NOT_STARTED
    elseif configuration_value == 1 then
      calibration_status = CLB_DONE
    elseif configuration_value == 2 then
      if device:get_field(CALIBRATION) == CLB_NOT_STARTED then
        calibration_status = CLB_PENDING
      end
    end
    device:set_field(CALIBRATION, calibration_status, {persist = true})
  elseif parameter_number == OPERATING_MODE_CONFIGURATION then
    if configuration_value == 1 or configuration_value == 5 or configuration_value == 6 then
      device:try_update_metadata({profile = "fibaro-roller-shutter"})
    elseif configuration_value == 2 then
      device:try_update_metadata({profile = "fibaro-roller-shutter-venetian"})
    end
  end
end

local function device_added(self, device)
  device:set_field(CALIBRATION, CLB_NOT_STARTED)
  device:do_refresh()
end

local fibaro_roller_shutter = {
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    }
  },
  NAME = "fibaro roller shutter",
  can_handle = require("window-treatment-venetian.fibaro-roller-shutter.can_handle"),
  lifecycle_handlers = {
    add = device_added
  }
}

return fibaro_roller_shutter
