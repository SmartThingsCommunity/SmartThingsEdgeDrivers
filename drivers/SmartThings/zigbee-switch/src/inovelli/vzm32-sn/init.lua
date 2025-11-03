-- Copyright 2025 SmartThings
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
local st_device = require "st.device"
local device_management = require "st.zigbee.device_management"
local inovelli_common = require "inovelli.common"

local OccupancySensing = clusters.OccupancySensing

local INOVELLI_VZM32_SN_FINGERPRINTS = {
  { mfr = "Inovelli", model = "VZM32-SN" },
}

local PRIVATE_CLUSTER_ID = 0xFC31
local MFG_CODE = 0x122F

local function can_handle_inovelli_vzm32_sn(opts, driver, device)
  for _, fp in ipairs(INOVELLI_VZM32_SN_FINGERPRINTS) do
    if device:get_manufacturer() == fp.mfr and device:get_model() == fp.model then
      return true
    end
  end
  return false
end

local function configure_illuminance_reporting(device)
  local min_lux_change = 15
  local value = math.floor(10000 * math.log(min_lux_change, 10) + 1)
  device:send(clusters.IlluminanceMeasurement.attributes.MeasuredValue:configure_reporting(device, 10, 600, value))
end

local function refresh_handler(driver, device, command)
  if device.network_type ~= device.NETWORK_TYPE_CHILD then
    device:refresh()
    device:send(OccupancySensing.attributes.Occupancy:read(device))
  else
    device:refresh()
  end
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    refresh_handler(driver, device, {})
  else
    device:emit_event(capabilities.colorControl.hue(1))
    device:emit_event(capabilities.colorControl.saturation(1))
    device:emit_event(capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = 2700, maximum = 6500} }))
    device:emit_event(capabilities.colorTemperature.colorTemperature(6500))
    device:emit_event(capabilities.switchLevel.level(100))
    device:emit_event(capabilities.switch.switch("off"))
  end
end

local function device_configure(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    inovelli_common.base_device_configure(driver, device, PRIVATE_CLUSTER_ID, MFG_CODE)
    device:send(device_management.build_bind_request(device, OccupancySensing.ID, driver.environment_info.hub_zigbee_eui))
    configure_illuminance_reporting(device)
  else
    device:configure()
  end
end

local vzm32_sn = {
  NAME = "inovelli vzm32-sn device-specific",
  can_handle = can_handle_inovelli_vzm32_sn,
  lifecycle_handlers = {
    added = device_added,
    doConfigure = device_configure,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_handler,
    }
  }
}

return vzm32_sn