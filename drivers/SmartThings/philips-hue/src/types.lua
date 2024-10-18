--- @meta

---@class HueSseEvent
---@field id string
---@field type string
---@field data HueResourceInfo[]

---@class HueServiceInfo
---@field public rid string
---@field public rtype HueDeviceTypes

---@class HueResourceInfo
---@field public metadata { name: string, [string]: any}
---@field public id string
---@field public id_v1 string?
---@field public service_id? integer
---@field public type HueDeviceTypes
---@field public owner HueServiceInfo?
---@field public hue_provided_name string
---@field public hue_device_data table

---@class HueZigbeeInfo: HueResourceInfo
---@field public status string

---@class HueDeviceInfo: HueResourceInfo
---@field public services HueServiceInfo[]
---@field public product_data { [string]: string }

---@class HueColorCoords
---@field public x number
---@field public y number

---@class HueGamut
---@field public red HueColorCoords
---@field public green HueColorCoords
---@field public blue HueColorCoords

---@class HueLightInfo: HueResourceInfo
---@field public hue_device_id string
---@field public parent_device_id string
---@field public on { on: boolean }
---@field public color { xy: HueColorCoords, gamut: HueGamut, gamut_type: string }
---@field public dimming { brightness: number, min_dim_level: number }
---@field public color_temperature { mirek: number?, mirek_valid: boolean, mirek_schema: { mirek_minimum: number, mirek_maximum: number }?}
---@field public mode string

---@class HueMotionInfo: HueResourceInfo
---@field public enabled boolean
---@field public motion { motion: boolean, motion_valid: boolean, motion_report: { motion: true, changed: string } }

---@class HuePowerLevelInfo: HueResourceInfo
---@field public power_state { battery_state: string, battery_level: number}

---@class HueTemperatureInfo: HueResourceInfo
---@field public enabled boolean
---@field public temperature { temperature: number, temperature_valid: boolean, temperature_report: { temperature: number, changed: string } }

---@class HueLightLevelInfo: HueResourceInfo
---@field public enabled boolean
---@field public light { light_level: number, light_level_valid: boolean, light_level_report: { light_level: number, changed: string } }

---@class HueButtonInfo: HueResourceInfo
---@field public metadata { control_id: integer }
---@field public button { repeat_interval: integer, last_event: string?, button_report: { updated: string, event: string }?, event_values: string[] }

---@class HueContactInfo: HueResourceInfo
---@field public enabled boolean
---@field public contact_report { changed: string, state: string }

--- Note that the tamper representation uses an array for its reports. Not sure why this is.
---@class HueTamperInfo: HueResourceInfo
---@field public tamper_reports { changed: string, source: string, state: string }[]

--- Hue Bridge Info as returned by the unauthenticated API endpoint `/api/config`
--- @class HueBridgeInfo: { [string]: any }
--- @field public name string
--- @field public datastoreversion string
--- @field public swversion string
--- @field public apiversion string
--- @field public mac string
--- @field public bridgeid string
--- @field public factorynew boolean
--- @field public replacesbridgeid string|nil
--- @field public modelid string
--- @field public starterkitid string
--- @field public ip string|nil

--- @class HueDevice:st.Device
--- @field public label string
--- @field public id string
--- @field public device_network_id string
--- @field public parent_device_id string
--- @field public parent_assigned_child_key string?
--- @field public manufacturer string
--- @field public model string
--- @field public vendor_provided_label string
--- @field public log table device-scoped logging module
--- @field public profile table
--- @field public data nil|{ username: string, bulbId: string } migration data for a migrated device
--- @field public get_child_list fun(self: HueBridgeDevice): HueChildDevice[]
--- @field public get_field fun(self: HueDevice, key: string):any
--- @field public set_field fun(self: HueDevice, key: string, value: any, args?: table)
--- @field public emit_event fun(self: HueDevice, event: any)
--- @field public supports_capability_by_id fun(self: HueDevice, capability_id: string, component: string?): boolean

--- @class HueBridgeDevice:HueDevice
--- @field public device_network_id string

--- @class HueChildDevice:HueDevice
--- @field public parent_assigned_child_key string
