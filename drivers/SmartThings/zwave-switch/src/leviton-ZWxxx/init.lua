--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local preferencesMap = require "preferences"

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
	if preferencesMap ~= nil then
		device:set_update_preferences_fn(update_preferences)
		local preferences = preferencesMap.get_device_parameters(device)
		if preferences == nil then
			print("init_dev(): preferences is nil!")
			return
		end
	else
		print("preferencesMap is nil!")
	end
end

local function device_added(self, device, event, args)
	local preferences = preferencesMap.get_device_parameters(device)
	for id, pref in pairs(preferences) do
		device:set_field(id, pref.parameter_number, { persist = true })
		device:send(Configuration:Get({ parameter_number = pref.parameter_number }))
	end
end

--- Handle preference changes
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param event table
--- @param args
local function info_changed(driver, device, event, args)
	local preferences = preferencesMap.get_device_parameters(device)
	for id, value in pairs(preferences) do
		local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
		if new_parameter_value ~= value and preferences then
			local pref = preferences[id]
			local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
			device:send(Configuration:Set({
				parameter_number = pref.parameter_number,
				size = pref.size,
				configuration_value = new_parameter_value
			}))
		end
	end
end

local leviton_zwxxx = {
	lifecycle_handlers = {
		init = init_dev,
		infoChanged = info_changed,
		added = device_added,
	},
	NAME = "Leviton Z-Wave in-wall device",
	can_handle = can_handle_leviton_zwxxx,
}

return leviton_zwxxx