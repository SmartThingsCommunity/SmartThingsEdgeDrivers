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
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })

local EATON_ACCESSORY_DIMMER_FINGERPRINTS = {
  {mfr = 0x001A, prod = 0x4441, model = 0x0000} -- Eaton Dimmer Switch
}

local function can_handle_eaton_accessory_dimmer(opts, driver, device, ...)
  for _, fingerprint in ipairs(EATON_ACCESSORY_DIMMER_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      local subdriver = require("eaton-accessory-dimmer")
      return true, subdriver
    end
  end
  return false
end

local function dimmer_event(driver, device, cmd)
  local level = cmd.args.value and cmd.args.value or cmd.args.target_value

  device:emit_event(level > 0 and capabilities.switch.switch.on() or capabilities.switch.switch.off())

  level = utils.clamp_value(level, 0, 100)
  device:emit_event(level >= 99 and capabilities.switchLevel.level(100) or capabilities.switchLevel.level(level))
end

local function basic_report_handler(driver, device, cmd)
-- Eaton Accessory dimmer sends unsolicited BasicReport together with BasicSet
-- Values in this report are not the same as BasicSet's correct target value
-- and their order is not always the same.
-- We always use SwitchMultilevelGet to check current level, so we can
-- ignore all Basic Reports for this device.

-- When switch is on/off, driver gets the below messages.
-- received Z-Wave command: {args={value=96}, cmd_class="BASIC", cmd_id="REPORT", dst_channels={}, encap="NONE", payload="`", src_channel=0, version=1}
-- received Z-Wave command: {args={value=92}, cmd_class="BASIC", cmd_id="REPORT", dst_channels={}, encap="NONE", payload="\", src_channel=0, version=1}
end

local function switch_on_handler(driver, device)
  device:send(Basic:Set({value = 0xff}))
  device.thread:call_with_delay(4, function(d)
    device:send(SwitchMultilevel:Get({}))
  end)
end

local function switch_off_handler(driver, device)
  device:send(Basic:Set({value = 0x00}))
  device.thread:call_with_delay(4, function(d)
    device:send(SwitchMultilevel:Get({}))
  end)
end

local function switch_level_set(driver, device, cmd)
  local level = utils.round(cmd.args.level)
  level = utils.clamp_value(level, 0, 99)

  device:emit_event(level > 0 and capabilities.switch.switch.on() or capabilities.switch.switch.off())

  local dimmingDuration = cmd.args.rate or constants.DEFAULT_DIMMING_DURATION -- dimming duration in seconds
  device:send(SwitchMultilevel:Set({ value=level, duration=dimmingDuration }))
  local query_level = function()
    device:send(SwitchMultilevel:Get({}))
  end
  -- delay shall be at least 5 sec.
  local delay = math.max(dimmingDuration + constants.DEFAULT_POST_DIMMING_DELAY , constants.MIN_DIMMING_GET_STATUS_DELAY) --delay in seconds
  device.thread:call_with_delay(delay, query_level)
end

local eaton_accessory_dimmer = {
  NAME = "eaton accessory dimmer",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = dimmer_event,
      [Basic.REPORT] = basic_report_handler
    },
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.SET] = dimmer_event,
      [SwitchMultilevel.REPORT] = dimmer_event
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_set
    }
  },
  can_handle = can_handle_eaton_accessory_dimmer,
}

return eaton_accessory_dimmer
