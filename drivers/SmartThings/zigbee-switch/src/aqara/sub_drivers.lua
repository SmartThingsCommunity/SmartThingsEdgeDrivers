local lazy_load = require "lazy_load_subdriver"

return {
  lazy_load("aqara.multi-switch"),
  lazy_load("aqara.version"),
}
