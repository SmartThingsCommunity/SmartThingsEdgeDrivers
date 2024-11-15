local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"

local OnOff = clusters.OnOff
local AnalogInput = clusters.AnalogInput

local POWER_METER_ENDPOINT = 0x15
local ENERGY_METER_ENDPOINT = 0x1F

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local PRIVATE_MODE = "PRIVATE_MODE"

local function on_off_handler(driver, device, value, zb_rx)
  device:emit_event_for_endpoint(
    zb_rx.address_header.src_endpoint.value,
    value.value and capabilities.switch.switch.on() or capabilities.switch.switch.off()
  )
  device.thread:call_with_delay(2, function(t)
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(POWER_METER_ENDPOINT))
  end)
end

local function energy_meter_power_consumption_report(device, raw_value)
  -- energy meter
  local offset = device:get_field(constants.ENERGY_METER_OFFSET) or 0
  if raw_value < offset then
    --- somehow our value has gone below the offset, so we'll reset the offset, since the device seems to have
    offset = 0
    device:set_field(constants.ENERGY_METER_OFFSET, offset, {persist = true})
  end
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value - offset, unit = "Wh" }))

  -- report interval
  local current_time = os.time()
  local last_time = device:get_field(LAST_REPORT_TIME) or 0
  local next_time = last_time + 60 * 15 -- 15 mins, the minimum interval allowed between reports
  if current_time < next_time then
    return
  end
  device:set_field(LAST_REPORT_TIME, current_time, { persist = true })

  -- power consumption report
  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({ energy = raw_value, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'
end

local function round(num)
  local mult = 10
  return math.floor(num * mult + 0.5) / mult
end

local function present_value_handler(driver, device, value, zb_rx)
  -- ignore unexpected event when the device is not private mode
  local private_mode = device:get_field(PRIVATE_MODE) or 0
  if private_mode == 0 then return end

  local src_endpoint = zb_rx.address_header.src_endpoint.value
  if src_endpoint == POWER_METER_ENDPOINT then
    -- power meter
    local raw_value = value.value -- 'W'
    raw_value = round(raw_value)
    device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))

    -- read energy meter
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENERGY_METER_ENDPOINT))
  elseif src_endpoint == ENERGY_METER_ENDPOINT then
    -- energy meter, power consumption report
    local raw_value = value.value -- 'kWh'
    raw_value = round(raw_value * 1000)
    energy_meter_power_consumption_report(device, raw_value)
  end
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  if (device:supports_capability_by_id(capabilities.powerMeter.ID)) then
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(POWER_METER_ENDPOINT))
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENERGY_METER_ENDPOINT))
  end
end

local aqara_switch_version_handler = {
  NAME = "Aqara Switch Version Handler",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    attr = {
      [AnalogInput.ID] = {
        [AnalogInput.attributes.PresentValue.ID] = present_value_handler
      },
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = on_off_handler
      }
    }
  },
  can_handle = function (opts, driver, device)
    local private_mode = device:get_field(PRIVATE_MODE) or 0
    return private_mode == 1
  end
}

return aqara_switch_version_handler
