local aqara_utils = require "aqara/aqara_utils"

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.motion.agl02" },
  { mfr = "LUMI", model = "lumi.motion.agl04" }
}
local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function detection_frequency_capability_handler(driver, device, command)
  local frequency = command.args.frequency
  aqara_utils.set_pref_changed_field(device, aqara_utils.PREF_FREQUENCY_KEY, frequency)
  aqara_utils.write_custom_attribute(device, aqara_utils.FREQUENCY_ATTRIBUTE_ID, frequency)
end

local function detection_frequency_attr_handler(driver, device, value, zb_rx)
  local frequency = value.value
  device:set_field(aqara_utils.PREF_FREQUENCY_KEY, frequency)
  device:emit_event(aqara_utils.detectionFrequency.detectionFrequency(frequency))
end

local aqara_motion_handler = {
  NAME = "Aqara Motion Handler",
  capability_handlers = {
    [aqara_utils.detectionFrequencyId] = {
      [aqara_utils.detectionFrequencyCommand] = detection_frequency_capability_handler,
    }
  },
  zigbee_handlers = {
    attr = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [aqara_utils.FREQUENCY_ATTRIBUTE_ID] = detection_frequency_attr_handler
      }
    }
  },
  sub_drivers = {
    require("aqara.motion-illuminance"),
    require("aqara.high-precision-motion")
  },
  can_handle = is_aqara_products
}

return aqara_motion_handler
