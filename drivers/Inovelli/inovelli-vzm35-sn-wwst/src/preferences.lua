local data_types = require "st.zigbee.data_types"
local log = require "log"
local utils = require "st.utils"

local devices = {
  INOVELLI_VZM35_SN = {
    FINGERPRINTS = {
      { mfr = "Inovelli", model = "VZM35-SN" }
    },
    PARAMETERS = {
      parameter258 = {parameter_number = 258, size = data_types.Boolean},
      parameter22 = {parameter_number = 22, size = data_types.Uint8},
      parameter52 = {parameter_number = 52, size = data_types.Boolean},
      parameter1 = {parameter_number = 1, size = data_types.Uint8},
      parameter2 = {parameter_number = 2, size = data_types.Uint8},
      parameter3 = {parameter_number = 3, size = data_types.Uint8},
      parameter4 = {parameter_number = 4, size = data_types.Uint8},
      parameter5 = {parameter_number = 5, size = data_types.Uint8},
      parameter6 = {parameter_number = 6, size = data_types.Uint8},
      parameter7 = {parameter_number = 7, size = data_types.Uint8},
      parameter8 = {parameter_number = 8, size = data_types.Uint8},
      parameter9 = {parameter_number = 9, size = data_types.Uint8},
      parameter10 = {parameter_number = 10, size = data_types.Uint8},
      parameter11 = {parameter_number = 11, size = data_types.Boolean},
      parameter12 = {parameter_number = 12, size = data_types.Uint16},
      parameter13 = {parameter_number = 13, size = data_types.Uint8},
      parameter14 = {parameter_number = 14, size = data_types.Uint8},
      parameter15 = {parameter_number = 15, size = data_types.Uint8},
      parameter17 = {parameter_number = 17, size = data_types.Uint8},
      parameter21 = {parameter_number = 21, size = data_types.Boolean},
      parameter50 = {parameter_number = 50, size = data_types.Uint8},
      parameter53 = {parameter_number = 53, size = data_types.Boolean},
      parameter54 = {parameter_number = 54, size = data_types.Boolean},
      parameter55 = {parameter_number = 55, size = data_types.Uint8},
      parameter56 = {parameter_number = 56, size = data_types.Uint8},
      parameter95 = {parameter_number = 95, size = data_types.Uint8},
      parameter96 = {parameter_number = 96, size = data_types.Uint8},
      parameter97 = {parameter_number = 97, size = data_types.Uint8},
      parameter98 = {parameter_number = 98, size = data_types.Uint8},
      parameter120 = {parameter_number = 120, size = data_types.Uint8},
      parameter121 = {parameter_number = 121, size = data_types.Boolean},
      parameter123 = {parameter_number = 123, size = data_types.Boolean},
      parameter125 = {parameter_number = 125, size = data_types.Boolean},
      parameter129 = {parameter_number = 129, size = data_types.Uint32},
      parameter130 = {parameter_number = 130, size = data_types.Uint8},
      parameter131 = {parameter_number = 131, size = data_types.Uint8},
      parameter132 = {parameter_number = 132, size = data_types.Uint8},
      parameter133 = {parameter_number = 133, size = data_types.Uint8},
      parameter134 = {parameter_number = 134, size = data_types.Uint8},
      parameter256 = {parameter_number = 256, size = data_types.Boolean},
      parameter260 = {parameter_number = 260, size = data_types.Boolean},
      parameter262 = {parameter_number = 262, size = data_types.Boolean},
      parameter263 = {parameter_number = 263, size = data_types.Boolean},
    }
  },
  INOVELLI_VZM35_SN_MG24 = {
    FINGERPRINTS = {
      { mfr = "Inovelli", model = "VZM35-SN-MG24" }
    },
    PARAMETERS = {
      parameter258 = {parameter_number = 258, size = data_types.Boolean},
      parameter22 = {parameter_number = 22, size = data_types.Uint8},
      parameter52 = {parameter_number = 52, size = data_types.Boolean},
      parameter1 = {parameter_number = 1, size = data_types.Uint8},
      parameter2 = {parameter_number = 2, size = data_types.Uint8},
      parameter3 = {parameter_number = 3, size = data_types.Uint8},
      parameter4 = {parameter_number = 4, size = data_types.Uint8},
      parameter5 = {parameter_number = 5, size = data_types.Uint8},
      parameter6 = {parameter_number = 6, size = data_types.Uint8},
      parameter7 = {parameter_number = 7, size = data_types.Uint8},
      parameter8 = {parameter_number = 8, size = data_types.Uint8},
      parameter9 = {parameter_number = 9, size = data_types.Uint8},
      parameter10 = {parameter_number = 10, size = data_types.Uint8},
      parameter11 = {parameter_number = 11, size = data_types.Boolean},
      parameter12 = {parameter_number = 12, size = data_types.Uint16},
      parameter13 = {parameter_number = 13, size = data_types.Uint8},
      parameter14 = {parameter_number = 14, size = data_types.Uint8},
      parameter15 = {parameter_number = 15, size = data_types.Uint8},
      parameter17 = {parameter_number = 17, size = data_types.Uint8},
      parameter21 = {parameter_number = 21, size = data_types.Boolean},
      parameter50 = {parameter_number = 50, size = data_types.Uint8},
      parameter53 = {parameter_number = 53, size = data_types.Boolean},
      parameter95 = {parameter_number = 95, size = data_types.Uint8},
      parameter96 = {parameter_number = 96, size = data_types.Uint8},
      parameter97 = {parameter_number = 97, size = data_types.Uint8},
      parameter98 = {parameter_number = 98, size = data_types.Uint8},
      parameter123 = {parameter_number = 123, size = data_types.Boolean},
      parameter125 = {parameter_number = 125, size = data_types.Boolean},
      parameter256 = {parameter_number = 256, size = data_types.Boolean},
      parameter260 = {parameter_number = 260, size = data_types.Boolean},
      parameter262 = {parameter_number = 262, size = data_types.Boolean},
    }
  }
}

local preferences = {}

preferences.get_device_parameters = function(zigbee_device)
      for _, device in pairs(devices) do
        for _, fingerprint in pairs(device.FINGERPRINTS) do
          if zigbee_device:get_manufacturer() == fingerprint.mfr and zigbee_device:get_model() == fingerprint.model then
            return device.PARAMETERS
          end
        end
      end
      return nil
end

preferences.to_numeric_value = function(new_value)
  local numeric = tonumber(new_value)
  if numeric == nil then -- in case the value is Booleanean
    numeric = new_value and 1 or 0
  end
  return numeric
end

preferences.calculate_parameter = function(new_value, type, number)
  local numeric = tonumber(new_value)
  --if numeric == nil then -- in case the value is Booleanean
  --  numeric = new_value and 1 or 0
  --end
  --return numeric
  --log.info(numeric)
  --log.info(type)
  --log.info(number)
  if number == "parameter9" or number == "parameter10" or number == "parameter13" or number == "parameter14"  or number == "parameter15" or number == "parameter55" or number == "parameter56" then
    if new_value == 101 then
      return 255
    else
      return utils.round(new_value / 100 * 254)
    end
  else
    return new_value
  end
  
end

return preferences