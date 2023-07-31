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

local capabilities = require "st.capabilities"
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })

local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31SN_PRODUCT_TYPE = 0x0001
local INOVELLI_LZW31_PRODUCT_TYPE = 0x0003
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001

local function can_handle_inovelli_led(opts, driver, device, ...)
  if device:id_match(
    INOVELLI_MANUFACTURER_ID,
    {INOVELLI_LZW31SN_PRODUCT_TYPE, INOVELLI_LZW31_PRODUCT_TYPE},
    INOVELLI_DIMMER_PRODUCT_ID
  ) then
    local subdriver = require("inovelli-LED")
    return true, subdriver
  end
  return false
end

local inovelli_led = {
  NAME = "Inovelli LED",
  can_handle = can_handle_inovelli_led,
  sub_drivers = {
    require("inovelli-LED/inovelli-lzw31sn")
  }
}

return inovelli_led
