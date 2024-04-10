local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local constants = require "st.zigbee.constants"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat

local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local Groups = clusters.Groups

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local WIRELESS_SWITCH_CLUSTER_ID = 0x0012
local WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0055
local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201
local CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0200
local RESTORE_TURN_OFF_INDICATOR_LIGHT_ATTRIBUTE_ID = 0x0203
local MAX_POWER_ATTRIBUTE_ID = 0x020B
local ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID = 0x000A

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local PRIVATE_MODE = "PRIVATE_MODE"

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.plug.maeu01" },
  { mfr = "LUMI", model = "lumi.plug.macn01" },
  { mfr = "LUMI", model = "lumi.switch.n0agl1" },
  { mfr = "LUMI", model = "lumi.switch.n0acn2" },
  { mfr = "LUMI", model = "lumi.switch.n1acn1" },
  { mfr = "LUMI", model = "lumi.switch.n2acn1" },
  { mfr = "LUMI", model = "lumi.switch.n3acn1" },
  { mfr = "LUMI", model = "lumi.switch.b2laus01" }
}

local preference_map = {
  ["stse.restorePowerState"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = RESTORE_POWER_STATE_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Boolean,
  },
  ["stse.changeToWirelessSwitch"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { [true] = 0x00,[false] = 0x01 },
  },
  ["stse.maxPower"] = {
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
  ["stse.maxPowerCN"] = {
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
      ["23"] = SinglePrecisionFloat(0, 11, 0.123046875),
      ["24"] = SinglePrecisionFloat(0, 11, 0.171875),
      ["25"] = SinglePrecisionFloat(0, 11, 0.220703125)
    },
  },
  ["stse.electricSwitchType"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { rocker = 0x01, rebound = 0x02 },
  },
  ["stse.turnOffIndicatorLight"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = RESTORE_TURN_OFF_INDICATOR_LIGHT_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Boolean,
  },
}

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("aqara")
      return true, subdriver
    end
  end
  return false
end

local function private_mode_handler(driver, device, value, zb_rx)
  device:set_field(PRIVATE_MODE, value.value, { persist = true })

  if value.value ~= 1 then
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01)) -- private
    device:send(SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(device, 900, 3600, 1)) -- minimal interval : 15min
    device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10, { persist = true })
    device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, { persist = true })
  end
end

local function wireless_switch_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      capabilities.button.button.pushed({ state_change = true }))
  end
end

local function energy_meter_power_consumption_report(device, raw_value)
  -- energy meter
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value, unit = "Wh" }))

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

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value -- '10W'
  raw_value = raw_value / 10
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value -- 'Wh'
  energy_meter_power_consumption_report(device, raw_value)
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(ElectricalMeasurement.attributes.ActivePower:read(device))
  device:send(SimpleMetering.attributes.CurrentSummationDelivered:read(device))
end

local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  if preferences ~= nil then
    for id, attr in pairs(preference_map) do
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

local function do_configure(self, device)
  device:configure()
  device:send(cluster_base.read_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE))
  device:send(Groups.server.commands.RemoveAllGroups(device)) -- required
  do_refresh(self, device)
end

local function device_added(driver, device)
  device:emit_event(capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
  device:emit_event(capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))

end

local aqara_switch_handler = {
  NAME = "Aqara Switch Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [WIRELESS_SWITCH_CLUSTER_ID] = {
        [WIRELESS_SWITCH_ATTRIBUTE_ID] = wireless_switch_handler
      },
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_ATTRIBUTE_ID] = private_mode_handler
      }
    }
  },
  sub_drivers = {
    require("aqara.version"),
    require("aqara.multi-switch")
  },
  can_handle = is_aqara_products
}

return aqara_switch_handler
