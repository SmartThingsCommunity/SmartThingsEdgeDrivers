local capabilities = require "st.capabilities"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })


-- print("DEBUG: philio-dimmer-switch/init.lua loaded")

local function dimmer_event(driver, device, cmd)
  local value = cmd.args.value or cmd.args.target_value or 0
  local level = utils.clamp_value(value, 0, 100)
  
  device:emit_event(level > 0 and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  device:emit_event(capabilities.switchLevel.level(level))
end

local function basic_report_handler(driver, device, cmd)
  local basic_level = cmd.args.value or 0
  local level = utils.clamp_value(basic_level, 0, 100)

  device:emit_event(basic_level > 0 and capabilities.switch.switch.on() or capabilities.switch.switch.off())
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
local function device_init(driver, device)
  -- print("DEBUG: PAD19 device_init called")
end

local function device_added(driver, device)
  -- print("DEBUG: PAD19 device_added - init state off")
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.switchLevel.level(0))
  -- print("DEBUG: PAD19 Initial switchlevel = 0")
end

-- NEW: 修正 driverSwitched 崩潰
local function device_driver_switched(driver, device, event, args)
  -- print("DEBUG: PAD19 driverSwitched - ignored")
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
	init = device_init,
    added = device_added,
	driverSwitched = device_driver_switched
  },

  -- 設置 Z-Wave 設備配置
  zwave_config = {}
--  zwave_config = {},

  -- 指定can_handle腳本, 讓上層可以先檢查這台Device是否能用這個子驅動控制,可以才載入
--  can_handle = require("philio-dimmer-switch.can_handle")
}

-- 回傳驅動範本
return pad19_driver_template
