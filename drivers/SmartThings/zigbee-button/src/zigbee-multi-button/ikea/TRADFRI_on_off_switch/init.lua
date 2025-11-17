-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local button_utils = require "button_utils"

local Level = clusters.Level
local OnOff = clusters.OnOff

local on_off_switch = {
  NAME = "On/Off Switch",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = button_utils.build_button_handler("button1", capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = button_utils.build_button_handler("button2", capabilities.button.button.pushed)
      },
      [Level.ID] = {
        [Level.server.commands.Move.ID] = button_utils.build_button_handler("button1", capabilities.button.button.held),
        [Level.server.commands.MoveWithOnOff.ID] = button_utils.build_button_handler("button2", capabilities.button.button.held)
      },
    }
  },
  can_handle = require "zigbee-multi-button.ikea.TRADFRI_on_off_switch.can_handle"
}

return on_off_switch
