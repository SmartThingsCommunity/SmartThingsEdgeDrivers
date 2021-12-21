local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local BAD_YALE_LOCK_FINGERPRINTS = {
  { mfr = "Yale", model = "YRD220/240 TSDB" },
  { mfr = "Yale", model = "YRL220 TS LL" },
  { mfr = "Yale", model = "YRD210 PB DB" },
  { mfr = "Yale", model = "YRL210 PB LL" },
}

local is_bad_yale_lock_models = function(opts, driver, device)
  for _, fingerprint in ipairs(BAD_YALE_LOCK_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local battery_report_handler = function(driver, device, value)
   device:emit_event(capabilities.battery.battery(value.value))
end

local bad_yale_driver = {
  NAME = "YALE BAD Lock Driver",
  zigbee_handlers = {
    attr = {
      [clusters.PowerConfiguration.ID] = {
        [clusters.PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_report_handler
      }
    }
  },
  can_handle =  is_bad_yale_lock_models
}

return bad_yale_driver
