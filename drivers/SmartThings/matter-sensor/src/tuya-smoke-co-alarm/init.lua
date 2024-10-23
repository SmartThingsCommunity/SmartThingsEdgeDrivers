-- Copyright 2024 SmartThings
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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"

local SMOKE_CO_ALARM_DEVICE_TYPE_ID = 0x0076
local TUYA_CO_MANUFACTURER_ID = 0x125D

local version = require "version"

if version.api < 10 then
  clusters.SmokeCoAlarm = require "SmokeCoAlarm"
end

local function is_tuya_smoke_co_alarm(opts, driver, device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == SMOKE_CO_ALARM_DEVICE_TYPE_ID and device.manufacturer_info.vendor_id == TUYA_CO_MANUFACTURER_ID then
        return true
      end
    end
  end
  return false
end


local function device_init(driver, device, ib)
    device:send(
      cluster_base.subscribe(device, ib.endpoint_id, clusters.SmokeCoAlarm.ID, clusters.SmokeCoAlarm.attributes.COState.ID, nil)
    )
    -- device:subscribe()
end

local function info_changed(self, device, event, args)
  -- resubscribe to new attributes as needed if a profile switch occured
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  end
end

-- Matter Handlers --
local function binary_state_handler_factory(zeroEvent, nonZeroEvent)
  return function(driver, device, ib, response)
    if ib.data.value == 0 and zeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, zeroEvent)
    elseif nonZeroEvent ~= nil then
      device:emit_event_for_endpoint(ib.endpoint_id, nonZeroEvent)
    end
  end
end

local matter_tuya_smoke_co_alarm_handler = {
  NAME = "matter-tyua-smoke-co-alarm",
  lifecycle_handlers = {
    -- added = device_added,
    init = device_init,
    infoChanged = info_changed
  },
  matter_handlers = {
    attr = {
      [clusters.SmokeCoAlarm.ID] = {
        [clusters.SmokeCoAlarm.attributes.COState.ID] = binary_state_handler_factory(capabilities.gasDetector.gas.clear(), capabilities.gasDetector.gas.detected()),
      }
    },
  },
  can_handle = is_tuya_smoke_co_alarm
}

return matter_tuya_smoke_co_alarm_handler