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
local CURRENT_LIFT = "__current_lift"
local CURRENT_TILT = "__current_tilt"

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
  local lift_eps = device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.LIFT})
  local tilt_eps = device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.TILT})
  local battery_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  local profile_name = "window-covering"
  if #tilt_eps > 0 then
    profile_name = profile_name .. "-tilt"
    if #lift_eps == 0 then
      profile_name = profile_name .. "-only"
    end
  end

  if #battery_eps > 0 then
    profile_name = profile_name .. "-battery"
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
  local lift_eps = device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.LIFT})
  local tilt_eps = device:get_endpoints(clusters.WindowCovering.ID, {feature_bitmap = clusters.WindowCovering.types.Feature.TILT})
  if #lift_eps > 0 then
    local lift_value = 100 - device.preferences.presetPosition
    local hundredths_lift_percent = lift_value * 100
    local req = clusters.WindowCovering.server.commands.GoToLiftPercentage(
      device, endpoint_id, hundredths_lift_percent
    )
    device:send(req)
  end
  if #tilt_eps > 0 then
    -- Use default preset tilt percentage to 50 until a canonical preference is created for preset tilt position
    local req = clusters.WindowCovering.server.commands.GoToTiltPercentage(
      device, endpoint_id, 50 * 100
    )
    device:send(req)
  end
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

-- move to shade level between 0-100
local function handle_shade_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local lift_percentage_value = 100 - cmd.args.shadeLevel
  local hundredths_lift_percentage = lift_percentage_value * 100
  local req = clusters.WindowCovering.server.commands.GoToLiftPercentage(
                device, endpoint_id, hundredths_lift_percentage
              )
  device:send(req)
end

-- move to shade tilt level between 0-100
local function handle_shade_tilt_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local tilt_percentage_value = 100 - cmd.args.level
  local hundredths_tilt_percentage = tilt_percentage_value * 100
  local req = clusters.WindowCovering.server.commands.GoToTiltPercentage(
    device, endpoint_id, hundredths_tilt_percentage
  )
  device:send(req)
end

-- current lift/tilt percentage, changed to 100ths percent
local current_pos_handler = function(attribute)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local windowShade = capabilities.windowShade.windowShade
    local position = 100 - math.floor((ib.data.value / 100))
    device:emit_event_for_endpoint(ib.endpoint_id, attribute(position))
    if attribute == capabilities.windowShadeLevel.shadeLevel then
      device:set_field(CURRENT_LIFT, position)
      local tilt_position = device:get_field(CURRENT_TILT)
      if position == 0 and (tilt_position == nil or tilt_position == 0) then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.closed())
      elseif position < 100 then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
      elseif position == 100 then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.open())
      else
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
      end
    else
      device:set_field(CURRENT_TILT, position)
      local lift_position = device:get_field(CURRENT_LIFT)
      if lift_position == nil then
        if position == 0 then
          device:emit_event_for_endpoint(ib.endpoint_id, windowShade.closed())
        elseif position == 100 then
          device:emit_event_for_endpoint(ib.endpoint_id, windowShade.open())
        elseif position > 0 and position < 100 then
          device:emit_event_for_endpoint(ib.endpoint_id, windowShade.partially_open())
        else
          device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
        end
      elseif position == 0 and lift_position == 0 then
        device:emit_event_for_endpoint(ib.endpoint_id, windowShade.closed())
      end
    end
  end
end

-- checks the current position of the shade
local function current_status_handler(driver, device, ib, response)
  local windowShade = capabilities.windowShade.windowShade
  local state = ib.data.value & clusters.WindowCovering.types.OperationalStatus.GLOBAL
  if state == 1 then -- opening
    device:emit_event_for_endpoint(ib.endpoint_id, windowShade.opening())
  elseif state == 2 then -- closing
    device:emit_event_for_endpoint(ib.endpoint_id, windowShade.closing())
  elseif state ~= 0 then -- unknown
    device:emit_event_for_endpoint(ib.endpoint_id, windowShade.unknown())
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
        [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = current_pos_handler(capabilities.windowShadeLevel.shadeLevel),
        [clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths.ID] = current_pos_handler(capabilities.windowShadeTiltLevel.shadeTiltLevel),
        [clusters.WindowCovering.attributes.OperationalStatus.ID] = current_status_handler,
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
    },
    [capabilities.windowShadeTiltLevel.ID] = {
      clusters.WindowCovering.attributes.CurrentPositionTiltPercent100ths,
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
    [capabilities.windowShadeTiltLevel.ID] = {
      [capabilities.windowShadeTiltLevel.commands.setShadeTiltLevel.NAME] = handle_shade_tilt_level,
    },
  },
  supported_capabilities = {
    capabilities.windowShadeLevel,
    capabilities.windowShadeTiltLevel,
    capabilities.windowShade,
    capabilities.windowShadePreset,
    capabilities.battery,
  },
  sub_drivers = {
    -- for devices sending a position update while device is in motion
    require("matter-window-covering-position-updates-while-moving")
  }
}

local matter_driver = MatterDriver("matter-window-covering", matter_driver_template)
matter_driver:run()