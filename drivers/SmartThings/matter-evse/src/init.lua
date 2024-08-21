local capabilities = require "st.capabilities"
local MatterDriver = require "st.matter.driver"
local clusters = require "st.matter.clusters"
local log = require "log"
local utils = require "st.utils"
local matter_driver_template = {}
local embedded_cluster_utils = require "embedded_cluster_utils"

local version = require "version"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.EnergyEvse = require "EnergyEvse"
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.DeviceEnergyManagementMode = require "DeviceEnergyManagementMode"
  clusters.EnergyEvseMode = require "EnergyEvseMode"
end

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local SUPPORTED_EVSE_MODES_MAP = "__supported_evse_modes_map"
local SUPPORTED_DEVICE_ENERGY_MANAGEMENT_MODES_MAP = "__supported_device_energy_management_modes_map"
local RECURRING_REPORT_POLL_TIMER = "__recurring_report_poll_timer"
local RECURRING_POLL_TIMER = "__recurring_poll_timer"
local LAST_REPORTED_TIME = "__last_reported_time"
local TOTAL_CUMULATIVE_ENERGY_IMORTED = "__total_cumulative_energy_imported" -- total in case there are multiple electrical sensors

local TIMER_REPEAT = (1 * 60) -- 1 minute
local REPORT_TIMEOUT = (15 * 60) -- Report the value each 15 minutes

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
  end
  return device.MATTER_DEFAULT_ENDPOINT
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

local function iso8601_to_epoch(iso8061Timestamp)
  local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
  local year, month, day, hour, mins, sec = iso8061Timestamp:match(pattern)
  local time_tab = {
    year  =  tonumber(year),
    month =  tonumber(month),
    day   =  tonumber(day),
    hour  =  tonumber(hour),
    mins  =  tonumber(mins),
    sec   =  tonumber(sec),
    isdst = false
  }
  return os.time(time_tab)
end

local function epoch_to_iso8601(time)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

-- MAPS --
local EVSE_STATE_ENUM_TO_CAPABILITY_MAP = {
  -- Since PLUGGED_IN_DISCHARGING is not to be supported, it is not checked.
  [clusters.EnergyEvse.types.StateEnum.NOT_PLUGGED_IN] = capabilities.evseState.state.notPluggedIn(),
  [clusters.EnergyEvse.types.StateEnum.PLUGGED_IN_NO_DEMAND] = capabilities.evseState.state.pluggedInNoDemand(),
  [clusters.EnergyEvse.types.StateEnum.PLUGGED_IN_DEMAND] = capabilities.evseState.state.pluggedInDemand(),
  [clusters.EnergyEvse.types.StateEnum.PLUGGED_IN_CHARGING] = capabilities.evseState.state.pluggedInCharging(),
  [clusters.EnergyEvse.types.StateEnum.SESSION_ENDING] = capabilities.evseState.state.sessionEnding(),
  [clusters.EnergyEvse.types.StateEnum.FAULT] = capabilities.evseState.state.fault(),
}

local EVSE_SUPPLY_STATE_ENUM_TO_CAPABILITY_MAP = {
  [clusters.EnergyEvse.types.SupplyStateEnum.DISABLED] = capabilities.evseState.supplyState.disabled(),
  [clusters.EnergyEvse.types.SupplyStateEnum.CHARGING_ENABLED] = capabilities.evseState.supplyState.chargingEnabled(),
  [clusters.EnergyEvse.types.SupplyStateEnum.DISCHARGING_ENABLED] = capabilities.evseState.supplyState.dischargingEnabled(),
  [clusters.EnergyEvse.types.SupplyStateEnum.DISABLED_ERROR] = capabilities.evseState.supplyState.disabledError(),
  [clusters.EnergyEvse.types.SupplyStateEnum.DISABLED_DIAGNOSTICS] = capabilities.evseState.supplyState.disabledDiagnostics(),
}

local EVSE_FAULTY_STATE_ENUM_TO_CAPABILITY_MAP = {
  [clusters.EnergyEvse.types.FaultStateEnum.NO_ERROR] = capabilities.evseState.faultState.noError(),
  [clusters.EnergyEvse.types.FaultStateEnum.METER_FAILURE] = capabilities.evseState.faultState.meterFailure(),
  [clusters.EnergyEvse.types.FaultStateEnum.OVER_VOLTAGE] = capabilities.evseState.faultState.overVoltage(),
  [clusters.EnergyEvse.types.FaultStateEnum.UNDER_VOLTAGE] = capabilities.evseState.faultState.underVoltage(),
  [clusters.EnergyEvse.types.FaultStateEnum.OVER_CURRENT] = capabilities.evseState.faultState.overCurrent(),
  [clusters.EnergyEvse.types.FaultStateEnum.CONTACT_WET_FAILURE] = capabilities.evseState.faultState.contactWetFailure(),
  [clusters.EnergyEvse.types.FaultStateEnum.CONTACT_DRY_FAILURE] = capabilities.evseState.faultState.contactDryFailure(),
  [clusters.EnergyEvse.types.FaultStateEnum.GROUND_FAULT] = capabilities.evseState.faultState.groundFault(),
  [clusters.EnergyEvse.types.FaultStateEnum.POWER_LOSS] = capabilities.evseState.faultState.powerLoss(),
  [clusters.EnergyEvse.types.FaultStateEnum.POWER_QUALITY] = capabilities.evseState.faultState.powerQuality(),
  [clusters.EnergyEvse.types.FaultStateEnum.PILOT_SHORT_CIRCUIT] = capabilities.evseState.faultState.pilotShortCircuit(),
  [clusters.EnergyEvse.types.FaultStateEnum.EMERGENCY_STOP] = capabilities.evseState.faultState.emergencyStop(),
  [clusters.EnergyEvse.types.FaultStateEnum.EV_DISCONNECTED] = capabilities.evseState.faultState.eVDisconnected(),
  [clusters.EnergyEvse.types.FaultStateEnum.WRONG_POWER_SUPPLY] = capabilities.evseState.faultState.wrongPowerSupply(),
  [clusters.EnergyEvse.types.FaultStateEnum.LIVE_NEUTRAL_SWAP] = capabilities.evseState.faultState.liveNeutralSwap(),
  [clusters.EnergyEvse.types.FaultStateEnum.OVER_TEMPERATURE] = capabilities.evseState.faultState.overTemperature(),
  [clusters.EnergyEvse.types.FaultStateEnum.OTHER] = capabilities.evseState.faultState.other(),
}

local function read_cumulative_energy_imported(device)
  local component_to_endpoint = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  local electrical_energy_measurement_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID)
  local electrical_sensor_eps = component_to_endpoint["electricalSensor"] or device.MATTER_DEFAULT_ENDPOINT
  -- TODO: Combine into a single read interaction request
  for _, ep in ipairs(electrical_sensor_eps) do
    device:send(clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(device, electrical_sensor_eps))
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
  local timer = device.thread:call_on_schedule(REPORT_TIMEOUT, function()
    local current_time = os.time()
    local last_time = device:get_field(LAST_REPORTED_TIME) or 0
    local total_cumulative_energy_imported = device:get_field(TOTAL_CUMULATIVE_ENERGY_IMORTED) or {}
    local total_energy = 0

    -- we sum up total cumulative energy across all electrical sensor endpoints
    for _, energyWh in ipairs(total_cumulative_energy_imported) do
      total_energy = total_energy + energyWh
    end

    device:set_field(LAST_REPORTED_TIME, current_time, { persist = true })

    -- Calculate the energy consumed between the start and the end time
    local previousTotalConsumptionWh = device:get_latest_state("electricalSensor", capabilities.powerConsumptionReport.ID,
      capabilities.powerConsumptionReport.powerConsumption.NAME)

    local deltaEnergyWh = 0.0
    if previousTotalConsumptionWh ~= nil and previousTotalConsumptionWh.energy ~= nil then
      deltaEnergyWh = math.max(total_energy - previousTotalConsumptionWh.energy, 0.0)
    end

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
end

local function device_added(driver, device)
  local electrical_sensor_eps = get_endpoints_for_dt(device, ELECTRICAL_SENSOR_DEVICE_ID) or {}
  local deivce_energy_mgmt_eps = get_endpoints_for_dt(device, DEVICE_ENERGY_MANAGEMENT_DEVICE_ID) or {}
  local component_to_endpoint_map = {
    ["main"] = device.MATTER_DEFAULT_ENDPOINT,
    ["electricalSensor"] = electrical_sensor_eps[1],
    ["deviceEnergyManagement"] = deivce_energy_mgmt_eps[1]
  }
  log.debug_with({hub_logs=true}, "component_to_endpoint_map "..utils.stringify_table(component_to_endpoint_map))
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_to_endpoint_map, {persist = true})
end

local function do_configure(driver, device)
  local power_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalPowerMeasurement.ID) or {}
  local energy_meas_eps = embedded_cluster_utils.get_endpoints(device, clusters.ElectricalEnergyMeasurement.ID) or {}
  local device_energy_mgmt_eps = embedded_cluster_utils.get_endpoints(device, clusters.DeviceEnergyManagementMode) or {}
  local profile_name = "evse"

  --As per spec, atleast one of electrical energy measurement or electrical power measurement clusters are to be supported.
  if #energy_meas_eps > 0 then
    profile_name = profile_name.."-energy-meas"
  elseif #power_meas_eps > 0 then
    profile_name = profile_name.."-power-meas"
  end

  if #device_energy_mgmt_eps > 0 then
    profile_name = profile_name.."-energy-mgmt-mode"
  end

  log.info_with({hub_logs = true}, "Updating device profile to "..profile_name)
  device:try_update_metadata({profile = profile_name})
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
local function evse_state_handler (diver, device, ib, response)
  local evse_state = ib.data.value
  local event = EVSE_STATE_ENUM_TO_CAPABILITY_MAP[evse_state]
  if event then
    device:emit_event_for_endpoint(ib.endpoint_id, event)
    return
  end
  log.warn("evse_state_handler invalid EVSE State: "..evse_state)
end

local function evse_supply_state_handler (diver, device, ib, response)
  local evse_faulty_state = ib.data.value
  local event = EVSE_SUPPLY_STATE_ENUM_TO_CAPABILITY_MAP[evse_faulty_state]
  if event then
    device:emit_event_for_endpoint(ib.endpoint_id, event)
    return
  end
  log.warn("evse_supply_state_handler invalid EVSE Supply State: "..evse_faulty_state)
end

local function evse_faulty_state_handler (diver, device, ib, response)
  local evse_faulty_state = ib.data.value
  local event = EVSE_FAULTY_STATE_ENUM_TO_CAPABILITY_MAP[evse_faulty_state]
  if event then
    device:emit_event_for_endpoint(ib.endpoint_id, event)
    return
  end
  log.warn("evse_faulty_state_handler invalid EVSE Faulty State: "..evse_faulty_state)
end

local function evse_charging_enabled_until_handler (diver, device, ib, response)
  local ep = ib.endpoint_id
  if ib.data.value ~= nil then
    local targetEndTime = epoch_to_iso8601(ib.data.value)
    device:emit_event_for_endpoint(ep, capabilities.evseChargingSession.targetEndTime(targetEndTime))
    return
  end
  log.warn("evse_charging_enabled_until_handler invalid EVSE Target End TIme, not reporting!")
end

local function evse_current_limit_handler(event)
  return function(driver, device, ib, response)
    local data = ib.data.value
    local ep = ib.endpoint_id
    if data then
      device:emit_event_for_endpoint(ep, event(data))
      return
    end
    log.warn("Failed to emit capability for "..event.NAME)
  end
end

local function evse_session_duration_handler (diver, device, ib, response)
  local session_duration = ib.data.value
  local endpoint_id = ib.endpoint_id
  if session_duration then
    device:emit_event_for_endpoint(endpoint_id, capabilities.evseChargingSession.sessionTime(session_duration))
    return
  end
  log.warn("evse_session_duration_handler received invalid EVSE Session Duration")
end

local function evse_session_energy_charged_handler (diver, device, ib, response)
  local charged_energy = ib.data.value
  local endpoint_id = ib.endpoint_id
  if charged_energy then
    device:emit_event_for_endpoint(endpoint_id, capabilities.evseChargingSession.energyDelivered(charged_energy))
    return
  end
  log.warn("evse_session_energy_charged_handler received invalid EVSE Session Energy Charged")
end

local function power_mode_handler (diver, device, ib, response)
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
  device:set_field(SUPPORTED_EVSE_MODES_MAP, supportedEvseModesMap, {persist = true})
  local event = capabilities.mode.supportedModes(supportedEvseModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function energy_evse_mode_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
    string.format("energy_evse_modes_attr_handler currentMode: %s", ib.data.value))

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
  local supportedDeviceEnergyMgmtModesMap = device:get_field(SUPPORTED_EVSE_MODES_MAP) or {}
  local supportedDeviceEnergyMgmtModes = {}
  for _, mode in ipairs(ib.data.elements) do
    clusters.EnergyEvseMode.types.ModeOptionStruct:augment_type(mode)
    table.insert(supportedDeviceEnergyMgmtModes, mode.elements.label.value)
  end
  supportedDeviceEnergyMgmtModesMap[ib.endpoint_id] = supportedDeviceEnergyMgmtModes
  device:set_field(SUPPORTED_EVSE_MODES_MAP, supportedDeviceEnergyMgmtModesMap, {persist = true})
  local event = capabilities.mode.supportedModes(supportedDeviceEnergyMgmtModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function device_energy_mgmt_mode_attr_handler(driver, device, ib, response)
  device.log.info_with({ hub_logs = true },
    string.format("device_energy_mgmt_mode_attr_handler currentMode: %s", ib.data.value))

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
  if ib.data.value then
    local cumulative_energy_imported = ib.data.value
    local endpoint_id = string.format(ib.endpoint_id)
    local cumulative_energy_imported_Wh = utils.round(1000 * cumulative_energy_imported)
    local total_cumulative_energy_imported = device:get_field(TOTAL_CUMULATIVE_ENERGY_IMORTED) or {}

    -- in case there are multiple electrical sensors store them in a table.
    total_cumulative_energy_imported[endpoint_id] = cumulative_energy_imported_Wh
    device:set_field(TOTAL_CUMULATIVE_ENERGY_IMORTED, total_cumulative_energy_imported, {persist=true})
  end
end

-- Capability Handlers --
local function handle_enable_charging (diver, device, cmd)
  local charging_enabled_until_iso8601 = cmd.args.time
  local minimum_current = cmd.args.minCurrent
  local maximum_current = cmd.args.maxCurrent
  local ep = component_to_endpoint(device, cmd.component)
  local charging_enabled_until_epoch_s = iso8601_to_epoch(charging_enabled_until_iso8601)
  device:send(clusters.EnergyEvse.commands.EnableCharging(device, ep, charging_enabled_until_epoch_s, minimum_current, maximum_current))
end

local function handle_disable_charging (diver, device, cmd)
  local ep = component_to_endpoint(device, cmd.component)
  device:send(clusters.EnergyEvse.commands.Disable(device, ep))
end

local function handle_set_mode_command (diver, device, cmd)
  local set_mode_handlers = {
    ["main"] = function ( ... )
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
    ["deviceEnergyManagement"] = function ( ... )
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
        [clusters.EnergyEvse.attributes.FaultState.ID] = evse_faulty_state_handler,
        [clusters.EnergyEvse.attributes.ChargingEnabledUntil.ID] = evse_charging_enabled_until_handler,
        [clusters.EnergyEvse.attributes.MinimumChargeCurrent.ID] = evse_current_limit_handler(capabilities.evseChargingSession.minCurrent),
        [clusters.EnergyEvse.attributes.MaximumChargeCurrent.ID] = evse_current_limit_handler(capabilities.evseChargingSession.maxCurrent),
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
    [capabilities.mode.ID] = {
      clusters.EnergyEvseMode.attributes.SupportedModes,
      clusters.EnergyEvseMode.attributes.CurrentMode,
      clusters.DeviceEnergyManagementMode.attributes.CurrentMode,
      clusters.DeviceEnergyManagementMode.attributes.CurrentMode,
    },
    [capabilities.powerConsumptionReport.ID] = {
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
    },
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_set_mode_command,
    },
    [capabilities.evseChargingSession.ID] = {
      [capabilities.evseChargingSession.commands.enableCharging.NAME] = handle_enable_charging,
      [capabilities.evseChargingSession.commands.disableCharging.NAME] = handle_disable_charging,
    },
  },
  supported_capabilities = {
    capabilities.evseState,
    capabilities.evseChargingSession,
    capabilities.powerSource,
    capabilities.mode,
    capabilities.powerConsumptionReport
  },
}

local matter_driver = MatterDriver("matter-evse", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()