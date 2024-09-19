local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"

local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local PREF_ATTRIBUTE_ID = 0x0401
local SHADE_STATE_ATTRIBUTE_ID = 0x0404

local SHADE_STATE_STOP = 0
local SHADE_STATE_OPEN = 1
local SHADE_STATE_CLOSE = 2

local UPDATE_SHADE_LEVEL = "update_shade_level"
local PREF_REVERSE_DEFAULT = "\x00\x02\x00\x00\x00\x00\x00"
local PREF_REVERSE_OFF = "\x00\x02\x00\x00\x00\x00\x00"
local PREF_REVERSE_ON = "\x00\x02\x00\x01\x00\x00\x00"

local aqara_utils = {}

local function enable_update_shade_level(device)
  device:set_field(UPDATE_SHADE_LEVEL, true)
end

local function disable_update_shade_level(device)
  device:set_field(UPDATE_SHADE_LEVEL, false)
end

local function shade_level_cmd(driver, device, command)
  disable_update_shade_level(device)
  local level = command.args.shadeLevel
  if level > 100 then
    level = 100
  end
  level = utils.round(level)

  -- send
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function emit_shade_event_by_state(device, value)
  local state = value.value

  -- update state ui
  if state == SHADE_STATE_STOP or state == 0x04 then
    -- read shade position to update the UI
    enable_update_shade_level(device)
    device:send(AnalogOutput.attributes.PresentValue:read(device))
  elseif state == SHADE_STATE_OPEN then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif state == SHADE_STATE_CLOSE then
    device:emit_event(capabilities.windowShade.windowShade.closing())
  end
end

local function emit_shade_event(device, value)
  if device:get_field(UPDATE_SHADE_LEVEL) then
    local level = value.value
    if level >= 100 then
      device:emit_event(capabilities.windowShade.windowShade.open())
    elseif level == 0 then
      device:emit_event(capabilities.windowShade.windowShade.closed())
    else
      device:emit_event(capabilities.windowShade.windowShade.partially_open())
    end
  end
end

local function emit_shade_level_event(device, value)
  if device:get_field(UPDATE_SHADE_LEVEL) then
    local level = value.value
    if level > 100 then
      level = 100
    end
    level = utils.round(level)

    -- update level ui
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  end
end

aqara_utils.PRIVATE_CLUSTER_ID = PRIVATE_CLUSTER_ID
aqara_utils.PRIVATE_ATTRIBUTE_ID = PRIVATE_ATTRIBUTE_ID
aqara_utils.MFG_CODE = MFG_CODE
aqara_utils.PREF_ATTRIBUTE_ID = PREF_ATTRIBUTE_ID
aqara_utils.SHADE_STATE_ATTRIBUTE_ID = SHADE_STATE_ATTRIBUTE_ID
aqara_utils.SHADE_STATE_STOP = SHADE_STATE_STOP
aqara_utils.PREF_REVERSE_DEFAULT = PREF_REVERSE_DEFAULT
aqara_utils.PREF_REVERSE_OFF = PREF_REVERSE_OFF
aqara_utils.PREF_REVERSE_ON = PREF_REVERSE_ON

aqara_utils.enable_update_shade_level = enable_update_shade_level
aqara_utils.disable_update_shade_level = disable_update_shade_level
aqara_utils.emit_shade_event = emit_shade_event
aqara_utils.emit_shade_event_by_state = emit_shade_event_by_state
aqara_utils.emit_shade_level_event = emit_shade_level_event
aqara_utils.shade_level_cmd = shade_level_cmd

return aqara_utils
