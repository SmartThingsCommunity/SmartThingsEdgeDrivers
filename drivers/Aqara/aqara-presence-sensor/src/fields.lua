--- Table of constants used to index in to device store fields
--- @module "fields"
--- @class table
--- @field IPV4 string the ipV4 address of the device

local fields = {
  DEVICE_IPV4 = "device_ipv4",
  DEVICE_INFO = "device_info",
  CONN_INFO = "conn_info",
  EVENT_SOURCE = "eventsource",
  MONITORING_TIMER = "monitoring_timer",
  CREDENTIAL = "credential",
  _INIT = "init"
}

return fields
