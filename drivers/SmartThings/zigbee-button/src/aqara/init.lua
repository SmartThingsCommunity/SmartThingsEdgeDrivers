local capabilities = require "st.capabilities"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"

local PowerConfiguration = clusters.PowerConfiguration
local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.remote.b1acn02" }
}

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function added_handler(self, device)
  device:emit_event(capabilities.button.supportedButtonValues({"pushed","held","double"}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}))
end

local do_configuration = function(self, device)
  device:configure()

  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))

  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
end

local function button_handler(driver, device, value, zb_rx)
  if value.value == 0 then
    device:emit_event(capabilities.button.button.held({ state_change = true }))
  elseif value.value == 1 then
    device:emit_event(capabilities.button.button.pushed({ state_change = true }))
  elseif value.value == 2 then
    device:emit_event(capabilities.button.button.double({ state_change = true }))
  end
end

local aqara_button_handler = {
  NAME = "Aqara Button Handler",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.6, 3.0),
    added = added_handler,
    doConfigure = do_configuration
  },
  zigbee_handlers = {
    attr = {
      [0x0012] = {
        [0x0055] = button_handler
      }
    }
  },
  can_handle = is_aqara_products
}

return aqara_button_handler
