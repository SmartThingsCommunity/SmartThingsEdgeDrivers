local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local fields = require "utils.switch_fields"
local embedded_cluster_utils = require "utils.embedded-cluster-utils"
local version = require "version"

local PowerConsumptionReporting = {}

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "embedded-clusters.ElectricalEnergyMeasurement"
end

-- [[ POWER CONSUMPTION REPORT HELPER FUNCTIONS ]] --

-- Return an ISO-8061 timestamp in UTC
local function iso8061Timestamp(time)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

-- Emit the capability event capturing the latest energy delta and timestamps
local function send_import_poll_report(device, latest_total_imported_energy_wh)
  local current_time = os.time()
  local last_time = device:get_field(fields.LAST_IMPORTED_REPORT_TIMESTAMP) or 0
  device:set_field(fields.LAST_IMPORTED_REPORT_TIMESTAMP, current_time, { persist = true })

  -- Calculate the energy delta between reports
  local energy_delta_wh = 0.0
  local previous_imported_report = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if previous_imported_report and previous_imported_report.energy then
    energy_delta_wh = math.max(latest_total_imported_energy_wh - previous_imported_report.energy, 0.0)
  end

  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  if not device:get_field(fields.ENERGY_MANAGEMENT_ENDPOINT) then
    device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
      start = iso8061Timestamp(last_time),
      ["end"] = iso8061Timestamp(current_time - 1),
      deltaEnergy = energy_delta_wh,
      energy = latest_total_imported_energy_wh
    }))
  else
    device:emit_event_for_endpoint(device:get_field(fields.ENERGY_MANAGEMENT_ENDPOINT),capabilities.powerConsumptionReport.powerConsumption({
      start = iso8061Timestamp(last_time),
      ["end"] = iso8061Timestamp(current_time - 1),
      deltaEnergy = energy_delta_wh,
      energy = latest_total_imported_energy_wh
    }))
  end
end

-- Set the poll report schedule on the timer defined by IMPORT_REPORT_TIMEOUT 
local function create_poll_report_schedule(device)
  local import_timer = device.thread:call_on_schedule(
    device:get_field(fields.IMPORT_REPORT_TIMEOUT), function()
    send_import_poll_report(device, device:get_field(fields.TOTAL_IMPORTED_ENERGY))
    end, "polling_import_report_schedule_timer"
  )
  device:set_field(fields.RECURRING_IMPORT_REPORT_POLL_TIMER, import_timer)
end

function PowerConsumptionReporting.set_poll_report_timer_and_schedule(device, is_cumulative_report)
  local cumul_eps = embedded_cluster_utils.get_endpoints(device,
    clusters.ElectricalEnergyMeasurement.ID,
    {feature_bitmap = clusters.ElectricalEnergyMeasurement.types.Feature.CUMULATIVE_ENERGY })
  if #cumul_eps == 0 then
    device:set_field(fields.CUMULATIVE_REPORTS_NOT_SUPPORTED, true, {persist = true})
  end
  if #cumul_eps > 0 and not is_cumulative_report then
    return
  elseif not device:get_field(fields.SUBSCRIPTION_REPORT_OCCURRED) then
    device:set_field(fields.SUBSCRIPTION_REPORT_OCCURRED, true)
  elseif not device:get_field(fields.FIRST_IMPORT_REPORT_TIMESTAMP) then
    device:set_field(fields.FIRST_IMPORT_REPORT_TIMESTAMP, os.time())
  else
    local first_timestamp = device:get_field(fields.FIRST_IMPORT_REPORT_TIMESTAMP)
    local second_timestamp = os.time()
    local report_interval_secs = second_timestamp - first_timestamp
    device:set_field(fields.IMPORT_REPORT_TIMEOUT, math.max(report_interval_secs, fields.MINIMUM_ST_ENERGY_REPORT_INTERVAL))
    -- the poll schedule is only needed for devices that support powerConsumption
    -- and enable powerConsumption when energy management is defined in root endpoint(0).
    if device:supports_capability(capabilities.powerConsumptionReport) or
       device:get_field(fields.ENERGY_MANAGEMENT_ENDPOINT) then
      create_poll_report_schedule(device)
    end
    device:set_field(fields.IMPORT_POLL_TIMER_SETTING_ATTEMPTED, true)
  end
end

function PowerConsumptionReporting.delete_import_poll_schedule(device)
  local import_poll_timer = device:get_field(fields.RECURRING_IMPORT_REPORT_POLL_TIMER)
  if import_poll_timer then
    device.thread:cancel_timer(import_poll_timer)
    device:set_field(fields.RECURRING_IMPORT_REPORT_POLL_TIMER, nil)
    device:set_field(fields.IMPORT_POLL_TIMER_SETTING_ATTEMPTED, nil)
  end
end

return PowerConsumptionReporting
