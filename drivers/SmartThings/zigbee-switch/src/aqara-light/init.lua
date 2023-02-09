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
  if device.preferences ~= nil then
    if device.preferences[restorePowerState.ID] ~= nil and
        device.preferences[restorePowerState.ID] ~= args.old_st_store.preferences[restorePowerState.ID] then
      device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID,
        RESTORE_POWER_STATE_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, device.preferences[restorePowerState.ID]))
    end

    if device.preferences[turnOffIndicatorLight.ID] ~= nil and
        device.preferences[turnOffIndicatorLight.ID] ~= args.old_st_store.preferences[turnOffIndicatorLight.ID] then
      device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID,
        TURN_OFF_INDICATOR_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, device.preferences[turnOffIndicatorLight.ID]))
    end

    if device.preferences[lightFadeInTimeInSec.ID] ~= nil and
        device.preferences[lightFadeInTimeInSec.ID] ~= args.old_st_store.preferences[lightFadeInTimeInSec.ID] then
      local raw_value = device.preferences[lightFadeInTimeInSec.ID] -- seconds
      raw_value = raw_value * 10 -- unit: 100ms
      device:send(Level.attributes.OnTransitionTime:write(device, raw_value))
    end

    if device.preferences[lightFadeOutTimeInSec.ID] ~= nil and
        device.preferences[lightFadeOutTimeInSec.ID] ~= args.old_st_store.preferences[lightFadeOutTimeInSec.ID] then
      local raw_value = device.preferences[lightFadeOutTimeInSec.ID] -- seconds
      raw_value = raw_value * 10 -- unit: 100ms
      device:send(Level.attributes.OffTransitionTime:write(device, raw_value))
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
