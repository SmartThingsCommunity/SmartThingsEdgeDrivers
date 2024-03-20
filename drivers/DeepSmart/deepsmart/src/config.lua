local config = {}
-- device info
-- NOTE: In the future this information
-- may be submitted through the Developer
-- Workspace to avoid hardcoded values.
config.DEVICE_PROFILE={}
config.DEVICE_PROFILE[3]='Ac.v1'
config.DEVICE_PROFILE[4]='Heater.v1'
config.DEVICE_PROFILE[53]='Newfan.v1'
config.DEVICE_TYPE='LAN'

-- SSDP Config
config.MC_ADDRESS='239.255.255.250'
config.MC_PORT=1900
config.MC_TIMEOUT=6

config.ENUM = {}
config.ENUM.AC = 3
config.ENUM.HEATER = 4
config.ENUM.NEWFAN = 53


--device addrtype
config.AC = {}
config.AC.ONOFF = 0
config.AC.MODE = 1
config.AC.FAN = 2
config.AC.SETTEMP = 3
config.AC.TEMP = 4

config.HEATER = {}
config.HEATER.ONOFF = 0
config.HEATER.SETTEMP = 2
config.HEATER.TEMP = 3

config.NEWFAN = {}
config.NEWFAN.ONOFF = 0
config.NEWFAN.FAN = 1

config.DEVICE = {}
config.DEVICE.ONOFF = 0

config.FIELD = {}
config.FIELD.DP2KNX = "dp2knx"
config.FIELD.DPENUM = "dpenum"
config.FIELD.DEVICES = "devices"
config.FIELD.IP = "ip"
config.FIELD.INVALID = "invalid"


return config
