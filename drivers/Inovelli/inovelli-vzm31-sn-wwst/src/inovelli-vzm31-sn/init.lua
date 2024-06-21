-- Copyright 2024 Inovelli
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
local cluster_base = require "st.zigbee.cluster_base"
local st_device = require "st.device"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local device_management = require "st.zigbee.device_management"
local log = require "log"
local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"

local INOVELLI_VZM31_SN_FINGERPRINTS = {
  { mfr = "Inovelli", model = "VZM31-SN" }
}

local is_inovelli_vzm31_sn = function(opts, driver, device)
  for _, fingerprint in ipairs(INOVELLI_VZM31_SN_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local do_configure = function(self, device)
  log.info("inovelli-vzm31-sn - do_configure")
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:refresh()
    device:configure()

    device:send(device_management.build_bind_request(device, 0xFC31, self.environment_info.hub_zigbee_eui, 2)) -- Bind device for button presses. 

    -- Retrieve Neutral Setting "Parameter 21"
    device:send(cluster_base.read_manufacturer_specific_attribute(device, 0xFC31, 21, 0x122F))
    device:send(cluster_base.read_attribute(device, data_types.ClusterId(0x0000), 0x4000))

    -- Additional one time configuration
    if  device:supports_capability(capabilities.powerMeter) then
      -- Divisor and multipler for PowerMeter
      device:send(SimpleMetering.attributes.Divisor:read(device))
      device:send(SimpleMetering.attributes.Multiplier:read(device))
    end

    if device:supports_capability(capabilities.energyMeter) then
      -- Divisor and multipler for EnergyMeter
      device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
      device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
    end
  end
end

local function initialize(device, driver)
    log.info("inovelli-vzm31-sn - initialize")
    if device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) == nil and device:supports_capability(capabilities.switchLevel)then
      log.info("No Switch Level event received. Initializing value")
      device:emit_event(capabilities.switchLevel.level(0))
    end
    if device:get_latest_state("main", capabilities.fanSpeed.ID, capabilities.fanSpeed.fanSpeed.NAME) == nil and device:supports_capability(capabilities.fanSpeed) then
      log.info("No fan event received. Initializing value")
      device:emit_event(capabilities.fanSpeed.fanSpeed(0))
    end
    if device:get_latest_state("main", capabilities.powerMeter.ID, capabilities.powerMeter.power.NAME) == nil and device:supports_capability(capabilities.powerMeter) then
      log.info("No power event received. Initializing value")
      device:emit_event(capabilities.powerMeter.power(0))
    end
    if device:get_latest_state("main", capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME) == nil and device:supports_capability(capabilities.energyMeter)then
      log.info("No energy event received. Initializing value")
      device:emit_event(capabilities.energyMeter.energy(0))
    end

    for _, component in pairs(device.profile.components) do
      for _, capability in pairs(component.capabilities) do
        --log.info(capability.id)
      end
      if string.find(component.id, "button") ~= nil then
        if device:get_latest_state(component.id, capabilities.button.ID, capabilities.button.supportedButtonValues.NAME) == nil then
          device:emit_component_event(
            component,
            capabilities.button.supportedButtonValues(
              {"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"},
              { visibility = { displayed = false } }
            )
          )
        end
        if device:get_latest_state(component.id, capabilities.button.ID, capabilities.button.numberOfButtons.NAME) == nil then
          device:emit_component_event(
            component,
            capabilities.button.numberOfButtons({value = 1}, { visibility = { displayed = false } })
          )
        end
      end
    end
    device:send(cluster_base.read_attribute(device, data_types.ClusterId(0x0000), 0x4000))
end

local device_init = function(self, device)
  log.info("inovelli-vzm31-sn - device_init")
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time())
    initialize(device, self)
  end
end

local function energy_meter_handler(driver, device, value, zb_rx)
  log.info("inovelli-vzm31-sn - energy_meter_handler")
  local raw_value = value.value
  raw_value = raw_value / 100
  device:emit_event(capabilities.energyMeter.energy({value = raw_value, unit = "kWh" }))
end

local function power_meter_handler(driver, device, value, zb_rx)
  log.info("inovelli-vzm31-sn - power_meter_handler")
  local raw_value = value.value
  raw_value = raw_value / 10
  device:emit_event(capabilities.powerMeter.power({value = raw_value, unit = "W" }))
end

local inovelli_vzm31_sn = {
  NAME = "inovelli vzm31-sn handler",
  lifecycle_handlers = {
    doConfigure = do_configure,
    init = device_init
  },
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.InstantaneousDemand.ID] = power_meter_handler,
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      }
    }
  },
  can_handle = is_inovelli_vzm31_sn
}

return inovelli_vzm31_sn
