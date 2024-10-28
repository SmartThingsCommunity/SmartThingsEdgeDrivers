-- Copyright 2024 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local MatterDriver = require "st.matter.driver"
local clusters = require "st.matter.clusters"
local log = require "log"
local utils = require "st.utils"
local matter_driver_template = {}
local embedded_cluster_utils = require "embedded_cluster_utils"

local version = require "version"

if version.api < 11 then
  clusters.EnergyEvse = require "EnergyEvse"
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.EnergyEvseMode = require "EnergyEvseMode"
end

--this cluster is not supported in any releases of the lua libs
clusters.DeviceEnergyManagementMode = require "DeviceEnergyManagementMode"

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local SUPPORTED_EVSE_MODES_MAP = "__supported_evse_modes_map"
local SUPPORTED_DEVICE_ENERGY_MANAGEMENT_MODES_MAP = "__supported_device_energy_management_modes_map"
local RECURRING_REPORT_POLL_TIMER = "__recurring_report_poll_timer"
local RECURRING_POLL_TIMER = "__recurring_poll_timer"
local LAST_REPORTED_TIME = "__last_reported_time"
local POWER_CONSUMPTION_REPORT_TIME_INTERVAL = "__pcr_time_interval"
local DEVICE_REPORTED_TIME_INTERVAL_CONSIDERED = "__timer_interval_considered"
-- total in case there are multiple electrical sensors
local TOTAL_CUMULATIVE_ENERGY_IMPORTED = "__total_cumulative_energy_imported"

local TIMER_REPEAT = (1 * 60)        -- 1 minute
local REPORT_TIMEOUT = (15 * 60)     -- Report the value each 15 minutes
local MAX_CHARGING_CURRENT_CONSTRAINT = 80000 -- In v1.3 release of stack, this check for 80 A is performed.

local ELECTRICAL_SENSOR_DEVICE_ID = 0x0510
local DEVICE_ENERGY_MANAGEMENT_DEVICE_ID = 0x050D

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function component_to_endpoint(device, component)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  else
    return device.MATTER_DEFAULT_ENDPOINT
  end
end

local function get_endpoints_for_dt(device, device_type)
  local endpoints = {}
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == device_type then
        table.insert(endpoints, ep.endpoint_id)
        break
      end
    end
  end
  table.sort(endpoints)
  return endpoints
end

local function time_zone_offset()
  return os.difftime(os.time(), os.time(os.date("!*t", os.time())))
end

local function iso8601_to_epoch(iso8061Timestamp)
  local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
  local year, month, day, hour, mins, sec = iso8061Timestamp:match(pattern)
  local time_tab = {
    year  = tonumber(year),
    month = tonumber(month),
    day   = tonumber(day),
    hour  = tonumber(hour),
    min  = tonumber(mins),
    sec   = tonumber(sec),
    isdst = false
  }
  return math.floor(os.time(time_tab) + time_zone_offset())
end

local function epoch_to_iso8601(time)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

local function tbl_contains(array, value)
  for _, element in ipairs(array) do
    if element == value then
      return true
    end
  end
  return false
end

-- MAPS --
local EVSE_STATE_ENUM_MAP = {
  -- Since PLUGGED_IN_DISCHARGING is not to be supported, it is not checked.
  [clusters.EnergyEvse.types.StateEnum.NOT_PLUGGED_IN] = capabilities.evseState.state.notPluggedIn,
  [clusters.EnergyEvse.types.StateEnum.PLUGGED_IN_NO_DEMAND] = capabilities.evseState.state.pluggedInNoDemand,
  [clusters.EnergyEvse.types.StateEnum.PLUGGED_IN_DEMAND] = capabilities.evseState.state.pluggedInDemand,
  [clusters.EnergyEvse.types.StateEnum.PLUGGED_IN_CHARGING] = capabilities.evseState.state.pluggedInCharging,
  [clusters.EnergyEvse.types.StateEnum.SESSION_ENDING] = capabilities.evseState.state.sessionEnding,
  [clusters.EnergyEvse.types.StateEnum.FAULT] = capabilities.evseState.state.fault,
}

local EVSE_SUPPLY_STATE_ENUM_MAP = {
  [clusters.EnergyEvse.types.SupplyStateEnum.DISABLED] = capabilities.evseState.supplyState.disabled,
  [clusters.EnergyEvse.types.SupplyStateEnum.CHARGING_ENABLED] = capabilities.evseState.supplyState.chargingEnabled,
  [clusters.EnergyEvse.types.SupplyStateEnum.DISCHARGING_ENABLED] = capabilities.evseState.supplyState.dischargingEnabled,
  [clusters.EnergyEvse.types.SupplyStateEnum.DISABLED_ERROR] = capabilities.evseState.supplyState.disabledError,
  [clusters.EnergyEvse.types.SupplyStateEnum.DISABLED_DIAGNOSTICS] = capabilities.evseState.supplyState.disabledDiagnostics,
}

local EVSE_FAULT_STATE_ENUM_MAP = {
  [clusters.EnergyEvse.types.FaultStateEnum.NO_ERROR] = capabilities.evseState.faultState.noError,
  [clusters.EnergyEvse.types.FaultStateEnum.METER_FAILURE] = capabilities.evseState.faultState.meterFailure,
  [clusters.EnergyEvse.types.FaultStateEnum.OVER_VOLTAGE] = capabilities.evseState.faultState.overVoltage,
  [clusters.EnergyEvse.types.FaultStateEnum.UNDER_VOLTAGE] = capabilities.evseState.faultState.underVoltage,
  [clusters.EnergyEvse.types.FaultStateEnum.OVER_CURRENT] = capabilities.evseState.faultState.overCurrent,
  [clusters.EnergyEvse.types.FaultStateEnum.CONTACT_WET_FAILURE] = capabilities.evseState.faultState.contactWetFailure,
  [clusters.EnergyEvse.types.FaultStateEnum.CONTACT_DRY_FAILURE] = capabilities.evseState.faultState.contactDryFailure,
  [clusters.EnergyEvse.types.FaultStateEnum.GROUND_FAULT] = capabilities.evseState.faultState.groundFault,
  [clusters.EnergyEvse.types.FaultStateEnum.POWER_LOSS] = capabilities.evseState.faultState.powerLoss,
  [clusters.EnergyEvse.types.FaultStateEnum.POWER_QUALITY] = capabilities.evseState.faultState.powerQuality,
  [clusters.EnergyEvse.types.FaultStateEnum.PILOT_SHORT_CIRCUIT] = capabilities.evseState.faultState.pilotShortCircuit,
  [clusters.EnergyEvse.types.FaultStateEnum.EMERGENCY_STOP] = capabilities.evseState.faultState.emergencyStop,
  [clusters.EnergyEvse.types.FaultStateEnum.EV_DISCONNECTED] = capabilities.evseState.faultState.eVDisconnected,
  [clusters.EnergyEvse.types.FaultStateEnum.WRONG_POWER_SUPPLY] = capabilities.evseState.faultState.wrongPowerSupply,
  [clusters.EnergyEvse.types.FaultStateEnum.LIVE_NEUTRAL_SWAP] = capabilities.evseState.faultState.liveNeutralSwap,
  [clusters.EnergyEvse.types.FaultStateEnum.OVER_TEMPERATURE] = capabilities.evseState.faultState.overTemperature,
  [clusters.EnergyEvse.types.FaultStateEnum.OTHER] = capabilities.evseState.faultState.other,
}

local function read_cumulative_energy_imported(device)
  local electrical_energy_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID)
  if electrical_energy_meas_eps and #electrical_energy_meas_eps > 0 then
    local read_req = clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(device, electrical_energy_meas_eps[1])
    for i, ep in ipairs(electrical_energy_meas_eps) do
      if i > 1 then
        read_req:merge(clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(device, ep))
      end
    end
    device:send(read_req)
  end
end

local function create_poll_schedule(device)
  local poll_timer = device:get_field(RECURRING_POLL_TIMER)
  if poll_timer ~= nil then
    return
  end

  -- The powerConsumption report needs to be updated at least every 15 minutes in order to be included in SmartThings Energy
  local timer = device.thread:call_on_schedule(TIMER_REPEAT, function()
    read_cumulative_energy_imported(device)
  end, "polling_schedule_timer")

  device:set_field(RECURRING_POLL_TIMER, timer)
end

local function create_poll_report_schedule(device)
  local polling_schedule_timer = device:get_field(RECURRING_REPORT_POLL_TIMER)
  if polling_schedule_timer ~= nil then
    return
  end

  -- The powerConsumption report needs to be updated at least every 15 minutes in order to be included in SmartThings Energy
  local pcr_interval = device:get_field(POWER_CONSUMPTION_REPORT_TIME_INTERVAL) or REPORT_TIMEOUT
  local timer = device.thread:call_on_schedule(pcr_interval, function()
    local current_time = os.time()
    local last_time = device:get_field(LAST_REPORTED_TIME) or 0
    local total_cumulative_energy_imported = device:get_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED) or {}
    local total_energy = 0

    -- we sum up total cumulative energy across all electrical sensor endpoints
    for _, energyWh in pairs(total_cumulative_energy_imported) do
      total_energy = total_energy + energyWh
    end

    device:set_field(LAST_REPORTED_TIME, current_time, { persist = true })

    -- Calculate the energy consumed between the start and the end time
    local previousTotalConsumptionWh = device:get_latest_state("main", capabilities.powerConsumptionReport
      .ID,
      capabilities.powerConsumptionReport.powerConsumption.NAME) or { energy = 0 }

    local deltaEnergyWh = math.max(total_energy - previousTotalConsumptionWh.energy, 0.0)
    local startTime = epoch_to_iso8601(last_time)
    local endTime = epoch_to_iso8601(current_time - 1)

    -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
    device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
      start = startTime,
      ["end"] = endTime,
      deltaEnergy = deltaEnergyWh,
      energy = total_energy
    }))
  end, "polling_report_schedule_timer")

  device:set_field(RECURRING_REPORT_POLL_TIMER, timer)
end

local function create_poll_schedules_for_cumulative_energy_imported(device)
  if not device:supports_capability(capabilities.powerConsumptionReport) then
    return
  end
  create_poll_schedule(device)
  create_poll_report_schedule(device)
end

local function delete_poll_schedules(device)
  local poll_timer = device:get_field(RECURRING_POLL_TIMER)
  local reporting_poll_timer = device:get_field(RECURRING_REPORT_POLL_TIMER)
  if poll_timer ~= nil then
    device.thread:cancel_timer(poll_timer)
    device:set_field(RECURRING_POLL_TIMER, nil)
  end
  if reporting_poll_timer ~= nil then
    device.thread:cancel_timer(reporting_poll_timer)
    device:set_field(RECURRING_REPORT_POLL_TIMER, nil)
  end
end

-- Lifecycle Handlers --
local function device_init(driver, device)
  device:subscribe()
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  create_poll_schedules_for_cumulative_energy_imported(device)
  local current_time = os.time()
  local current_time_iso8601 = epoch_to_iso8601(current_time)
  -- emit current time by default
  device:emit_event(capabilities.evseChargingSession.targetEndTime(current_time_iso8601))
end

local function device_added(driver, device)
  local electrical_sensor_eps = get_endpoints_for_dt(device, ELECTRICAL_SENSOR_DEVICE_ID) or {}
  local device_energy_mgmt_eps = get_endpoints_for_dt(device, DEVICE_ENERGY_MANAGEMENT_DEVICE_ID) or {}
  local component_to_endpoint_map = {
    ["main"] = device.MATTER_DEFAULT_ENDPOINT,
    ["electricalSensor"] = electrical_sensor_eps[1],
    ["deviceEnergyManagement"] = device_energy_mgmt_eps[1]
  }
  log.debug("component_to_endpoint_map " .. utils.stringify_table(component_to_endpoint_map))
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_to_endpoint_map, { persist = true })
end

local function do_configure(driver, device)
  local power_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalPowerMeasurement.ID) or {}
  local energy_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID) or {}
  local device_energy_mgmt_eps = embedded_cluster_utils.get_endpoints(device, clusters.DeviceEnergyManagementMode) or {}
  local profile_name = "evse"

  -- As per spec, at least one of the electrical energy measurement or electrical power measurement clusters are to be supported.
  if #energy_meas_eps > 0 then
    profile_name = profile_name .. "-energy-meas"
  end
  if #power_meas_eps > 0 then
    profile_name = profile_name .. "-power-meas"
  end

  if #device_energy_mgmt_eps > 0 then
    profile_name = profile_name .. "-energy-mgmt-mode"
  end

  device.log.info_with({ hub_logs = true }, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({ profile = profile_name })
end

local function info_changed(driver, device)
  for cap_id, attributes in pairs(matter_driver_template.subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
  create_poll_schedules_for_cumulative_energy_imported(device)
end

local function device_removed(driver, device)
  delete_poll_schedules(device)
end

-- Matter Handlers --
local function charging_readiness_state_handler(driver, device, evse_state, evse_supply_state)
  local event = capabilities.evseChargingSession.chargingState.stopped({state_change = true})
  if evse_supply_state.NAME == capabilities.evseState.supplyState.disabledError.NAME or
  evse_supply_state.NAME == capabilities.evseState.supplyState.disabledDiagnostics.NAME or
      evse_state.NAME == capabilities.evseState.state.fault.NAME then
    event = capabilities.evseChargingSession.chargingState.disabled({state_change = true})
  elseif evse_supply_state.NAME == capabilities.evseState.supplyState.chargingEnabled.NAME then
    event = capabilities.evseChargingSession.chargingState.charging({state_change = true})
  end
  device:emit_event(event)
end

local function evse_state_handler(driver, device, ib, response)
  local evse_state = ib.data.value
  local latest_supply_state = device:get_latest_state(
    "main",
    capabilities.evseState.ID,
    capabilities.evseState.supplyState.NAME
  )
  local event = EVSE_STATE_ENUM_MAP[evse_state]
  if event then
    device:emit_event_for_endpoint(ib.endpoint_id, event())
    charging_readiness_state_handler(driver, device, event, {NAME=latest_supply_state})
  else
    log.warn("evse_state_handler invalid EVSE State: " .. evse_state)
  end
end

local function evse_supply_state_handler(driver, device, ib, response)
  local evse_supply_state = ib.data.value

  local latest_evse_state = device:get_latest_state(
    device:endpoint_to_component(ib.endopint_id),
    capabilities.evseState.ID,
    capabilities.evseState.state.NAME
  )
  local event = EVSE_SUPPLY_STATE_ENUM_MAP[evse_supply_state]
  if event then
    device:emit_event_for_endpoint(ib.endpoint_id, event())
    charging_readiness_state_handler(driver, device, {NAME=latest_evse_state}, event)
  else
    log.warn("evse_supply_state_handler invalid EVSE Supply State: " .. evse_supply_state)
  end
end

local function evse_fault_state_handler(driver, device, ib, response)
  local evse_fault_state = ib.data.value
  local event = EVSE_FAULT_STATE_ENUM_MAP[evse_fault_state]
  if event then
    device:emit_event_for_endpoint(ib.endpoint_id, event())
    return
  end
  log.warn("Invalid EVSE fault state received: " .. evse_fault_state)
end

local function evse_charging_enabled_until_handler(driver, device, ib, response)
  local ep = ib.endpoint_id
  local targetEndTime = ib.data.value
  if targetEndTime ~= nil then
    if  targetEndTime == 0 then --if we get 0 we update with current time.
      targetEndTime = os.time()
    end
    targetEndTime = epoch_to_iso8601(targetEndTime)
    device:emit_event_for_endpoint(ep, capabilities.evseChargingSession.targetEndTime(targetEndTime))
    return
  end
  log.warn("Charging enabled handler received an invalid target end time, not reporting")
end

local function evse_current_limit_handler(event)
  return function(driver, device, ib, response)
    local data = ib.data.value
    local ep = ib.endpoint_id
    if data then
      device:emit_event_for_endpoint(ep, event(data))
      return
    end
    log.warn("Failed to emit capability for " .. event.NAME)
  end
end

local function evse_session_duration_handler(driver, device, ib, response)
  local session_duration = ib.data.value
  local endpoint_id = ib.endpoint_id
  if session_duration then
    device:emit_event_for_endpoint(endpoint_id, capabilities.evseChargingSession.sessionTime(session_duration))
    return
  end
  log.warn("evse_session_duration_handler received invalid EVSE Session Duration")
end

local function evse_session_energy_charged_handler(driver, device, ib, response)
  local charged_energy = ib.data.value
  local endpoint_id = ib.endpoint_id
  if charged_energy then
    device:emit_event_for_endpoint(endpoint_id, capabilities.evseChargingSession.energyDelivered(charged_energy))
    return
  end
  log.warn("evse_session_energy_charged_handler received invalid EVSE Session Energy Charged")
end

local function power_mode_handler(driver, device, ib, response)
  local power_mode = ib.data.value
  local endpoint_id = ib.endpoint_id

  if power_mode == clusters.ElectricalPowerMeasurement.types.PowerModeEnum.AC then
    device:emit_event_for_endpoint(endpoint_id, capabilities.powerSource.powerSource.mains())
  elseif power_mode == clusters.ElectricalPowerMeasurement.types.PowerModeEnum.DC then
    device:emit_event_for_endpoint(endpoint_id, capabilities.powerSource.powerSource.dc())
  else
    device:emit_event_for_endpoint(endpoint_id, capabilities.powerSource.powerSource.unknown())
  end
end

local function energy_evse_supported_modes_attr_handler(driver, device, ib, response)
  local supportedEvseModesMap = device:get_field(SUPPORTED_EVSE_MODES_MAP) or {}
  local supportedEvseModes = {}
  for _, mode in ipairs(ib.data.elements) do
    clusters.EnergyEvseMode.types.ModeOptionStruct:augment_type(mode)
    table.insert(supportedEvseModes, mode.elements.label.value)
  end
  supportedEvseModesMap[ib.endpoint_id] = supportedEvseModes
  device:set_field(SUPPORTED_EVSE_MODES_MAP, supportedEvseModesMap, { persist = true })
  local event = capabilities.mode.supportedModes(supportedEvseModes, { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
  event = capabilities.mode.supportedArguments(supportedEvseModes, { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function energy_evse_mode_attr_handler(driver, device, ib, response)
  device.log.info(string.format("energy_evse_modes_attr_handler currentMode: %s", ib.data.value))

  local supportedEvseModesMap = device:get_field(SUPPORTED_EVSE_MODES_MAP) or {}
  local supportedEvseModes = supportedEvseModesMap[ib.endpoint_id] or {}
  local currentMode = ib.data.value
  for i, mode in ipairs(supportedEvseModes) do
    if i - 1 == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      break
    end
  end
end

local function device_energy_mgmt_supported_modes_attr_handler(driver, device, ib, response)
  local supportedDeviceEnergyMgmtModesMap = device:get_field(SUPPORTED_DEVICE_ENERGY_MANAGEMENT_MODES_MAP) or {}
  local supportedDeviceEnergyMgmtModes = {}
  for _, mode in ipairs(ib.data.elements) do
    clusters.EnergyEvseMode.types.ModeOptionStruct:augment_type(mode)
    table.insert(supportedDeviceEnergyMgmtModes, mode.elements.label.value)
  end
  supportedDeviceEnergyMgmtModesMap[ib.endpoint_id] = supportedDeviceEnergyMgmtModes
  device:set_field(SUPPORTED_DEVICE_ENERGY_MANAGEMENT_MODES_MAP, supportedDeviceEnergyMgmtModesMap, { persist = true })
  local event = capabilities.mode.supportedModes(supportedDeviceEnergyMgmtModes, { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
  event = capabilities.mode.supportedArguments(supportedDeviceEnergyMgmtModes, { visibility = { displayed = false } })
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function device_energy_mgmt_mode_attr_handler(driver, device, ib, response)
  device.log.info(string.format("device_energy_mgmt_mode_attr_handler currentMode: %s", ib.data.value))

  local supportedDeviceEnergyMgmtModesMap = device:get_field(SUPPORTED_DEVICE_ENERGY_MANAGEMENT_MODES_MAP) or {}
  local supportedDeviceEnergyMgmtModes = supportedDeviceEnergyMgmtModesMap[ib.endpoint_id] or {}
  local currentMode = ib.data.value
  for i, mode in ipairs(supportedDeviceEnergyMgmtModes) do
    if i - 1 == currentMode then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.mode.mode(mode))
      break
    end
  end
end

local function cumulative_energy_imported_handler(driver, device, ib, response)
  if ib.data then
    clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct:augment_type(ib.data)
    local cumulative_energy_imported = ib.data.elements.energy.value
    local endpoint_id = string.format(ib.endpoint_id)
    local cumulative_energy_imported_Wh = utils.round(cumulative_energy_imported / 1000)
    local total_cumulative_energy_imported = device:get_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED) or {}

    -- in case there are multiple electrical sensors store them in a table.
    total_cumulative_energy_imported[endpoint_id] = cumulative_energy_imported_Wh
    device:set_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED, total_cumulative_energy_imported, { persist = true })
  end
end

local function periodic_energy_imported_handler(driver, device, ib, response)
  local endpoint_id = ib.endpoint_id
  local cumul_eps = embedded_cluster_utils.get_endpoints(device,
    clusters.ElectricalEnergyMeasurement.ID,
    {feature_bitmap = clusters.ElectricalEnergyMeasurement.types.Feature.CUMULATIVE_ENERGY })

  if ib.data then
    if version.api < 11 then
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct:augment_type(ib.data)
    end

    local start_timestamp = ib.data.elements.start_timestamp.value or 0
    local end_timestamp = ib.data.elements.end_timestamp.value or 0

    local device_reporting_time_interval = end_timestamp - start_timestamp
    if not device:get_field(DEVICE_REPORTED_TIME_INTERVAL_CONSIDERED) and device_reporting_time_interval > REPORT_TIMEOUT then
      -- This is a one time setup in order to consider a larger time interval if the interval the device chooses to report is greater than 15 minutes.
      device:set_field(DEVICE_REPORTED_TIME_INTERVAL_CONSIDERED, true, {persist=true})
      local polling_schedule_timer = device:get_field(RECURRING_REPORT_POLL_TIMER)
      if polling_schedule_timer ~= nil then
        device.thread:cancel_timer(polling_schedule_timer)
      end
      device:set_field(POWER_CONSUMPTION_REPORT_TIME_INTERVAL, device_reporting_time_interval, {persist = true})
      create_poll_report_schedule(device)
    end

    if tbl_contains(cumul_eps, endpoint_id) then
      -- Since cluster in this endpoint supports both CUME & PERE features, we will prefer
      -- cumulative_energy_imported_handler to handle the energy report for this endpoint over PeriodicEnergyImported.
      return
    end

    local energy_imported = ib.data.elements.energy.value
    endpoint_id = string.format(ib.endpoint_id)
    local energy_imported_Wh = utils.round(energy_imported / 1000)
    local total_cumulative_energy_imported = device:get_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED) or {}

    -- in case there are multiple electrical sensors store them in a table.
    total_cumulative_energy_imported[endpoint_id] = total_cumulative_energy_imported[endpoint_id] or 0
    total_cumulative_energy_imported[endpoint_id] = total_cumulative_energy_imported[endpoint_id] + energy_imported_Wh
    device:set_field(TOTAL_CUMULATIVE_ENERGY_IMPORTED, total_cumulative_energy_imported, { persist = true })
  end
end

-- Capability Handlers --
local function get_latest_charging_parameters(device)
  local min_charging_current = device:get_latest_state("main", capabilities.evseChargingSession.ID,
    capabilities.evseChargingSession.minCurrent.NAME) or 0
  local max_charging_current = device:get_latest_state("main", capabilities.evseChargingSession.ID,
    capabilities.evseChargingSession.maxCurrent.NAME)
  local target_end_time_iso8601 = device:get_latest_state("main", capabilities.evseChargingSession.ID,
    capabilities.evseChargingSession.targetEndTime.NAME)
  return min_charging_current, max_charging_current, target_end_time_iso8601
end

local function handle_enable_charging(driver, device, cmd)
  local ep = component_to_endpoint(device, cmd.component)
  local default_min_current, default_max_current, default_charging_enabled_until_iso8601 = get_latest_charging_parameters(
    device)
  local charging_enabled_until_iso8601 = cmd.args.time or default_charging_enabled_until_iso8601
  local minimum_current = cmd.args.minCurrent or default_min_current
  local maximum_current = cmd.args.maxCurrent or default_max_current
  local charging_enabled_until_epoch_s = iso8601_to_epoch(charging_enabled_until_iso8601)
  device:send(clusters.EnergyEvse.commands.EnableCharging(device, ep, charging_enabled_until_epoch_s, minimum_current,
    maximum_current))
end

local handle_set_charging_parameters = function(cap, arg)
  return function(driver, device, cmd)
    if arg == "maxCurrent" and cmd.args[arg] > MAX_CHARGING_CURRENT_CONSTRAINT then
      cmd.args[arg] = MAX_CHARGING_CURRENT_CONSTRAINT
      log.warn_with({hub_logs=true}, "Clipping Max Current as it cannot be greater than 80A")
    end
    local capability_event = cap(cmd.args[arg])
    log.info("Setting value " .. (cmd.args[arg]) .. " for " .. (cap.NAME))
    device:emit_event(capability_event)
  end
end

local function handle_disable_charging(driver, device, cmd)
  local ep = component_to_endpoint(device, cmd.component)
  device:send(clusters.EnergyEvse.commands.Disable(device, ep))
end

local function handle_set_mode_command(driver, device, cmd)
  local set_mode_handlers = {
    ["main"] = function( ... )
      local ep = component_to_endpoint(device, cmd.component)
      local supportedEvseModesMap = device:get_field(SUPPORTED_EVSE_MODES_MAP)
      local supportedEvseModes = supportedEvseModesMap[ep] or {}
      for i, mode in ipairs(supportedEvseModes) do
        if cmd.args.mode == mode then
          device:send(clusters.EnergyEvseMode.commands.ChangeToMode(device, ep, i - 1))
          return
        end
      end
      log.warn("Received request to set unsupported mode for EnergyEvseMode.")
    end,
    ["deviceEnergyManagement"] = function( ... )
      local ep = component_to_endpoint(device, cmd.component)
      local supportedDeviceEnergyMgmtModesMap = device:get_field(SUPPORTED_DEVICE_ENERGY_MANAGEMENT_MODES_MAP)
      local supportedDeviceEnergyMgmtModes = supportedDeviceEnergyMgmtModesMap[ep] or {}
      for i, mode in ipairs(supportedDeviceEnergyMgmtModes) do
        if cmd.args.mode == mode then
          device:send(clusters.DeviceEnergyManagementMode.commands.ChangeToMode(device, ep, i - 1))
          return
        end
      end
      log.warn("Received request to set unsupported mode for DeviceEnergyManagementMode.")
    end
  }
  set_mode_handlers[cmd.component]()
end

matter_driver_template = {
  NAME = "matter-evse",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed,
    removed = device_removed
  },
  matter_handlers = {
    attr = {
      [clusters.EnergyEvse.ID] = {
        [clusters.EnergyEvse.attributes.State.ID] = evse_state_handler,
        [clusters.EnergyEvse.attributes.SupplyState.ID] = evse_supply_state_handler,
        [clusters.EnergyEvse.attributes.FaultState.ID] = evse_fault_state_handler,
        [clusters.EnergyEvse.attributes.ChargingEnabledUntil.ID] = evse_charging_enabled_until_handler,
        [clusters.EnergyEvse.attributes.MinimumChargeCurrent.ID] = evse_current_limit_handler(capabilities
          .evseChargingSession.minCurrent),
        [clusters.EnergyEvse.attributes.MaximumChargeCurrent.ID] = evse_current_limit_handler(capabilities
          .evseChargingSession.maxCurrent),
        [clusters.EnergyEvse.attributes.SessionDuration.ID] = evse_session_duration_handler,
        [clusters.EnergyEvse.attributes.SessionEnergyCharged.ID] = evse_session_energy_charged_handler,
      },
      [clusters.ElectricalPowerMeasurement.ID] = {
        [clusters.ElectricalPowerMeasurement.attributes.PowerMode.ID] = power_mode_handler,
      },
      [clusters.EnergyEvseMode.ID] = {
        [clusters.EnergyEvseMode.attributes.SupportedModes.ID] = energy_evse_supported_modes_attr_handler,
        [clusters.EnergyEvseMode.attributes.CurrentMode.ID] = energy_evse_mode_attr_handler,
      },
      [clusters.DeviceEnergyManagementMode.ID] = {
        [clusters.DeviceEnergyManagementMode.attributes.SupportedModes.ID] = device_energy_mgmt_supported_modes_attr_handler,
        [clusters.DeviceEnergyManagementMode.attributes.CurrentMode.ID] = device_energy_mgmt_mode_attr_handler,
      },
      [clusters.ElectricalEnergyMeasurement.ID] = {
        [clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported.ID] = cumulative_energy_imported_handler,
        [clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported.ID] = periodic_energy_imported_handler
      },
    },
  },
  subscribed_attributes = {
    [capabilities.evseState.ID] = {
      clusters.EnergyEvse.attributes.State,
      clusters.EnergyEvse.attributes.SupplyState,
      clusters.EnergyEvse.attributes.FaultState,
    },
    [capabilities.evseChargingSession.ID] = {
      clusters.EnergyEvse.attributes.ChargingEnabledUntil,
      clusters.EnergyEvse.attributes.MinimumChargeCurrent,
      clusters.EnergyEvse.attributes.MaximumChargeCurrent,
      clusters.EnergyEvse.attributes.SessionDuration,
      clusters.EnergyEvse.attributes.SessionEnergyCharged,
    },
    [capabilities.powerSource.ID] = {
      clusters.ElectricalPowerMeasurement.attributes.PowerMode,
    },
    [capabilities.powerConsumptionReport.ID] = {
      clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
    },
    [capabilities.mode.ID] = {
      clusters.EnergyEvseMode.attributes.SupportedModes,
      clusters.EnergyEvseMode.attributes.CurrentMode,
      clusters.DeviceEnergyManagementMode.attributes.CurrentMode,
      clusters.DeviceEnergyManagementMode.attributes.SupportedModes
    }
  },
  capability_handlers = {
    [capabilities.evseChargingSession.ID] = {
      [capabilities.evseChargingSession.commands.enableCharging.NAME] = handle_enable_charging,
      [capabilities.evseChargingSession.commands.disableCharging.NAME] = handle_disable_charging,
      [capabilities.evseChargingSession.commands.setTargetEndTime.NAME] = handle_set_charging_parameters(capabilities.evseChargingSession.targetEndTime, "time"),
      [capabilities.evseChargingSession.commands.setMinCurrent.NAME] = handle_set_charging_parameters(capabilities.evseChargingSession.minCurrent, "minCurrent"),
      [capabilities.evseChargingSession.commands.setMaxCurrent.NAME] = handle_set_charging_parameters(capabilities.evseChargingSession.maxCurrent, "maxCurrent"),
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_set_mode_command,
    },
  },
  supported_capabilities = {
    capabilities.evseState,
    capabilities.evseChargingSession,
    capabilities.powerSource,
    capabilities.powerConsumptionReport,
    capabilities.mode
  },
}

local matter_driver = MatterDriver("matter-evse", matter_driver_template)
log.info(string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
