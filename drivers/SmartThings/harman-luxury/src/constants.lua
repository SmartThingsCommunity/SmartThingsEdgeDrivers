local Constants = {
  -- device constants
  IP = "device_ipv4",
  DEVICE_INFO = "device_info",
  HEALTH_TIMER = "value_health_timer",
  UPDATE_TIMER = "value_updates_timer",

  -- intervals constants (in seconds)
  UPDATE_INTERVAL = 2,
  HEALTH_CHEACK_INTERVAL = 10,

  -- discovery constants
  SERVICE_TYPE = "_sue-st._tcp",
  DOMAIN = "local",
  MAC = "mac",
  DNI = "dni",
  MNID = "mnid",
  SETUP_ID = "setupid",

  -- device setup constants
  DEFAULT_DEVICE_NAME = "HarmanLuxury",
  DEFAULT_MANUFACTURE_NAME = "Harman Luxury Audio",
  DEFAULT_MODEL_NAME = "Harman Luxury",
  DEFAULT_PRODUCT_NAME = "Harman Luxury",

  -- general consts
  VOL_STEP = 5
}
return Constants
