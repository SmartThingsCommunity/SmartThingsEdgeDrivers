local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local OccupancySensing = zcl_clusters.OccupancySensing

local THIRDREALITY_TVOC_CLUSTER = 0x042E
local THIRDREALITY_TVOC_VALUE = 0x0000

local function occupancy_attr_handler(driver, device, occupancy, zb_rx)
  device:emit_event(occupancy.value == 1 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local function tvoc_attr_handler(driver, device, value, zb_rx)
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.tvocMeasurement.tvocLevel({ value = value.value, unit = "ppb" }))
end

local added_handler = function(self, device)
    device:send(OccupancySensing.attributes.Occupancy:read(device))
    device:emit_event(capabilities.tvocMeasurement.tvocLevel({value = 0, unit = "ppb"}))
end

local thirdreality_device_handler = {
    NAME = "ThirdReality Multi-Function Smart Presence Sensor R3",
    lifecycle_handlers = {
        added = added_handler
    },
    zigbee_handlers = {
        attr = {
            [OccupancySensing.ID] = {
                [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
            },
            [THIRDREALITY_TVOC_CLUSTER] = {
                [THIRDREALITY_TVOC_VALUE] = tvoc_attr_handler
            }
        }
    },
    can_handle = require("thirdreality-presence-sensor-r3.can_handle"),
}

return thirdreality_device_handler
