local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat
local aqara_utils = require "aqara/aqara_utils"

local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local Basic = clusters.Basic

local MAX_POWER_ID = "stse.maxPower" -- maximum allowable power
local RESTORE_STATE_ID = "stse.restorePowerState" -- remember previous state

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009

local PREF_CLUSTER_ID = 0xFCC0
local PREF_MAX_POWER_ATTR_ID = 0x020B
local PREF_RESTORE_STATE_ATTR_ID = 0x0201

local APPLICATION_VERSION = "application_version"

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

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function write_private_attribute(device, cluster_id, attribute_id, data_type, value)
  device:send(cluster_base.write_manufacturer_specific_attribute(device, cluster_id, attribute_id, MFG_CODE, data_type,
    value))
end

local function write_max_power_preference(device, args)
  if device.preferences ~= nil then
    local maxPowerPreferenceValue = device.preferences[MAX_POWER_ID]
    if maxPowerPreferenceValue ~= nil then
      if maxPowerPreferenceValue ~= args.old_st_store.preferences[MAX_POWER_ID] then
        local value = tonumber(maxPowerPreferenceValue)
        write_private_attribute(device, PREF_CLUSTER_ID, PREF_MAX_POWER_ATTR_ID, data_types.SinglePrecisionFloat,
          max_power_data_type_table[value])
      end
    end
  end
end

local function write_restore_power_state_preference(device, args)
  if device.preferences ~= nil then
    local restorePowerStatePreferenceValue = device.preferences[RESTORE_STATE_ID]
    if restorePowerStatePreferenceValue ~= nil then
      if restorePowerStatePreferenceValue ~= args.old_st_store.preferences[RESTORE_STATE_ID] then
        write_private_attribute(device, PREF_CLUSTER_ID, PREF_RESTORE_STATE_ATTR_ID, data_types.Boolean,
          restorePowerStatePreferenceValue)
      end
    end
  end
end

local function application_version_handler(driver, device, value, zb_rx)
  local version = tonumber(value.value)
  device:set_field(APPLICATION_VERSION, version, { persist = true })
end

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value -- '10W'
  aqara_utils.emit_power_meter_event(device, { value = raw_value / 10 })
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value -- 'Wh'
  -- energyMeter
  aqara_utils.emit_energy_meter_event(device, { value = raw_value })
  -- powerConsumptionReport
  aqara_utils.emit_power_consumption_report_event(device, { value = raw_value })
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(ElectricalMeasurement.attributes.ActivePower:read(device))
  device:send(SimpleMetering.attributes.CurrentSummationDelivered:read(device))
end

local function device_info_changed(driver, device, event, args)
  write_max_power_preference(device, args)
  write_restore_power_state_preference(device, args)
end

local function do_configure(self, device)
  device:configure()
  device:send(Basic.attributes.ApplicationVersion:read(device))
  do_refresh(self, device)
end

local function device_added(driver, device)
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
  device:emit_event(capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))

  -- Set private attribute
  write_private_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, data_types.Uint8, 1)
end

local aqara_smart_plug_handler = {
  NAME = "Aqara Smart Plug Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.ApplicationVersion.ID] = application_version_handler
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      }
    }
  },
  sub_drivers = { require("aqara.aqara_version") },
  can_handle = is_aqara_products,
}

return aqara_smart_plug_handler
