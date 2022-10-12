local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering

local reverseCurtainDirectionPreferenceId = "stse.reverseCurtainDirection"

local MFG_CODE = 0x115F
local PREF_ATTRIBUTE_ID = 0x0401



local PREF_REVERSE_DEFAULT = "\x00\x02\x00\x00\x00\x00\x00"
local PREF_REVERSE_OFF = "\x00\x02\x00\x00\x00\x00\x00"
local PREF_REVERSE_ON = "\x00\x02\x00\x01\x00\x00\x00"

local aqara_utils = {}


local function read_custom_attribute(device, cluster_id, attribute)
  local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster_id), attribute)
  message.body.zcl_header.frame_ctrl:set_mfg_specific()
  message.body.zcl_header.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
  return message
end

local function read_pref_attribute(device)
  device:send(read_custom_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID))
end

local function write_pref_attribute(device, str)

  device:send(cluster_base.write_manufacturer_specific_attribute(device, Basic.ID, PREF_ATTRIBUTE_ID, MFG_CODE,
    data_types.CharString, str))
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

local function check_reverse_preferences(driver, device, event, args)



  if device.preferences[reverseCurtainDirectionPreferenceId] ~=
      args.old_st_store.preferences[reverseCurtainDirectionPreferenceId] then
    if device.preferences[reverseCurtainDirectionPreferenceId] == true then
      write_pref_attribute(device, PREF_REVERSE_ON)
    else
      write_pref_attribute(device, PREF_REVERSE_OFF)
    end

    device.thread:call_with_delay(2, function(d)
      read_pref_attribute(device)
    end)
  end
end

aqara_utils.PREF_ATTRIBUTE_ID = PREF_ATTRIBUTE_ID
aqara_utils.PREF_REVERSE_DEFAULT = PREF_REVERSE_DEFAULT
aqara_utils.read_custom_attribute = read_custom_attribute


aqara_utils.read_pref_attribute = read_pref_attribute


aqara_utils.write_pref_attribute = write_pref_attribute


aqara_utils.send_open_cmd = send_open_cmd


aqara_utils.send_close_cmd = send_close_cmd


aqara_utils.emit_shade_state_event = emit_shade_state_event


aqara_utils.emit_shade_level_event = emit_shade_level_event


aqara_utils.check_reverse_preferences = check_reverse_preferences







return aqara_utils
