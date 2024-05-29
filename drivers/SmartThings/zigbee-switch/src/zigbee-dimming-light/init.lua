-- Copyright 2022 SmartThings
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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local OnOff = clusters.OnOff
local Level = clusters.Level

local DIMMING_LIGHT_FINGERPRINTS = {
  {mfr = "Vimar", model = "DimmerSwitch_v1.0"},               -- Vimar Smart Dimmer Switch
  {mfr = "OSRAM", model = "LIGHTIFY A19 ON/OFF/DIM"},         -- SYLVANIA Smart A19 Soft White
  {mfr = "OSRAM", model = "LIGHTIFY A19 ON/OFF/DIM 10 Year"}, -- SYLVANIA Smart 10-Year A19
  {mfr = "OSRAM SYLVANIA", model = "iQBR30"},                 -- SYLVANIA Ultra iQ
  {mfr = "OSRAM", model = "LIGHTIFY PAR38 ON/OFF/DIM"},       -- SYLVANIA Smart PAR38 Soft White
  {mfr = "OSRAM", model = "LIGHTIFY BR ON/OFF/DIM"},          -- SYLVANIA Smart BR30 Soft White
  {mfr = "sengled", model = "E11-G13"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E11-G14"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E11-G23"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E11-G33"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E12-N13"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E12-N14"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E12-N15"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E11-N13"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E11-N14"},                       -- Sengled Element Classic
  {mfr = "sengled", model = "E1A-AC2"},                       -- Sengled DownLight
  {mfr = "sengled", model = "E11-N13A"},                      -- Sengled Extra Bright Soft White
  {mfr = "sengled", model = "E11-N14A"},                      -- Sengled Extra Bright Daylight
  {mfr = "sengled", model = "E21-N13A"},                      -- Sengled Soft White
  {mfr = "sengled", model = "E21-N14A"},                      -- Sengled Daylight
  {mfr = "sengled", model = "E11-U21U31"},                    -- Sengled Element Touch
  {mfr = "sengled", model = "E13-A21"},                       -- Sengled LED Flood Light
  {mfr = "sengled", model = "E11-N1G"},                       -- Sengled Smart LED Vintage Edison Bulb
  {mfr = "sengled", model = "E23-N11"},                       -- Sengled Element Classic par38
  {mfr = "Leviton", model = "DL6HD"},   -- Leviton Dimmer Switch
  {mfr = "Leviton", model = "DL3HL"},   -- Leviton Lumina RF Plug-In Dimmer
  {mfr = "Leviton", model = "DL1KD"},   -- Leviton Lumina RF Dimmer Switch
  {mfr = "Leviton", model = "ZSD07"},   -- Leviton Lumina RF 0-10V Dimming Wall Switch
  {mfr = "MRVL", model = "MZ100"},
  {mfr = "CREE", model = "Connected A-19 60W Equivalent"},
  {mfr = "Insta GmbH", model = "NEXENTRO Dimming Actuator"}
}

local DIMMING_LIGHT_CONFIGURATION = {
  {
    cluster = OnOff.ID,
    attribute = OnOff.attributes.OnOff.ID,
    minimum_interval = 0,
    maximum_interval = 300,
    data_type = OnOff.attributes.OnOff.base_type,
    reportable_change = 1

  },
  {
    cluster = Level.ID,
    attribute = Level.attributes.CurrentLevel.ID,
    minimum_interval = 0,
    maximum_interval = 300,
    data_type = Level.attributes.CurrentLevel.base_type,
    reportable_change = 1

  }
}

local function can_handle_zigbee_dimming_light(opts, driver, device)
  for _, fingerprint in ipairs(DIMMING_LIGHT_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("zigbee-dimming-light")
      return true, subdriver
    end
  end
  return false
end

local function device_init(driver, device)
  for _,attribute in ipairs(DIMMING_LIGHT_CONFIGURATION) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.switchLevel.level(100))
end

local zigbee_dimming_light = {
  NAME = "Zigbee Dimming Light",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  sub_drivers = {
    require("zigbee-dimming-light/osram-iqbr30"),
    require("zigbee-dimming-light/zll-dimmer")
  },
  can_handle = can_handle_zigbee_dimming_light
}

return zigbee_dimming_light
