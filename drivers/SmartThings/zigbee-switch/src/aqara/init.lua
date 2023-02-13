local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local constants = require "st.zigbee.constants"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat

local OnOff = clusters.OnOff
local AnalogInput = clusters.AnalogInput
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering

local restorePowerState = capabilities["stse.restorePowerState"]
local changeToWirelessSwitch = capabilities["stse.changeToWirelessSwitch"]
local maxPower = capabilities["stse.maxPower"]
local electricSwitchType = capabilities["stse.electricSwitchType"]

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local WIRELESS_SWITCH_CLUSTER_ID = 0x0012
local WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0055
local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201
local CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0200
local MAX_POWER_ATTRIBUTE_ID = 0x020B
local ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID = 0x000A

local POWER_METER_ENDPOINT = 0x15
local ENERGY_METER_ENDPOINT = 0x1F

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.plug.maeu01" },
  { mfr = "LUMI", model = "lumi.switch.n0agl1" },
  { mfr = "LUMI", model = "lumi.switch.n1acn1" },
  { mfr = "LUMI", model = "lumi.switch.n2acn1" },
  { mfr = "LUMI", model = "lumi.switch.n3acn1" },
}

local wireless_switch_endpoint_map = {
  [0x29] = 1,
  [0x2A] = 2,
  [0x2B] = 3,
}

local wireless_switch_button_event_map = {
  [1] = capabilities.button.button.pushed({ state_change = true }),
}

local preferences_map = {
  [restorePowerState.ID] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = RESTORE_POWER_STATE_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Boolean,
  },
  [changeToWirelessSwitch.ID] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { [true] = 0x00, [false] = 0x01 },
  },
  [maxPower.ID] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = MAX_POWER_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.SinglePrecisionFloat,
    value_map = {
      ["1"] = SinglePrecisionFloat(0, 6, 0.5625),
      ["2"] = SinglePrecisionFloat(0, 7, 0.5625),
      ["3"] = SinglePrecisionFloat(0, 8, 0.171875),
      ["4"] = SinglePrecisionFloat(0, 8, 0.5625),
      ["5"] = SinglePrecisionFloat(0, 8, 0.953125),
      ["6"] = SinglePrecisionFloat(0, 9, 0.171875),
      ["7"] = SinglePrecisionFloat(0, 9, 0.3671875),
      ["8"] = SinglePrecisionFloat(0, 9, 0.5625),
      ["9"] = SinglePrecisionFloat(0, 9, 0.7578125),
      ["10"] = SinglePrecisionFloat(0, 9, 0.953125),
      ["11"] = SinglePrecisionFloat(0, 10, 0.07421875),
      ["12"] = SinglePrecisionFloat(0, 10, 0.171875),
      ["13"] = SinglePrecisionFloat(0, 10, 0.26953125),
      ["14"] = SinglePrecisionFloat(0, 10, 0.3671875),
      ["15"] = SinglePrecisionFloat(0, 10, 0.46484375),
      ["16"] = SinglePrecisionFloat(0, 10, 0.5625),
      ["17"] = SinglePrecisionFloat(0, 10, 0.66015625),
      ["18"] = SinglePrecisionFloat(0, 10, 0.7578125),
      ["19"] = SinglePrecisionFloat(0, 10, 0.85546875),
      ["20"] = SinglePrecisionFloat(0, 10, 0.953125),
      ["21"] = SinglePrecisionFloat(0, 11, 0.025390625),
      ["22"] = SinglePrecisionFloat(0, 11, 0.07421875),
      ["23"] = SinglePrecisionFloat(0, 11, 0.123046875)
    },
  },
  [electricSwitchType.ID] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { ['rocker'] = 0x01, ['rebound'] = 0x02 },
  },
}

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
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
  local raw_value = value.value -- 'Wh'
  energy_meter_power_consumption_report(device, raw_value)
end

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value -- '10W'
  raw_value = raw_value / 10
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local function present_value_handler(driver, device, value, zb_rx)
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

local function on_off_handler(driver, device, value, zb_rx)
  device:emit_event_for_endpoint(
    zb_rx.address_header.src_endpoint.value,
    value.value and capabilities.switch.switch.on() or capabilities.switch.switch.off()
  )

  -- read power meter
  device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(POWER_METER_ENDPOINT))
end

local function wireless_switch_handler(driver, device, value, zb_rx)
  local endpoint = wireless_switch_endpoint_map[zb_rx.address_header.src_endpoint.value]
  local event = wireless_switch_button_event_map[value.value]
  if event ~= nil then
    device:emit_event_for_endpoint(endpoint, event)
  end
end

local function do_refresh(self, device)
  device:refresh()

  device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(POWER_METER_ENDPOINT))
  device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENERGY_METER_ENDPOINT))
end

local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  if preferences ~= nil then
    for id, attr in pairs(preferences_map) do
      local old_value = old_preferences[id]
      local value = preferences[id]
      if value ~= nil and value ~= old_value then
        if attr.value_map ~= nil then
          value = attr.value_map[value]
        end
        device:send(cluster_base.write_manufacturer_specific_attribute(device, attr.cluster_id, attr.attribute_id,
          attr.mfg_code, attr.data_type, value))
      end
    end
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.switch.switch.off())

  device:emit_event(capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
  device:emit_event(capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))

  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01)) -- private
end

local function init(driver, device)
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10, { persist = true })
  device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, { persist = true })
end

local aqara_switch_handler = {
  NAME = "Aqara Switch Handler",
  lifecycle_handlers = {
    init = init,
    added = device_added,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = on_off_handler
      },
      [AnalogInput.ID] = {
        [AnalogInput.attributes.PresentValue.ID] = present_value_handler
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [WIRELESS_SWITCH_CLUSTER_ID] = {
        [WIRELESS_SWITCH_ATTRIBUTE_ID] = wireless_switch_handler
      }
    }
  },
  sub_drivers = { 
    require("aqara.multi-switch"),
    require("aqara.smart-plug")
  },
  can_handle = is_aqara_products
}

return aqara_switch_handler
