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
local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"
local log = require "log"

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function fan_mode_handler(driver, device, ib, response)
  if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
    if ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.low())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.medium())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.high())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.auto())
    end
  end
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  local supportedAirPurifierFanModes
  if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
    }
  else
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
    }
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.supportedAirPurifierFanModes(supportedAirPurifierFanModes))
end

local function percent_current_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeedPercent.percent(ib.data.value))
end

local function hepa_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["hepaFilter"]
  if ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

local function activated_carbon_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["activatedCarbonFilter"]
  if ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

-- Capability Handlers --
local function set_air_purifier_fan_mode(driver, device, cmd)
  local fan_mode_id = nil
  if cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.sleep.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.quiet.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.windFree.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function handle_fan_speed_percent(driver, device, cmd)
  device:send(clusters.FanControl.attributes.PercentSetting:write(device, device:component_to_endpoint(cmd.component), cmd.args.percent))
end

local function wind_support_handler(driver, device, ib, response)
  local supportedFanWind = {}
  if ib.data.value & clusters.FanControl.types.WindSettingMask.SLEEP_WIND then
    table.insert(supportedFanWind, capabilities.windMode.windMode.sleepWind.NAME)
  end
  if ib.data.value & clusters.FanControl.types.WindSettingMask.NATURAL_WIND then
    table.insert(supportedFanWind, capabilities.windMode.windMode.naturalWind.NAME)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.supportedWindModes(supportedFanWind))
end

local function wind_setting_handler(driver, device, ib, response)
  if ib.data.value & clusters.FanControl.types.WindSettingMask.SLEEP_WIND then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.windMode.sleepWind())
  elseif ib.data.value & clusters.FanControl.types.WindSettingMask.NATURAL_WIND then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.windMode.naturalWind())
  end
end

local function set_fan_wind(driver, device, cmd)
  if cmd.args.windMode == capabilities.windMode.windMode.sleepWind.NAME then
    device:send(clusters.FanControl.attributes.WindSetting:write(device, device:component_to_endpoint(cmd.component), clusters.FanControl.types.WindSettingMask.SLEEP_WIND))
   elseif cmd.args.windMode == capabilities.windMode.windMode.naturalWind.NAME then
    device:send(clusters.FanControl.attributes.WindSetting:write(device, device:component_to_endpoint(cmd.component), clusters.FanControl.types.WindSettingMask.NATURAL_WIND))
  end
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
        [clusters.FanControl.attributes.PercentCurrent.ID] = percent_current_handler,
        [clusters.FanControl.attributes.WindSupport.ID] = wind_support_handler,
        [clusters.FanControl.attributes.WindSetting.ID] = wind_setting_handler,
      },
      [clusters.HepaFilterMonitoring.ID] = {
        [clusters.HepaFilterMonitoring.attributes.ChangeIndication.ID] = hepa_filter_change_indication_handler
      },
      [clusters.ActivatedCarbonFilterMonitoring.ID] = {
        [clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.ID] = activated_carbon_filter_change_indication_handler
      }
    }
  },
  subscribed_attributes = {
    [capabilities.airPurifierFanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.windMode.ID] = {
      clusters.FanControl.attributes.WindSupport,
      clusters.FanControl.attributes.WindSetting
    },
    [capabilities.fanSpeedPercent.ID] = {
      clusters.FanControl.attributes.PercentCurrent
    },
    [capabilities.filterStatus.ID] = {
      clusters.HepaFilterMonitoring.attributes.ChangeIndication,
      clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
    }
  },
  capability_handlers = {
    [capabilities.airPurifierFanMode.ID] = {
      [capabilities.airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = set_air_purifier_fan_mode
    },
    [capabilities.fanSpeedPercent.ID] = {
      [capabilities.fanSpeedPercent.commands.setPercent.NAME] = handle_fan_speed_percent
    },
    [capabilities.windMode.ID] = {
      [capabilities.windMode.commands.setWindMode.NAME] = set_fan_wind
    },
  },
  supported_capabilities = {
    capabilities.airPurifierFanMode,
    capabilities.fanSpeedPercent,
    capabilities.windMode
  },
}

local matter_driver = MatterDriver("matter-air-purifier", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()