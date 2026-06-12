-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local device_lib = require "st.device"
local buttonCfg = require "switch_utils.device_configuration".ButtonCfg
local create_child = require "switch_utils.device_configuration".ChildCfg.create_or_update_child_devices --new
local switch_utils = require "switch_utils.utils"
local fields = require "switch_utils.fields"

local ACTIVE_EPS = "__active_EPS"
local MATTER_DEVICE_ID = "MATTER_DEVICE_ID"
local PARENT_ID = "PARENT_ID"
local CURRENT_LIFT = "__current_lift"
local REVERSE_POLARITY = "__reverse_polarity"
local PRESET_LEVEL_KEY = "__preset_level_key"
local BUTTON_EPS = "__button_eps"
local MAIN_WC_EP = "__main_wc_ep"
local MAIN_ONOFF_EP = "FIELD_MAIN_ONOFF_EP"

local function subscribe (device, endpoint_id, cluster_id, attr_id, event_id)
    device:send(cluster_base.subscribe(device, endpoint_id, cluster_id, attr_id, event_id))
end

local function get_parent (driver, device)
    return driver:get_device_info(device:get_field(PARENT_ID) or nil)
end

local function get_matter_device(device)
    local matter_device_id = device:get_field(MATTER_DEVICE_ID)
    if matter_device_id then
        local driver = device.driver
        if driver then
            local matter_device = driver:get_device_info(matter_device_id)
            if matter_device then
                return matter_device
            end
        end
    end
    return nil
end

local function extract(ib)
    local eps = {}
    if ib.data and ib.data.elements then
        for _, el in ipairs(ib.data.elements) do
            local ep = el.value
            if type(ep) == "number" and ep ~= 1 and ep ~= 2 then
                table.insert(eps, ep)
            end
        end
    end
    return eps
end

local function diff (device, ib_elements)
    local stored_eps = device:get_field(ACTIVE_EPS) or {}
    ib_elements = ib_elements or {}

    local old_set, new_set = {}, {}
    for _, ep in ipairs(stored_eps) do
        old_set[ep] = true
    end
    for _, ep in ipairs(ib_elements) do
        new_set[ep] = true
    end

    local removed, added = {}, {}

    for ep in pairs(old_set) do
        if not new_set[ep] then
            table.insert(removed, ep)
        end
    end
    for ep in pairs(new_set) do
        if not old_set[ep] then
            table.insert(added, ep)
        end
    end
    return removed, added
end

local function assign_profile_for_endpoint(device_type_id)
    if device_type_id == fields.DEVICE_TYPE_ID.LIGHT.ON_OFF then
        return "light-binary"
    elseif device_type_id == fields.DEVICE_TYPE_ID.LIGHT.DIMMABLE then
        return "light-level"
    elseif device_type_id == fields.DEVICE_TYPE_ID.WINDOW_COVERING then
        return "window-covering"
    end
    return "switch-binary", nil
end

local function create_assign_profile_wrapper(device_type_id)
    local profile_name = assign_profile_for_endpoint(device_type_id)
    return function(device, ep_id, is_child_device)
        return profile_name, nil
    end
end

local function link_matter_device_and_parent(matter_device)
    local parent = matter_device:get_parent_device()
    matter_device:set_field(PARENT_ID, parent.id, { persist = true })
    matter_device:set_field(MATTER_DEVICE_ID, matter_device.id, { persist = true })
    parent:set_field(PARENT_ID, parent.id, { persist = true })
    parent:set_field(MATTER_DEVICE_ID, matter_device.id, { persist = true })
end

local function device_init (driver, device)
    if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
        return
    end

    device:set_field(fields.profiling_data.POWER_TOPOLOGY, false, { persist = true })
    device:set_field(fields.profiling_data.BATTERY_SUPPORT, fields.battery_support.NO_BATTERY, { persist = true })

    local wc_eps = device:get_endpoints(clusters.WindowCovering.ID)
    local oc_eps = device:get_endpoints(clusters.OccupancySensing.ID)
    local bt_eps = device:get_endpoints(clusters.Switch.ID)
    local lvl_eps = device:get_endpoints(clusters.LevelControl.ID)
    local product_id = device.manufacturer_info.product_id

    table.sort(wc_eps)
    table.sort(oc_eps)
    table.sort(lvl_eps)

    if device:get_parent_device() ~= nil then
        link_matter_device_and_parent(device)
        local parent = device:get_parent_device()
        device:extend_device("send", function(self, message)
            return parent:send(message)
        end)

        local main_onOff_at_join = device:get_field(MAIN_ONOFF_EP)
        if main_onOff_at_join and (product_id == 0x0005 or product_id == 0x0006) then
            device:set_field(MAIN_ONOFF_EP, 3, { persist = true })
            device.thread:call_with_delay(6, function()
                if device:supports_capability(capabilities.switchLevel) then
                    device:set_field(MAIN_ONOFF_EP, 4, { persist = true })
                end
            end)
        end

        if #oc_eps > 0 then
            device:try_update_metadata({ profile = "motion-illuminance" })
        elseif #wc_eps > 0 and product_id == 0x0005 then
            device:try_update_metadata({ profile = "window-covering" })
            device:set_field(MAIN_WC_EP, wc_eps[1])
        elseif #bt_eps == 4 then
            device:try_update_metadata({ profile = "4-button" })
        elseif #bt_eps == 2 then
            device:try_update_metadata({ profile = "2-button" })
        elseif #lvl_eps > 0  and product_id == 0x0005 then
            device:try_update_metadata({ profile = "light-level" })
        end
    else
        device.thread:call_with_delay(5, function()
            subscribe(device, 2, clusters.Descriptor.ID, clusters.Descriptor.attributes.PartsList.ID)
            local matter_device = get_matter_device(device)
            device:extend_device("emit_event_for_endpoint", function(self, ep_info, event)
                local endpoint_id = type(ep_info) == "number" and ep_info or ep_info.endpoint_id
                local child = self:get_child_by_parent_assigned_key(string.format("%d", endpoint_id))

                if child then
                    return child:emit_event(event)
                end
                if matter_device then
                    return matter_device:emit_event_for_endpoint(ep_info, event)
                end
            end)
        end)
    end
    device:set_component_to_endpoint_fn(switch_utils.component_to_endpoint)
    device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
end

local function handle_descriptor_report(driver, device, ib, response)
    if ib.endpoint_id ~= 2 then
        return
    end
    local parent = get_parent(driver, device)
    local matter_device = get_matter_device(device)

    if not parent then
        return
    end

    local new_eps = extract(ib) or {}
    table.sort(new_eps)
    local removed, added = diff(device, new_eps)

    device:set_field(ACTIVE_EPS, new_eps, { persist = true })

    local stored_eps = device:get_field(ACTIVE_EPS)

    for _, ep in ipairs(added or {}) do
        parent:send(clusters.Descriptor.attributes.DeviceTypeList:read(parent, ep))
        if device.network_type == device_lib.NETWORK_TYPE_MATTER then
            local product_id = device.manufacturer_info and device.manufacturer_info.product_id
            if product_id == 0x0005 and ep == 3 then
                matter_device:try_update_metadata({ profile = "light-binary" })
            elseif product_id == 0x0006 then
                if ep == 3 then
                    local profile = switch_utils.tbl_contains(stored_eps, 4) and "light-binary" or "2-button"
                    matter_device:try_update_metadata({ profile = profile })
                elseif ep == 4 then
                    local profile = switch_utils.tbl_contains(stored_eps, 3) and "light-binary" or "2-button"
                    matter_device:try_update_metadata({ profile = profile })
                end
            end
        end
    end

    for _, ep in ipairs(removed) do
        local button_eps = parent:get_field(BUTTON_EPS) or {}
        local clean_eps = {}

        for _, value in ipairs(button_eps) do
            if value ~= ep then
                table.insert(clean_eps, value)
            end
        end
        table.sort(clean_eps)
        parent:set_field(BUTTON_EPS, clean_eps, { persist = true })

        local child = parent:get_child_by_parent_assigned_key(tostring(ep))
        if child then
            driver:try_delete_device(child.id)
        end

        if ep == 3 then
            if device.manufacturer_info.product_id == 0x0005 then
                matter_device:try_update_metadata({ profile = "2-button" })
            elseif device.manufacturer_info.product_id == 0x0006 then
                local has_ep4 = switch_utils.tbl_contains(stored_eps, 4)
                matter_device:try_update_metadata({ profile = has_ep4 and "2-button" or "4-button" })
            end
        elseif ep == 4 then
            if device.manufacturer_info.product_id == 0x0006 then
                local button_comb = switch_utils.tbl_contains(stored_eps, 3)
                if button_comb then
                    matter_device:try_update_metadata({ profile = "2-button" })
                    create_child(driver, parent, { 3 }, 1, create_assign_profile_wrapper(fields.DEVICE_TYPE_ID.LIGHT.ON_OFF))
                else
                    matter_device:try_update_metadata({ profile = "4-button" })
                end
            end

        end
    end
end

local function handle_set_preset(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    local lift_value = device:get_field(PRESET_LEVEL_KEY) or 50
    local hundredths_lift_percent = (100 - tonumber(lift_value)) * 100
    device:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(device, endpoint_id, hundredths_lift_percent))
end

local function handle_close(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    endpoint_id = tonumber(endpoint_id)
    local req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
    if device:get_field(REVERSE_POLARITY) then
        req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
    end
    device:send(req)
end

local function handle_open(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    endpoint_id = tonumber(endpoint_id)
    local req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
    if device:get_field(REVERSE_POLARITY) then
        req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
    end
    device:send(req)
end

local function handle_pause(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    endpoint_id = tonumber(endpoint_id)
    local req = clusters.WindowCovering.server.commands.StopMotion(device, endpoint_id)
    device:send(req)
end

local function handle_shade_level(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    endpoint_id = tonumber(endpoint_id)
    local lift_percentage_value = 100 - cmd.args.shadeLevel
    local hundredths_lift_percentage = lift_percentage_value * 100
    local req = clusters.WindowCovering.server.commands.GoToLiftPercentage(
            device, endpoint_id, hundredths_lift_percentage
    )
    device:send(req)
end

local current_pos_handler = function(attribute)
    return function(driver, device, ib, response)
        if ib.data.value == nil then
            return
        end
        local windowShade = capabilities.windowShade.windowShade
        local position = 100 - math.floor(ib.data.value / 100)
        local reverse = device:get_field(REVERSE_POLARITY)
        device:emit_event_for_endpoint(ib.endpoint_id, attribute(position))
        if attribute == capabilities.windowShadeLevel.shadeLevel then
            device:set_field(CURRENT_LIFT, position)
        end
        local lift_position = device:get_field(CURRENT_LIFT)
        if lift_position == 100 then
            device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closed() or windowShade.open())
        elseif lift_position > 0 then
            device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
        elseif lift_position == 0 then
            device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.open() or windowShade.closed())
        end
    end
end

local function current_status_handler(driver, device, ib, response)
    local windowShade = capabilities.windowShade.windowShade
    local reverse = device:get_field(REVERSE_POLARITY)
    local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL
    if state == 1 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closing() or windowShade.opening())
    elseif state == 2 then
        device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.opening() or windowShade.closing())
    elseif state ~= 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
    end
end

local function occupancy_measured_value_handler(driver, device, ib, response)
    if ib.data.value ~= nil then
        device:emit_event_for_endpoint(ib.endpoint_id, ib.data.value == 0x01 and
                capabilities.motionSensor.motion.active() or
                capabilities.motionSensor.motion.inactive())
    end
end

local function info_changed(driver, device, event, args)
    local parent = get_parent(driver, device)
    local map = {}
    if device.network_type == device_lib.NETWORK_TYPE_MATTER and device.profile.id ~= args.old_st_store.profile.id then
        device.thread:call_with_delay(5, function()
            if device:supports_capability(capabilities.button) then
                local button_eps = parent:get_field(BUTTON_EPS)
                local clean_eps = {}
                for _, v in ipairs(button_eps or {}) do
                    table.insert(clean_eps, v)
                end
                buttonCfg.update_button_component_map(device, clean_eps[1], clean_eps)
                for _, ep in ipairs(clean_eps) do
                    subscribe(parent, ep, clusters.Switch.ID, nil, clusters.Switch.events.MultiPressComplete.ID)
                    subscribe(parent, ep, clusters.Switch.ID, nil, clusters.Switch.events.LongPress.ID)
                    device:emit_event_for_endpoint(ep, capabilities.button.supportedButtonValues({ "pushed", "double", "held" }))
                end
                return
            elseif device:supports_capability(capabilities.switch) then
                map = {main = 3}
                parent:send(clusters.OnOff.attributes.OnOff:read(parent))
                if device:supports_capability(capabilities.switchLevel) then
                    map = {main = 4}
                    parent:send(clusters.LevelControl.attributes.CurrentLevel:read(parent))
                end
            elseif device:supports_capability(capabilities.motionSensor) then
                parent:send(clusters.OccupancySensing.attributes.Occupancy:read(parent))
                parent:send(clusters.IlluminanceMeasurement.attributes.MeasuredValue:read(parent))
            elseif device:supports_capability(capabilities.windowShadeLevel) then
                map = {main = 5}
                parent:send(clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths:read(parent))
            end
            device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, map)
            parent:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, map)
        end)
    elseif args.old_st_store.preferences.reverse ~= device.preferences.reverse then
        if device.preferences.reverse then
            device:set_field(REVERSE_POLARITY, true, { persist = true })
        else
            device:set_field(REVERSE_POLARITY, false, { persist = true })
        end
    elseif args.old_st_store.preferences.presetPosition ~= device.preferences.presetPosition then
        local new_preset_value = device.preferences.presetPosition
        device:set_field(PRESET_LEVEL_KEY, new_preset_value, { persist = true })
    end
end

local function device_type_handler (driver, device, ib)
    local matter_device = get_matter_device(device)
    local parent = get_parent(driver, device)
    local stored = parent:get_field(BUTTON_EPS) or {}
    local button_eps = {}
    local ep = ib.endpoint_id
    local value = ib.data.elements

    for _, v in ipairs(stored) do
        table.insert(button_eps, v)
    end
    for _, element in ipairs(value) do
        local device_type_field = element.elements.device_type
        local device_type_id = device_type_field and device_type_field.value

        if device_type_id == fields.DEVICE_TYPE_ID.GENERIC_SWITCH then
            if not switch_utils.tbl_contains(button_eps, ep) then
                switch_utils.set_field_for_endpoint(parent, fields.SUPPORTS_MULTI_PRESS, ep)
                switch_utils.set_field_for_endpoint(parent, fields.IGNORE_NEXT_MPC, ep)
                table.insert(button_eps, ep)
                table.sort(button_eps)
                parent:set_field(BUTTON_EPS, button_eps, { persist = true })
            end
        end

        if device_type_id == fields.DEVICE_TYPE_ID.LIGHT.ON_OFF then
            local active_eps = device:get_field(ACTIVE_EPS)
            device.thread:call_with_delay(6, function()
                subscribe(parent, ep, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID)
            end)

            if ep == 3 and device.manufacturer_info.product_id == 0x0005 then
                return
            elseif ep == 4 and device.manufacturer_info.product_id == 0x0006 then
                if switch_utils.tbl_contains(active_eps, 3) then
                    local ep3 = parent:get_child_by_parent_assigned_key("3") or nil
                    if ep3 then
                        driver:try_delete_device(ep3.id)
                    end
                else
                    create_child(driver, parent, {4}, 1, create_assign_profile_wrapper(device_type_id))
                    return
                end
            elseif ep == 3 and device.manufacturer_info.product_id == 0x0006 then
                if not switch_utils.tbl_contains(active_eps, 4) then
                    create_child(driver, parent, {3}, 1, create_assign_profile_wrapper(device_type_id))
                end
                return
            end
            create_child(driver, parent, { ep }, 1, create_assign_profile_wrapper(device_type_id))
        elseif device_type_id == fields.DEVICE_TYPE_ID.LIGHT.DIMMABLE then
            subscribe(parent, ep, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID)
            subscribe(parent, ep, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID)
            subscribe(parent, ep, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID)
            subscribe(parent, ep, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID)
            if ep == 4 and device.manufacturer_info.product_id == 0x0005 then
                return
            end
            create_child(driver, parent, { ep }, 1, create_assign_profile_wrapper(device_type_id))
        elseif device_type_id == fields.DEVICE_TYPE_ID.WINDOW_COVERING then
            subscribe(parent, ep, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.OperationalStatus.ID)
            subscribe(parent, ep, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID)
            if matter_device:get_field(MAIN_WC_EP) == nil then
                create_child(driver, parent, { ep }, 1, create_assign_profile_wrapper(device_type_id))
            end
        elseif device_type_id == fields.DEVICE_TYPE_ID.MOTION_SENSOR then
            subscribe(parent, ep, clusters.OccupancySensing.ID, clusters.OccupancySensing.attributes.Occupancy.ID)
        elseif device_type_id == fields.DEVICE_TYPE_ID.ILLUMINATION_SENSOR then
            subscribe(parent, ep, clusters.IlluminanceMeasurement.ID, clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID)
        end
    end
end

local function do_configure (driver, device) end
local function added (driver, device) end
local function driver_switched(driver, device)  end

local Hager_switch = {
    NAME = "Hager matter switch handler",
    lifecycle_handlers = {
        added = added,
        init = device_init,
        infoChanged = info_changed,
        doConfigure = do_configure,
        driverSwitched = driver_switched
    },
    matter_handlers = {
        attr = {
            [clusters.Descriptor.ID] = {
                [clusters.Descriptor.attributes.PartsList.ID] = handle_descriptor_report,
                [clusters.Descriptor.attributes.DeviceTypeList.ID] = device_type_handler
            },
            [clusters.OccupancySensing.ID] = {
                [clusters.OccupancySensing.attributes.Occupancy.ID] = occupancy_measured_value_handler,
            },
            [clusters.WindowCovering.ID] = {
                [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = current_pos_handler(capabilities.windowShadeLevel.shadeLevel),
                [clusters.WindowCovering.attributes.OperationalStatus.ID] = current_status_handler,
            },
        },
    },
    capability_handlers = {
        [capabilities.windowShadePreset.ID] = {
            [capabilities.windowShadePreset.commands.presetPosition.NAME] = handle_set_preset,
        },
        [capabilities.windowShade.ID] = {
            [capabilities.windowShade.commands.close.NAME] = handle_close,
            [capabilities.windowShade.commands.open.NAME] = handle_open,
            [capabilities.windowShade.commands.pause.NAME] = handle_pause,
        },
        [capabilities.windowShadeLevel.ID] = {
            [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = handle_shade_level,
        },
    },
    can_handle = require("sub_drivers.hager.can_handle")
}

return Hager_switch
