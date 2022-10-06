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

local devices = {
    FIBARO = {
        MATCHING_MATRIX = {
            mfrs = 0x010F,
            product_types = 0x0C02,
            product_ids = {0x1002, 0x1003, 0x3002, 0x4002}
        },
        PARAMETERS = {
            ["certifiedpreferences.smokeSensorSensitivity"] = {parameter_number = 1, size = 1},
            ["certifiedpreferences.zwaveNotificationStatus"] = {parameter_number = 2, size = 1},
            ["certifiedpreferences.indicatorNotification"] = {parameter_number = 3},
            ["certifiedpreferences.soundNotificationStatus"] = {parameter_number = 4, size = 1},
            ["certifiedpreferences.tempReportInterval"] = {parameter_number = 20, size = 2},
            ["certifiedpreferences.tempReportHysteresis"] = {parameter_number = 21, size = 2},
            ["certifiedpreferences.temperatureThreshold"] = {parameter_number = 30, size = 2},
            ["certifiedpreferences.overheatInterval"] = {parameter_number = 31, size = 2},
            ["certifiedpreferences.outOfRange"] = {parameter_number = 32, size = 2}
        }
    },
    FIBARO_CO_SENSOR_ZW5= {
        MATCHING_MATRIX = {
            mfrs = 0x010F,
            product_types = 0x1201,
            product_ids = {0x1000, 0x1001}
        },
        PARAMETERS = {
            zwaveNotifications = {parameter_number = 2, size = 1},
            overheatThreshold = {parameter_number = 22, size = 1}
        }
    }
}

local preferences = {}

preferences.get_device_parameters = function(zw_device)
    for _, device in pairs(devices) do
        if zw_device:id_match(
            device.MATCHING_MATRIX.mfrs,
            device.MATCHING_MATRIX.product_types,
            device.MATCHING_MATRIX.product_ids) then
            return device.PARAMETERS
        end
    end
    return nil
end

preferences.to_numeric_value = function(new_value)
    local numeric = tonumber(new_value)
    if numeric == nil then -- in case the value is boolean
        numeric = new_value and 1 or 0
    end
    return numeric
end

return preferences
