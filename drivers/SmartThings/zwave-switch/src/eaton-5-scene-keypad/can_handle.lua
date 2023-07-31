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

local EATON_5_SCENE_KEYPAD_FINGERPRINT = {
  {mfr = 0x001A, prod = 0x574D, model = 0x0000}, -- Eaton 5-Scene Keypad
}

local function can_handle_eaton_5_scene_keypad(opts, driver, device, ...)
  for _, fingerprint in ipairs(EATON_5_SCENE_KEYPAD_FINGERPRINT) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("eaton-5-scene-keypad")
      return true, subdriver
    end
  end
  return false
end

local eaton_5_scene_keypad = {
  NAME = "Eaton 5-Scene Keypad",
  can_handle = can_handle_eaton_5_scene_keypad,
  lazy_load = true
}

return eaton_5_scene_keypad
