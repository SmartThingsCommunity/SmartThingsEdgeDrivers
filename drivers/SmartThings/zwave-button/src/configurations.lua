-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local devices = {
  AEOTEC_NANOMOTE_ONE = {
    MATCHING_MATRIX = {
      mfrs = 0x0371,
      product_types = {0x0002, 0x0102},
      product_ids = 0x0004
    },
    CONFIGS = {
      number_of_buttons = 1,
      supported_button_values = {"pushed", "held", "down_hold"}
    }
  },
  FIBARO_BUTTON = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0F01,
      product_ids = {0x1000, 0x2000, 0x3000}
    },
    CONFIGS = {
      number_of_buttons = 1,
      supported_button_values = {"pushed", "held", "down_hold", "double", "pushed_3x", "pushed_4x", "pushed_5x"}
    }
  },
  AEOTEC_KEYFOB = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = {0x0001, 0x0101},
      product_ids = 0x0058
    },
    CONFIGS = {
      number_of_buttons = 4,
      supported_button_values = {"pushed", "held"}
    }
  },
  AEOTEC_NANOMOTE_QUAD = {
    MATCHING_MATRIX = {
      mfrs = 0x0371,
      product_types = {0x0002, 0x0102},
      product_ids = 0x0003
    },
    CONFIGS = {
      number_of_buttons = 4,
      supported_button_values = {"pushed", "held"}
    }
  },
  AEOTEC_WALLMOTE = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = {0x0002, 0x0102},
      product_ids = 0x0081
    },
    CONFIGS = {
      number_of_buttons = 2,
      supported_button_values = {"pushed", "held"}
    }
  },
  AEOTEC_WALLMOTE_QUAD = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = {0x0002, 0x0102},
      product_ids = 0x0082
    },
    CONFIGS = {
      number_of_buttons = 4,
      supported_button_values = {"pushed", "held"}
    }
  },
  FIBARO_KEYFOB = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x1001,
      product_ids = {0x1000, 0x2000, 0x3000}
    },
    CONFIGS = {
      number_of_buttons = 6,
      supported_button_values = {"pushed", "held", "double", "down_hold", "pushed_3x"}
    }
  },
  EVERSPRING = {
    MATCHING_MATRIX = {
      mfrs = 0x0060,
      product_types = 0x000A,
      product_ids = 0x0003
    },
    CONFIGS = {
      number_of_buttons = 2,
      supported_button_values = {"pushed", "held", "double"}
    }
  },
  AEOTEC_MINIMOTE = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = 0x0001,
      product_ids = 0x0003
    },
    CONFIGS = {
      number_of_buttons = 4,
      supported_button_values = {"pushed", "held"}
    }
  },
  AEOTEC_ILLUMINO = {
    MATCHING_MATRIX = {
      mfrs = 0x0371,
      product_types = 0x0102,
      product_ids = 0x0016
    },
    CONFIGS = {
      number_of_buttons = 2,
      supported_button_values = {"pushed", "held", "down_hold", "double", "pushed_3x", "pushed_4x", "pushed_5x"}
    }
  },
  AEOTEC_PANIC_BUTTON = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = 0x0001,
      product_ids = 0x0026
    },
    CONFIGS = {
      number_of_buttons = 1,
      supported_button_values = {"pushed", "held"}
    }
  },
  SHELLY_WAVE_i4 = {
    MATCHING_MATRIX = {
      mfrs = 0x0460,
      product_types = {0x0009},
      product_ids = 0x0081
    },
    CONFIGS = {
      number_of_buttons = 4,
      supported_button_values = {"pushed", "held", "down_hold", "double"}
    }
  },
  SHELLY_WAVE_i4DC = {
    MATCHING_MATRIX = {
      mfrs = 0x0460,
      product_types = {0x0009},
      product_ids = 0x0082
    },
    CONFIGS = {
      number_of_buttons = 4,
      supported_button_values = {"pushed", "held", "down_hold", "double"}
    }
  }
}

local DEFAULT_CONFIGS = {
  number_of_buttons = 1,
  supported_button_values = {"pushed", "held"}
}

local configs = {}

configs.get_device_parameters = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.CONFIGS
    end
  end
  return DEFAULT_CONFIGS
end

return configs
