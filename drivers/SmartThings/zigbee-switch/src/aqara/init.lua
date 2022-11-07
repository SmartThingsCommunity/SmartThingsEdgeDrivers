local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat
local constants = require "st.zigbee.constants"

local Groups = clusters.Groups
local SimpleMetering = clusters.SimpleMetering

local MAX_POWER_ID = "stse.maxPower" -- maximum allowable power
local RESTORE_STATE_ID = "stse.restorePowerState" -- remember previous state

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009

local PREF_CLUSTER_ID = 0xFCC0
local PREF_MAX_POWER_ATTR_ID = 0x020B
local PREF_RESTORE_STATE_ATTR_ID = 0x0201

local PREF_MAX_POWER_DEFAULT_VALUE = 23
local PREF_RESTORE_STATE_DEFAULT_VALUE = false

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.plug.maeu01" }
}

-- Range from 100 to 2300 (100w ~ 2300w)
-- Data type conversion table
local max_power_data_type_table = {
  SinglePrecisionFloat(0, 6, 0.5625),
  SinglePrecisionFloat(0, 7, 0.5625),
  SinglePrecisionFloat(0, 8, 0.171875),
  SinglePrecisionFloat(0, 8, 0.5625),
  SinglePrecisionFloat(0, 8, 0.953125),
  SinglePrecisionFloat(0, 9, 0.171875),
  SinglePrecisionFloat(0, 9, 0.3671875),
  SinglePrecisionFloat(0, 9, 0.5625),
  SinglePrecisionFloat(0, 9, 0.7578125),
  SinglePrecisionFloat(0, 9, 0.953125),

  SinglePrecisionFloat(0, 10, 0.07421875),
  SinglePrecisionFloat(0, 10, 0.171875),
  SinglePrecisionFloat(0, 10, 0.26953125),
  SinglePrecisionFloat(0, 10, 0.3671875),
  SinglePrecisionFloat(0, 10, 0.46484375),
  SinglePrecisionFloat(0, 10, 0.5625),
  SinglePrecisionFloat(0, 10, 0.66015625),
  SinglePrecisionFloat(0, 10, 0.7578125),
  SinglePrecisionFloat(0, 10, 0.85546875),
  SinglePrecisionFloat(0, 10, 0.953125),

  SinglePrecisionFloat(0, 11, 0.025390625),
  SinglePrecisionFloat(0, 11, 0.07421875),
  SinglePrecisionFloat(0, 11, 0.123046875)
}

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local write_pref_attribute = function(device, cluster_id, attribute_id, dt, value)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, cluster_id, attribute_id, MFG_CODE, dt, value))
end

local do_configure = function(self, device)
  device:configure()
  device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10)

  device:send(Groups.server.commands.RemoveAllGroups(device))
end

local function device_added(driver, device)
  device:send(Groups.server.commands.RemoveAllGroups(device))

  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.energyMeter.energy({ value = 0, unit = "kWh" }))
  device:emit_event(capabilities.powerMeter.power({ value = 0, unit = "W" }))

  -- Set private attribute
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))

  -- Set default value to the device.
  write_pref_attribute(device, PREF_CLUSTER_ID, PREF_MAX_POWER_ATTR_ID, data_types.SinglePrecisionFloat,
    max_power_data_type_table[PREF_MAX_POWER_DEFAULT_VALUE])
  write_pref_attribute(device, PREF_CLUSTER_ID, PREF_RESTORE_STATE_ATTR_ID, data_types.Boolean,
    PREF_RESTORE_STATE_DEFAULT_VALUE)
end

local function device_info_changed(driver, device, event, args)
  local maxPowerPreferenceValue = device.preferences[MAX_POWER_ID]
  local restorePowerStatePreferenceValue = device.preferences[RESTORE_STATE_ID]

  if device.preferences ~= nil then
    if maxPowerPreferenceValue ~= args.old_st_store.preferences[MAX_POWER_ID] then
      local value = tonumber(maxPowerPreferenceValue)
      write_pref_attribute(device, PREF_CLUSTER_ID, PREF_MAX_POWER_ATTR_ID, data_types.SinglePrecisionFloat,
        max_power_data_type_table[value])
    end

    if restorePowerStatePreferenceValue ~= args.old_st_store.preferences[RESTORE_STATE_ID] then
      write_pref_attribute(device, PREF_CLUSTER_ID, PREF_RESTORE_STATE_ATTR_ID, data_types.Boolean,
        restorePowerStatePreferenceValue)
    end
  end
end

local function energy_meter_handler(driver, device, value, zb_rx)
  -- energyMeter
  local raw_value = value.value
  raw_value = raw_value / 1000
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value, unit = "kWh" }))

  -- powerConsumptionReport

  -- check the minimum interval
  local current_time = os.time()
  local last_time = device:get_field(LAST_REPORT_TIME) or 0
  local next_time = last_time + 60 * 15 -- minimum interval of 15 mins
  if current_time < next_time then
    return
  end
  device:set_field(LAST_REPORT_TIME, current_time)

  -- report
  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({ energy = raw_value, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'
end

local aqara_smart_plug_handler = {
  NAME = "Aqara Smart Plug Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      }
    }
  },
  can_handle = is_aqara_products,
}

return aqara_smart_plug_handler
