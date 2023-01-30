local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local battery = capabilities.battery
--local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local utils = require "st.utils"
--module emit signal metrics
local signal = require "signal-metrics"

local can_handle = function(opts, driver, device)
  if device:get_manufacturer() == "Ecolink" then
    return device:get_manufacturer() == "Ecolink"
  elseif device:get_manufacturer() == "frient A/S" then
    return device:get_manufacturer() == "frient A/S"
  elseif device:get_manufacturer() == "Sercomm Corp." then
    return device:get_manufacturer() == "Sercomm Corp."
  elseif device:get_manufacturer() == "Universal Electronics Inc" then
    return device:get_manufacturer() == "Universal Electronics Inc"
  elseif device:get_manufacturer() == "SmartThings" then
    return device:get_manufacturer() == "SmartThings"
  elseif device:get_manufacturer() == "CentraLite" then
    return device:get_manufacturer() == "CentraLite"
  elseif device:get_manufacturer() == "Visonic" then
    return device:get_manufacturer() == "Visonic"
  elseif device:get_manufacturer() == "Leedarson" then
    return device:get_manufacturer() == "Leedarson"
  end
end

local battery_handler = function(driver, device, value, zb_rx)

  -- emit signal metrics
  signal.metrics(device, zb_rx)

  local minVolts = 2.3
  local maxVolts = 3.0
  if device:get_manufacturer() == "Ecolink" or 
    device:get_manufacturer() == "Sercomm Corp." or
    device:get_manufacturer() == "SmartThings" or
    device:get_manufacturer() == "CentraLite" then

    local batteryMap = {[28] = 100, [27] = 100, [26] = 100, [25] = 90, [24] = 90, [23] = 70,
                      [22] = 70, [21] = 50, [20] = 50, [19] = 30, [18] = 30, [17] = 15, [16] = 1, [15] = 0}
    minVolts = 15
    maxVolts = 28

    value = utils.clamp_value(value.value, minVolts, maxVolts)

    device:emit_event(battery.battery(batteryMap[value]))
  else
    if device:get_manufacturer() == "Universal Electronics Inc" or device:get_manufacturer() == "Visonic" then
      minVolts = 2.1
      maxVolts = 3.0
    end
    local battery_pct = math.floor(((((value.value / 10) - minVolts) + 0.001) / (maxVolts - minVolts)) * 100)
    if battery_pct > 100 then 
      battery_pct = 100
    elseif battery_pct < 0 then
      battery_pct = 0
    end
    device:emit_event(battery.battery(battery_pct))
 end
end

local battery_voltage = {
	NAME = "Battery Voltage",
    zigbee_handlers = {
        attr = {
            [zcl_clusters.PowerConfiguration.ID] = {
              [zcl_clusters.PowerConfiguration.attributes.BatteryVoltage.ID] = battery_handler
            }
        }
    },
    lifecycle_handlers = {
        --added = battery_defaults.build_linear_voltage_init(2.3, 3.0)
    },
	can_handle = can_handle
}

return battery_voltage
