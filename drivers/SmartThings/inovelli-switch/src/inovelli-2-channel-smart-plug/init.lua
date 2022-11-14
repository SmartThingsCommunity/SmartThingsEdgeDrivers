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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchAll
local SwitchAll = (require "st.zwave.CommandClass.SwitchAll")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })
local st_device = require "st.device"

local log = require "log"

local INOVELLI_2_CHANNEL_SMART_PLUG_FINGERPRINTS = {
  {mfr = 0x015D, prod = 0x2500, model = 0x2500}, -- Inovelli Outlet
}

local function can_handle_inovelli_2_channel_smart_plug(opts, driver, device, ...)
  for _, fingerprint in ipairs(INOVELLI_2_CHANNEL_SMART_PLUG_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

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
      if find_child(device, endpoint) == nil then
        driver:try_create_device(prepare_metadata(device, endpoint, "switch-binary"))
      end
    end
  end
  device:refresh()
end

local function do_configure(driver, device)
  device:send(Association:Set({grouping_identifier = 1, node_ids = {driver.environment_info.hub_zwave_id}}))
end

local inovelli_2_channel_smart_plug = {
  NAME = "Inovelli 2 channel smart plug",
  zwave_handlers = {
  },
  capability_handlers = {
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
    init = device_init,
    added = device_added,
  },
  can_handle = can_handle_inovelli_2_channel_smart_plug,
}

return inovelli_2_channel_smart_plug
