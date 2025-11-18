-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local preferences = require "preferences"

local OnOff = clusters.OnOff
local Level = clusters.Level
local ColorControl = clusters.ColorControl

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.light.acn004" },
  { mfr = "Aqara", model = "lumi.light.acn014" },
  { mfr = "LUMI", model = "lumi.light.cwacn1" }
}

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(Level.attributes.CurrentLevel:read(device))
  device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
end

local function emit_event_if_latest_state_missing(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

local function device_added(driver, device, event)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1)) -- private

  local value = { minimum = 2700, maximum = 6000 }
  if device:get_model() == "lumi.light.cwacn1" then
    value.maximum = 6500
  end
  emit_event_if_latest_state_missing(device, "main", capabilities.colorTemperature, capabilities.colorTemperature.colorTemperatureRange.NAME, capabilities.colorTemperature.colorTemperatureRange(value))
end

local function do_configure(self, device)
  device:configure()

  preferences.sync_preferences(self, device)
  device:send(ColorControl.commands.MoveToColorTemperature(device, 200, 0x0000))

  do_refresh(self, device)
end

local function set_level_handler(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)
  local dimming_rate = 0x0000

  device:send(Level.commands.MoveToLevelWithOnOff(device, level, dimming_rate))
end

local function init(self, device)
  local value = { minimum = 2700, maximum = 6000 }
  if device:get_model() == "lumi.light.cwacn1" then
    value.maximum = 6500
  end
  emit_event_if_latest_state_missing(device, "main", capabilities.colorTemperature, capabilities.colorTemperature.colorTemperatureRange.NAME, capabilities.colorTemperature.colorTemperatureRange(value))
end

local aqara_light_handler = {
  NAME = "Aqara Light Handler",
  lifecycle_handlers = {
    init = init,
    added = device_added,
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = set_level_handler
        }
  },
  can_handle = require("aqara-light.can_handle"),
}

return aqara_light_handler
