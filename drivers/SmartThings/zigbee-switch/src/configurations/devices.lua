-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local ColorControl = clusters.ColorControl
local IASZone = clusters.IASZone
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local Alarms = clusters.Alarms
local BasicInput = clusters.BasicInput
local OnOff      = clusters.OnOff
local constants = require "st.zigbee.constants"
local data_types = require "st.zigbee.data_types"

local devices = {
  IKEA_RGB_BULB = {
    FINGERPRINTS = {
      { mfr = "IKEA of Sweden", model = "TRADFRI bulb E27 CWS opal 600lm" },
      { mfr = "IKEA of Sweden", model = "TRADFRI bulb E26 CWS opal 600lm" }
    },
    CONFIGURATION = {
      {
        cluster = ColorControl.ID,
        attribute = ColorControl.attributes.CurrentX.ID,
        minimum_interval = 1,
        maximum_interval = 3600,
        data_type = ColorControl.attributes.CurrentX.base_type,
        reportable_change = 16
      },
      {
        cluster = ColorControl.ID,
        attribute = ColorControl.attributes.CurrentY.ID,
        minimum_interval = 1,
        maximum_interval = 3600,
        data_type = ColorControl.attributes.CurrentY.base_type,
        reportable_change = 16
      }
    }
  },
  SENGLED_BULB_WITH_MOTION_SENSOR = {
    FINGERPRINTS = {
      { mfr = "sengled", model = "E13-N11" }
    },
    CONFIGURATION = {
      {
        cluster = IASZone.ID,
        attribute = IASZone.attributes.ZoneStatus.ID,
        minimum_interval = 30,
        maximum_interval = 300,
        data_type = IASZone.attributes.ZoneStatus.base_type
      }
    },
    IAS_ZONE_CONFIG_METHOD = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE
  },
  FRIENT_SWITCHES = {
    FINGERPRINTS = {
      { mfr = "frient A/S", model = "SPLZB-131" },
      { mfr = "frient A/S", model = "SPLZB-132" },
      { mfr = "frient A/S", model = "SPLZB-134" },
      { mfr = "frient A/S", model = "SPLZB-137" },
      { mfr = "frient A/S", model = "SPLZB-141" },
      { mfr = "frient A/S", model = "SPLZB-142" },
      { mfr = "frient A/S", model = "SPLZB-144" },
      { mfr = "frient A/S", model = "SPLZB-147" },
      { mfr = "frient A/S", model = "SMRZB-143" },
      { mfr = "frient A/S", model = "SMRZB-153" },
      { mfr = "frient A/S", model = "SMRZB-332" },
      { mfr = "frient A/S", model = "SMRZB-342" }
    },
    CONFIGURATION = {
      {
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.RMSVoltage.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = ElectricalMeasurement.attributes.RMSVoltage.base_type,
        reportable_change = 1
      },{
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.RMSCurrent.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = ElectricalMeasurement.attributes.RMSCurrent.base_type,
        reportable_change = 1
      },{
        cluster = ElectricalMeasurement.ID,
        attribute = ElectricalMeasurement.attributes.ActivePower.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = ElectricalMeasurement.attributes.ActivePower.base_type,
        reportable_change = 1
      },{
        cluster = SimpleMetering.ID,
        attribute = SimpleMetering.attributes.InstantaneousDemand.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = SimpleMetering.attributes.InstantaneousDemand.base_type,
        reportable_change = 1
      },{
        cluster = SimpleMetering.ID,
        attribute = SimpleMetering.attributes.CurrentSummationDelivered.ID,
        minimum_interval = 5,
        maximum_interval = 3600,
        data_type = SimpleMetering.attributes.CurrentSummationDelivered.base_type,
        reportable_change = 1
      },{
        cluster = Alarms.ID,
        attribute = Alarms.attributes.AlarmCount.ID,
        minimum_interval = 1,
        maximum_interval = 3600,
        data_type = Alarms.attributes.AlarmCount.base_type,
        reportable_change = 1,
      },
    }
  },
  FRIENT_IO_MODULE = {
    FINGERPRINTS = {
      { mfr = "frient A/S", model = "IOMZB-110" }
    },
    CONFIGURATION = {
      {
        cluster = OnOff.ID,
        attribute = OnOff.attributes.OnTime.ID,
        minimum_interval = 10,
        maximum_interval = 600,
        reportable_change = 1,
        data_type = OnOff.attributes.OnOff.base_type,
        configurable = true,
        monitored = true
      },
      {
        cluster = OnOff.ID,
        attribute = OnOff.attributes.OffWaitTime.ID,
        minimum_interval = 10,
        maximum_interval = 600,
        reportable_change = 1,
        data_type = OnOff.attributes.OffWaitTime.base_type,
        configurable = true,
        monitored = true
      },
      {
        cluster = BasicInput.ID,
        attribute = BasicInput.attributes.PresentValue.ID,
        minimum_interval = 10,
        maximum_interval = 600,
        reportable_change = 0,
        data_type = BasicInput.attributes.PresentValue.base_type,
        configurable = true,
        monitored = true
      },
      {
        cluster = BasicInput.ID,
        attribute = BasicInput.attributes.Polarity.ID,
        minimum_interval = 10,
        maximum_interval = 600,
        reportable_change = 0,
        data_type = BasicInput.attributes.Polarity.base_type,
        configurable = true,
        monitored = true
      },
      {
        cluster = BasicInput.ID,
        attribute = 0x8000, -- IASActivation
        minimum_interval = 10,
        maximum_interval = 600,
        reportable_change = 0,
        data_type = data_types.Uint16,
        mfg_code = 0x1015,
        configurable = true,
        monitored = true
      }
    }
  }
}

return devices