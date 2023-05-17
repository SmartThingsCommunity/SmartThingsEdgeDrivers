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

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = (require "st.zwave.CommandClass")
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({version=2})
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=3})
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})

local preferencesMap = require "preferences"

local utils = require "st.utils"

-- configuration parameters
local OPERATING_MODE_CONFIGURATION = 71

-- preference IDs
local SLATS_TURN_TIME = "slatsTurnTime"

-- fieldnames
local BLINDS_LAST_COMMAND = "blinds_last_command"
local SHADE_TARGET = "shade_target"

local ENERGY_UNIT_KWH = "kWh"
local POWER_UNIT_WATT = "W"

local QUBINO_FLUSH_SHUTTER_FINGERPRINTS = {
  {mfr = 0x0159, prod = 0x0003, model = 0x0052}, -- Qubino Flush Shutter AC
  {mfr = 0x0159, prod = 0x0003, model = 0x0053}, -- Qubino Flush Shutter DC
}

local function can_handle_qubino_flush_shutter(opts, self, device, ...)
  for _, fingerprint in ipairs(QUBINO_FLUSH_SHUTTER_FINGERPRINTS) do
    if device:id_match( fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function configuration_report(self, device, cmd)
  local parameter_number = cmd.args.parameter_number
  local configuration_value = cmd.args.configuration_value

  if parameter_number == OPERATING_MODE_CONFIGURATION then
    if configuration_value == 0 then
      device:try_update_metadata({profile = "qubino-flush-shutter"})
    elseif configuration_value == 1 then
      device:try_update_metadata({profile = "qubino-flush-shutter-venetian"})
    end
  end
end

local function window_shade_level_change(self, device, level, cmd)
  device:send_to_component(SwitchMultilevel:Set({value = level}), cmd.component)

  if cmd.component ~= "main" then
    local slatsMoveTime = preferencesMap.to_numeric_value(device.preferences[SLATS_TURN_TIME])
    local delay = utils.round(slatsMoveTime / 100 * 1.1)
    device.thread:call_with_delay(delay,
      function()
        device:send_to_component(SwitchMultilevel:Get({}), cmd.component)
      end
    )
  end
end

local function set_shade_level(self, device, cmd)
  local level = math.max(math.min(cmd.args.shadeLevel, 99), 0)
  window_shade_level_change(self, device, level, cmd)
end

local function open(driver, device, cmd)
  window_shade_level_change(driver, device, 99, cmd)
end

local function close(driver, device, cmd)
  window_shade_level_change(driver, device, 0, cmd)
end

local function multilevel_set_handler(self, device, cmd)
  local targetLevel = cmd.args.value
  local currentLevel = device:get_latest_state("main",  capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or 0
  local blindsCommand
  if currentLevel > targetLevel then
    blindsCommand = capabilities.windowShade.windowShade.closing()
  else
    blindsCommand = capabilities.windowShade.windowShade.opening()
  end
  device:set_field(BLINDS_LAST_COMMAND, blindsCommand)
  device:set_field(SHADE_TARGET, targetLevel)
  device.thread:call_with_delay(4,
    function()
      device:send(Meter:Get({scale = Meter.scale.electric_meter.WATTS}))
    end
  )
end

local function meter_report_handler(self, device, cmd)
  local event = nil
  local event_arguments
  if cmd.args.scale == Meter.scale.electric_meter.WATTS then
    event_arguments = {
      value = cmd.args.meter_value,
      unit = POWER_UNIT_WATT
    }
    event = capabilities.powerMeter.power(event_arguments)
    if event_arguments.value > 1 and device:get_field(BLINDS_LAST_COMMAND) ~= nil then
      device:emit_event(device:get_field(BLINDS_LAST_COMMAND))
      device:emit_event(capabilities.windowShadeLevel.shadeLevel(device:get_field(SHADE_TARGET)))
    else
      device:send(SwitchMultilevel:Get({}))
      device:send(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}))
    end

  elseif cmd.args.scale == Meter.scale.electric_meter.KILOWATT_HOURS then
    event_arguments = {
      value = cmd.args.meter_value,
      unit = ENERGY_UNIT_KWH
    }
    event = capabilities.energyMeter.energy(event_arguments)
  end

  if event ~= nil then
    device:emit_event(event)
  end
end

local function info_changed(driver, device, event, args)
  local preferences = preferencesMap.get_device_parameters(device)
  if preferences then
    for id, value in pairs(device.preferences) do
      if preferences[id] and args.old_st_store.preferences[id] ~= value then
        local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
        device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
        device.thread:call_with_delay(1,
          function()
            device:send(Configuration:Get({parameter_number = preferences[id].parameter_number}))
          end
        )
      end
    end
  end
end

local function device_added(self, device)
  device:send(Association:Set({grouping_identifier = 7, node_ids = {self.environment_info.hub_zwave_id}}))
  device:send(Configuration:Set({parameter_number = 40, size = 1, configuration_value = 1}))
  device:send(Configuration:Set({parameter_number = 71, size = 1, configuration_value = 0}))
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, { visibility = { displayed = false } }))
  device:refresh()
end

local qubino_flush_shutter = {
  NAME = "qubino flush shutter",
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    },
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.SET] = multilevel_set_handler,
    },
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    }
  },
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = set_shade_level
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = open,
      [capabilities.windowShade.commands.close.NAME] = close
    },
  },
  can_handle = can_handle_qubino_flush_shutter,
  lifecycle_handlers = {
    added = device_added,
    infoChanged = info_changed
  },
}

return qubino_flush_shutter
