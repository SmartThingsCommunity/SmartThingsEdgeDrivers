-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local preferences = require "preferences"

local WindowCovering = zcl_clusters.WindowCovering
local DeviceTemperatureConfiguration = zcl_clusters.DeviceTemperatureConfiguration
local Scenes = zcl_clusters.Scenes
local Alarm = zcl_clusters.Alarms

local WindowShade = capabilities.windowShade
local WindowShadeLevel = capabilities.windowShadeLevel
local WindowShadePreset = capabilities.windowShadePreset
local Button = capabilities.button
local Refresh = capabilities.refresh
local TemperatureAlarm = capabilities.temperatureAlarm

local SHADE_SET_STATUS = "shade_set_status"

local blinds = {
    ["main"] = {
        cmd = WindowCovering.server.commands.GoToLiftPercentage,
        pref = "presetLiftPosition"
    },
    ["venetianBlind"] = {
        cmd = WindowCovering.server.commands.GoToTiltPercentage,
        pref = "presetTiltPosition"
    }
}

local SCENE_ID_BUTTON_EVENT_MAP = {
    [0x01] = capabilities.button.button.pushed,     -- 0x06
    [0x02] = capabilities.button.button.double,     -- 0x07
    [0x03] = capabilities.button.button.pushed_3x,  -- 0x08
    [0x04] = capabilities.button.button.held,       -- 0x09
    [0x05] = capabilities.button.button.up          -- 0x0A
}

local function setTimer(device, level, ep)
    local set_status_timer = device:get_field(SHADE_SET_STATUS)
    local comp = tonumber(ep) == 1 and "main" or "venetianBlind"

    if set_status_timer then
        device.thread:cancel_timer(set_status_timer)
        device:set_field(SHADE_SET_STATUS, nil)
    end

    set_status_timer = device.thread:call_with_delay(1, function()
        local current_level = device:get_latest_state(comp, capabilities.windowShadeLevel.ID,
            capabilities.windowShadeLevel.shadeLevel.NAME)
        if current_level == 0 then
            device:emit_event_for_endpoint(ep, WindowShade.windowShade.open())
        elseif current_level == 100 then
            device:emit_event_for_endpoint(ep, WindowShade.windowShade.closed())
        elseif current_level > 0 and current_level < 100 then
            device:emit_event_for_endpoint(ep, WindowShade.windowShade.partially_open())
        else
            device:emit_event_for_endpoint(ep, WindowShade.windowShade.unknown())
        end
    end)

    device:set_field(SHADE_SET_STATUS, set_status_timer)
end

local function current_lift_position_attr_handler(driver, device, value, zb_rx)
    local ep = zb_rx.address_header.src_endpoint.value
    local comp = tonumber(ep) == 1 and "main" or "venetianBlind"
    local level = value.value > 100 and 100 or value.value
    local current_level = device:get_latest_state(comp, WindowShadeLevel.ID,
        WindowShadeLevel.shadeLevel.NAME)

    if level == 0 then
        device:emit_event_for_endpoint(ep, WindowShade.windowShade.open())
        device:emit_event_for_endpoint(ep, WindowShadeLevel.shadeLevel(0))
    elseif level == 100 then
        device:emit_event_for_endpoint(ep, WindowShade.windowShade.closed())
        device:emit_event_for_endpoint(ep, WindowShadeLevel.shadeLevel(100))
    else
        if current_level ~= level or current_level == nil then
            current_level = current_level or 0
            device:emit_event_for_endpoint(ep, WindowShadeLevel.shadeLevel(level))
            local event = nil
            if current_level ~= level then
                event = current_level < level and WindowShade.windowShade.closing() or
                WindowShade.windowShade.opening()
            end
            if event ~= nil then
                device:emit_event_for_endpoint(ep, event)
            end
        end
        setTimer(device, level, ep)
    end
end

local function current_tilt_position_attr_handler(driver, device, value, zb_rx)
    local level = value.value > 100 and 100 or value.value
    device:emit_event_for_endpoint(0x02, WindowShadeLevel.shadeLevel(level))
end

local function window_shade_level_cmd(driver, device, command)
    local comp = command.component
    local ep = comp == "main" and 1 or 2
    local level = command.args.shadeLevel

    if ep == 1 then
        device:send(WindowCovering.server.commands.GoToLiftPercentage(device, level):to_endpoint(ep))
    else
        device:send(WindowCovering.server.commands.GoToTiltPercentage(device, level):to_endpoint(ep))
    end
end

local function window_shade_preset_cmd(driver, device, command)
    local comp = command.component
    local level = blinds[comp] and device.preferences ~= nil and device.preferences[blinds[comp].pref] or 50
    local send_cmd = blinds[comp] and blinds[comp].cmd
    device:send_to_component(comp, send_cmd(device, level))
end

local alarm_handler = function(driver, device, zb_rx)
    if (zb_rx.body.zcl_body.alarm_code.value == 0x86) then
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm('heat'))
    else
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm('cleared'))
    end
end

local temperature_handler = function(driver, device, value, zb_rx)
    local temp_alarm = device:get_latest_state("main", capabilities.temperatureAlarm.ID,
        capabilities.temperatureAlarm.temperatureAlarm.NAME, 'cleared')
    -- handle temperature alarm if neccessary
    if value.value < 70 and temp_alarm == 'heat' then
        device:send(Alarm.server.commands.ResetAllAlarms(device))
        device:send(Alarm.attributes.AlarmCount:read(device))
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm('cleared'))
    end
end

local scenes_cluster_handler = function(driver, device, zb_rx)
    local ep = zb_rx.address_header.src_endpoint.value == 0x04 and 0x07 or 0x08
    local sceneID = zb_rx.body.zcl_body.scene_id.value > 5 and zb_rx.body.zcl_body.scene_id.value - 5 or
    zb_rx.body.zcl_body.scene_id.value

    local button_event = SCENE_ID_BUTTON_EVENT_MAP[sceneID]
    local event = button_event({state_change = true})
    device:emit_event_for_endpoint(ep, event)
end

local function window_shade_cmd(cmd)
    return function(driver, device, command)
        local comp = command.component
        local ep = comp == "main" and 1 or 2
        local send_cmd = blinds[comp] and blinds[comp].cmd
        local window_shade_state = device:get_latest_state("main", capabilities.windowShade.ID,
            capabilities.windowShade.windowShade.NAME) or "unknown"
        local  _cmd = cmd
        local send_event = comp == "main" and WindowCovering.attributes.CurrentPositionLiftPercentage or
        WindowCovering.attributes.CurrentPositionTiltPercentage

        -- reverse commands for slats (component is not main)
        if comp ~= "main" then
            _cmd = cmd == "open" and "close" or cmd == "close" and "open" or cmd
        end

        if _cmd == 'pause' then
            if window_shade_state == "opening" or window_shade_state == "closing" then
                device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
            else
                device:send_to_component(command.component, send_event:read(device))
            end
        else
            if _cmd == 'open' then
                device:emit_event_for_endpoint(ep, WindowShade.windowShade.opening())
                device:send_to_component(comp, send_cmd(device, 100))
            else
                device:emit_event_for_endpoint(ep, WindowShade.windowShade.closing())
                device:send_to_component(comp, send_cmd(device, 0))
            end
        end
    end
end

local function endpoint_to_component(device, ep)
    if ep == 2 and device.profile.components["venetianBlind"] ~= nil then
        return "venetianBlind"
    elseif ep == 8 and device.profile.components["button2"] ~= nil then
        return "button2"
    elseif ep == 7 and device.profile.components["button1"] ~= nil then
        return "button1"
    else
        return "main"
    end
end

local function component_to_endpoint(device, component_id)
    local ep_num = component_id == "venetianBlind" and 2 or component_id == "button2" and 2 or 1
    return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
end

local function device_init(driver, device)
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)

    -- initial set of temperatureAlarm
    device.thread:call_with_delay(1, function()
        device:emit_event(capabilities.temperatureAlarm.temperatureAlarm('cleared'))
    end)
end

local function device_added(driver, device)
    for _, component in pairs(device.profile.components) do
        if component["id"]:match("button(%d)") then
            device:emit_component_event(component, capabilities.button.supportedButtonValues({ "pushed", "double", "pushed_3x", "held", "up" }, { visibility = { displayed = false } }))
            device:emit_component_event(component, capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
        end
    end
end

local function do_refresh(driver, device)
    for endpoint = 1, 2 do
        device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device):to_endpoint(endpoint))
        device:send(WindowCovering.attributes.CurrentPositionTiltPercentage:read(device):to_endpoint(endpoint))
    end
    device:send(Alarm.attributes.AlarmCount:read(device))
end

local function do_configure(driver, device)
    device:configure()

    device:send(device_management.build_bind_request(device, Alarm.ID, driver.environment_info.hub_zigbee_eui))
    device:send(Alarm.attributes.AlarmCount:configure_reporting(device, 0, 21600, 0))

    device:send(device_management.build_bind_request(device, DeviceTemperatureConfiguration.ID, driver.environment_info.hub_zigbee_eui))
    device:send(DeviceTemperatureConfiguration.attributes.CurrentTemperature:configure_reporting(device, 1, 600, 10))

    for endpoint = 1, 4 do
        if endpoint <=2 then
            device:send(device_management.build_bind_request(device, WindowCovering.ID, driver.environment_info.hub_zigbee_eui, endpoint))
        else
            device:send(device_management.build_bind_request(device, Scenes.ID, driver.environment_info.hub_zigbee_eui, endpoint))
        end
    end

    do_refresh(driver, device)
end

local function device_info_changed(driver, device, event, args)
    if device.preferences ~= nil then
        local operatingMode = device.preferences.operatingMode
        if operatingMode ~= nil and
            operatingMode ~= args.old_st_store.preferences.operatingMode then
            local raw_value = tonumber(operatingMode)
            device:send(cluster_base.write_manufacturer_specific_attribute(device, 0xFD03, 0x0001, 0x0244, data_types.Uint8, raw_value))
            if raw_value == 0 then
                device:try_update_metadata({ profile = "window-treatment-aeotec-pico" })
            elseif raw_value == 1 then
                device:try_update_metadata({ profile = "window-treatment-aeotec-pico-venetian" })
            end
        else
            preferences.update_preferences(driver, device, args)
        end
    end
end

local aeotec_pico_shutter_window_treatment = {
    NAME = "Aeotec Pico Shutter",
    supported_capabilities = {
        WindowShade,
        WindowShadeLevel,
        WindowShadePreset,
        Button,
        Refresh,
        TemperatureAlarm
    },
    zigbee_handlers = {
        attr = {
            [WindowCovering.ID] = {
                [WindowCovering.attributes.CurrentPositionTiltPercentage.ID] = current_tilt_position_attr_handler,
                [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_lift_position_attr_handler
            },
            [DeviceTemperatureConfiguration.ID] = {
                [DeviceTemperatureConfiguration.attributes.CurrentTemperature.ID] = temperature_handler
            }
        },
        cluster = {
            [Alarm.ID] = {
                [Alarm.client.commands.Alarm.ID] = alarm_handler
            },
            [Scenes.ID] = {
                [Scenes.server.commands.RecallScene.ID] = scenes_cluster_handler
            }
        }
    },
    capability_handlers = {
        [WindowShadeLevel.ID] = {
            [WindowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
        },
        [WindowShadePreset.ID] = {
            [WindowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
        },
        [WindowShade.ID] = {
            [WindowShade.commands.open.NAME] = window_shade_cmd('close'),
            [WindowShade.commands.close.NAME] = window_shade_cmd('open'),
            [WindowShade.commands.pause.NAME] = window_shade_cmd('pause')
        },
        [Refresh.ID] = {
            [Refresh.commands.refresh.NAME] = do_refresh
        },
    },
    can_handle = function(opts, driver, device)
        return device:get_manufacturer() == "AEOTEC"
    end,
    lifecycle_handlers = {
        init = device_init,
        added = device_added,
        doConfigure = do_configure,
        infoChanged = device_info_changed
    }
}

return aeotec_pico_shutter_window_treatment
