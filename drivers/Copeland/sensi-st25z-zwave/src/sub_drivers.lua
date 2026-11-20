local lazy_load_if_possible = require "lazy_load_subdriver"
local sub_drivers = {
  lazy_load_if_possible("thermostat-sensi-st25z"),
}
return sub_drivers
