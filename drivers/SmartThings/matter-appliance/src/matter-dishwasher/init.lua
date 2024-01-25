-- Copyright 2023 SmartThings
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

local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local log = require "log"
local utils = require "st.utils"

local DISHWASHER_DEVICE_TYPE_ID = 0x0075

local dishwasherModeSupportedModes = {}

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function is_matter_dishwasher(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == DISHWASHER_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

local function dishwasher_supported_modes_attr_handler(driver, device, ib, response)
  dishwasherModeSupportedModes = {}
  for _, mode in ipairs(ib.data.elements) do
    table.insert(dishwasherModeSupportedModes, mode.elements.label.value)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.supportedModes(dishwasherModeSupportedModes))
end

local function dishwasher_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("dishwasher_mode_attr_handler currentMode: %s", ib.data.value))

  local currentMode = ib.data.value
  for i, mode in ipairs(dishwasherModeSupportedModes) do
    if i - 1 == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      break
    end
  end
end

-- Capability Handlers --
local function handle_dishwasher_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
    string.format("handle_dishwasher_mode mode: %s", cmd.args.mode))

  local ENDPOINT = 1
  for i, mode in ipairs(dishwasherModeSupportedModes) do
    if cmd.args.mode == mode then
      device:send(clusters.DishwasherMode.commands.ChangeToMode(device, ENDPOINT, i - 1))
      return
    end
  end
end

local matter_dishwasher_handler = {
  NAME = "matter-dishwasher",
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.DishwasherMode.ID] = {
        [clusters.DishwasherMode.attributes.SupportedModes.ID] = dishwasher_supported_modes_attr_handler,
        [clusters.DishwasherMode.attributes.CurrentMode.ID] = dishwasher_mode_attr_handler,
      },
    }
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_dishwasher_mode,
    },
  },
  can_handle = is_matter_dishwasher,
}

return matter_dishwasher_handler
