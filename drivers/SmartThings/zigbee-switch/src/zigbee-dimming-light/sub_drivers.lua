local lazy_load = require "lazy_load_subdriver"

return {
  lazy_load("zigbee-dimming-light.osram-iqbr30"),
  lazy_load("zigbee-dimming-light.zll-dimmer")
}
