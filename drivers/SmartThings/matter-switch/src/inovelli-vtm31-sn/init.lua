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

local clusters = require "st.matter.clusters"
local data_types = require "st.matter.data_types"
local device_lib = require "st.device"
local log = require "log"

local INOVELLI_VTM31_SN_FINGERPRINT = { vendor_id = 0x1361, product_id = 0x0001 }

local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"

local preference_map_inovelli_vtm31sn = {
  switchMode = {parameter_number = 1, size = data_types.Uint8},
  smartBulbMode = {parameter_number = 2, size = data_types.Uint8},
  dimmingEdge = {parameter_number = 3, size = data_types.Uint8},
  dimmingSpeed = {parameter_number = 4, size = data_types.Uint8},
  relayClick = {parameter_number = 5, size = data_types.Uint8},
  ledIndicatorColor = {parameter_number = 6, size = data_types.Uint8},
}

local is_inovelli_vtm31_sn = function(device)
  if device.manufacturer_info.vendor_id == INOVELLI_VTM31_SN_FINGERPRINT.vendor_id and
    device.manufacturer_info.product_id == INOVELLI_VTM31_SN_FINGERPRINT.product_id then
    log.info("Using sub driver")
    return true
  end
  return false
end

local preferences_to_numeric_value = function(new_value)
  local numeric = tonumber(new_value)
  if numeric == nil then -- in case the value is Boolean
    numeric = new_value and 1 or 0
  end
  return numeric
end

local function info_changed(device, args)
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    return
  end
  local time_diff = 3
  local last_clock_set_time = device:get_field(LATEST_CLOCK_SET_TIMESTAMP)
  if last_clock_set_time ~= nil then
    time_diff = os.difftime(os.time(), last_clock_set_time)
  end
  device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time(), {persist = true})
  if time_diff > 2 then
    local preferences = preference_map_inovelli_vtm31sn
    for id, value in pairs(device.preferences) do
      if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
        local new_parameter_value = preferences_to_numeric_value(device.preferences[id])
        local req = clusters.ModeSelect.server.commands.ChangeToMode(device, preferences[id].parameter_number,
          new_parameter_value)
        device:send(req)
      end
    end
  end
end

local inovelli_vtm31_sn_handler = {
  NAME = "inovelli vzm31-sn handler",
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = is_inovelli_vtm31_sn
}

return inovelli_vtm31_sn_handler
