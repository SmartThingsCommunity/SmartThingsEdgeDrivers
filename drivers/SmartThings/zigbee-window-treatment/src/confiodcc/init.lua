-- Copyright 2023 SmartThings
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
local WindowCovering = zcl_clusters.WindowCovering

local ep_num = 5

local function component_to_endpoint(device, component_id)
  if component_id == "main" then
    return ep_num
  else
    local ep_ini = component_id:match("switch(%d)")
    if ep_ini == "6" then
      return ep_num + 1
    end
  end
end

local function endpoint_to_component(device, ep)
  if ep == ep_num then
    return "main"
  else
    if ep == ep_num + 1 then
      return "switch6"
    end
  end
end

local function do_configure(driver, device)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device:configure()
  end
end

local function device_init (driver, device)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
  end
  local profile_type = "window-treatment-confio"
  local label = "Confio Dual Curtain 2"
  if not device:get_child_by_parent_assigned_key("switch6") then
  local metadata = {
    type = "EDGE_CHILD",
    label = label,
    profile = profile_type,
    parent_device_id = device.id,
    parent_assigned_child_key = "switch6",
    vendor_provided_label = profile_type
  }
  driver:try_create_device(metadata)
  end
end

local function driver_switched(driver,device)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device.thread:call_with_delay(2, function(d)
    device:configure()
    end, "configure")
  end
end

local function window_shade_set_level_handler(driver, device, command)
  local window_shade = capabilities.windowShade.windowShade
  local window_shadeLevel = capabilities.windowShadeLevel
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
  local level = command.args.shadeLevel
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
  if level == 0 or level == 100 then
    device:emit_event(level == 0 and window_shade.closed() or window_shade.open())
    device:emit_event(level == 0 and window_shadeLevel.shadeLevel(0) or window_shadeLevel.shadeLevel(100))
  elseif level > 0 and level < 100 then
    device:emit_event(window_shade.partially_open())
    device:emit_event(window_shadeLevel.shadeLevel(level))
  end
  else
    local parent_device = device:get_parent_device()
    local component = device.parent_assigned_child_key
    if component~="main" then
      local level = command.args.shadeLevel
      parent_device:send_to_component(component, WindowCovering.server.commands.GoToLiftPercentage(parent_device, level))
      if level == 0 or level == 100 then
        device:emit_event(level == 0 and window_shade.closed() or window_shade.open())
        device:emit_event(level == 0 and window_shadeLevel.shadeLevel(0) or window_shadeLevel.shadeLevel(100))
      elseif level > 0 and level < 100 then
        device:emit_event(window_shade.partially_open())
        device:emit_event(window_shadeLevel.shadeLevel(level))
      end
    end
  end
end

local function open_handler(driver, device, command)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    local current_level = device:get_latest_state(command.component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
    if current_level ~= 100 then
      device:emit_event(capabilities.windowShade.windowShade.opening())
      device:send_to_component(command.component, WindowCovering.server.commands.UpOrOpen(device))
    end
  else
    local parent_device = device:get_parent_device()
    local component = device.parent_assigned_child_key
    if component ~= "main" then
      device:emit_event(capabilities.windowShade.windowShade.open())
      parent_device:send_to_component(component, WindowCovering.server.commands.GoToLiftPercentage(parent_device, 100))
      device:emit_event(capabilities.windowShadeLevel.shadeLevel(100))    
    end
  end
end

local function close_handler(driver, device, command)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    local current_level = device:get_latest_state(command.component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
    if current_level ~= 0 then
      device:emit_event(capabilities.windowShade.windowShade.closing())
      device:send_to_component(command.component, WindowCovering.server.commands.DownOrClose(device))
    end
  else
    local parent_device = device:get_parent_device()
    local component = device.parent_assigned_child_key
    if component ~= "main" then
      device:emit_event(capabilities.windowShade.windowShade.closed())
      parent_device:send_to_component(component, WindowCovering.server.commands.GoToLiftPercentage(parent_device, 0))
      device:emit_event(capabilities.windowShadeLevel.shadeLevel(0))
    end
  end
end

local function pause_handler(driver, device, command)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then---- device (is NO Child device)
    device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  else
    local parent_device = device:get_parent_device()
    local component = device.parent_assigned_child_key
    if component ~= "main" then
      parent_device:send_to_component(component, WindowCovering.server.commands.Stop(parent_device))
      device:emit_event(capabilities.windowShade.windowShade.partially_open())
    end
  end
end

local function do_added(driver, device)
  if device.network_type == "DEVICE_EDGE_CHILD" then  ---- device (is Child device)
    local component = device.parent_assigned_child_key
    local parent_device = device:get_parent_device()
    if component == "main" then
      if parent_device:get_latest_state(component, capabilities.windowShade.ID, capabilities.windowShade.windowShade.NAME) == "open" then
        device:emit_event(capabilities.windowShade.windowShade.open())
      else
        device:emit_event(capabilities.windowShade.windowShade.closed())
      end
    else
      if device.preferences.profileType == "shadeLevel" then
        local child_level = parent_device:get_latest_state(component, capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
        device:emit_event(capabilities.windowShadeLevel.shadeLevel(child_level))
      end
    end
  end
end

local confiodcc_handler = {
  NAME = "confiodcc Device Handler",
  lifecycle_handlers = {
    init = device_init,
    driverSwitched = driver_switched,
    doConfigure = do_configure,
    added = do_added,
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = open_handler,
      [capabilities.windowShade.commands.close.NAME] = close_handler,
      [capabilities.windowShade.commands.pause.NAME] = pause_handler
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_set_level_handler
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "CT2CCZB"
  end
}

return confiodcc_handler