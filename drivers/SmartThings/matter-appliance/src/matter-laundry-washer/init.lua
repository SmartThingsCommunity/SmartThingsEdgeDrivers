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

local laundryWasherModeId = "spacewonder52282.laundryWasherMode"
local laundryWasherMode = capabilities[laundryWasherModeId]

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function is_matter_laundry_washer(opts, driver, device)
  return device:supports_capability_by_id(laundryWasherModeId)
end

local function laundry_washer_mode_attr_handler(driver, device, ib, response)
  log.info_with({ hub_logs = true },
  string.format("laundry_washer_mode_attr_handler currentMode: %s", ib.data.value))

  local current_mode=math.floor(ib.data.value)
  if current_mode==0 then
    device:emit_event_for_endpoint(ib.endpoint_id, laundryWasherMode.laundryWasherMode.normal())
  elseif current_mode==1 then
    device:emit_event_for_endpoint(ib.endpoint_id, laundryWasherMode.laundryWasherMode.heavy())
  elseif current_mode==2 then
    device:emit_event_for_endpoint(ib.endpoint_id, laundryWasherMode.laundryWasherMode.delicate())
  elseif current_mode==3 then
    device:emit_event_for_endpoint(ib.endpoint_id, laundryWasherMode.laundryWasherMode.whites())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, laundryWasherMode.laundryWasherMode.normal())
  end
end

-- Capability Handlers --
local function handle_laundry_washer_mode(driver, device, cmd)
  log.info_with({ hub_logs = true },
  string.format("handle_laundry_washer_mode currentMode: %s", cmd.args.mode))

  if cmd.args.mode==laundryWasherMode.laundryWasherMode.normal.NAME then
    device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, 1, 0))
  elseif cmd.args.mode==laundryWasherMode.laundryWasherMode.heavy.NAME then
    device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, 1, 1))
  elseif cmd.args.mode==laundryWasherMode.laundryWasherMode.delicate.NAME then
    device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, 1, 2))
  elseif cmd.args.mode==laundryWasherMode.laundryWasherMode.whites.NAME then
    device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, 1, 3))
  else
    device:send(clusters.LaundryWasherMode.commands.ChangeToMode(device, 1, 0))
  end
end

local matter_laundry_washer_handler = {
  NAME = "matter-laundry-washer",
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.LaundryWasherMode.ID] = {
        [clusters.LaundryWasherMode.attributes.CurrentMode.ID] = laundry_washer_mode_attr_handler,
      },
    }
  },
  subscribed_attributes = {
    [laundryWasherModeId] = {
      clusters.LaundryWasherMode.attributes.CurrentMode,
    },
  },
  capability_handlers = {
    [laundryWasherModeId] = {
      [laundryWasherMode.commands.setLaundryWasherMode.NAME] = handle_laundry_washer_mode,
    },
  },
  can_handle = is_matter_laundry_washer,
}

return matter_laundry_washer_handler
