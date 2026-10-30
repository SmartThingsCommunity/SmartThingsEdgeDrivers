-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- Device preference (Z-Wave Configuration parameter) definitions for the
--- Heatit Z-TRM6 thermostat. Parameter numbers above 400 are handled as
--- special actions rather than plain Configuration:Set/Get (see init.lua),
--- and parameter numbers >= 202 are Association / MultiChannelAssociation
--- groups (last digits of the parameter number encode the group id).
local HEATIT_ZTRM6_PARAMETERS = {
  disableButtons = {parameter_number = 1, size = 1},
  sensorMode = {parameter_number = 2, size = 1},
  floorSensorType = {parameter_number = 3, size = 1},
  aLo = {parameter_number = 4, size = 2},
  fLo = {parameter_number = 5, size = 2},
  eLo = {parameter_number = 6, size = 2},
  aHi = {parameter_number = 7, size = 2},
  fHi = {parameter_number = 8, size = 2},
  eHi = {parameter_number = 9, size = 2},

  roomSensorCalibration = {parameter_number = 10, size = 1},
  floorSensorCalibration = {parameter_number = 11, size = 1},
  externSensorCalibration = {parameter_number = 12, size = 1},

  regulationMode = {parameter_number = 13, size = 1},
  tempHysteresis = {parameter_number = 14, size = 1},
  tempDisplay = {parameter_number = 15, size = 1},
  displayBrightnessActive = {parameter_number = 16, size = 1},
  displayBrightnessDimmed = {parameter_number = 17, size = 1},
  tempReportInterval = {parameter_number = 18, size = 2},
  tempReportHysteresis = {parameter_number = 19, size = 1},
  meterReportInterval = {parameter_number = 20, size = 2},
  actionAfterError = {parameter_number = 21, size = 2},

  comfortSetpoint = {parameter_number = 22, size = 2},
  coolingSetpoint = {parameter_number = 23, size = 2},
  ecoSetpoint = {parameter_number = 24, size = 2},
  regulatorLevel = {parameter_number = 25, size = 1},

  updateInterval = {parameter_number = 26, size = 2},
  operationMode = {parameter_number = 27, size = 1},
  openWindowDetection = {parameter_number = 28, size = 1},
  loadSize = {parameter_number = 29, size = 1},

  assocGroup2OnOff = {parameter_number = 302, size = 35},
  assocGroup3Setpoint = {parameter_number = 303, size = 35},
  assocGroup4Mode = {parameter_number = 304, size = 35},

  showFloorTemp = {parameter_number = 901, size = 1},
  testFunction = {parameter_number = 999, size = 1},
}

return HEATIT_ZTRM6_PARAMETERS
