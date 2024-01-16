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

local dishwasherModeId = "spacewonder52282.dishwasherMode"
local dishwasherMode = capabilities[dishwasherModeId]

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function is_matter_dishwasher(opts, driver, device)
  return device:supports_capability_by_id(dishwasherModeId)
end

local function dishwasher_supported_modes_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
    string.format("dishwasher_supported_modes_attr_handler supportedModes: %s", ib.data.value))
end

local function dishwasher_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("dishwasher_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode=math.floor(ib.data.value)
  if current_mode==0 then
    device:emit_event_for_endpoint(ib.endpoint_id, dishwasherMode.dishwasherMode.normal())
  elseif current_mode==1 then
    device:emit_event_for_endpoint(ib.endpoint_id, dishwasherMode.dishwasherMode.heavy())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, dishwasherMode.dishwasherMode.light())
  end
end

-- Capability Handlers --
local function handle_dishwasher_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
  string.format("handle_dishwasher_mode currentMode: %s", cmd.args.mode))

  if cmd.args.mode==dishwasherMode.dishwasherMode.normal.NAME then
    device:send(clusters.DishwasherMode.commands.ChangeToMode(device, 1, 0))
  elseif cmd.args.mode==dishwasherMode.dishwasherMode.heavy.NAME then
    device:send(clusters.DishwasherMode.commands.ChangeToMode(device, 1, 1))
  elseif cmd.args.mode==dishwasherMode.dishwasherMode.light.NAME then
    device:send(clusters.DishwasherMode.commands.ChangeToMode(device, 1, 2))
  else
    device:send(clusters.DishwasherMode.commands.ChangeToMode(device, 1, 0))
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
  subscribed_attributes = {
    [dishwasherModeId] = {
      clusters.DishwasherMode.attributes.SupportedModes,
      clusters.DishwasherMode.attributes.CurrentMode,
    },
  },
  capability_handlers = {
    [dishwasherModeId] = {
      [dishwasherMode.commands.setDishwasherMode.NAME] = handle_dishwasher_mode,
    },
  },
  can_handle = is_matter_dishwasher,
}

return matter_dishwasher_handler
