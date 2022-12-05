local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat

local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local AnalogInput = clusters.AnalogInput
local Basic = clusters.Basic

local MAX_POWER_ID = "stse.maxPower" -- maximum allowable power
local RESTORE_STATE_ID = "stse.restorePowerState" -- remember previous state

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009

local PREF_CLUSTER_ID = 0xFCC0
local PREF_MAX_POWER_ATTR_ID = 0x020B
local PREF_RESTORE_STATE_ATTR_ID = 0x0201

local ENDPOINT_POWER_METER = 0x15
local ENDPOINT_ENERGY_METER = 0x1F

-- local PREF_MAX_POWER_DEFAULT_VALUE = 23
-- local PREF_RESTORE_STATE_DEFAULT_VALUE = false

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
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

-- local CONFIGURATIONS = {
--   {
--     cluster = AnalogInput.ID,
--     attribute = AnalogInput.attributes.PresentValue.ID,
--     minimum_interval = 1,
--     maximum_interval = 30,
--     data_type = AnalogInput.attributes.PresentValue.base_type,
--     reportable_change = 5
--   }
-- }

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

-- local function read_private_attribute(device, cluster_id, attribute_id)
--   local message = cluster_base.read_attribute(device, data_types.ClusterId(cluster_id), attribute_id)
--   message.body.zcl_header.frame_ctrl:set_mfg_specific()
--   message.body.zcl_header.mfg_code = data_types.validate_or_build_type(MFG_CODE, data_types.Uint16, "mfg_code")
--   device:send(message)
-- end

local function write_max_power_attribute(device, args)
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

local function write_restore_power_state_attribute(device, args)
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

local function emit_power_meter_event(device, value)
  local raw_value = value.value
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local function emit_energy_meter_event(device, value)
  local raw_value = value.value
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value, unit = "kWh" }))
end

local function emit_power_consumption_report_event(device, value)
  local raw_value = value.value

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

local function application_version_handler(driver, device, value, zb_rx)
  print("application_version_handler")
  local version = tonumber(value.value)
  print(version)
  device:set_field(APPLICATION_VERSION, version, { persist = true })
end

local function is_private_cluster_device(device)
  local softwareVersion = device:get_field(APPLICATION_VERSION)
  print(softwareVersion)
  return softwareVersion and softwareVersion == 32
end

local function Round(num, dp)
  --[[
    round a number to so-many decimal of places, which can be negative, 
    e.g. -1 places rounds to 10's,  
    
    examples
        173.2562 rounded to 0 dps is 173.0
        173.2562 rounded to 2 dps is 173.26
        173.2562 rounded to -1 dps is 170.0
    ]] --
  local mult = 10 ^ (dp or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function power_meter_handler(driver, device, value, zb_rx)
  print("power_meter_handler")
  if is_private_cluster_device(device) == true then
    return
  end
  print("in")

  local raw_value = value.value -- '10W'
  emit_power_meter_event(device, { value = Round(raw_value / 10, 2) })
end

local function energy_meter_handler(driver, device, value, zb_rx)
  print("energy_meter_handler")
  if is_private_cluster_device(device) == true then
    return
  end
  print("in")

  local raw_value = value.value -- 'Wh'
  -- energyMeter
  emit_energy_meter_event(device, { value = Round(raw_value / 1000, 2) })
  -- powerConsumptionReport
  emit_power_consumption_report_event(device, { value = Round(raw_value, 2) })
end

local function present_value_handler(driver, device, value, zb_rx)
  print("present_value_handler")
  if is_private_cluster_device(device) ~= true then
    return
  end
  print("in")

  local src_endpoint = zb_rx.address_header.src_endpoint.value
  if src_endpoint == ENDPOINT_POWER_METER then
    -- powerMeter
    local raw_value = value.value -- 'W'
    emit_power_meter_event(device, { value = Round(raw_value, 2) })
  elseif src_endpoint == ENDPOINT_ENERGY_METER then
    -- energyMeter, powerConsumptionReport
    local raw_value = value.value -- 'kWh'
    emit_energy_meter_event(device, { value = Round(raw_value, 2) })
    emit_power_consumption_report_event(device, { value = Round(raw_value * 1000, 2) })
  end
end

local function on_off_handler(driver, device, value, zb_rx)
  print("on_off_handler")
  print(value.value)

  if value.value == true then
    device:emit_event(capabilities.switch.switch.on())

    if is_private_cluster_device(device) == true then
      print("in")

      device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_POWER_METER))
      device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_ENERGY_METER))
    end
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function pref_handler(driver, device, value, zb_rx)
  print("pref_handler")
  print(value.value)
end

local function pref_handler2(driver, device, value, zb_rx)
  print("pref_handler2")
  print(value.value)
end

local function device_info_changed(driver, device, event, args)
  write_max_power_attribute(device, args)
  write_restore_power_state_attribute(device, args)
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  if is_private_cluster_device(device) == true then
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_POWER_METER))
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_ENERGY_METER))
  else
    device:send(ElectricalMeasurement.attributes.ActivePower:read(device))
    device:send(SimpleMetering.attributes.CurrentSummationDelivered:read(device))
  end

  -- read_private_attribute(device, PREF_CLUSTER_ID, PREF_MAX_POWER_ATTR_ID)
  -- read_private_attribute(device, PREF_CLUSTER_ID, PREF_RESTORE_STATE_ATTR_ID)

end

local function do_configure(self, device)
  device:configure()
  -- device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10)

  -- device:send(AnalogInput.attributes.PresentValue:configure_reporting(device, 1, 30, SinglePrecisionFloat(0, 8, 0.953125))
  --   :to_endpoint(ENDPOINT_POWER_METER))
  -- device:send(AnalogInput.attributes.PresentValue:configure_reporting(device, 1, 30, SinglePrecisionFloat(0, 8, 0.953125))
  --   :to_endpoint(ENDPOINT_ENERGY_METER))

  device:send(Basic.attributes.ApplicationVersion:read(device))
  do_refresh(self, device)
end

local function device_added(driver, device)
  device:emit_event(capabilities.switch.switch.off())
  device:emit_event(capabilities.powerMeter.power({ value = 0, unit = "W" }))
  device:emit_event(capabilities.energyMeter.energy({ value = 0, unit = "kWh" }))

  -- Set private attribute
  write_private_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, data_types.Uint8, 1)

  -- -- Set default value to the device.
  -- write_private_attribute(device, PREF_CLUSTER_ID, PREF_MAX_POWER_ATTR_ID, data_types.SinglePrecisionFloat,
  --   max_power_data_type_table[PREF_MAX_POWER_DEFAULT_VALUE])
  -- write_private_attribute(device, PREF_CLUSTER_ID, PREF_RESTORE_STATE_ATTR_ID, data_types.Boolean,
  --   PREF_RESTORE_STATE_DEFAULT_VALUE)
end

-- local function device_init(driver, device)
--   for _, attribute in ipairs(CONFIGURATIONS) do
--     device:add_configured_attribute(attribute)
--     device:add_monitored_attribute(attribute)
--   end
-- end

local aqara_smart_plug_handler = {
  NAME = "Aqara Smart Plug Handler",
  lifecycle_handlers = {
    -- init = device_init,
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
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = on_off_handler
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [AnalogInput.ID] = {
        [AnalogInput.attributes.PresentValue.ID] = present_value_handler
      },
      [PREF_CLUSTER_ID] = {
        [PREF_MAX_POWER_ATTR_ID] = pref_handler,
        [PREF_RESTORE_STATE_ATTR_ID] = pref_handler2
      }
    }
  },
  can_handle = is_aqara_products,
}

return aqara_smart_plug_handler
