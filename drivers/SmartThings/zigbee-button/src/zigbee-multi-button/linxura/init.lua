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
local IASZone = (require "st.zigbee.zcl.clusters").IASZone
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local Groups = clusters.Groups
local log = require "log"
local device_management = require "st.zigbee.device_management"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local BUTTON1_HELD = 0x0001
local BUTTON1_PUSHED = 0x0003
local BUTTON1_DOUBLE = 0x0005
local BUTTON2_HELD = 0x0007
local BUTTON2_PUSHED = 0x0009
local BUTTON2_DOUBLE = 0x000B
local BUTTON3_HELD = 0x000D
local BUTTON3_PUSHED = 0x000F
local BUTTON3_DOUBLE = 0x0011
local BUTTON4_HELD = 0x00013
local BUTTON4_PUSHED = 0x00015
local BUTTON4_DOUBLE = 0x0017

local BUTTON1 = "button1"
local BUTTON2 = "button2"
local BUTTON3 = "button3"
local BUTTON4 = "button4"


local LINXURA_BUTTON_FINGERPRINTS = {
    { mfr = "Linxura", model = "Smart Controller" }
}

local configuration = {
    {
        cluster = IASZone.ID,
        attribute = IASZone.attributes.ZoneStatus.ID,
        minimum_interval = 0,
        maximum_interval = 3600,
        data_type = IASZone.attributes.ZoneStatus.base_type,
        reportable_change = 1
    }
}
local is_linxura_button = function(opts, driver, device)
    for _, fingerprint in ipairs(LINXURA_BUTTON_FINGERPRINTS) do
        if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
        return true
        end
    end
    return false
end

local function present_value_attr_handler(driver, device, zone_status, zb_rx)   
    log.info("present_value_attr_handler The current value is: ", zone_status.value)
    local status = zone_status
    

    local additional_fields = {
        state_change = true
    }
    local event
    local mod = status.value % 6
    if mod == 1 then
        event = capabilities.button.button.pushed(additional_fields)
    elseif mod == 3 then
        event = capabilities.button.button.double(additional_fields)
    elseif mod == 5 then
        event = capabilities.button.button.held(additional_fields)
    else
        return false
    end

    if status.value == BUTTON1_HELD or status.value == BUTTON1_PUSHED or status.value == BUTTON1_DOUBLE then
        device:emit_component_event(device.profile.components[BUTTON1], event)
        device:emit_event(event)
    elseif status.value == BUTTON2_HELD or status.value == BUTTON2_PUSHED or status.value == BUTTON2_DOUBLE then
        device:emit_component_event(device.profile.components[BUTTON2], event)
        device:emit_event(event)
    elseif status.value == BUTTON3_HELD or status.value == BUTTON3_PUSHED or status.value == BUTTON3_DOUBLE then
        device:emit_component_event(device.profile.components[BUTTON3], event)
        device:emit_event(event)
    elseif status.value == BUTTON4_HELD or status.value == BUTTON4_PUSHED or status.value == BUTTON4_DOUBLE then
        device:emit_component_event(device.profile.components[BUTTON4], event)
        device:emit_event(event)
    end
end


local function device_init(driver, device)
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
  


local linxura_device_handler = {
    NAME = "Linxura Device Handler",
    lifecycle_handlers = {
        init = device_init,
    },
     
    zigbee_handlers = {
    attr = {
        [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = present_value_attr_handler
        }
    },
    },
    
    can_handle = is_linxura_button,
}

return linxura_device_handler