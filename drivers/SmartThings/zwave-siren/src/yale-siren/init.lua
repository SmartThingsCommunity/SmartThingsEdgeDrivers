-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local cc = require "st.zwave.CommandClass"
local capabilities = require "st.capabilities"
local Battery = (require "st.zwave.CommandClass.Battery")({version=1})
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=1})
local preferencesMap = require "preferences"

local function siren_set_helper(device, value)
  device:send(Basic:Set({value = value}))
  local query_device = function()
    device:send(Basic:Get({}))
    device:send(SwitchBinary:Get({}))
  end
  local delay = 3
  device.thread:call_with_delay(delay, query_device)
end

local function siren_on(self, device, command)
  siren_set_helper(device, SwitchBinary.value.ON_ENABLE)
end

local function siren_off(self, device, command)
  siren_set_helper(device, SwitchBinary.value.OFF_DISABLE)
end

local function do_refresh(self, device, command)
  device:send(Battery:Get({}))
  device:send(SwitchBinary:Get({}))
end

local function info_changed(driver, device, event, args)
  local preferences = preferencesMap.get_device_parameters(device)
  if preferences then
    local did_any_configuration_change = false
    local did_tamper_configuration_change = false
    for id, value in pairs(device.preferences) do
      if args.old_st_store.preferences[id] ~= value and preferences[id] then
        local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
        device:send(Configuration:Set({parameter_number = preferences[id].parameter_number, size = preferences[id].size, configuration_value = new_parameter_value}))
        if preferences[id].parameter_number == 4 then did_tamper_configuration_change = true end
        did_any_configuration_change = true
      end
    end

    if did_any_configuration_change then
      local delayed_commands = function(tamper_config_get_condition)
        if tamper_config_get_condition then
          return function()
            device:send(Basic:Set({value = 0x00}))
            device:send(Configuration:Get({parameter_number = 4}))
          end
        else
          return function()
            device:send(Basic:Set({value = 0x00}))
          end
        end
      end
      device.thread:call_with_delay(1, delayed_commands(did_tamper_configuration_change))
    end
  end
end

local function configuration_report_handler(self, device, cmd)
  if (cmd.args.parameter_number == 4) then
    if cmd.args.configuration_value == 1 then
      device:try_update_metadata({profile = "yale-siren-tamper"})
      device:emit_event(capabilities.tamperAlert.tamper.clear())
    elseif cmd.args.configuration_value == 0 then
      device:try_update_metadata({profile = "yale-siren"})
    end
  end
end

local function device_added(driver, device)
  do_refresh(driver, device)
end

local yale_siren = {
  NAME = "yale-siren",
  can_handle = require("yale-siren.can_handle"),
  capability_handlers = {
    [capabilities.alarm.ID] = {
      [capabilities.alarm.commands.both.NAME] = siren_on,
      [capabilities.alarm.commands.siren.NAME] = siren_on,
      [capabilities.alarm.commands.strobe.NAME] = siren_on,
      [capabilities.alarm.commands.off.NAME] = siren_off
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report_handler
    }
  },
  lifecycle_handlers = {
    infoChanged = info_changed,
    added = device_added
  }
}

return yale_siren
