-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local st_device = require "st.device"
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.Meter
local Meter = (require "st.zwave.CommandClass.Meter")({ version=4 })
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
local utils = require "st.utils"
local power_consumption = require("aeotec-home-energy-meter-gen8.power_consumption")

local POWER_UNIT_WATT = "W"
local ENERGY_UNIT_KWH = "kWh"

local HEM8_DEVICES = {
  { profile = 'aeotec-home-energy-meter-gen8-3-phase-con', name = 'Aeotec Home Energy Meter 8 Consumption', endpoints = { 1, 3, 5, 7 } },
  { profile = 'aeotec-home-energy-meter-gen8-3-phase-pro', name = 'Aeotec Home Energy Meter 8 Production', child_key = 'pro', endpoints = { 2, 4, 6, 8 } },
  { profile = 'aeotec-home-energy-meter-gen8-sald-con', name = 'Aeotec Home Energy Meter 8 Settled Consumption', child_key = 'sald-con', endpoints = { 9 } },
  { profile = 'aeotec-home-energy-meter-gen8-sald-pro', name = 'Aeotec Home Energy Meter 8 Settled Production', child_key = 'sald-pro', endpoints = { 10 } }
}

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
      power_consumption.emit_power_consumption_report_event(device, { value = event_arguments.value })
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
    added = device_added
  },
  can_handle = require("aeotec-home-energy-meter-gen8.3-phase.can_handle")
}

return aeotec_home_energy_meter_gen8_3_phase
