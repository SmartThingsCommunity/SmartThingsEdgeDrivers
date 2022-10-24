local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local utils = require "st.utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering

local deviceInitialization = capabilities["stse.deviceInitialization"]
local deviceInitializationId = "stse.deviceInitialization"
local setInitializedStateCommandName = "setInitializedState"

local reverseCurtainDirectionPreferenceId = "stse.reverseCurtainDirection"

local MFG_CODE = 0x115F
local PREF_ATTRIBUTE_ID = 0x0401
local SHADE_STATE_ATTR_ID = 0x0404

local SHADE_LEVEL = "shadeLevel"
local SHADE_STATE = "shadeState"
local SHADE_STATE_STOP = 0
local SHADE_STATE_OPEN = 1
local SHADE_STATE_CLOSE = 2

local PREF_REVERSE_DEFAULT = "\x00\x02\x00\x00\x00\x00\x00"
local PREF_REVERSE_OFF = "\x00\x02\x00\x00\x00\x00\x00"
local PREF_REVERSE_ON = "\x00\x02\x00\x01\x00\x00\x00"
local PREF_INITIALIZE = "\x00\x01\x00\x00\x00\x00\x00"

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.curtain", device_profile = "curtain" },
  { mfr = "LUMI", model = "lumi.curtain.v1", device_profile = "curtain" },
  { mfr = "LUMI", model = "lumi.curtain.aq2", device_profile = "roller-shade" }
}

local aqara_utils = {}

local function read_custom_attribute(device, cluster_id, attribute_id)
  local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster_id), attribute_id)
  message.body.zcl_header.frame_ctrl:set_mfg_specific()
  message.body.zcl_header.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
  device:send(message)
end

local function write_custom_attribute(device, cluster_id, attribute_id, dt, value)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, cluster_id, attribute_id, MFG_CODE,
    dt, value))
end

local function read_pref_attribute(device)
  read_custom_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID)
end

local function write_pref_attribute(device, str)
  write_custom_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, data_types.CharString, str)
end

local function send_open_cmd(device, component)
  device:send_to_component(component, WindowCovering.server.commands.GoToLiftPercentage(device, 100))
end

local function send_close_cmd(device, component)
  device:send_to_component(component, WindowCovering.server.commands.GoToLiftPercentage(device, 0))
end

local function emit_shade_state_event(device, shadeLevel)
  if shadeLevel == 100 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  elseif shadeLevel == 0 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
end

local function emit_shade_level_event(device, level)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
end

local function write_reverse_preferences(device, args)
  if device.preferences[reverseCurtainDirectionPreferenceId] ~=
      args.old_st_store.preferences[reverseCurtainDirectionPreferenceId] then
    if device.preferences[reverseCurtainDirectionPreferenceId] == true then
      write_pref_attribute(device, PREF_REVERSE_ON)
    else
      write_pref_attribute(device, PREF_REVERSE_OFF)
    end

    -- read updated value
    device.thread:call_with_delay(2, function(d)
      read_pref_attribute(device)
    end)
  end
end

local function setShadeStateField(device, value)
  device:set_field(SHADE_STATE, value)
end

local function getShadeStateField(device)
  return device:get_field(SHADE_STATE) or SHADE_STATE_STOP
end

local function setShadeLevelField(device, value)
  device:set_field(SHADE_LEVEL, value)
end

local function getShadeLevelField(device)
  return device:get_field(SHADE_LEVEL) or 0
end

local function shade_state_changed(device, value)
  local state = value.value
  setShadeStateField(device, state) -- store value

  -- update state ui
  if state == SHADE_STATE_STOP then
    local shadeLevel = getShadeLevelField(device)
    emit_shade_state_event(device, shadeLevel)
  elseif state == SHADE_STATE_OPEN then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif state == SHADE_STATE_CLOSE then
    device:emit_event(capabilities.windowShade.windowShade.closing())
  end
end

local function shade_position_changed(device, value)
  local level = value.value
  if level > 100 then
    level = 100
  end
  level = utils.round(level)
  setShadeLevelField(device, level) -- store value

  -- update level ui
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))

  -- update state ui
  local shadeState = getShadeStateField(device)
  if shadeState == SHADE_STATE_STOP then
    emit_shade_state_event(device, level)
  end
end

local function is_matched_profile(device, profile)
  for _, fingerprint in pairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model and fingerprint.device_profile == profile then
      return true
    end
  end
  return false
end

local function write_initialize(device)
  write_pref_attribute(device, PREF_INITIALIZE)
end

aqara_utils.FINGERPRINTS = FINGERPRINTS
aqara_utils.PREF_ATTRIBUTE_ID = PREF_ATTRIBUTE_ID
aqara_utils.PREF_REVERSE_DEFAULT = PREF_REVERSE_DEFAULT
aqara_utils.SHADE_STATE_ATTR_ID = SHADE_STATE_ATTR_ID

aqara_utils.deviceInitialization = deviceInitialization
aqara_utils.deviceInitializationId = deviceInitializationId
aqara_utils.setInitializedStateCommandName = setInitializedStateCommandName

aqara_utils.SHADE_STATE_STOP = SHADE_STATE_STOP

aqara_utils.read_pref_attribute = read_pref_attribute
aqara_utils.write_pref_attribute = write_pref_attribute
aqara_utils.send_open_cmd = send_open_cmd
aqara_utils.send_close_cmd = send_close_cmd
aqara_utils.emit_shade_state_event = emit_shade_state_event
aqara_utils.emit_shade_level_event = emit_shade_level_event
aqara_utils.write_reverse_preferences = write_reverse_preferences
aqara_utils.shade_state_changed = shade_state_changed
aqara_utils.shade_position_changed = shade_position_changed
aqara_utils.is_matched_profile = is_matched_profile
aqara_utils.write_initialize = write_initialize

return aqara_utils
