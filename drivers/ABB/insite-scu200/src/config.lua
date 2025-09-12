local config = {}

-- Device Config
config.DEVICE_TYPE = "LAN"

config.MANUFACTURER = "ABB"

config.BRIDGE_PROFILE = "abb.scu200.bridge.v1"
config.BRIDGE_TYPE    = "SCU200"
config.BRIDGE_VERSION = "1"

config.BRIDGE_URN = "urn:" .. config.MANUFACTURER .. ":device:" .. config.BRIDGE_TYPE .. ":" .. config.BRIDGE_VERSION

config.BRIDGE_CONN_MONITOR_INTERVAL = 300  -- 5 minutes

-- Edge Child Config
config.EDGE_CHILD_TYPE = "EDGE_CHILD"

config.EDGE_CHILD_CURRENT_SENSOR_TYPE      = "CurrentSensor"
config.EDGE_CHILD_ENERGY_METER_MODULE_TYPE = "EnergyMeterModule"
config.EDGE_CHILD_AUXILIARY_CONTACT_TYPE   = "AuxiliaryContact"
config.EDGE_CHILD_OUTPUT_MODULE_TYPE       = "OutputModule"
config.EDGE_CHILD_ENERGY_METER_TYPE        = "EnergyMeter"
config.EDGE_CHILD_WATER_METER_TYPE         = "WaterMeter"
config.EDGE_CHILD_GAS_METER_TYPE           = "GasMeter"
config.EDGE_CHILD_USB_ENERGY_METER_TYPE    = "USBEnergyMeter"

config.EDGE_CHILD_CURRENT_SENSOR_VERSION      = 1
config.EDGE_CHILD_ENERGY_METER_MODULE_VERSION = 1
config.EDGE_CHILD_AUXILIARY_CONTACT_VERSION   = 1
config.EDGE_CHILD_OUTPUT_MODULE_VERSION       = 1
config.EDGE_CHILD_ENERGY_METER_VERSION        = 1
config.EDGE_CHILD_WATER_METER_VERSION         = 1
config.EDGE_CHILD_GAS_METER_VERSION           = 1
config.EDGE_CHILD_USB_ENERGY_METER_VERSION    = 1

config.EDGE_CHILD_CURRENT_SENSOR_CONSUMPTION_PROFILE  = "abb.scu200.current-sensor-consumption.v1"
config.EDGE_CHILD_CURRENT_SENSOR_PRODUCTION_PROFILE   = "abb.scu200.current-sensor-production.v1"
config.EDGE_CHILD_AUXILIARY_CONTACT_PROFILE           = "abb.scu200.auxiliary-contact.v1"
config.EDGE_CHILD_OUTPUT_MODULE_PROFILE               = "abb.scu200.output-module.v1"
config.EDGE_CHILD_ENERGY_METER_PROFILE                = "abb.scu200.energy-meter.v1"
config.EDGE_CHILD_WATER_METER_PROFILE                 = "abb.scu200.water-meter.v1"
config.EDGE_CHILD_GAS_METER_PROFILE                   = "abb.scu200.gas-meter.v1"
config.EDGE_CHILD_USB_ENERGY_METER_PROFILE            = "abb.scu200.usb-energy-meter.v1"

config.EDGE_CHILD_CURRENT_SENSOR_REFRESH_PERIOD      = 30
config.EDGE_CHILD_ENERGY_METER_MODULE_REFRESH_PERIOD = 30
config.EDGE_CHILD_AUXILIARY_CONTACT_REFRESH_PERIOD   = 300  -- 5 minutes
config.EDGE_CHILD_OUTPUT_MODULE_REFRESH_PERIOD       = 300  -- 5 minutes
config.EDGE_CHILD_ENERGY_METER_REFRESH_PERIOD        = 30
config.EDGE_CHILD_WATER_METER_REFRESH_PERIOD         = 300  -- 5 minutes
config.EDGE_CHILD_GAS_METER_REFRESH_PERIOD           = 300  -- 5 minutes
config.EDGE_CHILD_USB_ENERGY_METER_REFRESH_PERIOD    = 30

config.EDGE_CHILD_ENERGY_REPORT_INTERVAL = 900  -- 15 minutes

-- REST API Config
config.REST_API_PORT = 1025

-- SSDP Config
config.MC_ADDRESS = "239.255.255.250"
config.MC_PORT    = 1900
config.MC_TIMEOUT = 5
config.MSEARCH    = table.concat({
    "M-SEARCH * HTTP/1.1",
    "HOST: 239.255.255.250:1900",
    "MAN: \"ssdp:discover\"",
    "MX: 5",
    "ST: " .. config.BRIDGE_URN
}, "\r\n")

return config
