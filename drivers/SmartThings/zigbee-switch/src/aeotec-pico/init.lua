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

local device_management = require "st.zigbee.device_management"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local st_device = require "st.device"
local utils = require "st.utils"

-- Clusters
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local DeviceTemperatureConfiguration = clusters.DeviceTemperatureConfiguration
local Alarm= clusters.Alarms
local Scenes = clusters.Scenes

-- Variables
local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local VOLTAGE_MULTIPLIER_KEY = "voltage_multiplier"
local VOLTAGE_DIVISOR_KEY = "voltage_divisor"
local CURRENT_MULTIPLIER_KEY = "current_multiplier"
local CURRENT_DIVISOR_KEY = "current_divisor"

local AEOTEC_PICO_FINGERPRINTS = {
  { mfr = "AEOTEC", model = "ZGA002", children = 0 },
  { mfr = "AEOTEC", model = "ZGA003", children = 1 }
}

local SCENE_ID_BUTTON_EVENT_MAP = {
  [0x01] = capabilities.button.button.pushed,
  [0x02] = capabilities.button.button.double,
  [0x03] = capabilities.button.button.pushed_3x,
  [0x04] = capabilities.button.button.held,
  [0x05] = capabilities.button.button.up,
  [0x06] = capabilities.button.button.pushed,
  [0x07] = capabilities.button.button.double,
  [0x08] = capabilities.button.button.pushed_3x,
  [0x09] = capabilities.button.button.held,
  [0x0A] = capabilities.button.button.up
}

--- handler for attribute fields
local function set_attribute_as_field_name_handler(field_name)
  return function(driver, device, key_type, zb_rx)
    local raw_value = key_type.value
    device:set_field(field_name, raw_value, { persist = true })
  end
end

local function is_aeotec_pico_switch(opts, driver, device)
  for _, fingerprint in ipairs(AEOTEC_PICO_FINGERPRINTS) do
    if device:get_manufacturer() == nil and device:get_model() == fingerprint.model then
      return true
    elseif device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function get_children_amount(device)
  for _, fingerprint in ipairs(AEOTEC_PICO_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.children
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function emit_power_consumption_report_event(device, value, channel)
  -- powerConsumptionReport report interval
  local current_time = os.time()
  local last_time = device:get_field(LAST_REPORT_TIME) or 0
  local next_time = last_time + 60 * 15 -- 15 mins, the minimum interval allowed between reports
  if current_time < next_time then
    return
  end
  device:set_field(LAST_REPORT_TIME, current_time, { persist = true })
  local raw_value = value.value -- 'Wh'

  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state('main', capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event_for_endpoint(channel, capabilities.powerConsumptionReport.powerConsumption({
    energy = raw_value,
    deltaEnergy = delta_energy
  }))
end

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value -- 'Wh'
  -- energyMeter
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    capabilities.energyMeter.energy({ value = raw_value / 1000, unit = "kWh" }))
  -- powerConsumptionReport
  emit_power_consumption_report_event(device, { value = raw_value }, zb_rx.address_header.src_endpoint.value) -- the unit of these values should be 'Wh'
end

local function power_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value / 10 -- 'W'
  -- powerMeter
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

local function current_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local multiplier = device:get_field(CURRENT_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(CURRENT_DIVISOR_KEY) or 1000

  raw_value = raw_value * multiplier / divisor

  -- currentMeasurement
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    capabilities.currentMeasurement.current({ value = raw_value, unit = "A" }))
end

local function voltage_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local multiplier = device:get_field(VOLTAGE_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(VOLTAGE_DIVISOR_KEY) or 10

  raw_value = raw_value * multiplier / divisor

  -- voltageMeasurement
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
    capabilities.voltageMeasurement.voltage({ value = raw_value, unit = "V" }))
end

local refresh = function(driver, device, cmd)
  device:refresh()
  local attributes = {
    ElectricalMeasurement.attributes.RMSCurrent,
    ElectricalMeasurement.attributes.RMSVoltage,
    Alarm.attributes.AlarmCount
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local alarm_handler = function(driver, device, zb_rx)
  if (zb_rx.body.zcl_body.alarm_code.value == 0x86) then
    device:emit_event(capabilities.temperatureAlarm.temperatureAlarm('heat'))
  else
    device:emit_event(capabilities.temperatureAlarm.temperatureAlarm('cleared'))
  end
end

local temperature_handler = function(driver, device, value, zb_rx)
  local ep = zb_rx.address_header.src_endpoint.value or 0x01
  local temp_alarm = device:get_latest_state("main", capabilities.temperatureAlarm.ID,
    capabilities.temperatureAlarm.temperatureAlarm.NAME, 'cleared')
  -- handle temperature alarm if neccessary
  if value.value < 70 and temp_alarm == 'heat' then
    device:send(Alarm.server.commands.ResetAllAlarms(device):to_endpoint(ep))
    device:send(Alarm.attributes.AlarmCount:read(device):to_endpoint(ep))
    device:emit_event(capabilities.temperatureAlarm.temperatureAlarm('cleared'), ep)
  end
end

local scenes_cluster_handler = function(driver, device, zb_rx)
  local ep = 0x01
  if device:get_model() == "ZGA002" then
    ep = zb_rx.address_header.src_endpoint.value == 0x03 and 0x08 or 0x07
  else
    ep = zb_rx.address_header.src_endpoint.value == 0x04 and 0x02 or ep
  end

  local button_event = SCENE_ID_BUTTON_EVENT_MAP[zb_rx.body.zcl_body.scene_id.value]

  local additional_fields = {
    state_change = true
  }
  local event = button_event(additional_fields)

  device:emit_event_for_endpoint(ep, event)
end

local device_added = function(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    local children_amount = get_children_amount(device)
    if not (device.child_ids and utils.table_size(device.child_ids) ~= 0) then
      for i = 2, children_amount+1, 1 do
        local device_name_without_number = device.label
        local name = string.format("%s %s", device_name_without_number, '(CH'.. i ..')')
        if find_child(device, i) == nil then
          local metadata = {
            type = "EDGE_CHILD",
            label = name,
            profile = "switch-scenes-power-energy-consumption-report-aeotec",
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%02X", i),
            vendor_provided_label = name,
          }
          driver:try_create_device(metadata)
        end
      end
    end
  end

  if device:get_model() == "ZGA002" then
    device:try_update_metadata({ profile = "aeotec-pico-switch-two-button-control" })
  end

  device.thread:call_with_delay(3, function()
    if device.profile.components.main.capabilities["button"] ~= nil then
      device:emit_event(
        capabilities.button.supportedButtonValues({ "pushed", "double", "pushed_3x", "held", "up" },
          { visibility = { displayed = false } }))
      device:emit_event(capabilities.button.numberOfButtons({ value = 1 },
        { visibility = { displayed = false } }))
    else
      for _, component in pairs(device.profile.components) do
        if component["id"]:match("button(%d)") then
          device:emit_component_event(component,
            capabilities.button.supportedButtonValues({ "pushed", "double", "pushed_3x", "held", "up" },
              { visibility = { displayed = false } }))
          device:emit_component_event(component,
            capabilities.button.numberOfButtons({ value = 2 }, { visibility = { displayed = false } }))
        end
      end
    end
  end)

  refresh(driver, device)
end

local do_configure = function(driver, device)

  device:send(device_management.build_bind_request(device, Alarm.ID, driver.environment_info.hub_zigbee_eui))
  device:send(Alarm.attributes.AlarmCount:configure_reporting(device, 0, 21600, 0))

  device:send(device_management.build_bind_request(device, DeviceTemperatureConfiguration.ID,
    driver.environment_info.hub_zigbee_eui))
  device:send(DeviceTemperatureConfiguration.attributes.CurrentTemperature:configure_reporting(device, 1, 65534, 1))

  for endpoint = 1, 2 do
    device:send(device_management.build_bind_request(device, SimpleMetering.ID, driver.environment_info.hub_zigbee_eui, endpoint))
    device:send(device_management.build_bind_request(device, ElectricalMeasurement.ID, driver.environment_info.hub_zigbee_eui, endpoint))
    device:send(SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(device, 5, 3600, 1):to_endpoint(endpoint))
    device:send(ElectricalMeasurement.attributes.ActivePower:configure_reporting(device, 10, 3600, 1):to_endpoint(endpoint))
    device:send(ElectricalMeasurement.attributes.RMSCurrent:configure_reporting(device, 10, 3600, 10):to_endpoint(endpoint))
    device:send(ElectricalMeasurement.attributes.RMSVoltage:configure_reporting(device, 10, 3600, 10):to_endpoint(endpoint))
  end

  for endpoint = 1, 4 do
    device:send(device_management.build_bind_request(device, Scenes.ID, driver.environment_info.hub_zigbee_eui, endpoint))
  end

  device:emit_event(capabilities.temperatureAlarm.temperatureAlarm('cleared'))
end

local function endpoint_to_component(device, ep)
  if ep == 8 and device.profile.components["button2"] ~= nil then
    return "button2"
  elseif ep == 7 and device.profile.components["button1"] ~= nil then
    return "button1"
  else
    return "main"
  end
end

local device_init = function(driver, device, event)

  if device:get_model() == "ZGA002" then
    device:set_endpoint_to_component_fn(endpoint_to_component)
  end

  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local aeotec_pico_switch = {
  NAME = "Aeotec Pico Switch",
  supported_capabilities = {
    capabilities.switch,
    capabilities.button,
    capabilities.voltageMeasurement,
    capabilities.currentMeasurement,
    capabilities.temperatureAlarm
  },
  zigbee_handlers = {
    cluster = {
      [Alarm.ID] = {
        [Alarm.client.commands.Alarm.ID] = alarm_handler
      },
      [Scenes.ID] = {
        [Scenes.server.commands.RecallScene.ID] = scenes_cluster_handler
      }
    },
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.RMSCurrent.ID] = current_meter_handler,
        [ElectricalMeasurement.attributes.ACCurrentDivisor.ID] = set_attribute_as_field_name_handler(CURRENT_DIVISOR_KEY),
        [ElectricalMeasurement.attributes.ACCurrentMultiplier.ID] = set_attribute_as_field_name_handler(CURRENT_MULTIPLIER_KEY),
        [ElectricalMeasurement.attributes.RMSVoltage.ID] = voltage_meter_handler,
        [ElectricalMeasurement.attributes.ACVoltageDivisor.ID] = set_attribute_as_field_name_handler(VOLTAGE_DIVISOR_KEY),
        [ElectricalMeasurement.attributes.ACVoltageMultiplier.ID] = set_attribute_as_field_name_handler(VOLTAGE_MULTIPLIER_KEY),
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      },
      [DeviceTemperatureConfiguration.ID] = {
        [DeviceTemperatureConfiguration.attributes.CurrentTemperature.ID] = temperature_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure
  },
  can_handle = is_aeotec_pico_switch
}

return aeotec_pico_switch
