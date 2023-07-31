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

--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local preferences = require "preferences"

local LEVITON_MANUFACTURER_ID = 0x001D
local LEVITON_PRODUCT_TYPE_ZWXXX = 0x0002
local LEVITON_PRODUCT_ID_ZW6HD = 0x0041
local LEVITON_PRODUCT_ID_ZW15S = 0x0042

local function can_handle_leviton_zwxxx(opts, driver, device, ...)
  local is_match = device:id_match(
    LEVITON_MANUFACTURER_ID,
    LEVITON_PRODUCT_TYPE_ZWXXX,
    {LEVITON_PRODUCT_ID_ZW6HD, LEVITON_PRODUCT_ID_ZW15S}
  );

  print("can_handle_leviton_zwxxx", is_match);

  if is_match then
    return true
  end

  return false
end

local function device_added(self, device, event, args)
  local parameters = preferences.get_device_parameters(device)

  if parameters then
    for id, pref in pairs(parameters) do
      print("leviton_zwxxx get configuration", pref.parameter_number)
      device:send(Configuration:Get({ parameter_number = pref.parameter_number }))
    end
  end
end

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
  local parameters = preferences.get_device_parameters(device)

  if parameters then
    for id, pref in pairs(parameters) do

      local new_parameter_value = preferences.to_numeric_value(device.preferences[id])
      local old_parameter_value = new_parameter_value

      if args and args.old_st_store and args.old_st_store.preferences then
        old_parameter_value = preferences.to_numeric_value(args.old_st_store.preferences[id])
      end

      if new_parameter_value ~= old_parameter_value then
        print("leviton_zwxxx info_changed", pref.parameter_number, old_parameter_value, new_parameter_value)
        device:send(Configuration:Set({
          parameter_number = pref.parameter_number,
          size = pref.size,
          configuration_value = new_parameter_value
        }))
      end
    end
  end
end

local leviton_zwxxx = {
  NAME = "Leviton Z-Wave in-wall device",
  can_handle = can_handle_leviton_zwxxx,
  lifecycle_handlers = {
    infoChanged = info_changed,
    added = device_added,
  }
}

return leviton_zwxxx