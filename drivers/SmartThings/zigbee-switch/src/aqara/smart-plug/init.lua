local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"

local AnalogInput = clusters.AnalogInput
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local Basic = clusters.Basic

local POWER_METER_ENDPOINT = 0x15
local ENERGY_METER_ENDPOINT = 0x1F

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local APPLICATION_VERSION = "application_version"

local function application_version_handler(driver, device, value, zb_rx)
  local version = tonumber(value.value)
  device:set_field(APPLICATION_VERSION, version, { persist = true })
end

local function round(num)
  local mult = 10
  return math.floor(num * mult + 0.5) / mult
end

local function energy_meter_power_consumption_report(device, raw_value)
  -- report interval
  local current_time = os.time()
  local last_time = device:get_field(LAST_REPORT_TIME) or 0
  local next_time = last_time + 60 * 15 -- 15 mins, the minimum interval allowed between reports
  if current_time < next_time then
    return
  end
  device:set_field(LAST_REPORT_TIME, current_time, { persist = true })

  -- energy meter
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))

  -- power consumption report
  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({ energy = raw_value, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local version = device:get_field(APPLICATION_VERSION) or 0
  if version ~= 32 then
    local raw_value = value.value -- 'Wh'
    energy_meter_power_consumption_report(device, raw_value)
  end
end

local function power_meter_handler(driver, device, value, zb_rx)
  local version = device:get_field(APPLICATION_VERSION) or 0
  if version ~= 32 then
    local raw_value = value.value -- '10W'
    raw_value = raw_value / 10
    device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
  end
end

local function present_value_handler(driver, device, value, zb_rx)
  local version = device:get_field(APPLICATION_VERSION) or 0
  if version == 32 then
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
end

local function do_configure(self, device)
  device:configure()
  device:send(Basic.attributes.ApplicationVersion:read(device))
  device:refresh()
end

local aqara_smart_plug_handler = {
  NAME = "Aqara Smart Plug Handler",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [AnalogInput.ID] = {
        [AnalogInput.attributes.PresentValue.ID] = present_value_handler
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [Basic.ID] = {
        [Basic.attributes.ApplicationVersion.ID] = application_version_handler
      }
    }
  },
  can_handle = function(opts, driver, device)
    if device:get_model() == "lumi.plug.maeu01" then
      return true
    end
    return false
  end
}

return aqara_smart_plug_handler
