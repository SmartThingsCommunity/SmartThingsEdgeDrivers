--- Hue Bridge Info as returned by the unauthenticated API endpoint `/api/config`
--- @class HueBridgeInfo
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

--- @class HueDriver:Driver
--- @field public ignored_bridges table<string,boolean>
--- @field public joined_bridges table<string,table>
--- @field public light_id_to_device table<string,HueChildDevice>
--- @field public device_rid_to_light_rid table<string,string>
--- @field public stray_bulb_tx table cosock channel
--- @field public api_key_to_bridge_id table<string,string>
--- @field private _lights_pending_refresh table<string,HueChildDevice>
--- @field public emit_light_status_events fun(light_device: HueChildDevice, light: table)

--- @class HueDevice:st.Device
--- @field public label string
--- @field public data table|nil migration data for a migrated device
--- @field public get_field fun(self: HueDevice, key: string):any
--- @field public set_field fun(self: HueDevice, key: string, value: any, args?: table)
--- @field public emit_event fun(self: HueDevice, event: any)

--- @class HueBridgeDevice:HueDevice
--- @field public device_network_id string

--- @class HueChildDevice:HueDevice
--- @field public parent_device_id string
--- @field public parent_assigned_child_key string
