-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local cluster_base = require "st.matter.cluster_base"

local SubscriptionMap = {
  subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.switchLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.LevelControl.attributes.MaxLevel,
      clusters.LevelControl.attributes.MinLevel,
    },
    [capabilities.motionSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy,
    },
    [capabilities.illuminanceMeasurement.ID] = {
      clusters.IlluminanceMeasurement.attributes.MeasuredValue
    },
    [capabilities.windowShadeLevel.ID] = {
      clusters.WindowCovering.attributes.OperationalStatus,
      clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths
    }
  },
  subscribed_events = {
    [capabilities.button.ID] = {
      clusters.Switch.events.MultiPressComplete,
      clusters.Switch.events.LongPress
    }
  },
  component_map = {
    [capabilities.switch.ID] = { main = 3 },
    [capabilities.switchLevel.ID] = { main = 4 },
    [capabilities.windowShadeLevel.ID] = { main = 5 },
  }
}

return SubscriptionMap