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

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local log = require "log"

local SMARTVILL_SWITCH_FINGERPRINTS = {
    { mfr = "SMARTvill", model = "SLA02"},
    { mfr = "SMARTvill", model = "SLA03"},
    { mfr = "SMARTvill", model = "SLA04"},
    { mfr = "SMARTvill", model = "SLA05"},
    { mfr = "SMARTvill", model = "SLA06"}
}

local function is_smartvill(opts, driver, device)
    for _, fingerprint in ipairs(SMARTVILL_SWITCH_FINGERPRINTS) do
        -- log.info("is_smartvill")
        if device:get_manufacturer() == nil and device:get_model() == fingerprint.model then
            return true
        elseif device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
            return true
        end
    end
    return false
end
 
local function component_to_endpoint(device, component_id)
    local ep_num = 1
    if component_id == "main" then
        ep_num = 1
        return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
    else
        ep_num = tonumber(component_id:match("switch(%d)"))
        return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
    end
end
  
local function endpoint_to_component(device, ep)
    local ep_num = ep
    return string.format("switch%d", ep_num)
end

local function device_init(driver, device, event)
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
end

local smartvill = {
    NAME = "smartvill",
    lifecycle_handlers = {
        init = device_init,
    },
    can_handle = is_smartvill
}

return smartvill