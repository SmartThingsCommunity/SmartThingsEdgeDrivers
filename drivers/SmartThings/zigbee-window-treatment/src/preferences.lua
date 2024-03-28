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

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local devices = {
    AEOTEC_PICO_SHUTTER = {
        MATCHING_MATRIX = { mfr = "AEOTEC", model = "ZGA004" },
        PARAMETERS = {
            ["operatingMode"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD03,
                    0x0001, 0x0244, data_types.Uint8, tonumber(value)):to_endpoint(0x01)
            end,
            ["timeSlatsTilting"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD03,
                    0x0002, 0x0244, data_types.Uint16, tonumber(value)):to_endpoint(0x01)
            end,
            ["slatsPosition"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD03,
                    0x0003, 0x0244, data_types.Uint8, tonumber(value)):to_endpoint(0x01)
            end,
            ["timeShadeOpenClose"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD03,
                    0x0004, 0x0244, data_types.Uint16, tonumber(value)):to_endpoint(0x01)
            end,
            ["timeMomentaryMovement"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD03,
                    0x0005, 0x0244, data_types.Uint16, tonumber(value)):to_endpoint(0x01)
            end,
            ["shadeMovementMode"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD03,
                    0x0006, 0x0244, data_types.Uint8, tonumber(value)):to_endpoint(0x01)
            end,
            ["timeMotorResponse"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD03,
                    0x0007, 0x0244, data_types.Uint8, tonumber(value)):to_endpoint(0x01)
            end,
            ["autoOpenClosePosition"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD03,
                    0x0008, 0x0244, data_types.Uint8, tonumber(value)):to_endpoint(0x01)
            end,
            ["s1LocalControlMode"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD00,
                    0x0011, 0x1310, data_types.Enum8, tonumber(value)):to_endpoint(0x02)
            end,
            ["s2LocalControlMode"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD00,
                    0x0011, 0x1310, data_types.Enum8, tonumber(value)):to_endpoint(0x03)
            end,
            ["s1Actions"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD00,
                    0x0010, 0x1310, data_types.Enum8, tonumber(value)):to_endpoint(0x02)
            end,
            ["s2Actions"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD00,
                    0x0010, 0x1310, data_types.Enum8, tonumber(value)):to_endpoint(0x03)
            end,
            ["s1ExternalSwitchConfig"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD00,
                    0x0000, 0x1310, data_types.Enum8, tonumber(value)):to_endpoint(0x02)
            end,
            ["s2ExternalSwitchConfig"] = function(device, value)
                return cluster_base.write_manufacturer_specific_attribute(device, 0xFD00,
                    0x0000, 0x1310, data_types.Enum8, tonumber(value)):to_endpoint(0x03)
            end
        }
    }
}
local preferences = {}

preferences.update_preferences = function(driver, device, args)
    local prefs = preferences.get_device_parameters(device)
    if prefs ~= nil then
        for id, value in pairs(device.preferences) do
            if not (args and args.old_st_store) or (args.old_st_store.preferences[id] ~= value and prefs and prefs[id]) then
                local message = prefs[id](device, value)
                device:send(message)
            end
        end
    end
end

preferences.get_device_parameters = function(zigbee_device)
    for _, device in pairs(devices) do
        if zigbee_device:get_manufacturer() == device.MATCHING_MATRIX.mfr and
            zigbee_device:get_model() == device.MATCHING_MATRIX.model then
            return device.PARAMETERS
        end
    end
    return nil
end

return preferences
