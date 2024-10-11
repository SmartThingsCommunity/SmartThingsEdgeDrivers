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

--Note: Currently only support for window shades with the PositionallyAware Feature
--Note: No support for setting device into calibration mode, it must be done manually
local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local MatterDriver = require "st.matter.driver"

local PROFILE_MATCHED = "__profile_matched"
local CURRENT_POSITION = "__current_position"
local TARGET_POSITION = "__target_position"
local Initial_Status_Display = "__initial_status_display"

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name)
  -- Use the find_default_endpoint function to return the first endpoint that
  -- supports a given cluster.
  return find_default_endpoint(device, clusters.WindowCovering.ID)
end

local function match_profile(device)
  local profile_name = "window-covering"
  local battery_eps = device:get_endpoints(clusters.PowerSource.ID,
          {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})

  if #battery_eps > 0 then
    profile_name = "window-covering-battery"
  end
  device:try_update_metadata({profile = profile_name})
  device:set_field(PROFILE_MATCHED, 1)
end

local function device_init(driver, device)
  if not device:get_field(PROFILE_MATCHED) then
    match_profile(device)
  end
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:subscribe()
  device:set_field(Initial_Status_Display, true)
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    -- Profile has changed, resubscribe
    device:subscribe()
  else
    -- Something else has changed info (SW update, reinterview, etc.), so
    -- try updating profile as needed
    match_profile(device)
  end
end

local function device_added(driver, device)
  device:emit_event(
    capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, {visibility = {displayed = false}})
  )
end

local function device_removed(driver, device) log.info("device removed") end

-- capability handlers
local function handle_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local lift_value = 100 - device.preferences.presetPosition
  local hundredths_lift_percent = lift_value * 100
  local req = clusters.WindowCovering.server.commands.GoToLiftPercentage(
                device, endpoint_id, hundredths_lift_percent
              )

  device:send(req)
end

-- close covering
local function handle_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
  device:send(req)
end

-- open covering
local function handle_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
  device:send(req)
end

-- pause covering
local function handle_pause(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.StopMotion(device, endpoint_id)
  device:send(req)
end

-- move to shade level
-- beteween 0-100
local function handle_shade_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local lift_percentage_value = 100 - cmd.args.shadeLevel
  local hundredths_lift_percentage = lift_percentage_value * 100
  local req = clusters.WindowCovering.server.commands.GoToLiftPercentage(
                device, endpoint_id, hundredths_lift_percentage
              )
  device:send(req)
end

-- to decide the status of window covering
local function decide_status(device, ib, position)
  if position == 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShade.windowShade.closed())
  elseif position == 100 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShade.windowShade.open())
  elseif position > 0 and position < 100 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShade.windowShade.partially_open())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShade.windowShade.unknown())
  end
end

-- current lift percentage, changed to 100ths percent
local function current_pos_handler(driver, device, ib, response)
  local position = 0
  if ib.data.value ~= nil then
    position = 100 - math.floor((ib.data.value / 100))
    device:emit_event_for_endpoint(
      ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(position)
    )
  end
  device:set_field(CURRENT_POSITION, position)
  if device:get_field(Initial_Status_Display) == true then
    -- Emiting window status during initialization
    decide_status(device, ib, position)
    device:set_field(Initial_Status_Display, false)
  elseif device:get_field(TARGET_POSITION) == position and device:get_field(Initial_Status_Display) == false then
    -- Emiting window status after arriving to the target position
    decide_status(device, ib, position)
  end
end

-- checks the current position of the shade
local function target_pos_handler(driver, device, ib, response)
  local attr = capabilities.windowShade.windowShade
  local target_position
  if ib.data.value ~= nil then
    target_position = 100 - math.floor((ib.data.value / 100))
  end
  device:set_field(TARGET_POSITION, target_position)
  if device:get_field(CURRENT_POSITION) > target_position then
    device:emit_event_for_endpoint(ib.endpoint_id, attr.closing())
  elseif device:get_field(CURRENT_POSITION) < target_position then
    device:emit_event_for_endpoint(ib.endpoint_id, attr.opening())
  end 
end

local function level_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    --TODO should we invert this like we do for CurrentLiftPercentage100ths?
    local level = math.floor((ib.data.value / 254.0 * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windowShadeLevel.shadeLevel(level))
  end
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local matter_driver_template = {
  lifecycle_handlers = {init = device_init, removed = device_removed, added = device_added, infoChanged = info_changed},
  matter_handlers = {
    attr = {
      --TODO LevelControl may not be needed for certified devices since
      -- certified should use CurrentPositionLiftPercent100ths attr
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = level_attr_handler,
      },
      [clusters.WindowCovering.ID] = {
        --uses percent100ths more often
        [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = current_pos_handler,
        [clusters.WindowCovering.attributes.TargetPositionLiftPercent100ths.ID] = target_pos_handler,
        -- [clusters.WindowCovering.attributes.OperationalStatus.ID] = current_status_handler,
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler,
      }
    },
  },
  subscribed_attributes = {
    [capabilities.windowShade.ID] = {
      clusters.WindowCovering.attributes.OperationalStatus
    },
    [capabilities.windowShadeLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths,
      clusters.WindowCovering.attributes.TargetPositionLiftPercent100ths,
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = nil --TODO: define me!
    },
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
  },
  supported_capabilities = {
    capabilities.windowShadeLevel,
    capabilities.windowShade,
    capabilities.windowShadePreset,
    capabilities.battery,
  },
}

local matter_driver = MatterDriver("matter-window-covering", matter_driver_template)
matter_driver:run()