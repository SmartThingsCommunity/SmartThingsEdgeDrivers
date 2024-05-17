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

local ep_ini = 7

local function component_to_endpoint(device, component_id)
  ep_ini = 7
  if component_id == "main" then
    return ep_ini
  end
end

local function endpoint_to_component(device, ep)
  ep_ini = 7
  if ep == ep_ini then
    return "main"
  end
end

local function do_configure(driver, device)
  device:configure()
end

local function device_init (driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local function driver_switched(driver,device)
  device.thread:call_with_delay(2, function(d)
  device:configure()
  end, "configure")
end

local function window_shade_level_cmd_handler(driver, device, command)
  local window_shade = capabilities.windowShade.windowShade
  local window_shadeLevel = capabilities.windowShadeLevel
  local level = command.args.shadeLevel
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
  if level == 0 or level == 100 then
    device:emit_event(level == 0 and window_shade.closed() or window_shade.open())
    device:emit_event(level == 0 and window_shadeLevel.shadeLevel(0) or window_shadeLevel.shadeLevel(100))
  elseif level > 0 and level < 100 then
    device:emit_event(window_shade.partially_open())
    device:emit_event(window_shadeLevel.shadeLevel(level))
  end
end

local function pause_handler(driver, device, command)
  device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
  device:emit_event(capabilities.windowShade.windowShade.partially_open())
end

local function open_handler(driver, device, command)
  local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  if current_level ~= 100 then
    device:emit_event(capabilities.windowShade.windowShade.opening())
    device:send_to_component(command.component, WindowCovering.server.commands.UpOrOpen(device))
  end
end

local function close_handler(driver, device, command)
  local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  if current_level ~= 0 then
    device:emit_event(capabilities.windowShade.windowShade.closing())
    device:send_to_component(command.component, WindowCovering.server.commands.DownOrClose(device))
  end
end

local confioscc_handler = {
  NAME = "confioscc Device Handler",
  lifecycle_handlers = {
    init = device_init,
    driverSwitched = driver_switched,
    doConfigure = do_configure,
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = open_handler,
      [capabilities.windowShade.commands.close.NAME] = close_handler,
      [capabilities.windowShade.commands.pause.NAME] = pause_handler
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd_handler
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "CTCCZB"
  end
}

return confioscc_handler