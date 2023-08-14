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
local clusters = require "st.matter.clusters"
local airPurifierFanMode = capabilities.airPurifierFanMode
local airPurifierFanModeId = "airPurifierFanMode"

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function handle_switch_on(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  -- Room Air Conditioner
  local supportedAirPurifierFanModes
  if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
    supportedAirPurifierFanModes = {
      airPurifierFanMode.airPurifierFanMode.low.NAME,
      airPurifierFanMode.airPurifierFanMode.medium.NAME,
      airPurifierFanMode.airPurifierFanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
    supportedAirPurifierFanModes = {
      airPurifierFanMode.airPurifierFanMode.low.NAME,
      airPurifierFanMode.airPurifierFanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
    supportedAirPurifierFanModes = {
      airPurifierFanMode.airPurifierFanMode.low.NAME,
      airPurifierFanMode.airPurifierFanMode.medium.NAME,
      airPurifierFanMode.airPurifierFanMode.high.NAME,
      airPurifierFanMode.airPurifierFanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
    supportedAirPurifierFanModes = {
      airPurifierFanMode.airPurifierFanMode.low.NAME,
      airPurifierFanMode.airPurifierFanMode.high.NAME,
      airPurifierFanMode.airPurifierFanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
    supportedAirPurifierFanModes = {
      airPurifierFanMode.airPurifierFanMode.high.NAME,
      airPurifierFanMode.airPurifierFanMode.auto.NAME
    }
  else
    supportedAirPurifierFanModes = {
      airPurifierFanMode.airPurifierFanMode.high.NAME
    }
  end
  device:emit_event_for_endpoint(ib.endpoint_id, airPurifierFanMode.supportedAirPurifierFanModes(supportedAirPurifierFanModes))
end

local function fan_mode_handler(driver, device, ib, response)
  -- Room Air Conditioner
  if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
    if ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
      device:emit_event_for_endpoint(ib.endpoint_id, airPurifierFanMode.airPurifierFanMode.low())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
      device:emit_event_for_endpoint(ib.endpoint_id, airPurifierFanMode.airPurifierFanMode.medium())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
      device:emit_event_for_endpoint(ib.endpoint_id, airPurifierFanMode.airPurifierFanMode.high())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, airPurifierFanMode.airPurifierFanMode.auto())
    end
  end
end

local function set_fan_mode(driver, device, cmd)
  local fan_mode_id = nil
  if cmd.args.airPurifierFanMode == airPurifierFanMode.airPurifierFanMode.low.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == airPurifierFanMode.airPurifierFanMode.sleep.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == airPurifierFanMode.airPurifierFanMode.quiet.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == airPurifierFanMode.airPurifierFanMode.windFree.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == airPurifierFanMode.airPurifierFanMode.medium.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.airPurifierFanMode == airPurifierFanMode.airPurifierFanMode.high.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.airPurifierFanMode == airPurifierFanMode.airPurifierFanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local air_purifer_fan_mode_handler = {
  NAME = "Air Purifier Fan Mode",
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler
      },
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [airPurifierFanModeId] = {
      [airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = set_fan_mode,
    }
  },
  can_handle = function(opts, driver, device)
    return device:supports_capability_by_id(airPurifierFanModeId)
  end
}

return air_purifer_fan_mode_handler