local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"

local MatterDriver = require "st.matter.driver"
local utils = require "st.utils"

local BOOLEAN_DEVICE_TYPE_INFO = {
    ["RAIN_SENSOR"] = {
        id = 0x0044,
        alarmComponentName = "rainSensorAlarm",
    },
    ["WATER_FREEZE_DETECTOR"] = {
        id = 0x0043,
        alarmComponentName = "waterFreezeDetectorAlarm",
    },
    ["WATER_LEAK_DETECTOR"]   = {
        id = 0x0041,
        alarmComponentName = "waterLeakDetectorAlarm",
    },
}

local function set_device_type_per_endpoint(driver, device)
    for _, ep in ipairs(device.endpoints) do
        for _, dt in ipairs(ep.device_types) do
            local this_id = dt.device_type_id
            for name, info in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
                if this_id == info.id then
                    device:set_field(name, ep.endpoint_id)
                end
            end
        end
    end
end

local function do_configure(driver, device)
    set_device_type_per_endpoint(driver, device)
end

-- matter protocol handling

local BOOLEAN_CAP_EVENT_MAP = {
    [true] = {
        ["WATER_FREEZE_DETECTOR"] = capabilities.temperatureAlarm.temperatureAlarm.freeze(),
        ["WATER_LEAK_DETECTOR"] = capabilities.waterSensor.water.wet(),
        ["RAIN_SENSOR"] = capabilities.smilevirtual57983.customRainSensor.rain.detected(),
    },
    [false] = {
        ["WATER_FREEZE_DETECTOR"] = capabilities.temperatureAlarm.temperatureAlarm.cleared(),
        ["WATER_LEAK_DETECTOR"] = capabilities.waterSensor.water.dry(),
        ["RAIN_SENSOR"] = capabilities.smilevirtual57983.customRainSensor.rain.undetected(),
    }
}

local function boolean_state_handler(driver, device, ib, response)
    local name = nil
    for dt_name, _ in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
        local dt_ep_id = device:get_field(dt_name)
        if ib.endpoint_id == dt_ep_id then
            name = dt_name
            break
        end
    end
    if name == nil then
        log.error()
    end
    device:emit_event_for_endpoint(ib.endpoint_id, BOOLEAN_CAP_EVENT_MAP[ib.data.value][name])
end

local function find_device_component_helper(driver, device, ib, response)
    local name = nil
    for dt_name, _ in pairs(BOOLEAN_DEVICE_TYPE_INFO) do
        local dt_ep_id = device:get_field(dt_name)
        if ib.endpoint_id == dt_ep_id then
            name = dt_name
            break
        end
    end
    if name == nil then
        log.error()
    end
    return device.profile.components[BOOLEAN_DEVICE_TYPE_INFO[name].alarmComponentName]
end

local function alarms_suppressed_handler(driver, device, ib, response)
    for index=1,2 do
        if ((ib.data.value >> index) & 1) > 0 then
            device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smilevirtual57983.customAlarmSensor.alarmSensorState.suppressed())
            break
        end
    end
end

local function alarms_enabled_handler(driver, device, ib, response)
    local device_is_enabled = false
    for index=1,2 do
        if ((ib.data.value >> index) & 1) > 0 then
            device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smilevirtual57983.customAlarmSensor.alarmSensorState.enabled())
            device_is_enabled = true
            break
        end
    end
    if not device_is_enabled then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.smilevirtual57983.customAlarmSensor.alarmSensorState.off())
    end
end

local function sensor_fault_handler(driver, device, ib, response)
    if ib.data.value > 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.hardwareFault.hardwareFault.detected())
    else
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.hardwareFault.hardwareFault.clear())
    end
end

-- capability handling

local matter_driver_template = {
    lifecycle_handlers = {
        init = device_init,
        doConfigure = do_configure,
        infoChange = info_changed,
    },
    matter_handlers = {
        attr = {
            [clusters.BooleanState.StateValue.ID] = boolean_state_handler,
            [clusters.BooleanStateConfiguration.ID] = {
                [clusters.BooleanStateConfiguration.AlarmsSuppressed.ID] = alarms_suppressed_handler,
                [clusters.BooleanStateConfiguration.AlarmsEnabled.ID] = alarms_enabled_handler,
                [clusters.BooleanStateConfiguration.SensorFault.ID] = sensor_fault_handler,
            },
        },
    },
    subscribed_attributes =  {
        [capabilities.hardwareFault.ID] = {
            clusters.BooleanStateConfiguration.SensorFault,
        },
        [smilevirtual57983.customAlarmSensor.ID] = {
            clusters.BooleanStateConfiguration.AlarmsSuppressed,
            clusters.BooleanStateConfiguration.AlarmsEnabled,
        },
        [capabilities.waterSensor.ID] = {
            clusters.BooleanState.StateValue,
        },
        [capabilities.temperatureAlarm.ID] = {
            clusters.BooleanState.StateValue,
        },
        [smilevirtual57983.customRainSensor.ID] = {
            clusters.BooleanState.StateValue,
        }
    },
    capability_handler = {

    }
}
