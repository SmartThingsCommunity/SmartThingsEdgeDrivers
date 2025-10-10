-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- This is a patch for the zigbee-switch driver to fix https://smartthings.atlassian.net/browse/CHAD-16558
-- Several hubs were found that had zigbee switch drivers hosting zwave devices.
-- This patch works around it until hubcore 0.59 is released with
-- https://smartthings.atlassian.net/browse/CHAD-16552

local log = require "log"


local function device_added(driver, device, event)
    log.info(string.format("Non zigbee device added: %s", device))
end

local function device_init(driver, device, event)
    log.info(string.format("Non zigbee device init: %s", device))
end

local function do_configure(driver, device)
    log.info(string.format("Non zigbee do configure: %s", device))
end

local function info_changed(driver, device, event, args)
    log.info(string.format("Non zigbee infoChanged: %s", device))
end

local non_zigbee_devices = {
  NAME = "non zigbee devices filter",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  can_handle = require("non_zigbee_devices.can_handle"),
}

return non_zigbee_devices
