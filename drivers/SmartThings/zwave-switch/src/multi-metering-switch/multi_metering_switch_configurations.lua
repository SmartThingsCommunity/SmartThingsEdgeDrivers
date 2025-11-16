-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local devices = {
  AEOTEC_NANO_SWITCH_1 = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = 0x0003,
      product_ids = 0x0084,
    },
    CONFIGURATION = {
      child_switch_device_profile = "metering-switch"
    }
  },
  AEOTEC_NANO_SWITCH_2 = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = 0x0103,
      product_ids = 0x0084,
    },
    CONFIGURATION = {
      child_switch_device_profile = "metering-switch"
    }
  },
  AEOTEC_NANO_SWITCH_3 = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = 0x0203,
      product_ids = 0x0084,
    },
    CONFIGURATION = {
      child_switch_device_profile = "metering-switch"
    }
  },
  ZOOZ_ZEN_POWER_STRIP = {
    MATCHING_MATRIX = {
      mfrs = 0x027A,
      product_types = 0xA000,
      product_ids = 0xA004,
      children = 4
    },
    CONFIGURATION = {
      child_switch_device_profile = "metering-switch"
    }
  },
  WYFY_TOUCH_1 = {
    MATCHING_MATRIX = {
      mfrs = 0x015F,
      product_types = 0x3102,
      product_ids = 0x0201,
    },
    CONFIGURATION = {
      child_switch_device_profile = "switch-binary"
    }
  },
  WYFY_TOUCH_2 = {
    MATCHING_MATRIX = {
      mfrs = 0x015F,
      product_types = 0x3102,
      product_ids = 0x0202,
    },
    CONFIGURATION = {
      child_switch_device_profile = "switch-binary"
    }
  },
  WYFY_TOUCH_4 = {
    MATCHING_MATRIX = {
      mfrs = 0x015F,
      product_types = 0x3102,
      product_ids = 0x0204,
    },
    CONFIGURATION = {
      child_switch_device_profile = "switch-binary"
    }
  },
  WYFY_TOUCH_1_1 = {
    MATCHING_MATRIX = {
      mfrs = 0x015F,
      product_types = 0x3111,
      product_ids = 0x5102,
    },
    CONFIGURATION = {
      child_switch_device_profile = "switch-binary"
    }
  },
  WYFY_TOUCH_2_1 = {
    MATCHING_MATRIX = {
      mfrs = 0x015F,
      product_types = 0x3121,
      product_ids = 0x5102,
    },
    CONFIGURATION = {
      child_switch_device_profile = "switch-binary"
    }
  },
  WYFY_TOUCH_4_1 = {
    MATCHING_MATRIX = {
      mfrs = 0x015F,
      product_types = 0x3141,
      product_ids = 0x5102,
    },
    CONFIGURATION = {
      child_switch_device_profile = "switch-binary"
    }
  },
  SHELLY_WAVE_2PM_AND_PRO = {
    MATCHING_MATRIX = {
      mfrs = 0x0460,
      product_ids = {0x0081, 0x008D},
      product_types = 0x0002,
      children = 1
    },
    CONFIGURATION = {
      child_switch_device_profile = "metering-switch"
    }
  },
  SHELLY_WAVE_PRO_2 = {
    MATCHING_MATRIX = {
      mfrs = 0x0460,
      product_ids = 0x008C,
      product_types = 0x0002,
      children = 1
    },
    CONFIGURATION = {
      child_switch_device_profile = "switch-binary"
    }
  },
}

local multi_metering_switch_configurations = {}

multi_metering_switch_configurations.get_child_switch_device_profile = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.CONFIGURATION.child_switch_device_profile
    end
  end
end

multi_metering_switch_configurations.get_child_amount = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.MATCHING_MATRIX.children
    end
  end
end

return multi_metering_switch_configurations
