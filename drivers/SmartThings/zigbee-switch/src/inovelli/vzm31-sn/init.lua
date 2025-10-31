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

local INOVELLI_VZM31_SN_FINGERPRINTS = {
  { mfr = "Inovelli", model = "VZM31-SN" },
}

local function can_handle_inovelli_vzm31_sn(opts, driver, device)
  for _, fp in ipairs(INOVELLI_VZM31_SN_FINGERPRINTS) do
    if device:get_manufacturer() == fp.mfr and device:get_model() == fp.model then
      return true
    end
  end
  return false
end

local vzm31_sn = {
  NAME = "inovelli vzm31-sn device-specific",
  can_handle = can_handle_inovelli_vzm31_sn,
}

return vzm31_sn