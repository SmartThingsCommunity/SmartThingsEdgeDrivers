local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local aqara_utils = require "aqara/aqara_utils"

local Basic = clusters.Basic
local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput

local INIT_STATE = "initState"
local INIT_STATE_OPEN = "open"
local INIT_STATE_CLOSE = "close"
local INIT_STATE_REVERSE = "reverse"

local APPLICATION_VERSION = "application_version"

local function shade_level_report_legacy_handler(driver, device, value, zb_rx)
  -- reported before initialized
  aqara_utils.shade_position_changed(device, value)
  aqara_utils.emit_shade_state_event(device, value.value)
end

local function shade_level_report_handler(driver, device, value, zb_rx)
  -- emit shade event required
  aqara_utils.shade_position_changed(device, value)
  aqara_utils.emit_shade_state_event(device, value.value)
end

local function shade_state_report_handler(driver, device, value, zb_rx)
  -- not reported in last initState step
  aqara_utils.shade_state_changed(device, value)

  -- initializedState
  local state = value.value
  if state == aqara_utils.SHADE_STATE_STOP or state == 0x04 then
    local init_state_value = device:get_field(INIT_STATE) or ""
    if init_state_value == INIT_STATE_OPEN then
      device:set_field(INIT_STATE, INIT_STATE_REVERSE)
      device.thread:call_with_delay(2, function(d)
        device:send_to_component("main", WindowCovering.server.commands.GoToLiftPercentage(device, 0))
      end)
    elseif init_state_value == INIT_STATE_CLOSE then
      device:set_field(INIT_STATE, INIT_STATE_REVERSE)
      device.thread:call_with_delay(2, function(d)
        device:send_to_component("main", WindowCovering.server.commands.GoToLiftPercentage(device, 100))
      end)
    elseif init_state_value == INIT_STATE_REVERSE then
      device:set_field(INIT_STATE, "")
      device.thread:call_with_delay(2, function(d)
        device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, aqara_utils.PREF_ATTRIBUTE_ID,
          aqara_utils.MFG_CODE))
      end)
    end
  end
end

local aqara_window_treatment_version_handler = {
  NAME = "Aqara Window Treatment Version Handler",
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = shade_level_report_legacy_handler
      },
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = shade_level_report_handler
      },
      [Basic.ID] = {
        [aqara_utils.SHADE_STATE_ATTRIBUTE_ID] = shade_state_report_handler
      }
    }
  },
  can_handle = function(opts, driver, device)
    local softwareVersion = device:get_field(APPLICATION_VERSION)
    return softwareVersion and softwareVersion == 34
  end
}

return aqara_window_treatment_version_handler
