-- Copyright 2021 SmartThings
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
local json = require "st.json"
local utils = require "st.utils"
local datastore = require "datastore"
local devices = _envlibrequire("devices")
local report_error = _envlibrequire("util.report_error")
local device_lib = require "st.device"
local thread = require "st.thread"
local cosock = require "cosock"
local log = require "log"
local version = require "version"
local CapabilityCommandDispatcher = require "st.capabilities.dispatcher"
local DeviceLifecycleDispatcher = require "st.device_lifecycle_dispatcher"

local CONTROL_THREAD_NAME = "control"
-- The time between attempts to send a heartbeat RPC message (15 minutes)
local HEARTBEAT_INTERVAL_SECONDS = 15 * 60

local _AUGMENT_DATASTORE_EVT_KINDS = {
  Upsert = 0,
  Delete = 1,
}

local _VALID_AUGMENT_DATASTORE_EVT_KINDS = {}

for _, v in pairs(_AUGMENT_DATASTORE_EVT_KINDS) do
  _VALID_AUGMENT_DATASTORE_EVT_KINDS[v] = true
end

--- @module driver_templates
local driver_templates = {}

--- @class message_channel
local message_channel = {}


--- @class SubDriver
---
--- A SubDriver is a way to bundle groups of functionality that overrides the basic behavior of a given driver by gating
--- it behind a can_handle function.
---
--- @field public can_handle fun(type: Driver, type: Device, ...):boolean whether or not this sub driver, if it has a matching handler, should handle a message
--- @field public zigbee_handlers table the same zigbee handlers that a driver would have
--- @field public zwave_handlers table the same zwave handlers that a driver would have
--- @field public capability_handlers table the same capability handlers that a driver would have
--- @field public secret_data_handlers table the same secret_data handlers that a driver would have
local sub_driver = {}


--- @class Driver
---
--- This is a template class to define the various parts of a driver table.  The Driver object represents all of the
--- state necessary for running and supporting the operation of this class of devices.  This can be as specific as a
--- single model of device, or if there is much shared functionality can manage several different models and
--- manufacturers.
---
--- Drivers go through initial set up on hub boot, or initial install, but after that the Drivers are considered
--- long running.  That is, they will behave as if they run forever.  As a result, they should have a main run loop
--- that continues to check for work/things to process and handles it when available.  For MOST uses the provided
--- run function should work, and there should be no reason to overwrite the existing run loop.
---
--- @field public NAME string a name used for debug and error output
--- @field public capability_channel message_channel the communication channel for capability commands/events
--- @field public lifecycle_channel message_channel the communication channel for device lifecycle events
--- @field private timer_api timer_api utils related to timer functionality
--- @field private device_api device_api utils related to device functionality
--- @field private environment_channel message_channel the communication channel for environment info updates
--- @field public timers table this will contain a list of in progress timers running for the driver
--- @field public capability_dispatcher CapabilityCommandDispatcher dispatcher for routing capability commands
--- @field public lifecycle_dispatcher DeviceLifecycleDispatcher dispatcher for routing lifecycle events
--- @field public secret_data_dispatcher SecretDataDispatcher dispatcher for routing secret data events
--- @field public sub_drivers SubDriver[] A list of sub_drivers that contain more specific behavior behind a can_handle function
local Driver = {}
Driver.__index = Driver

driver_templates.Driver = Driver

--------------------------------------------------------------------------------------------
-- Timer related functions
--------------------------------------------------------------------------------------------

--- A template of a callback for a timer
---
--- @param driver Driver the driver the callback was associated with
function driver_templates.timer_callback_template(driver)
end

--- Set up a one shot timer to hit the callback after delay_s seconds
---
--- @param self Driver the driver setting up the timer
--- @param delay_s number the number of seconds to wait before hitting the callback
--- @param callback function the function to call when the timer expires. @see Driver.timer_callback_template
--- @param name string an optional name for the timer
--- @return timer the created timer
function Driver:call_with_delay(delay_s, callback, name)
  if type(delay_s) ~= "number" then
    error("Timer delay must be a number", 2)
  end
  return self._driver_thread:call_with_delay(delay_s, function()
    callback(self)
  end, name)
end

--- Set up a periodic timer to hit the callback every interval_s seconds
---
--- @param self Driver the driver setting up the timer
--- @param interval_s number the number of seconds to wait between hitting the callback
--- @param callback function the function to call when the timer expires. @see Driver.timer_callback_template
--- @param name string an optional name for the timer
--- @return timer the created timer
function Driver:call_on_schedule(interval_s, callback, name)
  if type(interval_s) ~= "number" then
    error("Timer interval must be a number", 2)
  end
  return self._driver_thread:call_on_schedule(interval_s, function()
    callback(self)
  end, name)
end

--- Cancel a timer set up on this driver
---
--- @param self Driver the driver with the timer
--- @param t Timer the timer to cancel
function Driver:cancel_timer(t)
  self._driver_thread:cancel_timer(t)
end

--------------------------------------------------------------------------------------------
-- Default capability command handling
--------------------------------------------------------------------------------------------

--- Default handler that can be registered for the capability message channel
---
--- @param self Driver the driver to handle the capability commands
--- @param capability_channel message_channel the capability message channel with data to be read
function Driver:capability_message_handler(capability_channel)
  local device_uuid, cap_data = capability_channel:receive()
  local cap_table = json.decode(cap_data)
  local device = self:get_device_info(device_uuid)
  if device ~= nil and cap_table ~= nil then
    device.thread:queue_event(self.handle_capability_command, self, device, cap_table)
  end
end

--- Default capability command handler.  This takes the parsed command and will look up the command handler and call it
---
--- @param self Driver the driver to handle the capability commands
--- @param device st.Device the device that this command was sent to
--- @param cap_command table the capability command table including the capability, command, component and args
--- @param quiet boolean if true, suppress logging; useful if the driver is injecting a capability command itself
function Driver:handle_capability_command(device, cap_command, quiet)
  local capability = cap_command.capability
  local command = cap_command.command
  if not capabilities[capability].commands[command]:validate_and_normalize_command(cap_command) then
    error(
      string.format("Invalid capability command: %s.%s (%s)", capability, command, utils.stringify_table(command.args))
    )
  else
    if device:supports_capability_by_id(capability) then
      local _ = quiet or device.log.info_with({ hub_logs = true }, string.format("received command: %s", json.encode(cap_command)))
      self.capability_dispatcher:dispatch(
        self, device, cap_command,
        self.default_handler_opts and self.default_handler_opts.native_capability_cmds_enabled
      )
    else
      local _ = quiet or device.log.warn_with({ hub_logs = true }, string.format("received command for unsupported capability: %s", json.encode(cap_command)))
    end
  end
end

--- Inject a capability command into the capability command dispatcher.
---
--- @param self Driver the driver to handle the capability command
--- @param device st.Device the device for which this command is injected
--- @param cap_command table the capability command table including the capability, command, component and args (positional) or named_args (key value pairs)
function Driver:inject_capability_command(device, cap_command)
  local quiet = true -- quiet so we do not mistake this for a message received from an external entity
  self:handle_capability_command(device, cap_command, quiet)
end

--------------------------------------------------------------------------------------------
-- Default message channel handling
--------------------------------------------------------------------------------------------

local function lifecycle_result_handler(driver, pcall_status, err_or_event_ret, ...)
  local lifecycle_dispatcher, driver, device, event, event_args = select(1, ...)
  if not pcall_status then
    return
  end

  if driver ~= nil and device ~= nil then
    local device_already_existed = (event_args and event_args.device_already_existed)
    if event == "added"
    and not device_already_existed
    then
      device.log.debug_with({ hub_logs = true },
        "added callback did not fail"
      )
      if version.rpc < 9 then
        device.log.debug_with({ hub_logs = true },
          string.format("queuing synthetic init for %s", device)
        )
        -- Old way of generating init lifecycle messages after receiving an added message
        lifecycle_dispatcher:dispatch(driver, device, "init")
      end
    elseif event == "doConfigure" then
      device.log.debug_with({ hub_logs = true },
        'doConfigure callback did not fail, transitioning device to \"PROVISIONED\"'
      )
      device.thread:queue_event(
        device.try_update_metadata, device, { provisioning_state = "PROVISIONED" }
      )
    end
  end
end

--- Default handler that can be registered for the device lifecycle events
---
--- @param self Driver the driver to handle the device lifecycle events
--- @param lifecycle_channel message_channel the lifecycle message channel with data to be read
function Driver:lifecycle_message_handler(lifecycle_channel)
  local device_uuid, event, data = lifecycle_channel:receive()
  local device_already_existed = self.device_cache and self.device_cache[device_uuid] ~= nil
  local device = self:get_device_info(device_uuid)
  device.log.info_with({ hub_logs = true }, string.format("received lifecycle event: %s", event))
  if version.rpc >= 9 then
    -- handle the init event
    if event == "init" then
      if not device then
        log.warn_with({ hub_logs = true }, string.format("device (%s) not found for init event", device_uuid))
      else
        device.thread:queue_event(self.lifecycle_dispatcher.dispatch, self.lifecycle_dispatcher, self, device, "init")
        if self.environment_info.startup_devices then
          self.environment_info.startup_devices[device_uuid] = nil
        end
      end
      return
    end
  end

  -- handle the update event, not something that can be overridden by a template callback
  if event == "update" then
    local status, tbl = pcall(json.decode, data)
    if status then
      device:_updated(tbl)
    else
      log.warn_with({hub_logs=true}, string.format("Failed to decode device update payload: %s", data))
    end
    return
  end

  local args = {}
  args["device_already_existed"] = device_already_existed
  if event == "infoChanged" then
    local old_device_st_store = self:get_device_info(device_uuid).st_store
    args["old_st_store"] = old_device_st_store
    local raw_device = json.decode(data)
    self.device_cache[device_uuid]:load_updated_data(raw_device)
    device = self.device_cache[device_uuid]
  end

  local event_result_handler = lifecycle_result_handler
  device.thread:queue_event_with_handler(
    self.lifecycle_dispatcher.dispatch,
    event_result_handler,
      self.lifecycle_dispatcher, self, device, event, args
  )

  -- Do event cleanup that needs to happen regardless
  if event == "removed" then
    if self.device_cache ~= nil then
      self.device_cache[device_uuid] = nil
    end
    device.thread:queue_event(device.deleted, device)
  end
end

--- Default handler that can be registered for the driver lifecycle events
---
--- @param self Driver the driver to handle the device lifecycle events
--- @param ch message_channel the lifecycle message channel with data to be read
function Driver:driver_lifecycle_message_handler(ch)
  local event, msg_val = ch:receive()
  if event == "generateMemoryReport" then
    self._driver_thread:queue_event(self._handle_memory_report, self, event)
  elseif event == "startupState" and type(msg_val) == "table" and type(msg_val.json_blob) == "string" then
    log.info_with({hub_logs=true}, string.format("received driver startupState: %s", msg_val.json_blob))
    local state = json.decode(msg_val.json_blob)
    if type(state) ~= "table" then return end
    if version.rpc >= 9 then
      local device_ids = state.device_ids or {}
      self.environment_info.startup_devices = {}
      for _,id in ipairs(device_ids) do
        self.environment_info.startup_devices[id]=true
      end
      log.info_with({hub_logs=true}, string.format("Starting driver[%s] with %s device IDs",self.NAME, #device_ids))
    end

    if state.hub_zigbee_id then
      local base64 = require "base64"
      self.environment_info.hub_zigbee_eui = base64.decode(state.hub_zigbee_id)
    end
    if state.hub_node_id then

      self.environment_info.hub_zwave_id = state.hub_node_id
    end
    if state.hub_ipv4 then
      self.environment_info.hub_ipv4 = state.hub_ipv4
    end
    if state.augmented_store and type(state.augmented_store) == "table" then
      self.hub_augmented_driver_data = self.hub_augmented_driver_data or {}
      for _, record in ipairs(state.augmented_store) do
        -- for some reason, the field is still coming across here as an array of numbers.
        -- This is in spite of the fact that we're using the same data structure with the
        -- same `#[serde(with="serde_bytes")] attribute that we use for the regular updates.
        -- So we explicitly convert to a byte string here.
        self.hub_augmented_driver_data[record.data_key] = string.char(table.unpack(record.data_value))
      end
    end
    if self.handle_startup_state_received ~= nil then
      self:handle_startup_state_received()
    end
  elseif event == "shutdown" then
    self.datastore:_force_save()
    if self.driver_lifecycle == nil then
      os.exit(0)
    else
      self._driver_thread:queue_event(self.driver_lifecycle, self, event)
    end
  elseif self.driver_lifecycle ~= nil then
    self._driver_thread:queue_event(self.driver_lifecycle, self, event)
  end
end

--- Handle requests for memory reports
---
--- @param self Driver the driver this report is run on
function Driver:_handle_memory_report()
  -- The memory interface is a custom one on our runtime so it may not be available
  -- if this is run on an older version of the runtime or on a different one
  -- (integeration tests).
  if memory ~= nil then
    local report = memory.generate_report()
    memory.submit_report(report)
  else
    log.warn("Memory report requested but no memory interface is available!")
  end
end



--- Default handler that can be registered for the environment info messages
---
--- @param self Driver the driver to handle the device lifecycle events
--- @param environment_channel message_channel the environment update message channel
function Driver:environment_info_handler(environment_channel)
  local msg_type, msg_val = environment_channel:receive()
  self.environment_info = self.environment_info or {}
  if msg_type == "zigbee" then
    local base64 = require "base64"
    self.environment_info.hub_zigbee_eui = base64.decode(msg_val.hub_zigbee_id)
    --TODO should we do this for LAN and ZWAVE too? I think yes, and if we do, update documentation.
    local devices = self:get_devices()
    for _, dev in ipairs(devices) do
      if dev.network_type == device_lib.NETWORK_TYPE_ZIGBEE and
        (dev._provisioning_state == "TYPED") then
        local event_result_handler = lifecycle_result_handler
        dev.log.info_with({ hub_logs = true }, string.format("generating doConfigure event for %s provisioning state", dev._provisioning_state))
        dev.thread:queue_event_with_handler(
          self.lifecycle_dispatcher.dispatch,
          event_result_handler,
          self.lifecycle_dispatcher, self, dev, "doConfigure"
        )
      end
    end
  elseif msg_type == "lan" then
    if msg_val.hub_ipv4 ~= nil then
      self.environment_info.hub_ipv4 = msg_val.hub_ipv4
      if self.lan_info_changed_handler ~= nil then
        self:lan_info_changed_handler(self.environment_info.hub_ipv4)
      end
    end
  elseif msg_type == "zwave" then
    log.debug_with({ hub_logs = true }, "Z-Wave hub node ID environment changed.")
    self.environment_info.hub_zwave_id = msg_val.hub_node_id
    if self.zwave_hub_node_id_changed_handler ~= nil then
      self:zwave_hub_node_id_changed_handler(self.environment_info.hub_zwave_id)
    end
  elseif msg_type == "augmentDatastore" and type(msg_val.payload) == "table" then
    local event_kind = msg_val.evt_kind or -1
    if not _VALID_AUGMENT_DATASTORE_EVT_KINDS[event_kind] then
      log.warn_with({ hub_logs = true }, string.format("Received unexpected Augmented Data Store Event Kind: %s", event_kind))
      return
    end

    -- Upsert -> payload is a single record. Replace the existing key with the new value.
    if event_kind == _AUGMENT_DATASTORE_EVT_KINDS.Upsert then
      self.hub_augmented_driver_data[msg_val.payload.data_key] = msg_val.payload.data_value
      -- notify with the updated record
      if self.notify_augmented_data_changed ~= nil then
        self:notify_augmented_data_changed("upsert", msg_val.payload.data_key, msg_val.payload.data_value)
      end
    -- Delete -> payload is a single record. Nil out the entry with the corresponding key.
    elseif event_kind == _AUGMENT_DATASTORE_EVT_KINDS.Delete then
      self.hub_augmented_driver_data[msg_val.payload.data_key] = nil
      -- notify with just the key that got deleted
      if self.notify_augmented_data_changed ~= nil then
        self:notify_augmented_data_changed("delete", msg_val.payload.data_key)
      end
    end
  end
end




--- @function Driver:get_devices()
--- Get a list of all devices known to this driver.
---
--- @return List of Device objects
function Driver:get_devices()
  local devices = {}

  local device_uuid_list = self.device_api.get_device_list()
  for i, uuid in ipairs(device_uuid_list) do
    table.insert(devices, self:get_device_info(uuid))
  end

  return devices
end

function Driver:build_child_device(raw_device_table)
  return device_lib.Device(self, raw_device_table)
end

--------------------------------------------------------------------------------------------
-- Default get device info handling
--------------------------------------------------------------------------------------------

---  Default function for getting and caching device info on a driver
---
--- By default this will use the devices api to request information about the device id provided
--- it will then cache that information on the driver.  The information will be stored as a table
--- after being decoded from the JSON sent across.
---
--- @param self Driver the driver running
--- @param device_uuid string the uuid of the device to get info for
--- @param force_refresh boolean if true, re-request from the driver api instead of returning cached value
function Driver:get_device_info(device_uuid, force_refresh)

  -- check if device__uuid is a string
  if type(device_uuid) ~= "string" then
    return nil, "device_uuid is required to be a string"
  end

  if self.device_cache == nil then
    self.device_cache = {}
  end

  -- We don't have any information for this device
  if self.device_cache[device_uuid] == nil then
    -- During driver startup, we use a lot of memory initializing devices.
    -- Doing a gc before building up the device object avoids adding to heap.
    collectgarbage()
    local unknown_device_info = self.device_api.get_device_info(device_uuid)
    if unknown_device_info == nil then
      return nil, "device_uuid is invalid string or non-corresponding uuid"
    end

    local raw_device = json.decode(unknown_device_info)
    local new_device
    if raw_device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
      local zigbee_device = require "st.zigbee.device"
      new_device = zigbee_device.ZigbeeDevice(self, raw_device)
    elseif raw_device.network_type == device_lib.NETWORK_TYPE_ZWAVE then
      local zwave_device = require "st.zwave.device"
      new_device = zwave_device.ZwaveDevice(self, raw_device)
    elseif raw_device.network_type == device_lib.NETWORK_TYPE_MATTER then
      local matter_device = require "st.matter.device"
      new_device = matter_device.MatterDevice(self, raw_device)
    elseif raw_device.network_type == device_lib.NETWORK_TYPE_CHILD then
      new_device = self:build_child_device(raw_device)
    else
      new_device = device_lib.Device(self, raw_device)
    end

    self.device_cache[new_device.id] = new_device
  elseif force_refresh == true then
    -- We have a device record, but we want to force refresh the data
    local raw_device = json.decode(self.device_api.get_device_info(device_uuid))
    self.device_cache[device_uuid]:load_updated_data(raw_device)
  end
  return self.device_cache[device_uuid]
end

--- @function Driver:try_create_device
--- Send a request to create a new device.
---
--- .. note::
---  At this time, only LAN type devices can be created via this api.
---
--- Example usage::
---
---  local metadata = {
---    type = "LAN",
---    device_network_id = "24FD5B0001044502",
---    label = "Kitchen Smart Bulb",
---    profile = "bulb.rgb.v1",
---    manufacturer = "WiFi Smart Bulb Co.",
---    model = "WiFi Bulb 9000",
---    vendor_provided_label = "Kitchen Smart Bulb"
---  })
---
---  driver:try_create_device(metadata))
---
--- All metadata fields are type string. Valid metadata fields are:
---
--- * **type** - network type of the device. Must be "LAN" or "EDGE_CHILD".(required)
--- * **device_network_id** - unique identifier specific for this device
--- * **label** - label for the device (required)
--- * **profile** - profile name defined in the profile .yaml file (required)
--- * **parent_device_id** - device id of a parent device (required for EDGE_CHILD)
--- * **manufacturer** - device manufacturer
--- * **model** - model name of the device
--- * **vendor_provided_label** - device label provided by the manufacturer/vendor (typically the same as label during device creation)
--- * **external_id** - The unique identifier of the device on its host platform.
--- * **parent_assigned_child_key** - unique key per parent, used to identify individual children (required for EDGE_CHILD)
---
--- @param device_metadata table A table of device metadata
function Driver:try_create_device(device_metadata)
  if type(device_metadata) ~= "table" then
    error(string.format("Metadata provided to create device is of type `%s`, which is not of the expected type `table`.", type(device_metadata)), 2)
  end

  -- Required `device_metadata` fields:
  -- `type` - network type of the device
  -- `label` - label for the device
  -- `profile` - profile name defined in the profile .yaml file
  local required_metadata_fields_array = { "type", "label", "profile" }
  for _, value in ipairs(required_metadata_fields_array) do
    if device_metadata[value] == nil then
      error(string.format("Device `%s` is missing but is required.", value), 2)
    end
  end


  -- Network type of device is expected to be valid for the following:
  -- `LAN`
  -- `EDGE_CHILD`
  -- `ZIGBEE` and `ZWAVE` disabled but listed here for ease of change in the future
  local valid_network_type_options = {
    ["LAN"] = true,
    ["EDGE_CHILD"] = true,
    ["ZIGBEE"] = false,
    ["ZWAVE"] = false
  }

  -- Validate the values are of `type` `string`, and that only valid network types are provided
  for metadata_key, metadata_value in pairs(device_metadata) do
    if type(metadata_value) ~= "string" then
      error(string.format("Value provided for device key `%s` is of type `%s`, which is not of the expected type `string`.", metadata_key, type(metadata_value)), 2)
    elseif metadata_key == "type" and valid_network_type_options[(string.upper(metadata_value))] ~= true then
      error("Invalid network type for key `type` was provided.", 2)
    end
  end


  -- Store only data of interest
  local normalized_metadata = {
    deviceNetworkId = device_metadata.device_network_id,
    label = device_metadata.label,
    profileReference = device_metadata.profile,
    parentDeviceId = device_metadata.parent_device_id,
    manufacturer = device_metadata.manufacturer,
    model = device_metadata.model,
    externalId = device_metadata.external_id
  }

  local network_type = string.upper(device_metadata.type)
  if network_type == "LAN" then
    normalized_metadata["vendorProvidedLabel"] = device_metadata.vendor_provided_label
  elseif network_type == "EDGE_CHILD" then
    assert(normalized_metadata.parentDeviceId, "Parent Device ID must be set for EDGE_CHILD device")
    assert(device_metadata.parent_assigned_child_key, "parent_assigned_child_key must be set for EDGE_CHILD devices")
    normalized_metadata["parentAssignedChildKey"] = device_metadata.parent_assigned_child_key
    if normalized_metadata.deviceNetworkId ~= nil then
      normalized_metadata.deviceNetworkId = nil
      log.warn("EDGE_CHILD can not explicitly set the device_network_id, use \"parent_assigned_child_key\" for identification")
    end
  end
  normalized_metadata["type"] = network_type

  local metadata_json = json.encode(normalized_metadata)
  if metadata_json == nil then
    error("error parsing device info", 2)
  end
  return devices.create_device(metadata_json)
end

--- @function Driver:try_delete_device
--- Send a request to delete an existing device
---
--- .. note::
---   At this time, only LAN and EDGE_CHILD type devices can be deleted via this api.
---
--- Example usage::
---   local device_uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
---
---   driver:try_delete_device(device_uuid)
---
--- **device_uuid** is expected to be of type string, otherwise a warn-level message will be logged
--- and two values will be returned: nil and a string message
---
--- @param device_uuid string A string of the device UUID
function Driver:try_delete_device(device_uuid)
  -- check if device_uuid is a string
  if type(device_uuid) ~= "string" then
    log.warn_with({ hub_logs = true }, "device uuid is not a string")
    return nil, "device_uuid is required to be a string"
  end

  if type(devices.delete_device) ~= "function" then
    return nil, "hub does not support device delete functionality"
  end
  return devices.delete_device(device_uuid)
end

--------------------------------------------------------------------------------------------
-- Message stream handling registration
--------------------------------------------------------------------------------------------

--- Template function for a message handler
---
--- @param driver Driver the driver to handle the message channel
--- @param message_channel message_channel the channel that has the data to read.  A receive should be called on the channel to get the data
function driver_templates.message_handler_callback(driver, message_channel)
end

--- Function to register a message_channel handler
---
--- @param self Driver the driver to handle message events
--- @param message_channel message_channel the message channel to listen to input on
--- @param callback function the callback function to call when there is data on the message channel
--- @param name string Optional name for the channel handler, used for logging
function Driver:register_channel_handler(message_channel, callback, name)
  self._driver_thread:register_socket(message_channel, function()
      callback(self, message_channel)
    end, name)
end

--- Private method for registering work on the main thread
--- @param self Driver the driver to handle message events
--- @param message_channel message_channel the message channel to listen to input on
--- @param callback function the callback function to call when there is data on the message channel
--- @param name string Optional name for the channel handler, used for logging
function Driver:_register_channel_handler(message_channel, callback, name)
  self.message_handlers[message_channel] = {
    callback = callback,
    name = (name or "unnamed")
  }
end

--- Function to unregister a message_channel handler
---
--- @param self Driver the driver to handle the message events
--- @param message_channel message_channel the message channel to stop listening for input on
function Driver:unregister_channel_handler(message_channel)
  self._driver_thread:unregister_socket(message_channel)
end

--------------------------------------------------------------------------------------------
-- Helper function for building drivers
--------------------------------------------------------------------------------------------

--- Standardize the structure of the sub driver structure of this driver
---
--- The handlers registered as a part of the base driver file (or capability defaults) are
--- assumed to be the default behavior of the driver.  However, if there is need for a subset
--- of devices to override the base behavior for one reason or another (e.g. manufacturer or
--- model specific behavior), a value can be added to the "sub_drivers".  Each sub_driver must
--- contain a `can_handle` function of the signature `can_handle(opts, driver, device, ...)`
--- where opts can be used to provide context specific information necessary to determine if
--- the sub_driver should be responsible for some type of work.  The most common use for the
--- sub drivers will be to provide capabiltiy/zigbee/zwave/matter handlers that need to override the
--- default for the driver.  It may optionally also contain its own `sub_drivers` containing
--- further subservient sets.
---
--- @param driver Driver the driver
function Driver.standardize_sub_drivers(driver)
  local handler_sets = {}
  for i, handler_set_list in pairs(driver.sub_drivers or {}) do
    local unwrapped_list = {table.unpack(handler_set_list)}
    if #unwrapped_list ~= 0 then
      for j, list in ipairs(unwrapped_list) do
        -- If there isn't a can_handle, it is a useless handler_set and should be ignored
        if list.can_handle ~= nil then
          table.insert(handler_sets, utils.deep_copy(list))
        end
      end
    else
      if handler_set_list.can_handle ~= nil then
        table.insert(handler_sets, utils.deep_copy(handler_set_list))
      end
    end
  end
  driver.sub_drivers = handler_sets
  for i, s_d in ipairs(driver.sub_drivers) do
    Driver.standardize_sub_drivers(s_d)
  end
end

--- Load reduced version of sub driver for memory savings
---
--- This function takes a sub driver and removes the handlers so that they can be
--- "lazy loaded" later when needed. All that is saved is the sub driver name
--- and the can_handle function. This allows the handlers to be garbage collected
--- for memory savings. The handlers will be loaded again later if the dispatcher
--- receives a message that can be handled by this sub driver.
---
--- @param sub_driver Driver the sub driver
function Driver.lazy_load_sub_driver(sub_driver)
  local can_handle = require(sub_driver..".can_handle")

  assert(type(can_handle == "function") and type(sub_driver) == "string")
  local lazy_sub_driver = {
    NAME = sub_driver,
    can_handle = can_handle,
    has_secret_data_handlers = false
  }

  -- handle sub sub drivers
  -- if sub_driver.sub_drivers ~= nil then
  --   lazy_sub_driver.sub_drivers = utils.deep_copy(sub_driver.sub_drivers)
  -- end

  collectgarbage()

  return lazy_sub_driver
end

--- @function SubDriver:should_lazy_load_sub_driver()
--- Determine if a sub driver should be lazy loaded.
--- Drivers with no handlers defined will be lazy loaded.
---
--- @return boolean true if driver should be lazy loaded
function Driver.should_lazy_load_sub_driver(sub_driver)
  if sub_driver.capability_handlers == nil and
      sub_driver.lifecycle_handlers == nil and
      sub_driver.zwave_handlers == nil and
      sub_driver.zigbee_handlers == nil and
      sub_driver.matter_handlers == nil then
    return true
  end
  return false
end

--- Recursively build the capability dispatcher structure from sub_drivers
---
--- This will recursively follow the `sub_drivers` defined on the driver and build
--- a structure that will correctly find and execute a handler that matches.  It should be
--- noted that a child handler will always be preferred over a handler at the same level,
--- but that if multiple child handlers report that they can handle a message, it will be
--- sent to each handler that reports it can handle the message.
---
--- @param driver Driver the driver
function Driver.populate_capability_dispatcher_from_sub_drivers(driver)
  for _, sub_driver in ipairs(driver.sub_drivers) do
    local capability_handlers
    if Driver.should_lazy_load_sub_driver(sub_driver) then
      log.info("!!!!! lazy loading subdriver")
      capability_handlers = {}
    else
      capability_handlers = sub_driver.capability_handlers or {}
    end
    sub_driver.capability_dispatcher =
      CapabilityCommandDispatcher(
        sub_driver.NAME,
        sub_driver.can_handle,
        capability_handlers
      )
    driver.capability_dispatcher:register_child_dispatcher(sub_driver.capability_dispatcher)
    Driver.populate_capability_dispatcher_from_sub_drivers(sub_driver)
  end
end


--- Recursively build the lifecycle dispatcher structure from sub_drivers
---
--- @param driver Driver the driver
function Driver.populate_lifecycle_dispatcher_from_sub_drivers(driver)
  for _, sub_driver in ipairs(driver.sub_drivers) do
    local lifecycle_handlers
    if Driver.should_lazy_load_sub_driver(sub_driver) then
      lifecycle_handlers = {}
    else
      lifecycle_handlers = sub_driver.lifecycle_handlers or {}
    end
    sub_driver.lifecycle_dispatcher = DeviceLifecycleDispatcher(
        sub_driver.NAME,
        sub_driver.can_handle,
        lifecycle_handlers
    )
    driver.lifecycle_dispatcher:register_child_dispatcher(sub_driver.lifecycle_dispatcher)
    Driver.populate_lifecycle_dispatcher_from_sub_drivers(sub_driver)
  end
end


local function default_lifecycle_event_handler(driver, device, event)
  device.log.trace_with({ hub_logs = true }, string.format("received unhandled lifecycle event: %s", event))
end

function Driver.default_nonfunctional_driverSwitched_hander(driver, device, event, args)
  -- If a device was switched to this driver and there was no overriding behavior mark it as non-functional
  device.thread:queue_event(device.try_update_metadata, device, { provisioning_state = "NONFUNCTIONAL" })
end

function Driver.default_capability_match_driverSwitched_handler(driver, device, event, args)
  -- This is just a best guess that will allow us to let a device run in this
  -- driver if we think it will function here.  However, it is still possible that we may think
  -- a device will function when it won't.  In these cases a driver should implement a custom
  -- handler for this event to properly handle the switched case
  for _, comp in pairs(device.profile.components) do
    for _, component_cap in pairs(comp.capabilities) do
      local cap_matched = false
      for _, driver_cap in ipairs(driver.supported_capabilities) do
        if type(driver_cap) == "table" then driver_cap = driver_cap.ID end
        if driver_cap == component_cap.id or component_cap.id == "firmwareUpdate" then
          cap_matched = true
          break
        end
      end
      if not cap_matched then
        -- This device profile includes a capability not supported by this driver
        device.thread:queue_event(device.try_update_metadata, device, { provisioning_state = "NONFUNCTIONAL" })
        return
      end
    end
  end
  -- Every capability in the device profile is supported by this driver
  device.thread:queue_event(device.try_update_metadata, device, { provisioning_state = "PROVISIONED" })
end


---Given a driver template and name initialize the context
---
--- This is used to build the driver context that will be passed around to provide access to various state necessary
--- for operation
---
--- @param cls Driver class to be instantiated
--- @param name string the name of the driver used for logging
--- @param template table a template with any override or necessary driver information
--- @return Driver the constructed driver context
function Driver.init(cls, name, template)
  local socket = cosock.socket
  local timer = cosock.timer

  local out_driver = template or {}
  out_driver.NAME = name
  out_driver.capability_handlers = out_driver.capability_handlers or {}
  out_driver.lifecycle_handlers = out_driver.lifecycle_handlers or {}
  out_driver.message_handlers = out_driver.message_handlers or {}

  out_driver.capability_channel = socket.capability()
  if template.discovery_message_handler or template.discovery then
    out_driver.discovery_channel = socket.discovery()
    out_driver.discovery_state = {}
  end
  out_driver.environment_channel = socket.environment_update()
  out_driver.lifecycle_channel = socket.device_lifecycle()
  out_driver.driver_lifecycle_channel = socket.driver_lifecycle()

  out_driver.timer_api = timer
  out_driver.device_api = devices
  out_driver.environment_info = {}
  out_driver.device_cache = {}
  out_driver.datastore = datastore.init()
  out_driver.hub_augmented_driver_data = {}
  setmetatable(out_driver, cls)
  out_driver._driver_thread = thread.Thread(out_driver, "driver")

  Driver.standardize_sub_drivers(out_driver)

  --- Moving the checking of sub drivers for secret handlers after the standardization
  local has_sub_driver_secret_handler = false
  for _, sub_driver in ipairs(out_driver.sub_drivers)  do
    if sub_driver.has_secret_data_handlers or sub_driver.secret_data_handlers then
      has_sub_driver_secret_handler = true
      break
    end
  end
  if has_sub_driver_secret_handler or template.security_handler or template.secret_data_handlers then
    log.trace_with({ hub_logs = true }, string.format("Setup security channel for %s", out_driver.NAME))
    out_driver.security_channel = socket.security()
  end

  utils.merge(
      out_driver.lifecycle_handlers,
      {
        fallback = default_lifecycle_event_handler,
        driverSwitched = Driver.default_nonfunctional_driverSwitched_hander,
      }
  )
  out_driver.lifecycle_dispatcher =
  DeviceLifecycleDispatcher(
      name,
      function(...)
        return true
      end,
      out_driver.lifecycle_handlers
  )
  out_driver.populate_lifecycle_dispatcher_from_sub_drivers(out_driver)
  log.trace_with({ hub_logs = true }, string.format("Setup driver %s with lifecycle handlers:\n%s", out_driver.NAME, out_driver.lifecycle_dispatcher))

  out_driver.capability_dispatcher =
  CapabilityCommandDispatcher(
      name,
      function(...)
        return true
      end,
      out_driver.capability_handlers
  )
  out_driver.populate_capability_dispatcher_from_sub_drivers(out_driver)
  log.trace_with({ hub_logs = true }, string.format("Setup driver %s with Capability handlers:\n%s", out_driver.NAME, out_driver.capability_dispatcher))

  if out_driver.security_channel ~= nil then
    local SecretDataDispatcher = require "st.secret_data_dispatcher"
    local SecretDataHandlerModule = require "st.handlers.secret_data_handlers"
    out_driver.secret_data_dispatcher =
    SecretDataDispatcher(
      name,
      function(...)
        return true
      end,
      out_driver.secret_data_handlers
    )
    SecretDataHandlerModule.populate_secret_data_dispatcher_from_sub_drivers(out_driver)
    log.trace_with({ hub_logs = true }, string.format("Setup driver %s with Secret Data handlers:\n%s", out_driver.NAME, out_driver.secret_data_dispatcher))

    out_driver:_register_channel_handler(
      out_driver.security_channel,
      template.security_handler or SecretDataHandlerModule.security_handler,
      "security"
    )
  end
  out_driver:_register_channel_handler(
    out_driver.capability_channel,
    template.capability_message_handler or Driver.capability_message_handler,
    "capability"
  )
  out_driver:_register_channel_handler(
    out_driver.lifecycle_channel,
    template.lifecycle_message_handler or Driver.lifecycle_message_handler,
    "device_lifecycle"
  )
  out_driver:_register_channel_handler(
    out_driver.driver_lifecycle_channel,
    template.driver_lifecycle_message_handler or Driver.driver_lifecycle_message_handler,
    "driver_lifecycle"
  )
  if out_driver.discovery_channel ~= nil then
    local DiscoveryMessageHandlers = require "st.handlers.discovery_message_handlers"
    out_driver:_register_channel_handler(
      out_driver.discovery_channel,
      template.discovery_message_handler or DiscoveryMessageHandlers.discovery_message_handler,
      "discovery"
    )
  end

  out_driver:_register_channel_handler(
    out_driver.environment_channel,
    template.environment_info_handler or Driver.environment_info_handler,
    "environment_info"
  )

  return out_driver
end

--- Internal select function
---
--- Allow for test mocking of the select call
---
--- @param recv table table of sockets to test for available data
--- @param sendt table table of sockets to test to see if data can be written
--- @param timeout number the maximum amount of time in seconds to wait for a change in status
function Driver:_internal_select(recv, sendt, timeout)
  return cosock.socket.select(recv, sendt, timeout)
end

--- Spawn Heartbeat task
---
--- This will spawn a cosock task that will sleep for HEARTBEAT_INTERVAL_SECONDS
--- and then call the global `send_heartbeat` RPC message. If we are in an environment
--- where `send_heartbeat` is undefined, this is a noop
---
--- @param self Driver the driver to spawn on
function Driver:_spawn_heartbeat_task()
  ---@diagnostic disable-next-line: undefined-global
  if type(send_heartbeat) == "function" then
    cosock.spawn(function()
      while true do
        cosock.socket.sleep(HEARTBEAT_INTERVAL_SECONDS)
        ---@diagnostic disable-next-line: undefined-global
        send_heartbeat()
      end
    end, "heartbeat")
  end
end

--- Wait for Startup Devices
---
--- This will select, wait, then read the driver_lifecycle_channel until
--- a driver startup message has been received and occupies a table of startup_devices
--- @return boolean - If a startup message was received and able to set startup_devices
function Driver:_wait_for_startup_devices()
  while not self.environment_info.startup_devices do

    local read_socks, _write_sockets, err = self:_internal_select({self.driver_lifecycle_channel},nil,2*60)
    if read_socks ~= nil then
      self:driver_lifecycle_message_handler(read_socks[1])
    else
      -- If we get a timeout then we should signal false to indicate
      -- that we failed to receive an init for all startup devices
      return false
    end
  end
  return true
end

--- Wait for Startup Devices
---
--- This will select, wait, then read the driver_lifecycle_channel until
--- a driver startup message has been received and occupies a table of startup_devices
--- @return boolean - If all startup_devices received an init lifecycle message
function Driver:_wait_to_init_startup_devices()
  while next(self.environment_info.startup_devices) do
    local read_socks, _write_sockets, err = self:_internal_select({self.lifecycle_channel},nil,2*60)
    if read_socks ~= nil then
      self:lifecycle_message_handler(read_socks[1])
    else
      return false
    end
  end
  return true
end

--------------------------------------------------------------------------------------------
-- Default run loop for drivers
--------------------------------------------------------------------------------------------

--- Function to run a driver
---
--- This will run an "infinite" loop for this driver. Upon startup, it will wait for a driver startup message that
--- contains a list of devices for the driver then wait for an init message for each device before running the "infinite"
--- loop. In this loop it will wait for input on any message channel that has a handler registered for it through the
--- register_channel_handler function.  In addition it will wait for any registered timers to expire and trigger as
--- well.  Whenever data becomes available on one of the message channels the callback will be called and then it will
--- go back to waiting for input.
---
--- @param self Driver the driver to run
function Driver:run(fail_on_error)
  -- Do a collectgarbage when a driver is first started as there is a lot of memory bloat as a part of startup
  collectgarbage()
  self._fail_on_error = fail_on_error ~= nil and fail_on_error or self._fail_on_error
  self:_spawn_heartbeat_task()
  local function inner_run()

    if version.rpc >= 9 then
      -- Wait until we have received an list of startup device IDs which occupies environment_info.startup_devices
      log.trace("Waiting on startupState message")
      if not self:_wait_for_startup_devices() then
        log.error("Failed to receive startup state message")
        report_error({message = "Failed to receive startup state message"})
        os.exit(504)
      end
      log.trace("Waiting on init messages")
      -- Wait until we have dispatched an init thread for each device in environment_info.startup_devices
      if not self:_wait_to_init_startup_devices() then
        log.error("Failed to init for every device")
        report_error({message = "Failed to receive init for every device"})
        os.exit(504)
      end
      log.trace("Startup process completed")
    else -- RPC version < 9: Old dispatching of device init messages
      local existing_devices = self.device_api.get_device_list()
      for _, deviceid in pairs(existing_devices) do
        local device, err = self:get_device_info(deviceid)
        if not device then
          log.warn_with({ hub_logs = true }, string.format("device (%s) not found for init event: %q", deviceid, err))
        else
          device.thread:queue_event(self.lifecycle_dispatcher.dispatch, self.lifecycle_dispatcher, self, device, "init")
        end
      end
    end

    if memory ~= nil and memory.trim ~= nil then
      memory.trim()
    end

    -- a random interval between 10 and 15 seconds to provide jitter across drivers
    local select_timeout = math.random(10, 15)
    while true do
      local sock_list = {}
      for sock, cb in pairs(self.message_handlers) do
        sock_list[#sock_list + 1] = sock
      end
      local read, _, err = self:_internal_select(sock_list, nil, select_timeout)
      if err and err ~= "timeout" then
        log.warn("Error from message handlers:", err)
      end

      -- Handle driver lifecycle events first.
      -- This is meant to ensure that the startup state event is the first event handled.
      local read_socks = {}
      for i, sock in ipairs(read or {}) do
        local handler = self.message_handlers[sock]
        if handler and handler.name == "driver_lifecycle" then
          table.insert(read_socks, 1, sock)
        else
          table.insert(read_socks, sock)
        end
      end

      for i, sock in ipairs(read_socks) do
        local handler = self.message_handlers[sock]
        if handler then
          log.trace_with({ hub_logs = true }, string.format("Received event with handler %s", handler.name))
          assert(type(handler.callback) == "function", "not a function")
          local status, err = pcall(handler.callback, self, sock)
          if not status then
            if self._fail_on_error == true then
              error(err, 2)
            else
              log.warn_with({ hub_logs = true }, string.format("%s encountered error: %s", self.NAME, tostring(err)))
            end
          end
        end
      end
      if self.datastore ~= nil then
        if self.datastore:is_dirty() then
          self.datastore:save()
        end
      end
    end
  end

  socket = cosock.socket
  cosock.spawn(inner_run, CONTROL_THREAD_NAME)

  cosock.run()
end

setmetatable(Driver, {
  __call = Driver.init
})

return Driver
