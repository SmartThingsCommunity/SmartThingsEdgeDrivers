local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local restorePowerState = capabilities["stse.restorePowerState"]
local turnOffIndicatorLight = capabilities["stse.turnOffIndicatorLight"]
local lightFadeInTimeInSec = capabilities["stse.lightFadeInTimeInSec"]
local lightFadeOutTimeInSec = capabilities["stse.lightFadeOutTimeInSec"]

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201
local TURN_OFF_INDICATOR_ATTRIBUTE_ID = 0x0203

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.light.acn004" }
}

local preference_message_map = {
  [restorePowerState.ID] = function(device, value)
    return cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID,
      RESTORE_POWER_STATE_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, value)
  end,
  [turnOffIndicatorLight.ID] = function(device, value)
    return cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID,
      TURN_OFF_INDICATOR_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, value)
  end,
  [lightFadeInTimeInSec.ID] = function(device, value)
    local raw_value = value * 10 -- value unit: 1sec, transition time unit: 100ms
    return Level.attributes.OnTransitionTime:write(device, raw_value)
  end,
  [lightFadeOutTimeInSec.ID] = function(device, value)
    local raw_value = value * 10 -- value unit: 1sec, transition time unit: 100ms
    return Level.attributes.OffTransitionTime:write(device, raw_value)
  end
}

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(Level.attributes.CurrentLevel:read(device))
  device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
end

local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  if preferences ~= nil then
    for id, attr in pairs(preference_message_map) do
      local old_value = old_preferences[id]
      local value = preferences[id]
      if value ~= nil and value ~= old_value then
        local write_message = attr(device, value)
        if write_message ~= nil then
          device:send(write_message)
        end
      end
    end
  end
end

local function do_configure(self, device)
  device:send(ColorControl.commands.MoveToColorTemperature(device, 200, 0x0000))
  device:configure()
  do_refresh(self, device)
end

local function device_added(driver, device, event)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1)) -- private

  device:send(Level.attributes.OnTransitionTime:write(device, 0))
  device:send(Level.attributes.OffTransitionTime:write(device, 0))
end

local aqara_light_handler = {
  NAME = "Aqara Light Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  can_handle = is_aqara_products
}

return aqara_light_handler
