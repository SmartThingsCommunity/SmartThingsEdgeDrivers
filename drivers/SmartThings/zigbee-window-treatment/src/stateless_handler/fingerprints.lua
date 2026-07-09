-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Brand-specific configuration for window treatment devices
-- Supports statelessWindowShadeLevelStep capability

local FINGERPRINTS = {
  -- invert_level = true:The level values on the device side and the driver side need to be inverted.
  {
    name = "aqara",
    mfr = "LUMI",
    models = { "lumi.curtain", "lumi.curtain.v1", "lumi.curtain.aq2" },
    invert_level = false,
  },
  {
    name = "vimar",
    mfr = "Vimar",
    models = { "Window_Cov_v1.0", "Window_Cov_Module_v1.0" },
    invert_level = true,
  },
  {
    name = "somfy",
    mfr = "SOMFY",
    models = { "Glydea Ultra Curtain", "Sonesse 30 WF Roller", "Sonesse 40 Roller" },
    invert_level = true,
  },
  {
    name = "invert-lift-percentage",
    mfrs = { "IKEA of Sweden", "Smartwings", "Insta GmbH" },
    models = {},
    invert_level = true,
  },
  {
    name = "yoolax",
    mfrs = { "Yookee", "yooksmart" },
    models = { "D10110" },
    invert_level = true,
  },
  -- use_level_cluster = true: Use Level cluster instead of WindowCovering
  -- Level cluster uses 0-254 range, converted from percentage: level_value = math.floor(percentage / 100.0 * 254)
  {
    name = "feibit",
    mfr = "Feibit Co.Ltd",
    models = { "FTB56-ZT218AK1.6", "FTB56-ZT218AK1.8" },
    use_level_cluster = true,
  },
  {
    name = "axis",
    mfr = "AXIS",
    models = {},
    use_level_cluster = true,
  },
  -- Standard devices (no special handling needed)
  -- Use WindowCovering.GoToLiftPercentage with 0-100 percentage
  {
    name = "rooms-beautiful",
    mfr = "Rooms Beautiful",
    models = { "C001" },
    invert_level = true,
  },
  {
    name = "hanssem",
    mfr = "_TZE204_fzbskaga",
    models = { "TS0601" },
    use_tuya_cluster = true,
  },
  {
    name = "screen-innovations",
    mfr = "Screen Innovations",
    models = { "WM25/L-Z" },
  },
  {
    name = "sombra-shades",
    mfr = "Sombra Shades",
    models = { "SOMBRA/Z-M" },
  },
}

return FINGERPRINTS
