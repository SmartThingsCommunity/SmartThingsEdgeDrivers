local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local zigbee_water_driver_template = {
  supported_capabilities = {
    capabilities.waterSensor,
    capabilities.switch,
    capabilities.battery,
  },
}

defaults.register_for_default_handlers(zigbee_water_driver_template, zigbee_water_driver_template.supported_capabilities)
local driver = ZigbeeDriver("zigbee-watering-kit", zigbee_water_driver_template)
driver:run()
