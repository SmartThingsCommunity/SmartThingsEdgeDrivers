-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local button_utils = require "button_utils"

local WindowCovering = clusters.WindowCovering

local open_close_remote = {
  NAME = "Open/Close Remote",
  zigbee_handlers = {
    cluster = {
      [WindowCovering.ID] = {
        [WindowCovering.server.commands.UpOrOpen.ID] = button_utils.build_button_handler("button1", capabilities.button.button.pushed),
        [WindowCovering.server.commands.DownOrClose.ID] = button_utils.build_button_handler("button2", capabilities.button.button.pushed)
      }
    }
  },
  can_handle = require "zigbee-multi-button.ikea.TRADFRI_open_close_remote.can_handle",
}

return open_close_remote
