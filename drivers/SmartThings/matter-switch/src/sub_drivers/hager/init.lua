-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local device_lib = require "st.device"
local buttonCfg = require "switch_utils.device_configuration".ButtonCfg
local create_child = require "switch_utils.device_configuration".ChildCfg.create_or_update_child_devices
local switch_utils = require "switch_utils.utils"
local fields = require "switch_utils.fields"

local ACTIVE_EPS = "__active_EPS"
local MATTER_DEVICE_ID = "MATTER_DEVICE_ID"
local PARENT_ID = "PARENT_ID"
local CURRENT_LIFT = "__current_lift"
local BUTTON_EPS = "__button_eps"
local MAIN_WC_EP = "__main_wc_ep"

local PRODUCT_ID = {
  SWITCH_1G = 0x0005,
  SWITCH_2G = 0x0006,
  PIR_1_1M = 0x0007,
  PIR_2_2M = 0x000A,
}

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

local function extract_reported_endpoints(ib)
  local eps = {}
  if ib.data and ib.data.elements then
    for _, el in ipairs(ib.data.elements) do
      local ep_id = el.value
      if type(ep_id) == "number" and ep_id ~= 1 and ep_id ~= 2 then
        table.insert(eps, ep_id)
      end
    end
  end
  return eps
end

local function detect_endpoint_changes (device, ib_elements)
  local stored_eps = device:get_field(ACTIVE_EPS) or {}
  ib_elements = ib_elements or {}

  local old_set, new_set = {}, {}
  for _, ep_id in ipairs(stored_eps) do
    old_set[ep_id] = true
  end
  for _, ep_id in ipairs(ib_elements) do
    new_set[ep_id] = true
  end

  local removed_eps, added_eps = {}, {}

  for ep_id in pairs(old_set) do
    if not new_set[ep_id] then
      table.insert(removed_eps, ep_id)
    end
  end
  for ep_id in pairs(new_set) do
    if not old_set[ep_id] then
      table.insert(added_eps, ep_id)
    end
  end
  return removed_eps, added_eps
end

local function assign_profile_for_endpoint(device_type_id)
  local profile = fields.device_type_profile_map[device_type_id] or "switch-binary"
  return function(device, ep_id, is_child_device)
    return profile, nil
  end
end

local function link_matter_device_and_parent(matter_device)
  local parent = matter_device:get_parent_device()
  matter_device:set_field(PARENT_ID, parent.id, { persist = true })
  matter_device:set_field(MATTER_DEVICE_ID, matter_device.id, { persist = true })
  parent:set_field(PARENT_ID, parent.id, { persist = true })
  parent:set_field(MATTER_DEVICE_ID, matter_device.id, { persist = true })
end

local function handle_set_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local lift_value = device.preferences.presetPosition
  local hundredths_lift_percent = (100 - tonumber(lift_value)) * 100
  device:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(device, endpoint_id, hundredths_lift_percent))
end

local function handle_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
  if device.preferences.reverse then
    req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
  end
  device:send(req)
end

local function handle_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
  if device.preferences.reverse then
    req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
  end
  device:send(req)
end

local function handle_pause(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.StopMotion(device, endpoint_id)
  device:send(req)
end

local function handle_shade_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
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
    local reverse = device.preferences.reverse
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
  local reverse = device.preferences.reverse
  local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL
  if state == 1 then
    device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.closing() or windowShade.opening())
  elseif state == 2 then
    device:emit_event_for_endpoint(ib.endpoint_id, reverse and windowShade.opening() or windowShade.closing())
  elseif state ~= 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
  end
end

local function info_changed(driver, device, event, args)
  if not device or not device.id or not device.profile then
    return
  end

  if device.profile.id ~= args.old_st_store.profile.id or device.network_type == device_lib.NETWORK_TYPE_CHILD then
    local parent = device:get_parent_device()
    local matter_device = get_matter_device(parent)
    local map = {}
    device.thread:call_with_delay(2, function()
      if device:supports_capability(capabilities.button) then
        local button_eps = parent:get_field(BUTTON_EPS)
        local clean_eps = {}
        table.sort(button_eps)

        for _, v in ipairs(button_eps or {}) do
          table.insert(clean_eps, v)
        end

        buttonCfg.update_button_component_map(matter_device, clean_eps[1], clean_eps)
        for _, ep_id in ipairs(clean_eps) do
          subscribe(device, ep_id, clusters.Switch.ID, nil, clusters.Switch.events.MultiPressComplete.ID)
          subscribe(device, ep_id, clusters.Switch.ID, nil, clusters.Switch.events.LongPress.ID)
          device:emit_event_for_endpoint(ep_id, capabilities.button.supportedButtonValues({ "pushed", "double", "held" }))
        end
        return
      elseif device:supports_capability(capabilities.switch) then
        map = { main = 3 }
        subscribe(device, nil, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil)
        if device:supports_capability(capabilities.switchLevel) then
          map = { main = 4 }
          subscribe(device, nil, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID, nil)
          subscribe(device, nil, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID)
          subscribe(device, nil, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID)
        end
      elseif device:supports_capability(capabilities.motionSensor) then
        subscribe(device, nil, clusters.OccupancySensing.ID, clusters.OccupancySensing.attributes.Occupancy.ID, nil)
        subscribe(device, nil, clusters.IlluminanceMeasurement.ID, clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID, nil)
      elseif device:supports_capability(capabilities.windowShadeLevel) then
        map = { main = 5 }
        subscribe(device, nil, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.OperationalStatus.ID)
        subscribe(device, nil, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID, nil)
      end
      if device.id == matter_device.id then
        parent:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, map, { persist = true })
        matter_device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, map, { persist = true })
      end
    end)
  end
end

local function device_init (driver, device)
  if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
    device.thread:call_with_delay(4, function()
      info_changed(driver, device, nil, {
        old_st_store = { profile = {  } }
      })
    end)
    return
  end

  if device:get_parent_device() ~= nil then
    link_matter_device_and_parent(device)
    local parent = device:get_parent_device()
    device:extend_device("send", function(self, message)
      return parent:send(message)
    end)
  else
    subscribe(device, 2, clusters.Descriptor.ID, clusters.Descriptor.attributes.PartsList.ID)
    device.thread:call_with_delay(3, function()
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
  local product_id = device.manufacturer_info and device.manufacturer_info.product_id
  local parent = get_parent(driver, device)

  if not parent or ib.endpoint_id ~= 2 then
    return
  end

  local matter_device = get_matter_device(device)

  local new_eps = extract_reported_endpoints(ib) or {}
  table.sort(new_eps)
  local removed_eps, added_eps = detect_endpoint_changes(device, new_eps)

  device:set_field(ACTIVE_EPS, new_eps, { persist = true })

  for _, ep_id in ipairs(added_eps or {}) do
    subscribe(parent, ep_id, clusters.Descriptor.ID, clusters.Descriptor.attributes.DeviceTypeList.ID, nil)

    if product_id == PRODUCT_ID.SWITCH_1G and ep_id == 3 then
      matter_device:try_update_metadata({ profile = "light-binary" })
    elseif product_id == PRODUCT_ID.SWITCH_2G then
      if ep_id == 3 then
        local profile = switch_utils.tbl_contains(new_eps, 4) and "light-binary" or "2-button"
        matter_device:try_update_metadata({ profile = profile })
      elseif ep_id == 4 then
        local profile = switch_utils.tbl_contains(new_eps, 3) and "light-binary" or "2-button"
        matter_device:try_update_metadata({ profile = profile })
      end
    end
  end

  for _, ep_id in ipairs(removed_eps) do
    local button_eps = parent:get_field(BUTTON_EPS) or {}
    local clean_eps = {}

    for _, value in ipairs(button_eps) do
      if value ~= ep_id then
        table.insert(clean_eps, value)
      end
    end
    table.sort(clean_eps)
    parent:set_field(BUTTON_EPS, clean_eps, { persist = true })
    matter_device:set_field(BUTTON_EPS, clean_eps, { persist = true })

    local child = parent:get_child_by_parent_assigned_key(tostring(ep_id))
    if child then
      driver:try_delete_device(child.id)
    end

    if ep_id == 3 then
      if device.manufacturer_info.product_id == PRODUCT_ID.SWITCH_1G then
        matter_device:try_update_metadata({ profile = "2-button" })
      elseif device.manufacturer_info.product_id == PRODUCT_ID.SWITCH_2G then
        local has_ep4 = switch_utils.tbl_contains(new_eps, 4)
        matter_device:try_update_metadata({ profile = has_ep4 and "2-button" or "4-button" })
      end
    elseif ep_id == 4 then
      if device.manufacturer_info.product_id == PRODUCT_ID.SWITCH_2G then
        local button_comb = switch_utils.tbl_contains(new_eps, 3)
        if button_comb then
          matter_device:try_update_metadata({ profile = "2-button" })
          create_child(driver, parent, { 3 }, 1, assign_profile_for_endpoint(fields.DEVICE_TYPE_ID.LIGHT.ON_OFF))
        else
          matter_device:try_update_metadata({ profile = "4-button" })
        end
      end
    end
  end
end

local function device_type_handler (driver, device, ib)
  local parent = get_parent(driver, device)
  if not parent then
    return
  end

  local matter_device = get_matter_device(device)
  local stored_btn_eps = parent:get_field(BUTTON_EPS) or {}
  local new_btn_eps = {}
  local ep_id = ib.endpoint_id
  local value = ib.data.elements

  for _, v in ipairs(stored_btn_eps) do
    table.insert(new_btn_eps, v)
  end
  for _, element in ipairs(value) do
    local device_type_field = element.elements.device_type
    local device_type_id = device_type_field and device_type_field.value

    if device_type_id == fields.DEVICE_TYPE_ID.GENERIC_SWITCH then
      if not switch_utils.tbl_contains(new_btn_eps, ep_id) then
        switch_utils.set_field_for_endpoint(parent, fields.SUPPORTS_MULTI_PRESS, ep_id)
        switch_utils.set_field_for_endpoint(parent, fields.IGNORE_NEXT_MPC, ep_id)
        table.insert(new_btn_eps, ep_id)
        table.sort(new_btn_eps)
        parent:set_field(BUTTON_EPS, new_btn_eps, { persist = true })
      end
    end

    if device_type_id == fields.DEVICE_TYPE_ID.LIGHT.ON_OFF then
      local active_eps = device:get_field(ACTIVE_EPS)

      if ep_id == 3 and device.manufacturer_info.product_id == PRODUCT_ID.SWITCH_1G then
        return
      elseif ep_id == 4 and device.manufacturer_info.product_id == PRODUCT_ID.SWITCH_2G then
        if switch_utils.tbl_contains(active_eps, 3) then
          local ep3 = parent:get_child_by_parent_assigned_key("3")
          if ep3 then
            driver:try_delete_device(ep3.id)
          end
        else
          create_child(driver, parent, { 4 }, 1, assign_profile_for_endpoint(device_type_id))
          return
        end
      elseif ep_id == 3 and device.manufacturer_info.product_id == PRODUCT_ID.SWITCH_2G then
        if not switch_utils.tbl_contains(active_eps, 4) then
          create_child(driver, parent, { 3 }, 1, assign_profile_for_endpoint(device_type_id))
        else
          driver:try_delete_device(ep_id)
        end
        return
      end
      create_child(driver, parent, { ep_id }, 1, assign_profile_for_endpoint(device_type_id))
    elseif device_type_id == fields.DEVICE_TYPE_ID.LIGHT.DIMMABLE then
      if ep_id == 4 and device.manufacturer_info.product_id == PRODUCT_ID.SWITCH_1G then
        return
      end
      create_child(driver, parent, { ep_id }, 1, assign_profile_for_endpoint(device_type_id))
    elseif device_type_id == fields.DEVICE_TYPE_ID.WINDOW_COVERING then
      if matter_device:get_field(MAIN_WC_EP) == nil then
        create_child(driver, parent, { ep_id }, 1, assign_profile_for_endpoint(device_type_id))
      end
    end
  end
end

local function do_configure (driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then

    local wc_eps = device:get_endpoints(clusters.WindowCovering.ID)
    local oc_eps = device:get_endpoints(clusters.OccupancySensing.ID)
    local bt_eps = device:get_endpoints(clusters.Switch.ID)
    local lvl_eps = device:get_endpoints(clusters.LevelControl.ID)
    local product_id = device.manufacturer_info.product_id

    table.sort(wc_eps)
    table.sort(oc_eps)
    table.sort(lvl_eps)

    if #oc_eps > 0 then
      device:try_update_metadata({ profile = "motion-illuminance" })
    elseif #wc_eps > 0 and product_id == PRODUCT_ID.SWITCH_1G then
      device:try_update_metadata({ profile = "window-covering" })
      device:set_field(MAIN_WC_EP, wc_eps[1], { persist = true })
    elseif #bt_eps == 4 then
      device:try_update_metadata({ profile = "4-button" })
    elseif #bt_eps == 2 then
      device:try_update_metadata({ profile = "2-button" })
    elseif #lvl_eps > 0 and product_id == PRODUCT_ID.SWITCH_1G then
      device:try_update_metadata({ profile = "light-level" })
    end
    device:set_field(BUTTON_EPS, bt_eps, { persist = true })
  end
end

local function added (driver, device) end
local function driver_switched(driver, device) end

local hager_switch = {
  NAME = "Hager Subdriver",
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
        [clusters.Descriptor.attributes.DeviceTypeList.ID] = device_type_handler,
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

return hager_switch
