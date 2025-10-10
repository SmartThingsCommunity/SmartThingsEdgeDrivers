local lazy_load = require "lazy_load_subdriver"

return {
  lazy_load("zigbee-switch-power.aurora-relay"),
  lazy_load("zigbee-switch-power.vimar")
}
