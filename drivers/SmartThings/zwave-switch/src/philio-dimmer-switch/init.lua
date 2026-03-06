-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local utils = require "st.utils"
local constants = require "st.zwave.constants"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })

local function dimmer_event(driver, device, cmd)
  local raw = cmd.args.value or cmd.args.target_value or 0

  if raw == "OFF_DISABLE" then
    raw = 0
  end

  if type(raw) ~= "number" then
    raw = 0
  end

  local level = utils.clamp_value(raw, 0, 99)
  
  device:emit_event(level > 0 and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  device:emit_event(capabilities.switchLevel.level(level))
end

local function basic_report_handler(driver, device, cmd)
  local basic_level = cmd.args.value or 0
  local level = utils.clamp_value(basic_level, 0, 99)

  device:emit_event(level > 0 and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  device:emit_event(capabilities.switchLevel.level(level))
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
  device:emit_event(capabilities.switchLevel.level(level))

  ------------------------------------------------------------------
  -- 修正：SmartThings 可能送出 rate="default"，不是數字 → 會造成崩潰
  ------------------------------------------------------------------
  local raw_rate = cmd.args.rate  
  local dimmingDuration = tonumber(raw_rate)  -- dimming duration in seconds
    if dimmingDuration == nil then
    dimmingDuration = 0   -- Z-Wave duration=0 = 快速/立即
  end

  device:send(SwitchMultilevel:Set({ value=level, duration=dimmingDuration }))
  local function query_level()
    device:send(SwitchMultilevel:Get({}))
  end
  -- delay shall be at least 5 sec.
  local delay = math.max(dimmingDuration + constants.DEFAULT_POST_DIMMING_DELAY , constants.MIN_DIMMING_GET_STATUS_DELAY) --delay in seconds
  device.thread:call_with_delay(delay, query_level)
end

---- Refresh 指令函式（SmartThings Test Suite 必要）
local function refresh_cmd(driver, device, command)
  -- print("DEBUG: PAD19 refresh_cmd called")

  -- 取得目前開關狀態
  local switch_get = Basic:Get({})
  device:send(switch_get)

  -- 取得目前dimmer的level
  local switchlevel_get = SwitchMultilevel:Get({})
  device:send(switchlevel_get)
end

-------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------
local function device_added(driver, device)
  if device == nil then
       return   -- 安全跳出，不做任何操作
  end

  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.switchLevel.level(0))
end

local pad19_driver_template = {
  NAME = "Philio PAD19 Dimmer Switch",
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
    },
	[capabilities.refresh.ID] = {
	  [capabilities.refresh.commands.refresh.NAME] = refresh_cmd
	}	
  },

  lifecycle_handlers = {
    added = device_added
  }
  
}

-- 回傳驅動範本
return pad19_driver_template
