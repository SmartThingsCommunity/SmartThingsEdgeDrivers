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

local st_device = require "st.device"
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version=4 })
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
local utils = require "st.utils"

local AEOTEC_HOME_ENERGY_METER_GEN8_FINGERPRINTS = {
  { mfr = 0x0371, prod = 0x0003, model = 0x0034 }, -- HEM Gen8 3 Phase EU
  { mfr = 0x0371, prod = 0x0102, model = 0x0034 }  -- HEM Gen8 3 Phase AU
}

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local POWER_UNIT_WATT = "W"
local ENERGY_UNIT_KWH = "kWh"

local HEM8_DEVICES = {
  { profile = 'aeotec-home-energy-meter-gen8-3-phase-con', name = 'Aeotec Home Energy Meter 8 Consumption', endpoints = { 1, 3, 5, 7 } },
  { profile = 'aeotec-home-energy-meter-gen8-3-phase-pro', name = 'Aeotec Home Energy Meter 8 Production', child_key = 'pro', endpoints = { 2, 4, 6, 8 } },
  { profile = 'aeotec-home-energy-meter-gen8-sald-con', name = 'Aeotec Home Energy Meter 8 Settled Consumption', child_key = 'sald-con', endpoints = { 9 } },
  { profile = 'aeotec-home-energy-meter-gen8-sald-pro', name = 'Aeotec Home Energy Meter 8 Settled Production', child_key = 'sald-pro', endpoints = { 10 } }
}

local function can_handle_aeotec_meter_gen8_3_phase(opts, driver, device, ...)
  for _, fingerprint in ipairs(AEOTEC_HOME_ENERGY_METER_GEN8_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function find_hem8_child_device_key_by_endpoint(endpoint)
  for _, child in ipairs(HEM8_DEVICES) do
    if child.endpoints then
      for _, e in ipairs(child.endpoints) do
        if e == endpoint then
          return child.child_key
        end
      end
    end
  end
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
  local raw_value = value.value * 1000 -- 'Wh'

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

local function meter_report_handler(driver, device, cmd, zb_rx)
  local endpoint = cmd.src_channel
  local device_to_emit_with = device
  local child_device_key = find_hem8_child_device_key_by_endpoint(endpoint);
  local child_device = device:get_child_by_parent_assigned_key(child_device_key)

  if(child_device) then
    device_to_emit_with = child_device
  end

  if cmd.args.scale == Meter.scale.electric_meter.KILOWATT_HOURS then
    local event_arguments = {
      value = cmd.args.meter_value,
      unit = ENERGY_UNIT_KWH
    }
    -- energyMeter
    device_to_emit_with:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.energyMeter.energy(event_arguments)
    )

    if endpoint == 9 then
      -- powerConsumptionReport
      emit_power_consumption_report_event(device_to_emit_with, { value = event_arguments.value }, endpoint)
    end
  elseif cmd.args.scale == Meter.scale.electric_meter.WATTS then
    local event_arguments = {
      value = cmd.args.meter_value,
      unit = POWER_UNIT_WATT
    }
    -- powerMeter
    device_to_emit_with:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.powerMeter.power(event_arguments)
    )
  end
end

local function do_refresh(self, device)
  for _, d in ipairs(HEM8_DEVICES) do
    for _, endpoint in ipairs(d.endpoints) do
      device:send(Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS}, {dst_channels = {endpoint}}))
      device:send(Meter:Get({scale = Meter.scale.electric_meter.WATTS}, {dst_channels = {endpoint}}))
    end
  end
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("clamp(%d)")
  return { ep_num and tonumber(ep_num) }
end

local function endpoint_to_component(device, ep)
  local meter_comp = string.format("clamp%d", ep)
  if device.profile.components[meter_comp] ~= nil then
    return meter_comp
  else
    return "main"
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local function device_added(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE and not (device.child_ids and utils.table_size(device.child_ids) ~= 0) then
    for i, hem8_child in ipairs(HEM8_DEVICES) do
      if(hem8_child["child_key"]) then
        local name = hem8_child.name
        local metadata = {
          type = "EDGE_CHILD",
          label = name,
          profile = hem8_child.profile,
          parent_device_id = device.id,
          parent_assigned_child_key = hem8_child.child_key,
          vendor_provided_label = name
        }
        driver:try_create_device(metadata)
      end
    end
  end
  do_refresh(driver, device)
end

local aeotec_home_energy_meter_gen8_3_phase = {
  NAME = "Aeotec Home Energy Meter Gen8",
  supported_capabilities = {
    capabilities.powerConsumptionReport
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zwave_handlers = {
    [cc.METER] = {
      [Meter.REPORT] = meter_report_handler
    }
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init
  },
  can_handle = can_handle_aeotec_meter_gen8_3_phase
}

return aeotec_home_energy_meter_gen8_3_phase
