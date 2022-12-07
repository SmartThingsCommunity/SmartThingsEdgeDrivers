local capabilities = require "st.capabilities"

local aqara_utils = {}

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local function emit_power_meter_event(device, value)
  local raw_value = value.value -- 'W'
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local function emit_energy_meter_event(device, value)
  local raw_value = value.value -- 'Wh'
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))
end

local function emit_power_consumption_report_event(device, value)
  local raw_value = value.value -- 'Wh'

  -- check the minimum interval
  local current_time = os.time()
  local last_time = device:get_field(LAST_REPORT_TIME) or 0
  local next_time = last_time + 60 * 15 -- minimum interval of 15 mins
  if current_time < next_time then
    return
  end
  device:set_field(LAST_REPORT_TIME, current_time, { persist = true })

  -- report
  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({ energy = raw_value, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'
end

aqara_utils.emit_power_meter_event = emit_power_meter_event
aqara_utils.emit_energy_meter_event = emit_energy_meter_event
aqara_utils.emit_power_consumption_report_event = emit_power_consumption_report_event

return aqara_utils
