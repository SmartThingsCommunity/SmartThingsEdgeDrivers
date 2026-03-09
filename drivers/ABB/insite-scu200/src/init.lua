local log = require('log')
local Driver = require('st.driver')
local caps = require('st.capabilities')

-- Local imports
local discovery = require('discovery')
local commands = require('commands')
local config = require('config')
local lifecycles = require('lifecycles')
local connection_monitor = require('connection_monitor')

-- Driver definition
local driver = Driver("ABB.SCU200", {
	discovery = discovery.start,
	lifecycle_handlers = lifecycles,
	capability_handlers = {
		-- Refresh command handler
		[caps.refresh.ID] = {
			[caps.refresh.commands.refresh.NAME] = commands.refresh
		},
		[caps.switch.ID] = {
			[caps.switch.commands.on.NAME] = commands.switch_on,
			[caps.switch.commands.off.NAME] = commands.switch_off
		}
	}
})

-- Prepare datastores for bridge and thing discovery caches
if driver.datastore.bridge_discovery_cache == nil then
    driver.datastore.bridge_discovery_cache = {}
end

if driver.datastore.thing_discovery_cache == nil then
    driver.datastore.thing_discovery_cache = {}
end

-- Connection monitoring thread
driver:call_on_schedule(config.BRIDGE_CONN_MONITOR_INTERVAL, connection_monitor.monitor_connections, "SCU200 Bridge connection monitoring thread")

-- Initialize driver
log.info("Starting driver")

driver:run()

log.warn("Exiting driver")