local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local IASZone = clusters.IASZone
local ZONE_STATUS_ATTR = IASZone.attributes.ZoneStatus

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"
local device_management = require "st.zigbee.device_management"

local THIRDREALITY_WATERING_CLUSTER = 0xFFF2
local WATERING_TIME = 0x0000
local WATERING_INTERVAL = 0x0001
local W_TIME = "watering-time"
local W_INTERVAL = "watering-interval"

local function device_added(driver, device)
    device:emit_event(capabilities.hardwareFault.hardwareFault.clear())
    device:emit_component_event(device.profile.components[W_TIME], capabilities.fanSpeed.fanSpeed(10))
    device:emit_component_event(device.profile.components[W_INTERVAL], capabilities.fanSpeed.fanSpeed(0))
end

local generate_event_from_zone_status = function(driver, device, zone_status, zb_rx)
    local event
    if zone_status:is_alarm1_set() then
      event = capabilities.hardwareFault.hardwareFault.detected()
    else
      event = capabilities.hardwareFault.hardwareFault.clear()
    end
    if event ~= nil then
      device:emit_event(event)
    end
end

local ias_zone_status_attr_handler = function(driver, device, zone_status, zb_rx)
    generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local ias_zone_status_change_handler = function(driver, device, zb_rx)
    generate_event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local function custom_write_attribute(device, cluster, attribute, data_type, value, mfg_code)
    local data = data_types.validate_or_build_type(value, data_type)
    local message = cluster_base.write_attribute(device, data_types.ClusterId(cluster), attribute, data)
    if mfg_code ~= nil then
      message.body.zcl_header.frame_ctrl:set_mfg_specific()
      message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
    else
      message.body.zcl_header.frame_ctrl = FrameCtrl(0x10)
    end
    return message
end

local function set_watering_time(device, speed)
    local watering_time = speed
    device:send(custom_write_attribute(device, THIRDREALITY_WATERING_CLUSTER, WATERING_TIME,
          data_types.Uint16, watering_time, nil))
end

local function set_watering_interval(device, interval)
    device:send(custom_write_attribute(device, THIRDREALITY_WATERING_CLUSTER, WATERING_INTERVAL,
          data_types.Uint8, interval, nil))
end

local function fan_speed_handler(driver, device, command)
    if command.component == W_TIME then
        set_watering_time(device, command.args.speed)
    elseif command.component == W_INTERVAL then
        set_watering_interval(device, command.args.speed)
    end
end

local function watering_time_handler(driver, device, value, zb_rx)
    local fan_speed_value = value.value
    device:emit_component_event(device.profile.components[W_TIME], capabilities.fanSpeed.fanSpeed(fan_speed_value))
end

local function watering_interval_handler(driver, device, value, zb_rx)
    local fan_speed_value = value.value
    device:emit_component_event(device.profile.components[W_INTERVAL], capabilities.fanSpeed.fanSpeed(fan_speed_value))
end

local function do_refresh(driver, device)
    device:refresh()
    device:send(cluster_base.read_manufacturer_specific_attribute(device, THIRDREALITY_WATERING_CLUSTER, WATERING_TIME, 0x1407))
    device:send(cluster_base.read_manufacturer_specific_attribute(device, THIRDREALITY_WATERING_CLUSTER, WATERING_INTERVAL, 0x1407))
end

local function do_configure(driver, device)
    device:configure()
    device:send(device_management.build_bind_request(device, THIRDREALITY_WATERING_CLUSTER, driver.environment_info.hub_zigbee_eui), 1)
    do_refresh(driver, device)
end

local thirdreality_device_handler = {
    NAME = "ThirdReality Smart Watering Kit",
    zigbee_handlers = {
        attr = {
            [IASZone.ID] = {
                [ZONE_STATUS_ATTR.ID] = ias_zone_status_attr_handler
            },
            [THIRDREALITY_WATERING_CLUSTER] = {
                [WATERING_TIME] = watering_time_handler,
                [WATERING_INTERVAL] = watering_interval_handler
            }
        },
        cluster = {
            [IASZone.ID] = {
              [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
            }
        }
    },
    capability_handlers = {
        [capabilities.fanSpeed.ID] = {
            [capabilities.fanSpeed.commands.setFanSpeed.NAME] = fan_speed_handler
        },
        [capabilities.refresh.ID] = {
            [capabilities.refresh.commands.refresh.NAME] = do_refresh,
        }
    },
    lifecycle_handlers = {
        added = device_added,
        doConfigure = do_configure
    },
    can_handle = function(opts, driver, device, ...)
      return device:get_manufacturer() == "Third Reality, Inc" and device:get_model() == "3RWK0148Z"
    end
}

return thirdreality_device_handler
