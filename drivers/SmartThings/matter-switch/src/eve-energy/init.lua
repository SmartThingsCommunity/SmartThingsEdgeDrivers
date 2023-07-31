-------------------------------------------------------------------------------------
-- Definitions
-------------------------------------------------------------------------------------

local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local MatterDriver = require "st.matter.driver"
local utils = require "st.utils"
local data_types = require "st.matter.data_types"

local EVE_MANUFACTURER_ID = 0x130A
local PRIVATE_CLUSTER_ID = 0x130AFC01

local PRIVATE_ATTR_ID_WATT = 0x130A000A
local PRIVATE_ATTR_ID_WATT_ACCUMULATED = 0x130A000B

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local TIMER_REPEAT = (1 * 60)    -- Run the timer each minute
local REPORT_TIMEOUT = (10 * 60) -- Report the value each 10 minutes


-------------------------------------------------------------------------------------
-- Eve specifics
-------------------------------------------------------------------------------------

local function is_eve_energy_products(opts, driver, device)
	if device.manufacturer_info.vendor_id == EVE_MANUFACTURER_ID then
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
	-- Report the energy consumed
	device:emit_event(capabilities.energyMeter.energy({ value = totalConsumptionWh, unit = "Wh" }))

	-- Only send powerConsumptionReport every 10 minutes
	local current_time = os.time()
	local last_time = device:get_field(LAST_REPORT_TIME) or 0
	local next_time = last_time + REPORT_TIMEOUT
	if current_time < next_time then
		return
	end

	device:set_field(LAST_REPORT_TIME, current_time, { persist = true })

	-- Calculate the energy consumed between the start and the end time
	local previousTotalConsumptionWh = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
		capabilities.powerConsumptionReport.powerConsumption.NAME)

	local deltaEnergyWh = 0.0
	if previousTotalConsumptionWh ~= nil and previousTotalConsumptionWh.energy ~= nil then
		deltaEnergyWh = math.max(totalConsumptionWh - previousTotalConsumptionWh.energy, 0.0)
	end

	local startTime = iso8061Timestamp(last_time)
	local endTime = iso8061Timestamp(current_time - 1)

	-- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
	device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
		start = startTime,
		["end"] = endTime,
		deltaEnergy = deltaEnergyWh,
		energy = totalConsumptionWh
	}))
end


-------------------------------------------------------------------------------------
-- Timer
-------------------------------------------------------------------------------------

local function requestData(device)
	-- Update the on/off status
	device:send(clusters.OnOff.attributes.OnOff:read(device))

	-- Update the Watt usage
	device:send(cluster_base.read(device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT, nil))

	-- Update the energy consumption
	device:send(cluster_base.read(device, 0x01, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID_WATT_ACCUMULATED, nil))
end

local timer = nil
local function create_poll_schedule(device)
	-- The powerConsumption report needs to be updated at least every 15 minutes in order to be included in SmartThings Energy
	-- Eve Energy generally report changes every 10 or 17 minutes
	timer = device.thread:call_on_schedule(TIMER_REPEAT, function()
		requestData(device)
	end, "polling_schedule_timer")
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
end

local function device_added(driver, device)
	-- Reset the values
	device:emit_event(capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
	device:emit_event(capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))
end

local function device_removed(driver, device)
	if timer ~= nil then
		device.thread:cancel_timer(timer)
	end
end

local function handle_refresh(self, device)
	requestData(device)
end


-------------------------------------------------------------------------------------
-- Eve Energy Handler
-------------------------------------------------------------------------------------

local function matter_handler(driver, device, response_block)
	log.info(string.format("Fallback handler for %s", response_block))
end

local function on_off_attr_handler(driver, device, ib, response)
	if ib.data.value then
		device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
	else
		device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
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
		fallback = matter_handler,
	},
	capability_handlers = {
		[capabilities.refresh.ID] = {
			[capabilities.refresh.commands.refresh.NAME] = handle_refresh,
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
