-- Copyright 2023 SmartThings
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

-------------------------------------------------------------------------------------
-- Definitions
-------------------------------------------------------------------------------------

local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local utils = require "st.utils"
local data_types = require "st.matter.data_types"
local device_lib = require "st.device"

local EVE_MANUFACTURER_ID = 0x130A
local PRIVATE_CLUSTER_ID = 0x130AFC01

local PRIVATE_ATTR_ID_WATT = 0x130A000A
local PRIVATE_ATTR_ID_WATT_ACCUMULATED = 0x130A000B
local PRIVATE_ATTR_ID_ACCUMULATED_CONTROL_POINT = 0x130A000E

-- Timer to update the data each minute if the device is on
local RECURRING_POLL_TIMER = "RECURRING_POLL_TIMER"
local TIMER_REPEAT = (1 * 60) -- Run the timer each minute

-- Timer to report the power consumption every 15 minutes to satisfy the ST energy requirement
local RECURRING_REPORT_POLL_TIMER = "RECURRING_REPORT_POLL_TIMER"
local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local LATEST_TOTAL_CONSUMPTION_WH = "LATEST_TOTAL_CONSUMPTION_WH"
local REPORT_TIMEOUT = (15 * 60) -- Report the value each 15 minutes


-------------------------------------------------------------------------------------
-- Eve specifics
-------------------------------------------------------------------------------------

local function is_eve_energy_products(opts, driver, device)
  -- this sub driver does not support child devices
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
     device.manufacturer_info.vendor_id == EVE_MANUFACTURER_ID then
    return true
  end

  return false
end

-- Return a ISO 8061 formatted timestamp in UTC (Z)
-- @return e.g. 2022-02-02T08:00:00Z
local function iso8061Timestamp(time)
  return os.date("!%Y-%m-%dT%TZ", time)
end

local function updateEnergyMeter(device, totalConsumptionWh)
  -- Remember the total consumption so we can report it every 15 minutes
  device:set_field(LATEST_TOTAL_CONSUMPTION_WH, totalConsumptionWh, { persist = true })

  -- Report the energy consumed
  device:emit_event(capabilities.energyMeter.energy({ value = totalConsumptionWh, unit = "Wh" }))
end


-------------------------------------------------------------------------------------
-- Timer
-------------------------------------------------------------------------------------

local function requestData(device)
  -- Update the Watt usage
  local req = cluster_base.read(device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT, nil)

  -- Update the energy consumption
  req:merge(cluster_base.read(device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT_ACCUMULATED, nil))

  device:send(req)
end

local function create_poll_schedule(device)
  local poll_timer = device:get_field(RECURRING_POLL_TIMER)
  if poll_timer ~= nil then
    return
  end

  -- The powerConsumption report needs to be updated at least every 15 minutes in order to be included in SmartThings Energy
  -- Eve Energy generally report changes every 10 or 17 minutes
  local timer = device.thread:call_on_schedule(TIMER_REPEAT, function()
    requestData(device)
  end, "polling_schedule_timer")

  device:set_field(RECURRING_POLL_TIMER, timer)
end

local function delete_poll_schedule(device)
  local poll_timer = device:get_field(RECURRING_POLL_TIMER)
  if poll_timer ~= nil then
    device.thread:cancel_timer(poll_timer)
    device:set_field(RECURRING_POLL_TIMER, nil)
  end
end


local function create_poll_report_schedule(device)
  -- The powerConsumption report needs to be updated at least every 15 minutes in order to be included in SmartThings Energy
  local timer = device.thread:call_on_schedule(REPORT_TIMEOUT, function()
    local current_time = os.time()
    local last_time = device:get_field(LAST_REPORT_TIME) or 0
    local latestTotalConsumptionWH = device:get_field(LATEST_TOTAL_CONSUMPTION_WH) or 0

    device:set_field(LAST_REPORT_TIME, current_time, { persist = true })

    -- Calculate the energy consumed between the start and the end time
    local previousTotalConsumptionWh = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
      capabilities.powerConsumptionReport.powerConsumption.NAME)

    local deltaEnergyWh = 0.0
    if previousTotalConsumptionWh ~= nil and previousTotalConsumptionWh.energy ~= nil then
      deltaEnergyWh = math.max(latestTotalConsumptionWH - previousTotalConsumptionWh.energy, 0.0)
    end

    local startTime = iso8061Timestamp(last_time)
    local endTime = iso8061Timestamp(current_time - 1)

    -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
    device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
      start = startTime,
      ["end"] = endTime,
      deltaEnergy = deltaEnergyWh,
      energy = latestTotalConsumptionWH
    }))
  end, "polling_report_schedule_timer")

  device:set_field(RECURRING_REPORT_POLL_TIMER, timer)
end


-------------------------------------------------------------------------------------
-- Matter Utilities
-------------------------------------------------------------------------------------

--- component_to_endpoint helper function to handle situations where
--- device does not have endpoint ids in sequential order from 1
--- In this case the function returns the lowest endpoint value that isn't 0
local function find_default_endpoint(device, component)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(nil)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      res = v
      break
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead",
    device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_id)
  -- Assumes matter endpoint layout is sequentional starting at 1.
  local ep_num = component_id:match("switch(%d)")
  return ep_num and tonumber(ep_num) or find_default_endpoint(device, component_id)
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end


-------------------------------------------------------------------------------------
-- Device Management
-------------------------------------------------------------------------------------

local function device_init(driver, device)
  log.info_with({ hub_logs = true }, "device init")
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:subscribe()

  create_poll_schedule(device)
  create_poll_report_schedule(device)
end

local function device_added(driver, device)
  -- Reset the values
  device:emit_event(capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
  device:emit_event(capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))
end

local function device_removed(driver, device)
  delete_poll_schedule(device)
end

local function handle_refresh(self, device)
  requestData(device)
end

local function handle_resetEnergyMeter(self, device)
  -- 978307200 is the number of seconds from 1 January 1970 to 1 January 2001
  local current_time = os.time()
  local current_time_2001 = current_time - 978307200
  if current_time_2001 < 0 then
    current_time_2001 = 0
  end

  local last_time = device:get_field(LAST_REPORT_TIME) or 0
  local startTime = iso8061Timestamp(last_time)
  local endTime = iso8061Timestamp(current_time - 1)

  -- Reset the consumption on the device
  local data = data_types.validate_or_build_type(current_time_2001, data_types.Uint32)
  device:send(cluster_base.write(device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_ACCUMULATED_CONTROL_POINT, nil,
    data))

  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
    start = startTime,
    ["end"] = endTime,
    deltaEnergy = 0,
    energy = 0
  }))

  device:set_field(LAST_REPORT_TIME, current_time, { persist = true })
end

-------------------------------------------------------------------------------------
-- Eve Energy Handler
-------------------------------------------------------------------------------------

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())

    create_poll_schedule(device)
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())

    -- We want to prevent to read the power reports of the device if the device is off
    -- We set here the power to 0 before the read is skipped so that the power is correctly displayed and not using a stale value
    device:emit_event(capabilities.powerMeter.power({ value = 0, unit = "W" }))

    -- Stop the timer when the device is off
    delete_poll_schedule(device)
  end
end

local function watt_attr_handler(driver, device, ib, zb_rx)
  if ib.data.value then
    local wattValue = ib.data.value
    device:emit_event(capabilities.powerMeter.power({ value = wattValue, unit = "W" }))
  end
end

local function watt_accumulated_attr_handler(driver, device, ib, zb_rx)
  if ib.data.value then
    local totalConsumptionRawValue = ib.data.value
    local totalConsumptionWh = utils.round(1000 * totalConsumptionRawValue)
    updateEnergyMeter(device, totalConsumptionWh)
  end
end

local eve_energy_handler = {
  NAME = "Eve Energy Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_ATTR_ID_WATT] = watt_attr_handler,
        [PRIVATE_ATTR_ID_WATT_ACCUMULATED] = watt_accumulated_attr_handler
      }
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
    [capabilities.energyMeter.ID] = {
      [capabilities.energyMeter.commands.resetEnergyMeter.NAME] = handle_resetEnergyMeter,
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.powerConsumptionReport
  },
  can_handle = is_eve_energy_products
}

return eve_energy_handler
