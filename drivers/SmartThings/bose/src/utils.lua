
--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.

local utils = {}

--- This gets the serial number for the device which is how we identify unique speakers on the LAN
--- Devices that were migrated from DTHs will have the value stored in device.data.
---
--- @param device table
--- @return string the serial number of the device
utils.get_serial_number = function(device)
  local res = device:get_field("serial_number")
  if res == nil then
    res = device.data and device.data.deviceID or device.device_network_id
    device:set_field("serial_number", res)
  end
  return res
end

--- Sanitize xml fields parsed from device responses
--- Namely this converts empty tables to nil.
---
--- @param f any the field to sanitize
--- @param def any the default value to return if field is empty or nil
--- @return any the sanitized field or the default
utils.sanitize_field = function(f, def)
  if not f or (type(f) == "table" and #f == 0) then
    return def
  else
    return f
  end
end

return utils
