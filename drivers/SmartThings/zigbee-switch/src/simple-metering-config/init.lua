-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zigbee_constants = require "st.zigbee.constants"
local SimpleMetering = require "st.zigbee.cluster".clusters.SimpleMetering
local zigbee_handlers = require "st.zigbee.handlers"

-- 设置 Simple Metering 集群的 multipliers 和 divisors 属性
local function device_init(driver, device)
  -- 在设备初始化时设置 multipliers 和 divisors
  device:configure()
  
  -- 设置 Multiplier 为 1
  local write_multiplier_cmd = SimpleMetering.server.commands.WriteAttributes(device)
  if write_multiplier_cmd then
    device:send_to_component(
      write_multiplier_cmd({
        {id = SimpleMetering.attributes.Multiplier.ID, value = 1, DataType = 0x22} -- 0x22 is 24-bit integer
      }),
      "main"
    )
  end
  
  -- 设置 Divisor 为 100
  local write_divisor_cmd = SimpleMetering.server.commands.WriteAttributes(device)
  if write_divisor_cmd then
    device:send_to_component(
      write_divisor_cmd({
        {id = SimpleMetering.attributes.Divisor.ID, value = 100, DataType = 0x23} -- 0x23 is 32-bit integer
      }),
      "main"
    )
  end
end

-- 处理能量计量事件
local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local divisor = device:get_field(SimpleMetering.attributes.Divisor.ID) or 100
  local multiplier = device:get_field(SimpleMetering.attributes.Multiplier.ID) or 1
  
  local calculated_value = (raw_value * multiplier) / divisor
  device:emit_event_for_endpoint(
    zb_rx.address_header.src_endpoint.value,
    capabilities.energyMeter.energy({value = calculated_value, unit = "kWh"})
  )
end

-- 定义子驱动程序模板
local simple_metering_config_subdriver = {
  supported_capabilities = {
    capabilities.energyMeter,
    capabilities.powerMeter
  },
  lifecycle_handlers = {
    init = device_init
  },
  zigbee_handlers = {
    cluster = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      }
    }
  }
}

return simple_metering_config_subdriver