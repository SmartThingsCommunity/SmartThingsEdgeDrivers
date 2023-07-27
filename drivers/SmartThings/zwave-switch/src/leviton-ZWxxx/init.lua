--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

local capabilities = require "st.capabilities"
--- @type st.Device
local st_device = require "st.device"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
-- local sceneActuatorConf = require "st.zwave.CommandClass.SceneActuatorConf"
-- local sceneActivation = require "st.zwave.CommandClass.SceneActivation"
local preferencesMap = require "preferences"
local log = require "log"

local LEVITON_FINGERPRINTS = {
	{ mfr = 0x001D, prod = 0x0002, model = 0x0041 }, -- ZW6HD US In-wall Dimmer
	{ mfr = 0x001D, prod = 0x0002, model = 0x0042 } -- ZW15S US In-wall Switch
}

local function can_handle_leviton_zwxxx(opts, driver, device, ...)
	for _, fingerprint in ipairs(LEVITON_FINGERPRINTS) do
		if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
			return true
		end
	end
	return false
end

local update_preferences = function(driver, device, args)
	print("update_preferences()")
	local prefs = preferences.get_device_parameters(device)
	if prefs ~= nil then
		for id, value in pairs(device.preferences) do
			if not (args and args.old_st_store) or (args.old_st_store.preferences[id] ~= value and prefs and prefs[id]) then
				local new_parameter_value = preferences.to_numeric_value(device.preferences[id])
				device:set_field(id, args.old_st_store.preferences[id], { persist = true })
				device:send(Configuration:Set({
					parameter_number = prefs[id].parameter_number,
					size = prefs[id].size,
					configuration_value = new_parameter_value
				}))
			end
		end
	else
		print("update_preferences(): prefs is nil!")
	end
end

local function init_dev(self, device, event, args)
	print("init_dev()")
	print(device:debug_pretty_print())
	print("")
	print(device:pretty_print())
	print("")

	if preferencesMap ~= nil then
		device:set_update_preferences_fn(update_preferences)
		local preferences = preferencesMap.get_device_parameters(device)
		if preferences == nil then
			print("init_dev(): preferences is nil!")
			return
		end
		for id, pref in pairs(preferences) do
			device:set_field(id, pref.parameter_number, { persist = true })
			device:send(Configuration:Get({ parameter_number = pref.parameter_number }))
		end
	else
		print("preferencesMap is nil!")
	end
	print("init_dev() END")
end

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
	print("info_changed() v3")
	local preferences = preferencesMap.get_device_parameters(device)
	for id, value in pairs(preferences) do
		print("value: ", value)
		local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
		-- if args.old_st_store.preferences[id] ~= value and preferences then
		if new_parameter_value ~= value and preferences then
			local pref = preferences[id]
			print("info_changed(): id: ", id)
			local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
			print("Z-WAVE SEND CONFIG SET")
			print("preferences[id].parameter_number: ", pref.parameter_number)
			print("configuration_value: ", new_parameter_value)
			print("size: ", pref.size)
			device:send(Configuration:Set({
				parameter_number = pref.parameter_number,
				size = pref.size,
				configuration_value = new_parameter_value
			}))
		end
	end
end

local driver_template = {
	supported_capabilities = {
		capabilities.switch,
		capabilities.switchLevel,
		capabilities.firmwareUpdate,
		capabilities.configuration,
		-- capabilities.zwMultichannel,
		-- capabilities.healthCheck,
		-- capabilities.refresh,
		-- capabilities.sceneActivation,
		-- capabilities.SceneActuatorConf,
	},
	-- capability_handlers = {
	-- 	[capabilities.switch.commands.on] = on_handler,
	-- 	[capabilities.switch.commands.off] = off_handler,
	-- 	[capabilities.switchLevel.commands.on] = on_handler,
	-- 	[capabilities.switchLevel.commands.off] = off_handler,
	-- },
	lifecycle_handlers = {
		-- This device init function will be called any time a device object needs to be instantiated
		-- within the driver. There are 2 main cases where this happens: 1) the driver just started up
		-- and needs to create the objects for existing devices and 2) a device was newly added to the driver.
		init = init_dev,
		-- This represents a change that has happened in the data representing the device on the
		-- SmartThings platform. An example could be a change to the name of the device.
		infoChanged = info_changed,
		-- This is an event that will be sent when the platform believes the device needs to go through
		-- provisioning for it to work as expected. The most common situation for this is when the device
		-- is first added to the platform, but there are other protocol specific cases that this may be
		-- triggered as well.
		-- doConfigure = do_configure,
		-- A device was newly added to this driver. This represents when the device is, for the first time,
		-- assigned to run with this driver. For example, when it is first joined to the network and
		-- fingerprinted to this driver.
		-- added = device_added,
		-- This represents a device being switched from using a different driver, to using the current
		-- driver. This will be sent after an added event and it can be used to determine if this device
		-- can properly be supported by the driver or not. See Driver.default_capability_match_driverSwitched_handler
		-- as an example. Updating the devices metadata field provisioning_state to either NONFUNCTIONAL or
		-- PROVISIONED can be used to indicate that the driver won’t or will, respectively, function within
		-- this driver.
		-- driverSwitched =
		-- This represents a device being removed from this driver.
		-- removed =
	},
	NAME = "zwave leviton in-wall dimmer",
	can_handle = can_handle_leviton_zwxxx,
}

--[[
	The default handlers take care of the Command Classes and the translation to capability events
	for most devices, but you can still define custom handlers to override them.
]]
   --

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local device = ZwaveDriver("zwave-leviton", driver_template)
device:run()
