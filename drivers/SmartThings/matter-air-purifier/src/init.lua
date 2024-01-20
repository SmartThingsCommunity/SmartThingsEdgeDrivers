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

local log = require "log"

local hepaFilterStatusId = "spacewonder52282.hepaFilterStatus3"
local activatedCarbonFilterStatusId = "spacewonder52282.activatedCarbonFilterStatus3"
local hepaFilterStatus = capabilities[hepaFilterStatusId]
local activatedCarbonFilterStatus = capabilities[activatedCarbonFilterStatusId]

local function device_init(driver, device)
  device:subscribe()
end

-- Matter Handlers --
local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function fan_mode_handler(driver, device, ib, response)
  if ib.data.value == clusters.FanControl.attributes.FanMode.base_type.OFF then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
    if ib.data.value == clusters.FanControl.attributes.FanMode.base_type.LOW then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.low())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.base_type.MEDIUM then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.medium())
    elseif ib.data.value == clusters.FanControl.attributes.FanMode.base_type.HIGH then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.high())
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.airPurifierFanMode.airPurifierFanMode.auto())
    end
  end
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  local supportedAirPurifierFanModes
  if ib.data.value == clusters.FanControl.attributes.FanModeSequence.base_type.OFF_LOW_MED_HIGH then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.base_type.OFF_LOW_HIGH then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.base_type.OFF_LOW_MED_HIGH_AUTO then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.base_type.OFF_LOW_HIGH_AUTO then
    supportedAirPurifierFanModes = {
      capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME,
      capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.base_type.OFF_ON_AUTO then
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

local function speed_current_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeed.fanSpeed(ib.data.value))
end

local function wind_support_handler(driver, device, ib, response)
  local supportedFanWind = {}
  if ib.data.value & clusters.FanControl.types.WindSettingMask.SLEEP_WIND then
    table.insert(supportedFanWind, capabilities.windMode.windMode.sleepWind.NAME)
  end
  if ib.data.value & clusters.FanControl.types.WindSettingMask.NATURAL_WIND then
    table.insert(supportedFanWind, capabilities.windMode.windMode.naturalWind.NAME)
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.supportedFanWind(supportedFanWind))
end

local function wind_setting_handler(driver, device, ib, response)
  if ib.data.value & clusters.FanControl.types.WindSettingMask.SLEEP_WIND then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.windMode.sleepWind())
  elseif ib.data.value & clusters.FanControl.types.WindSettingMask.NATURAL_WIND then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.windMode.windMode.naturalWind())
  end
end

local function hepa_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["HEPA-Filter"]
  if ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.base_type.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.base_type.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.HepaFilterMonitoring.attributes.ChangeIndication.base_type.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

local function activated_carbon_filter_change_indication_handler(driver, device, ib, response)
  local component = device.profile.components["Activated-Carbon-Filter"]
  if ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.base_type.OK then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.base_type.WARNING then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.normal())
  elseif ib.data.value == clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication.base_type.CRITICAL then
    device:emit_component_event(component, capabilities.filterStatus.filterStatus.replace())
  end
end

-- Capability Handlers --
local function handle_switch_on(driver, device, cmd)
  local fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.LOW
  device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
end

local function handle_switch_off(driver, device, cmd)
  local fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.OFF
  device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
end

local function set_air_purifier_fan_mode(driver, device, cmd)
  local fan_mode_id = nil
  if cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.low.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.sleep.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.quiet.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.windFree.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.LOW
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.medium.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.MEDIUM
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.high.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.HIGH
  elseif cmd.args.airPurifierFanMode == capabilities.airPurifierFanMode.airPurifierFanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.base_type.OFF
  end
  if fan_mode_id then
    device:send(clusters.FanControl.attributes.FanMode:write(device, device:component_to_endpoint(cmd.component), fan_mode_id))
  end
end

local function set_fan_wind(driver, device, cmd)
  if cmd.args.windMode == capabilities.windMode.windMode.sleepWind.NAME then
    device:send(clusters.FanControl.attributes.WindSetting:write(device, device:component_to_endpoint(cmd.component), clusters.FanControl.types.WindSettingMask.SLEEP_WIND))
  elseif cmd.args.windMode == capabilities.windMode.windMode.naturalWind.NAME then
    device:send(clusters.FanControl.attributes.WindSetting:write(device, device:component_to_endpoint(cmd.component), clusters.FanControl.types.WindSettingMask.NATURAL_WIND))
  end
end

local function handle_fan_speed(driver, device, cmd)
  device:send(clusters.FanControl.attributes.SpeedSetting:write(device, device:component_to_endpoint(cmd.component), cmd.args.speed))
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
        [clusters.FanControl.attributes.SpeedCurrent.ID] = speed_current_handler,
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
    [capabilities.windMode] = {
      clusters.FanControl.attributes.WindSupport,
      clusters.FanControl.attributes.WindSetting
    },
    [capabilities.fanSpeed.ID] = {
      clusters.FanControl.attributes.SpeedCurrent
    },
    [capabilities.filterStatus.ID] = {
      clusters.HepaFilterMonitoring.attributes.ChangeIndication,
      clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.airPurifierFanMode.ID] = {
      [capabilities.airPurifierFanMode.commands.setAirPurifierFanMode.NAME] = set_air_purifier_fan_mode
    },
    -- [capabilities.windMode] = {
    --   [capabilities.windMode.commands.setWindMode.NAME] = set_fan_wind
    -- },
    [capabilities.fanSpeed.ID] = {
      [capabilities.fanSpeed.commands.setFanSpeed.NAME] = handle_fan_speed
    }
  },
  supported_capabilities = {
    capabilities.switch
  },
}

local matter_driver = MatterDriver("matter-air-purifier", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
