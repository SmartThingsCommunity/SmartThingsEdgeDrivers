-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

--ZCL
local zcl_clusters = require "st.zigbee.zcl.clusters"
local Basic               = zcl_clusters.Basic
--Capability
local capabilities = require "st.capabilities"
local battery = capabilities.battery
local valve = capabilities.valve
local powerSource = capabilities.powerSource
local refresh = capabilities.refresh

local function device_added(self, device)
  device:refresh()
end

local zigbee_valve_driver_template = {
  supported_capabilities = {
    valve,
    battery,
    powerSource,
    refresh
  },
  cluster_configurations = {
    [powerSource.ID] = {
      {
        cluster = Basic.ID,
        attribute = Basic.attributes.PowerSource.ID,
        minimum_interval = 5,
        maximum_interval = 600,
        data_type = Basic.attributes.PowerSource.base_type,
        configurable = true
      }
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  sub_drivers = require("sub_drivers"),
  health_check = false,
}

defaults.register_for_default_handlers(zigbee_valve_driver_template, zigbee_valve_driver_template.supported_capabilities)
local zigbee_valve = ZigbeeDriver("zigbee-valve", zigbee_valve_driver_template)
zigbee_valve:run()
