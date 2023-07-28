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

local function device_added(self, device, event, args)
	local preferences = preferencesMap.get_device_parameters(device)
	for id, pref in pairs(preferences) do
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
	local parameters = preferencesMap.get_device_parameters(device)
	for id, value in pairs(parameters) do
		local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
		if new_parameter_value ~= value and parameters then
			local pref = parameters[id]
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
		infoChanged = info_changed,
		added = device_added,
	},
	NAME = "Leviton Z-Wave in-wall device",
	can_handle = can_handle_leviton_zwxxx,
}

return leviton_zwxxx