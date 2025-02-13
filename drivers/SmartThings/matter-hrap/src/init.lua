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

local MatterDriver = require "st.matter.driver"
local clusters = require "st.matter.clusters"

local utils = require "lustre.utils"
local log = require "log"

local capabilities = require "st.capabilities"
local threadVersion = capabilities["smilevirtual57983.threadVersion"]
local routerState = capabilities["smilevirtual57983.routerState"]
local routerName = capabilities["smilevirtual57983.routerName"]
local wifiSsid = capabilities["smilevirtual57983.wifiSsid"]

-- Include driver-side definitions when lua libs api version is <13
local version = require "version"
if version.api < 13 then
  clusters.ThreadBorderRouterManagement = require "ThreadBorderRouterManagement"
  clusters.WifiNetworkMangement = require "WiFiNetworkManagement"
end


--[[ ATTRIBUTE HANDLERS ]]--

local function ssid_attribute_handler(driver, device, ib)
  if ib.data.value == string.char(0x014) then -- TLV-encoded NULL
    device.log.info("Ssid is null. Per the spec, no primary Wi-Fi network is available at the moment.")
    return
  end
  local valid_utf8, utf8_err = utils.validate_utf8(ib.data.value)
  if valid_utf8 then
    device:emit_event_for_endpoint(ib.endpoint, wifiSsid.ssid({ value = ib.data.value }))
  else
    device.log.info("UTF8 validation of Ssid failed: Error: '"..utf8_err.."'.")
  end
end

local function border_router_name_attribute_handler(driver, device, ib)
  -- per the spec, the recommended attribute format is <VendorName> <ProductName>._meshcop._udp. This logic removes the meschop suffix IFF it is present
  local meshCop_name = ib.data.value
  local terminal_display_char = (string.find(meshCop_name, "._mescop._udp") or 64) - 1 -- where 64-1=63, the maximum allowed length for BorderRouterName
  local display_name = string.sub(meshCop_name, 1, terminal_display_char)
  device:emit_event_for_endpoint(ib.endpoint, routerName.name({ value = display_name }))
end

-- Spec uses TLV encoding of Thread Version, which should be mapped to a more user-friendly name
local VERSION_TLV_MAP = {
  [1] = "1.0.0",
  [2] = "1.1.0",
  [3] = "1.2.0",
  [4] = "1.3.0",
  [5] = "1.4.0",
}

local function thread_version_attribute_handler(driver, device, ib)
  local version_name = VERSION_TLV_MAP[ib.data.value]
  if version_name then
    device:emit_event_for_endpoint(ib.endpoint, threadVersion.threadVersion({ value = version_name }))
  end
end

local function thread_interface_enabled_attribute_handler(driver, device, ib)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint, routerState.state.enabled())
  else
    device:emit_event_for_endpoint(ib.endpoint, routerState.state.off())
  end
end


--[[ LIFECYCLE HANLDERS ]]--

local function device_init(driver, device)
  device:subscribe()
end


--[[ MATTER DRIVER TEMPLATE ]]--

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
  },
  matter_handlers = {
    attr = {
      [clusters.WifiNetworkMangement.ID] = {
        [clusters.WifiNetworkMangement.attributes.Ssid.ID] = ssid_attribute_handler,
      },
      [clusters.ThreadBorderRouterManagement.ID] = {
        [clusters.ThreadBorderRouterManagement.attributes.BorderRouterName.ID] = border_router_name_attribute_handler,
        [clusters.ThreadBorderRouterManagement.attributes.ThreadVersion.ID] = thread_version_attribute_handler,
        [clusters.ThreadBorderRouterManagement.attributes.InterfaceEnabled.ID] = thread_interface_enabled_attribute_handler,
      }
    }
  },
  subscribed_attributes = {
    [routerName.ID] = {
      clusters.ThreadBorderRouterManagement.attributes.BorderRouterName,
    },
    [routerState.ID] = {
      clusters.ThreadBorderRouterManagement.attributes.InterfaceEnabled,
    },
    [threadVersion.ID] = {
      clusters.ThreadBorderRouterManagement.attributes.ThreadVersion,
    },
    [wifiSsid.ID] = {
      clusters.WifiNetworkMangement.attributes.Ssid,
    },
  },
  supported_capabilities = {
    threadVersion,
    routerName,
    routerState,
    wifiSsid,
  },
}

local matter_driver = MatterDriver("matter-hrap", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
