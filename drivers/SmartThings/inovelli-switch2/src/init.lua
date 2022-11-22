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

local capabilities = require "st.capabilities"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.Device
local st_device = require "st.device"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
local preferencesMap = require "preferences"
local configurationsMap = require "configurations"
local log = require "log"

local function find_child(device, src_channel)
  if src_channel == 0 then
    return device
  else
    return device:get_child_by_parent_assigned_key(string.format("%02X", src_channel))
  end
end

local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    print("setting find child")
    device:set_find_child(find_child)
  end
end

local function prepare_metadata(device, endpoint, profile)
  local name = string.format("%s %d", device.label, endpoint)
  return {
    type = "EDGE_CHILD",
    label = name,
    profile = profile,
    parent_device_id = device.id,
    parent_assigned_child_key = string.format("%02X", endpoint),
    vendor_provided_label = name
  }
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    for index, endpoint in pairs(device.zwave_endpoints) do
      log.info("##### iterating endoints for newly added zw devices", index)
      --TODO test with/without this check...
      -- if find_child(device, index) == nil then
      driver:try_create_device(prepare_metadata(device, index, "switch-binary"))
      -- else
      --   log.info("##### not creating child for ep because it exists")
      -- end
    end
  end
  device:refresh()
end


-------------------------------------------------------------------------------------------
-- Register message handlers and run driver
-------------------------------------------------------------------------------------------
local driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.refresh
  },
  NAME = "Inovelli 2 channel smart plug",
  zwave_handlers = {
  },
  capability_handlers = {
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local switch = ZwaveDriver("zwave_switch", driver_template)
switch:run()
