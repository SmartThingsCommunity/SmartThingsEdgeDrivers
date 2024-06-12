-- Copyright 2023 SmartThings
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
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local embedded_cluster_utils = require "embedded-cluster-utils"

local log = require "log"
local utils = require "st.utils"

local version = require "version"
if version.api < 10 then
  clusters.DishwasherAlarm = require "DishwasherAlarm"
  clusters.DishwasherMode = require "DishwasherMode"
  clusters.LaundryWasherControls = require "LaundryWasherControls"
  clusters.LaundryWasherMode = require "LaundryWasherMode"
  clusters.OperationalState = require "OperationalState"
  clusters.RefrigeratorAlarm = require "RefrigeratorAlarm"
  clusters.RefrigeratorAndTemperatureControlledCabinetMode = require "RefrigeratorAndTemperatureControlledCabinetMode"
  clusters.TemperatureControl = require "TemperatureControl"
end

local dishwasher = require("matter-dishwasher")
local laundryWasher = require("matter-laundry-washer")
local refrigerator = require("matter-refrigerator")

local setpoint_limit_device_field = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP",
}

local subscribed_attributes = {
  [capabilities.switch.ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [capabilities.temperatureSetpoint.ID] = {
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.MaxTemperature,
  },
  [capabilities.temperatureLevel.ID] = {
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels,
  },
  [capabilities.operationalState.ID] = {
    clusters.OperationalState.attributes.AcceptedCommandList,
    clusters.OperationalState.attributes.OperationalState,
    clusters.OperationalState.attributes.OperationalError,
  },
  [capabilities.mode.ID] = {
    clusters.DishwasherMode.attributes.SupportedModes,
    clusters.DishwasherMode.attributes.CurrentMode,
    clusters.LaundryWasherMode.attributes.SupportedModes,
    clusters.LaundryWasherMode.attributes.CurrentMode,
    clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes,
    clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode,
  },
  [capabilities.laundryWasherRinseMode.ID] = {
    clusters.LaundryWasherControls.attributes.NumberOfRinses,
    clusters.LaundryWasherControls.attributes.SupportedRinses,
  },
  [capabilities.laundryWasherSpinSpeed.ID] = {
    clusters.LaundryWasherControls.attributes.SpinSpeeds,
    clusters.LaundryWasherControls.attributes.SpinSpeedCurrent,
  },
  [capabilities.contactSensor.ID] = {
    clusters.DishwasherAlarm.attributes.State,
    clusters.RefrigeratorAlarm.attributes.State,
  },
  [capabilities.temperatureMeasurement.ID] = {
    clusters.TemperatureMeasurement.attributes.MeasuredValue
  },
  [capabilities.waterFlowAlarm.ID] = {
    clusters.DishwasherAlarm.attributes.State
  },
  [capabilities.temperatureAlarm.ID] = {
    clusters.DishwasherAlarm.attributes.State
  },
}

local function device_init(driver, device)
  device:subscribe()
end

local function do_configure(driver, device)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
  local tl_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL})
  if dishwasher.can_handle({}, driver, device) then
    local profile_name = "dishwasher"
    if #tn_eps > 0 and #tl_eps > 0 then
      profile_name = profile_name .. "-tn" .. "-tl"
    elseif #tn_eps > 0 then
      profile_name = profile_name .. "-tn"
    elseif #tl_eps > 0 then
      profile_name = profile_name .. "-tl"
    end
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  elseif laundryWasher.can_handle({}, driver, device) then
    local profile_name = "laundry-washer"
    if #tn_eps > 0 and #tl_eps > 0 then
      profile_name = profile_name .. "-tn" .. "-tl"
    elseif #tn_eps > 0 then
      profile_name = profile_name .. "-tn"
    elseif #tl_eps > 0 then
      profile_name = profile_name .. "-tl"
    end
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  elseif refrigerator.can_handle({}, driver, device) then
    local profile_name = "refrigerator-freezer"
    if #tn_eps > 0 and #tl_eps > 0 then
      profile_name = profile_name .. "-tn" .. "-tl"
    elseif #tn_eps > 0 then
      profile_name = profile_name .. "-tn"
    elseif #tl_eps > 0 then
      profile_name = profile_name .. "-tl"
    end
    device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  else
    device.log.warn_with({hub_logs=true}, "Device has not sub driver")
  end

  --Query setpoint limits if needed
  local setpoint_limit_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if #tn_eps ~= 0 then
    if device:get_field(setpoint_limit_device_field.MIN_TEMP) == nil then
      setpoint_limit_read:merge(clusters.TemperatureControl.attributes.MinTemperature:read())
    end
    if device:get_field(setpoint_limit_device_field.MAX_TEMP) == nil then
      setpoint_limit_read:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
    end
  end
  if #setpoint_limit_read.info_blocks ~= 0 then
    device:send(setpoint_limit_read)
  end
end

local function info_changed(driver, device, event, args)
  --Note this is needed because device:subscribe() does not recalculate
  -- the subscribed attributes each time it is run, that only happens at init.
  -- This will change in the 0.48.x release of the lua libs.
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

-- Matter Handlers --
local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

local function temperature_setpoint_attr_handler(driver, device, ib, response)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
  if #tn_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_NUMBER feature"))
    return
  end
  device.log.info_with({ hub_logs = true },
    string.format("temperature_setpoint_attr_handler: %d", ib.data.value))

  local min = device:get_field(setpoint_limit_device_field.MIN_TEMP) or 0
  local max = device:get_field(setpoint_limit_device_field.MAX_TEMP) or 100
  local unit = "C"
  local range = {
    minimum = min,
    maximum = max,
  }
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpointRange({value = range, unit = unit}))

  local temp = ib.data.value / 100.0
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureSetpoint.temperatureSetpoint({value = temp, unit = unit}))
end

local function setpoint_limit_handler(limit_field)
  return function(driver, device, ib, response)
    local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
    if #tn_eps == 0 then
      device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_NUMBER feature"))
      return
    end
    local val = ib.data.value / 100.0
    log.info("Setting " .. limit_field .. " to " .. string.format("%s", val))
    device:set_field(limit_field, val, { persist = true })
  end
end

-- Capability Handlers --
local function handle_switch_on(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local function handle_temperature_setpoint(driver, device, cmd)
  local tn_eps = embedded_cluster_utils.get_endpoints(device, clusters.TemperatureControl.ID, {feature_bitmap = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER})
  if #tn_eps == 0 then
    device.log.warn_with({ hub_logs = true }, string.format("Device does not support TEMPERATURE_NUMBER feature"))
    return
  end
  device.log.info_with({ hub_logs = true },
    string.format("handle_temperature_setpoint: %s", cmd.args.setpoint))

  local value = cmd.args.setpoint
  local _, temp_setpoint = device:get_latest_state(
    cmd.component, capabilities.temperatureSetpoint.ID,
    capabilities.temperatureSetpoint.temperatureSetpoint.NAME,
    0, { value = 0, unit = "C" }
  )
  local min = device:get_field(setpoint_limit_device_field.MIN_TEMP) or 0
  local max = device:get_field(setpoint_limit_device_field.MAX_TEMP) or 100
  if value < min or value > max then
    log.warn(string.format(
      "Invalid setpoint (%s) outside the min (%s) and the max (%s)",
      value, min, max
    ))
    device:emit_event(capabilities.temperatureSetpoint.temperatureSetpoint(temp_setpoint))
    return
  end

  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.TemperatureControl.commands.SetTemperature(device, endpoint_id, utils.round(value * 100.0), nil))
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.TemperatureControl.ID] = {
        [clusters.TemperatureControl.attributes.TemperatureSetpoint.ID] = temperature_setpoint_attr_handler,
        [clusters.TemperatureControl.attributes.MinTemperature.ID] = setpoint_limit_handler(setpoint_limit_device_field.MIN_TEMP),
        [clusters.TemperatureControl.attributes.MaxTemperature.ID] = setpoint_limit_handler(setpoint_limit_device_field.MAX_TEMP),
      },
    }
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.temperatureSetpoint.ID] = {
      [capabilities.temperatureSetpoint.commands.setTemperatureSetpoint.NAME] = handle_temperature_setpoint,
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.temperatureSetpoint,
    capabilities.operationalState.ID,
    capabilities.mode,
    capabilities.laundryWasherRinseMode,
    capabilities.contactSensor,
    capabilities.temperatureMeasurement,
    capabilities.waterFlowAlarm,
    capabilities.temperatureAlarm,
  },
  sub_drivers = {
    dishwasher,
    laundryWasher,
    refrigerator
  }
}

local matter_driver = MatterDriver("matter-appliance", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
