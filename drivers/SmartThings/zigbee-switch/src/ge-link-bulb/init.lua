-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local Level = clusters.Level

local function info_changed(driver, device, event, args)
  local command
  local new_dim_onoff_value = tonumber(device.preferences.dimOnOff)
  local new_dim_rate_value = tonumber(device.preferences.dimRate)

  if device.preferences then
    if device.preferences.dimOnOff ~= args.old_st_store.preferences.dimOnOff then
      if new_dim_onoff_value == 0 then
        command = Level.attributes.OnOffTransitionTime:write(device, 0)
      else
        command = Level.attributes.OnOffTransitionTime:write(device, new_dim_rate_value)
      end
    elseif device.preferences.dimRate ~= args.old_st_store.preferences.dimRate and tonumber(device.preferences.dimOnOff) == 1 then
      command = Level.attributes.OnOffTransitionTime:write(device, new_dim_rate_value)
    end
  end

  if command then
    device:send(command)
  end
end

local function set_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)
  local dimming_rate = tonumber(device.preferences.dimRate) or 0
  local query_delay = math.floor(dimming_rate / 10 + 0.5)

  device:send(Level.commands.MoveToLevelWithOnOff(device, level, dimming_rate == 0 and 0xFFFF or dimming_rate))

  device.thread:call_with_delay(query_delay, function(d)
    device:refresh()
  end)
end

local ge_link_bulb = {
  NAME = "GE Link Bulb",
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = set_level_handler
    }
  },
  can_handle = require("ge-link-bulb.can_handle"),
}

return ge_link_bulb
