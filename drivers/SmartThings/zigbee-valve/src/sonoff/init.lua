--[[
Description: SONOFF Water Valve sub-driver for zigbee-valve
Version: 1.2
Author: guoxin.yang
Date: 2026-07-06
--]]
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local utils = require "st.utils"

-- 电池轮询间隔（秒）：SWV1C 是电池休眠设备，每 2 小时轮询一次
local BATTERY_POLL_INTERVAL = 7200

-- SWV1C 设备指纹匹配表
local FINGERPRINTS = {
  { mfr = "SONOFF", model = "SWV-ZFU" },
  { mfr = "SONOFF", model = "SWV-ZFE" },
  { mfr = "SONOFF", model = "SWV-ZNU" },
  { mfr = "SONOFF", model = "SWV-ZNE" }
}

--- OnOff 属性上报处理器 → valve 能力点事件
--- 必须显式处理，因为子驱动定义了 capability_handlers 后，
--- 父驱动的默认 OnOff→valve 映射会被跳过（只剩 OnOff→switch）
--- @param driver table 驱动实例
--- @param device table 设备实例
--- @param value table Zigbee 属性值
local function onoff_attr_handler(driver, device, value)
  local is_on = value.value ~= false and value.value ~= 0
  if is_on then
    device:emit_event(capabilities.valve.valve.open())
  else
    device:emit_event(capabilities.valve.valve.closed())
  end
end

--- 电池百分比属性处理器
--- Zigbee BatteryPercentageRemaining 范围 0-200（0%-100%），需除以 2
--- @param driver table 驱动实例
--- @param device table 设备实例
--- @param value table Zigbee 属性值
local function battery_percentage_handler(driver, device, value)
  local raw = value.value
  local percent = utils.round(raw / 2)
  device:emit_event(capabilities.battery.battery(percent))
end

--- 生命周期初始化处理函数
--- 通过周期性主动读取 BatteryPercentageRemaining 来保证电池数据可用
--- @param driver table 驱动实例
--- @param device table 设备实例
local function device_init(driver, device)
  device.thread:call_on_schedule(
    BATTERY_POLL_INTERVAL,
    function()
      device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
    end
  )
end

--- valve.open 能力点处理器
--- @param driver table 驱动实例
--- @param device table 设备实例
--- @param command table 能力点命令
local function valve_open_handler(driver, device, command)
  device:send(OnOff.server.commands.On(device))
  device:send(OnOff.attributes.OnOff:read(device))
end

--- valve.close 能力点处理器
--- @param driver table 驱动实例
--- @param device table 设备实例
--- @param command table 能力点命令
local function valve_close_handler(driver, device, command)
  device:send(OnOff.server.commands.Off(device))
  device:send(OnOff.attributes.OnOff:read(device))
end

--- 设备匹配检查
--- @param opts table 选项
--- @param driver table 驱动实例
--- @param device table 设备实例
--- @return boolean 是否由此子驱动接管
local function is_sonoff_valve(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local sonoff_valve_handler = {
  NAME = "SONOFF Water Valve Handler",
  lifecycle_handlers = {
    init = device_init
  },
  capability_handlers = {
    [capabilities.valve.ID] = {
      [capabilities.valve.commands.open.NAME] = valve_open_handler,
      [capabilities.valve.commands.close.NAME] = valve_close_handler,
    }
  },
  zigbee_handlers = {
    attr = {
      -- OnOff 属性上报 → valve 事件（弥补父驱动默认映射被跳过的缺陷）
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = onoff_attr_handler
      },
      -- 电池百分比属性上报 → battery 事件
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_percentage_handler
      }
    }
  },
  can_handle = is_sonoff_valve
}

return sonoff_valve_handler
