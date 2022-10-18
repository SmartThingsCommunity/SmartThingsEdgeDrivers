-- Copyright 2022 SmartThings
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
local st_device = require "st.device"

local FIBARO_WALLI_DOUBLE_SWITCH_FINGERPRINT = {mfr = 0x010F, prod = 0x1B01, model = 0x1000}

local function can_handle_fibaro_walli_double_switch(opts, driver, device, ...)
  return device:id_match(FIBARO_WALLI_DOUBLE_SWITCH_FINGERPRINT.mfr, FIBARO_WALLI_DOUBLE_SWITCH_FINGERPRINT.prod, FIBARO_WALLI_DOUBLE_SWITCH_FINGERPRINT.model)
end

local function generate_child_name(parent_label)
  if string.sub(parent_label, -1) == '1' then
    return string.format("%s2", string.sub(parent_label, 0, -2))
  else
    return string.format("%s 2", parent_label)
  end
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    local name = generate_child_name(device.label)
    local metadata = {
      type = "EDGE_CHILD",
      label = name,
      profile = "metering-switch",
      parent_device_id = device.id,
      parent_assigned_child_key = string.format("%02X", 2),
      vendor_provided_label = name
    }
    driver:try_create_device(metadata)
  end
  device:refresh()
end

local fibaro_walli_double_switch = {
  NAME = "fibaro walli double switch",
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = can_handle_fibaro_walli_double_switch
}

return fibaro_walli_double_switch
