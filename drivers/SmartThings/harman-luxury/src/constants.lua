local Constants = {
  -- device constants
  IP = "device_ipv4",
  DEVICE_INFO = "device_info",
  CREDENTIAL = "credential",
  INITIALISED = "initialised",
  WEBSOCKET = "websocket",

  -- message fields
  MESSAGE = "message",
  CAPABILITY = "capability",
  COMMAND = "command",
  ARG = "arg",

  -- intervals constants (in seconds)
  WS_SOCKET_TIMEOUT = 10,
  WS_IDLE_PING_PERIOD = 30,
  WS_RECONNECT_PERIOD = 10,
  HTTP_TIMEOUT = 5,

  -- discovery constants
  SERVICE_TYPE = "_sue-st._tcp",
  DOMAIN = "local",
  MAC = "mac",
  DNI = "dni",
  MNID = "mnid",
  SETUP_ID = "setupid",

  -- device setup constants
  DEFAULT_DEVICE_NAME = "HarmanLuxury",
  DEFAULT_MANUFACTURER_NAME = "Harman Luxury Audio",
  DEFAULT_MODEL_NAME = "Harman Luxury",
  DEFAULT_PRODUCT_NAME = "Harman Luxury",

  -- general consts
  VOL_STEP = 5,
  WS_PORT = 50002,
}
return Constants
