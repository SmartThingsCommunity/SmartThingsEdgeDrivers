-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local device_lib = require "st.device"
local utils = require "st.utils"
local ButtonCfg = require "switch_utils.device_configuration"
local switch_utils = require "switch_utils.utils"
local fields = require "switch_utils.fields"

local IGNORE_NEXT_MPC = "__ignore_next_mpc"
local SUPPORTS_MULTI_PRESS = "__multi_button"

local ACTIVE_EPS = "__active_EPS"
local FIELD_MAIN_ONOFF_EP = "FIELD_MAIN_ONOFF_EP"
local FIELD_MOTION_HOST = "FIELD_MOTION_HOST"
local FIELD_LUX_TO_MOTION = "__lux_to_motion"
local HOST_ID = "HOST_ID"
local SUBHUB_ID = "SUBHUB_ID"
local CURRENT_LIFT = "__current_lift"
local CURRENT_TILT = "__current_tilt"
local REVERSE_POLARITY = "__reverse_polarity"
local PRESET_LEVEL_KEY = "__preset_level_key"
local BUTTON_EPS = "__button_eps"

local DEFAULT_PRESET_LEVEL = 50
local descriptor_cluster_id = 0x001D
local part_list_attr_id = 0x0003

local function subscribe_descriptor (device, endpoint_id)
    local req = cluster_base.subscribe(device, endpoint_id, descriptor_cluster_id, part_list_attr_id, nil)
    device:send(req)
end

local function set_field_for_endpoint(device, field, endpoint, value, persist)
    device:set_field(string.format("%s_%d", field, endpoint), value, { persist = persist })
end
local function get_field_for_endpoint(device, field, endpoint)
    return device:get_field(string.format("%s_%d", field, endpoint))
end

local function get_subhub (driver, device)
    local id = device:get_field(SUBHUB_ID)
    if not id then
        return nil
    end
    return driver:get_device_info(id)
end

local function get_host (driver, device)
    local id = device:get_field(HOST_ID)
    return driver:get_device_info(id)
end

local function build_lux_to_motion_map(occ_eps, lux_eps)
    local map = {}

    if #occ_eps == 0 or #lux_eps == 0 then
        return map
    end

    table.sort(occ_eps)
    table.sort(lux_eps)

    if #occ_eps == #lux_eps then
        for i, lux_ep in ipairs(lux_eps) do
            map[lux_ep] = occ_eps[i]
        end
    else
        for _, lux_ep in ipairs(lux_eps) do
            local best_ep = nil
            local best_dist = nil

            for _, occ_ep in ipairs(occ_eps) do
                local d = math.abs(lux_ep - occ_ep)
                if not best_dist or d < best_dist then
                    best_dist = d
                    best_ep = occ_ep
                end
            end

            map[lux_ep] = best_ep
        end
    end

    return map
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

local function emit_for_ep(driver, device, ep, event)
    local host = get_host(driver, device)
    local subhub = get_subhub(driver, device)
    local mapped_ep = ep
    local lux_map = device:get_field(FIELD_LUX_TO_MOTION)

    if lux_map and lux_map[ep] then
        mapped_ep = lux_map[ep]
    end

    local child = nil
    if subhub then
        child = subhub:get_child_by_parent_assigned_key(tostring(mapped_ep))
    end

    local target = child or host
    target:emit_event(event)
end

local function create_child_for_ep(driver, device, ep_id, profile)
    local subhub = get_subhub(driver, device)

    if not subhub then
        return nil
    end

    local key = string.format("%d", ep_id)

    local device_num = (subhub:get_field("CHILD_COUNTER") or 0) + 1
    subhub:set_field("CHILD_COUNTER", device_num, { persist = false })

    local name = string.format("%s %d", subhub.label, device_num)
    driver:try_create_device({
        type = "EDGE_CHILD",
        label = name,
        profile = profile,
        parent_device_id = subhub.id,
        parent_assigned_child_key = key,
        vendor_provided_label = name,
    })

    return nil
end

local function diff (driver, device, ib_elements)
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

local function resolve_host_and_ep(driver, device)
    local parent = get_subhub(driver, device)
    local host = get_host(driver, device)

    if device.network_type == device_lib.NETWORK_TYPE_MATTER then
        local wc_eps = device:get_endpoints(clusters.WindowCovering.ID) or {}
        local wc_main = wc_eps[1]

        local onOff_eps = host and host:get_field(FIELD_MAIN_ONOFF_EP)

        if wc_main then
            return parent, wc_main
        elseif onOff_eps then
            return parent, onOff_eps
        else
            return nil, nil
        end
    end

    if device.network_type == device_lib.NETWORK_TYPE_CHILD then
        local ep = tonumber(device.parent_assigned_child_key)
        if not ep then
            return nil, nil
        end
        return device, ep
    end

    return nil, nil
end

local function link_host_and_subhub(host)
    local parent = host:get_parent_device()

    host:set_field(SUBHUB_ID, parent.id, { persist = true })
    host:set_field(HOST_ID, host.id, { persist = true })

    parent:set_field(SUBHUB_ID, parent.id, { persist = true })
    parent:set_field(HOST_ID, host.id, { persist = true })
end

local function device_init(driver, device)
    if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
        return
    end

    local wc_eps = device:get_endpoints(clusters.WindowCovering.ID)
    local oc_eps = device:get_endpoints(clusters.OccupancySensing.ID)
    local product_id = device.manufacturer_info.product_id

    subscribe_descriptor(device, 2)
    subscribe_descriptor(device, 0)

    if device:get_parent_device() ~= nil then
        link_host_and_subhub(device)
    end

    table.sort(wc_eps)
    table.sort(oc_eps)

    local subhub = get_subhub(driver, device)
    local host = get_host(driver, device)
    local main_onOff_at_join = device:get_field(FIELD_MAIN_ONOFF_EP)

    if host and not main_onOff_at_join and (product_id == 0x0005 or product_id == 0x0006) then
        host:set_field(FIELD_MAIN_ONOFF_EP, 3, { persist = true })
        device.thread:call_with_delay(6, function()
            if host:supports_capability(capabilities.switchLevel) then
                host:set_field(FIELD_MAIN_ONOFF_EP, 4, { persist = true })
            end
        end)
    end

    if #oc_eps > 0 then
        device:try_update_metadata({ profile = "motion-illuminance" })
        device:set_field(FIELD_MOTION_HOST, oc_eps[1])
    elseif #wc_eps > 0 and product_id == 0x0005 then
        device:try_update_metadata({ profile = "window-covering" })
    elseif #wc_eps > 0 and product_id == 0x0006 then
        host:try_update_metadata({ profile = "2-button" })
    end
    if subhub then
        subhub:subscribe()
    end

end

local function handle_descriptor_report(driver, device, ib, response)
    if ib.endpoint_id ~= 0 and ib.endpoint_id ~= 2 then
        return
    end

    local subhub = get_subhub(driver, device)
    local host = get_host(driver, device)

    if not subhub then
        return
    end

    local new_eps = extract(ib) or {}
    table.sort(new_eps)

    local removed, added = diff(driver, device, new_eps)

    device:set_field(ACTIVE_EPS, new_eps, { persist = true })

    local occ_eps = device:get_endpoints(clusters.OccupancySensing.ID)
    local lux_eps = device:get_endpoints(clusters.IlluminanceMeasurement.ID)
    local lux_to_motion = build_lux_to_motion_map(occ_eps, lux_eps)

    if next(lux_to_motion) ~= nil then
        device:set_field(FIELD_LUX_TO_MOTION, lux_to_motion)
    end

    local stored_eps = device:get_field(ACTIVE_EPS)

    for _, ep in ipairs(added or {}) do

        local button_comb

        if subhub.id == device.id then
            subhub:send(clusters.Descriptor.attributes.DeviceTypeList:read(subhub, ep))

            if ep == 3 and device.network_type == device_lib.NETWORK_TYPE_MATTER and device.manufacturer_info.product_id == 0x0005 then
                host:try_update_metadata({ profile = "light-binary" })
            elseif ep == 4 and device.network_type == device_lib.NETWORK_TYPE_MATTER and device.manufacturer_info.product_id == 0x0006 then
                for _, ep_match in ipairs(stored_eps) do
                    if ep_match == 3 then
                        button_comb = true
                        break
                    end
                    button_comb = false
                end

                if button_comb then
                    host:try_update_metadata({ profile = "light-binary" })
                else
                    host:try_update_metadata({ profile = "2-button" })
                end
            elseif ep == 3 and device.network_type == device_lib.NETWORK_TYPE_MATTER and device.manufacturer_info.product_id == 0x0006 then
                for _, ep_match in ipairs(stored_eps) do
                    if ep_match == 4 then
                        button_comb = true
                        break
                    end
                    button_comb = false
                end
                if button_comb then
                    host:try_update_metadata({ profile = "light-binary" })
                else
                    host:try_update_metadata({ profile = "2-button" })
                end
            end
        end
    end

    for _, ep in ipairs(removed) do

        local button_eps = subhub:get_field(BUTTON_EPS) or {}
        local clean_eps = {}
        for _, value in ipairs(button_eps) do
            if value ~= ep then
                table.insert(clean_eps, value)
            end
        end

        table.sort(clean_eps)
        subhub:set_field(BUTTON_EPS, clean_eps, { persist = true })

        device.thread:call_with_delay(5, function()
            if subhub.id == device.id then
                subhub:send(clusters.Descriptor.attributes.DeviceTypeList:read(subhub, ep))
            end
        end)

        local key = tostring(ep)

        if not subhub then
        end
        local child = subhub:get_child_by_parent_assigned_key(key)
        if child and child.network_type == device_lib.NETWORK_TYPE_CHILD then
            driver:try_delete_device(child.id)
        end

        local button_comb
        if ep == 3 then
            if device:get_parent_device() ~= nil then
                if device.manufacturer_info.product_id == 0x0005 then
                    device:try_update_metadata({ profile = "2-button" })
                elseif device.manufacturer_info.product_id == 0x0006 then
                    for _, eps in ipairs(stored_eps) do
                        if eps == 4 then
                            button_comb = true
                            break
                        end
                        button_comb = false
                    end
                    if not button_comb then
                        host:try_update_metadata({ profile = "4-button" })
                    else
                        host:try_update_metadata({ profile = "2-button" })
                    end

                end
            end
        elseif ep == 4 then
            if device.manufacturer_info.product_id == 0x0006 then
                for _, eps in ipairs(stored_eps) do
                    if eps == 3 then
                        button_comb = true
                        break
                    end
                    button_comb = false
                end
                if not button_comb then
                    host:try_update_metadata({ profile = "4-button" })
                else
                    host:try_update_metadata({ profile = "2-button" })
                    create_child_for_ep(driver, subhub, 3, "light-binary")
                end
            end
        end
    end

end

local function on_off_attr_handler(driver, device, ib, response)
    if ib.data.value then
        emit_for_ep(driver, device, ib.endpoint_id, capabilities.switch.switch.on())
    else
        emit_for_ep(driver, device, ib.endpoint_id, capabilities.switch.switch.off())
    end
end

local function handle_preset(driver, device, cmd)
    local subhub, ep = resolve_host_and_ep(driver, device)
    if not subhub or not ep then
        return
    end
    local lift_value = device:get_field(PRESET_LEVEL_KEY) or DEFAULT_PRESET_LEVEL
    local hundredths_lift_percent = (100 - tonumber(lift_value)) * 100
    subhub:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(subhub, ep, hundredths_lift_percent))
end

local function handle_close(driver, device, cmd)
    local subhub, ep = resolve_host_and_ep(driver, device)
    if not subhub or not ep then
        return
    end
    local req = clusters.WindowCovering.commands.DownOrClose(subhub, ep)
    if device:get_field(REVERSE_POLARITY) then
        req = clusters.WindowCovering.server.commands.UpOrOpen(subhub, ep)
    end
    subhub:send(req)
end

local function handle_open(driver, device, cmd)
    local subhub, ep = resolve_host_and_ep(driver, device)
    if not subhub or not ep then
        return
    end
    local req = clusters.WindowCovering.commands.UpOrOpen(subhub, ep)
    if device:get_field(REVERSE_POLARITY) then
        req = clusters.WindowCovering.server.commands.DownOrClose(subhub, ep)
    end
    subhub:send(req)
end

local function handle_pause(driver, device, cmd)
    local subhub, ep = resolve_host_and_ep(driver, device)
    if not subhub or not ep then
        return
    end
    subhub:send(clusters.WindowCovering.commands.StopMotion(subhub, ep))
end

local function handle_shade_level(driver, device, cmd)
    local subhub, ep = resolve_host_and_ep(driver, device)
    if not subhub or not ep then
        return
    end
    local lift_percentage_value = 100 - cmd.args.shadeLevel
    local hundredths_lift_percentage = lift_percentage_value * 100
    subhub:send(clusters.WindowCovering.commands.GoToLiftPercentage(subhub, ep, hundredths_lift_percentage))
end

local current_pos_handler = function(attribute)
    return function(driver, device, ib, response)
        if ib.data.value == nil then
            return
        end
        local windowShade = capabilities.windowShade.windowShade
        local position = 100 - math.floor(ib.data.value / 100)
        local reverse = device:get_field(REVERSE_POLARITY)
        emit_for_ep(driver, device, ib.endpoint_id, attribute(position))
        if attribute == capabilities.windowShadeLevel.shadeLevel then
            device:set_field(CURRENT_LIFT, position)
        else
            device:set_field(CURRENT_TILT, position)
        end
        local lift_position = device:get_field(CURRENT_LIFT)
        local tilt_position = device:get_field(CURRENT_TILT)
        if lift_position == nil then
            if tilt_position == 0 then
                emit_for_ep(driver, device, ib.endpoint_id, reverse and windowShade.open() or windowShade.closed())
            elseif tilt_position == 100 then
                emit_for_ep(driver, device, ib.endpoint_id, reverse and windowShade.closed() or windowShade.open())
            else
                emit_for_ep(driver, device, ib.endpoint_id, windowShade.partially_open())
            end
        elseif lift_position == 100 then
            emit_for_ep(driver, device, ib.endpoint_id, reverse and windowShade.closed() or windowShade.open())
        elseif lift_position > 0 then
            emit_for_ep(driver, device, ib.endpoint_id, windowShade.partially_open())
        elseif lift_position == 0 then
            if tilt_position == nil or tilt_position == 0 then
                emit_for_ep(driver, device, ib.endpoint_id, reverse and windowShade.open() or windowShade.closed())
            elseif tilt_position > 0 then
                emit_for_ep(driver, device, ib.endpoint_id, windowShade.partially_open())
            end
        end
    end
end

local function current_status_handler(driver, device, ib, response)
    local windowShade = capabilities.windowShade.windowShade
    local reverse = device:get_field(REVERSE_POLARITY)
    local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL
    if state == 1 then
        emit_for_ep(driver, device, ib.endpoint_id, reverse and windowShade.closing() or windowShade.opening())
    elseif state == 2 then
        emit_for_ep(driver, device, ib.endpoint_id, reverse and windowShade.opening() or windowShade.closing())
    elseif state ~= 0 then
        emit_for_ep(driver, device, ib.endpoint_id, windowShade.unknown())
    end
end

local function occupancy_measured_value_handler(driver, device, ib, response)
    local host = get_host(driver, device)
    if ib.data.value ~= nil then
        emit_for_ep(driver, host, ib.endpoint_id, ib.data.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
    else
        return
    end
end

local function illuminance_measured_value_handler(driver, device, ib, response)
    local host = get_host(driver, device)
    if ib.data.value ~= nil then
        local lux = math.floor(10 ^ ((ib.data.value - 1) / 10000))
        emit_for_ep(driver, host, ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(lux))
    else
        return
    end
end

local function device_removed(driver, device)
    local subhub = get_subhub(driver, device)
    if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
        return
    end

    if subhub == nil then
        return
    end

    local eps = device:get_field(ACTIVE_EPS) or {}

    for _, ep in ipairs(eps) do
        local key = tostring(ep)
        local child = subhub:get_child_by_parent_assigned_key(key) or nil

        if child then
            driver:try_delete_device(child.id)
        else
        end
    end
end

local function handle_switch_on(driver, device, cmd)
    local subhub, ep = resolve_host_and_ep(driver, device)
    if not subhub or not ep then
        return
    end
    subhub:send(clusters.OnOff.commands.On(subhub, ep))
end

local function handle_switch_off(driver, device, cmd)
    local subhub, ep = resolve_host_and_ep(driver, device)
    if not subhub or not ep then
        return
    end
    subhub:send(clusters.OnOff.commands.Off(subhub, ep))
end

local function handle_switch_set_levels(driver, device, cmd)
    local subhub, ep = resolve_host_and_ep(driver, device)
    if not subhub or not ep then
        return
    end
    local level = math.floor(cmd.args.level / 100.0 * 254)
    subhub:send(clusters.LevelControl.server.commands.MoveToLevelWithOnOff(subhub, ep, level, cmd.args.rate, 0, 0))
end

local function level_control_current_level_handler(driver, device, ib, response)
    if ib.data.value ~= nil then
        local level = ib.data.value
        if level > 0 then
            level = math.max(1, utils.round(level / 254.0 * 100))
        end
        emit_for_ep(driver, device, ib.endpoint_id, capabilities.switchLevel.level(level))
    end
end

local function long_press_event_handler(driver, device, ib, response)
    local host = get_host(driver, device)
    host:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.held({ state_change = true }))
    if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
        set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, true)
    end
end

local function multi_press_complete_handler(driver, device, ib, response)
    local host = get_host(driver, device)
    if ib.data and not switch_utils.get_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id) then
        local press_value = ib.data.elements.total_number_of_presses_counted.value
        if press_value < 7 then
            local button_event = capabilities.button.button.pushed({ state_change = true })
            if press_value == 2 then
                button_event = capabilities.button.button.double({ state_change = true })
            elseif press_value > 2 then

                button_event = capabilities.button.button(string.format("pushed_%dx", press_value), { state_change = true })
            end
            host:emit_event_for_endpoint(ib.endpoint_id, button_event)
        else
        end
    end
    switch_utils.set_field_for_endpoint(device, fields.IGNORE_NEXT_MPC, ib.endpoint_id, nil)
end

local function info_changed(driver, device, event, args)
    local host = get_host(driver, device)
    local subhub = get_subhub(driver, device)
    if device.network_type == device_lib.NETWORK_TYPE_MATTER and device.profile.id ~= args.old_st_store.profile.id then

        host:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
        host.thread:call_with_delay(5, function()
            if host:supports_capability(capabilities.button) then
                local button_eps = subhub:get_field(BUTTON_EPS)
                local clean_eps = {}
                for _, v in ipairs(button_eps or {}) do
                    table.insert(clean_eps, v)
                end
                ButtonCfg.ButtonCfg.update_button_component_map(host, 1, clean_eps)
                ButtonCfg.ButtonCfg.configure_buttons(host)
                for _, value in ipairs(clean_eps) do
                    subhub:send(cluster_base.subscribe(subhub, value, clusters.Switch.ID, nil, clusters.Switch.events.MultiPressComplete.ID))
                    subhub:send(cluster_base.subscribe(subhub, value, clusters.Switch.ID, nil, clusters.Switch.events.ShortRelease.ID))
                    subhub:send(cluster_base.subscribe(subhub, value, clusters.Switch.ID, nil, clusters.Switch.events.LongPress.ID))
                    host:emit_event_for_endpoint(value, capabilities.button.supportedButtonValues({ "pushed", "double", "held" }))
                end

            end
        end)
    elseif args.old_st_store.preferences.reverse ~= device.preferences.reverse then
        if device.preferences.reverse then
            device:set_field(REVERSE_POLARITY, true, { persist = true })
        else
            device:set_field(REVERSE_POLARITY, false, { persist = true })
        end
    elseif args.old_st_store.preferences.presetPosition ~= device.preferences.presetPosition then
        local new_preset_value = device.preferences.presetPosition
        log.info(new_preset_value, " To new preset vlaue ")
        device:set_field(PRESET_LEVEL_KEY, new_preset_value, { persist = true })
    end
end

local function contains_ep (list, ep)
    for _, v in ipairs(list) do
        if v == ep then
            return true
        end
    end
    return false
end

local function device_type_handler (driver, device, ib)
    local host = get_host(driver, device)
    local subhub = get_subhub(driver, device)

    if not subhub then
        return
    end

    local stored = subhub:get_field(BUTTON_EPS) or {}
    local button_endpoints = {}

    local ep = ib.endpoint_id
    local value = ib.data.elements
    if stored then
        for _, v in ipairs(stored) do
            table.insert(button_endpoints, v)
        end
    end

    for _, element in ipairs(value) do
        local device_type_field = element.elements.device_type
        local device_type_id = device_type_field and device_type_field.value

        if device_type_id == 15 then
            if not contains_ep(button_endpoints, ep) then
                set_field_for_endpoint(subhub, SUPPORTS_MULTI_PRESS, ep, true, true)
                table.insert(button_endpoints, ep)
                table.sort(button_endpoints)
                subhub:set_field(BUTTON_EPS, button_endpoints, { persist = true })
            end
        end

        if device_type_id == 256 then
            local active_eps = device:get_field(ACTIVE_EPS)
            device.thread:call_with_delay(6, function()
                local subscribe = cluster_base.subscribe(subhub, ep, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil)
                subhub:send(subscribe)
            end)

            if ep == 3 and device.manufacturer_info.product_id == 0x0005 then
                return
            elseif ep == 4 and device.manufacturer_info.product_id == 0x0006 then
                local flag = false

                for _, eps in ipairs(active_eps) do
                    if eps == 3 then
                        flag = true
                        local ep3 = subhub:get_child_by_parent_assigned_key("3") or nil
                        if ep3 then
                            driver:try_delete_device(ep3.id)
                        end
                        break
                    end
                end

                if not flag then
                    create_child_for_ep(driver, subhub, 4, "light-binary")
                    return
                end
            elseif ep == 3 and device.manufacturer_info.product_id == 0x0006 then
                host.thread:call_with_delay(4, function()
                    local latest_eps = host:get_field(ACTIVE_EPS) or {}
                    local has4 = false
                    for _, eps in ipairs(latest_eps) do
                        if eps == 4 then
                            has4 = true
                            break
                        end
                    end

                    if has4 then
                        return
                    end
                    create_child_for_ep(driver, subhub, 3, "light-binary")
                end)
                return
            end
            create_child_for_ep(driver, subhub, ib.endpoint_id, "light-binary")

        elseif device_type_id == 257 then
            subhub:send(cluster_base.subscribe(subhub, ep, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil))
            subhub:send(cluster_base.subscribe(subhub, ep, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID, nil))
            subhub:send(cluster_base.subscribe(subhub, ep, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID, nil))
            subhub:send(cluster_base.subscribe(subhub, ep, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID, nil))
            if ep == 4 and device.manufacturer_info.product_id == 0x0005 then
                return
            end
            create_child_for_ep(driver, device, ib.endpoint_id, "light-level")

        elseif device_type_id == 514 then
            subhub:send(cluster_base.subscribe(subhub, ep, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.OperationalStatus.ID, nil))
            subhub:send(cluster_base.subscribe(subhub, ep, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID, nil))
            if device.manufacturer_info.product_id == 0x0005 then
                return
            else
                create_child_for_ep(driver, device, ib.endpoint_id, "window-covering")
            end
        elseif device_type_id == 263 then
            subhub:send(cluster_base.subscribe(subhub, ep, clusters.OccupancySensing.ID, clusters.OccupancySensing.attributes.Occupancy.ID, nil))

        elseif device_type_id == 262 then
            subhub:send(cluster_base.subscribe(subhub, ep, clusters.IlluminanceMeasurement.ID, clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID, nil))

        end
    end
end

local Hager_switch = {
    NAME = "Hager matter switch handler",
    lifecycle_handlers = {
        init = device_init,
        infoChanged = info_changed,
        removed = device_removed,
    },
    matter_handlers = {
        attr = {
            [clusters.Descriptor.ID] = {
                [part_list_attr_id] = handle_descriptor_report,
                [clusters.Descriptor.attributes.DeviceTypeList.ID] = device_type_handler
            },
            [clusters.IlluminanceMeasurement.ID] = {
                [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = illuminance_measured_value_handler
            },
            [clusters.OccupancySensing.ID] = {
                [clusters.OccupancySensing.attributes.Occupancy.ID] = occupancy_measured_value_handler,
            },
            [clusters.OnOff.ID] = {
                [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler
            },
            [clusters.LevelControl.ID] = {
                [clusters.LevelControl.attributes.CurrentLevel.ID] = level_control_current_level_handler
            },
            [clusters.WindowCovering.ID] = {
                [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = current_pos_handler(capabilities.windowShadeLevel.shadeLevel),
                [clusters.WindowCovering.attributes.OperationalStatus.ID] = current_status_handler,
            },

        },
        event = {
            [clusters.Switch.ID] = {
                [clusters.Switch.events.LongPress.ID] = long_press_event_handler,
                [clusters.Switch.events.MultiPressComplete.ID] = multi_press_complete_handler,
            }
        },

    },
    capability_handlers = {
        [capabilities.windowShadePreset.ID] = {
            [capabilities.windowShadePreset.commands.presetPosition.NAME] = handle_preset,
        },
        [capabilities.windowShade.ID] = {
            [capabilities.windowShade.commands.close.NAME] = handle_close,
            [capabilities.windowShade.commands.open.NAME] = handle_open,
            [capabilities.windowShade.commands.pause.NAME] = handle_pause,
        },
        [capabilities.windowShadeLevel.ID] = {
            [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = handle_shade_level,
        },
        [capabilities.switch.ID] = {
            [capabilities.switch.commands.off.NAME] = handle_switch_off,
            [capabilities.switch.commands.on.NAME] = handle_switch_on,
        },
        [capabilities.switchLevel.ID] = {
            [capabilities.switchLevel.commands.setLevel.NAME] = handle_switch_set_levels
        },
    },
    can_handle = require("sub_drivers.Hager.can_handle")
}

return Hager_switch
