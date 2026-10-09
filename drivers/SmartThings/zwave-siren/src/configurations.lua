-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local devices = {
  YALE_SIREN = {
    MATCHING_MATRIX = {
      mfrs = 0x0129,
      product_types = 0x6F01,
      product_ids = 0x0001
    },
    CONFIGURATION = {
      {parameter_number = 1, size = 1, configuration_value = 10},
      {parameter_number = 2, size = 1, configuration_value = 1},
      {parameter_number = 3, size = 1, configuration_value = 0},
      {parameter_number = 4, size = 1, configuration_value = 0},
    }
  },
  EVERSPRING_SIREN = {
    MATCHING_MATRIX = {
      mfrs = 0x0060,
      product_types = 0x000C,
      product_ids = 0x0002
    },
    CONFIGURATION = {
      {parameter_number = 1, size = 2, configuration_value = 180}
    }
	},
	ZIPATO_SIREN = {
    MATCHING_MATRIX = {
      mfrs = 0x0131,
      product_types = 0x0003,
      product_ids = 0x1083
    },
    CONFIGURATION = {
      {parameter_number = 1, size = 1, configuration_value = 3},
      {parameter_number = 2, size = 1, configuration_value = 2},
      {parameter_number = 5, size = 1, configuration_value = 10}
    }
  }
}

local configurations = {}

configurations.get_device_configuration = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.CONFIGURATION
    end
  end
  return nil
end

return configurations
