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

--- @type st.Device
local st_device = require "st.device"
--- @type st.utils
local utils = require "st.utils"
--- @type st.capabilities
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })

local DAWON_WALL_SMART_SWITCH_CONFIGURATION_MAP = require "dawon-wall-smart-switch/dawon_wall_smart_switch_configurations"

local DAWON_WALL_SMART_SWITCH_FINGERPRINTS = {
  {mfr = 0x018C, prod = 0x0061, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 1 KR
  {mfr = 0x018C, prod = 0x0062, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 2 KR
  {mfr = 0x018C, prod = 0x0063, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 3 KR
  {mfr = 0x018C, prod = 0x0064, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 1 US
  {mfr = 0x018C, prod = 0x0065, model = 0x0001}, -- Dawon Multipurpose Sensor + Smart Switch endpoint 2 US
  {mfr = 0x018C, prod = 0x0066, model = 0x0001} -- Dawon Multipurpose Sensor + Smart Switch endpoint 3 US
}

--- Determine whether the passed device is Dawon wall smart switch
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_dawon_wall_smart_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(DAWON_WALL_SMART_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function find_child(parent, src_channel)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", src_channel))
end

local function create_child_device(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    if not (device.child_ids and utils.table_size(device.child_ids) ~= 0) then
      local children_amount = DAWON_WALL_SMART_SWITCH_CONFIGURATION_MAP.get_child_amount(device)
      local device_profile = DAWON_WALL_SMART_SWITCH_CONFIGURATION_MAP.get_child_switch_device_profile(device)

      if children_amount == nil then
        children_amount = utils.table_size(device.zwave_endpoints)-1
      end
      
      for i = 1, children_amount, 1 do
        if find_child(device, i) == nil then
          local child_metadata = {
            type = "EDGE_CHILD",
            label = device.label,
            profile = device_profile,
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%02X", i),
            vendor_provided_label = device.label
          }
          driver:try_create_device(child_metadata)
        end
      end
    end
  end
end

--- Default handler for notification reports
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_report_handler(self, device, cmd)
  if cmd.args.notification_type == Notification.notification_type.POWER_MANAGEMENT then
    if cmd.args.event == Notification.event.power_management.AC_MAINS_DISCONNECTED then
      device:emit_event_for_endpoint(cmd.src_channel, capabilities.switch.switch.off())
    elseif cmd.args.event == Notification.event.power_management.AC_MAINS_RE_CONNECTED then
      device:emit_event_for_endpoint(cmd.src_channel, capabilities.switch.switch.on())
    end
  end
end

local function device_init(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_find_child(find_child)
  end
end

local function added_handler(self, device)
  create_child_device(self, device)
  device:refresh()
end

local function do_configure(driver, device)
  if device.preferences ~= nil and device.preferences.reportingInterval ~= nil then
    device:send(Configuration:Set({ parameter_number = 1, size = 2, configuration_value = device.preferences.reportingInterval * 60}))
  end
end

local function info_changed(driver, device, event, args)
  if args.old_st_store.preferences.reportingInterval ~= device.preferences.reportingInterval then
    do_configure(driver, device)
  end
end

local dawon_wall_smart_switch = {
  NAME = "Dawon Wall Smart Switch",
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = added_handler,
    doConfigure = do_configure,
    infoChanged = info_changed
  },
  can_handle = can_handle_dawon_wall_smart_switch,
}

return dawon_wall_smart_switch
