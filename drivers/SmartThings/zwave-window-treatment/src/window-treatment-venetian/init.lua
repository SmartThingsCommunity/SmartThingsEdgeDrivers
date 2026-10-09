-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0



local cc = (require "st.zwave.CommandClass")
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=3})

local WindowShadeDefaults = require "st.zwave.defaults.windowShade"
local WindowShadeLevelDefaults = require "st.zwave.defaults.windowShadeLevel"



local function shade_event_handler(self, device, cmd)
  WindowShadeDefaults.zwave_handlers[cc.SWITCH_MULTILEVEL][SwitchMultilevel.REPORT](self, device, cmd)
  WindowShadeLevelDefaults.zwave_handlers[cc.SWITCH_MULTILEVEL][SwitchMultilevel.REPORT](self, device, cmd)
end

local function endpoint_to_component(device, endpoint)
  if endpoint == 2 then
    return "venetianBlind"
  else
    return "main"
  end
end

local function component_to_endpoint(device, component)
  if component == "venetianBlind" then
    return {2}
  else
    return {}
  end
end

local function map_components(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local window_treatment_venetian = {
  NAME = "window treatment venetian",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = shade_event_handler
    },
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.REPORT] = shade_event_handler
    }
  },
  can_handle = require("window-treatment-venetian.can_handle"),
  lifecycle_handlers = {
    init = map_components
  },
  sub_drivers = require("window-treatment-venetian.sub_drivers"),
}

return window_treatment_venetian
