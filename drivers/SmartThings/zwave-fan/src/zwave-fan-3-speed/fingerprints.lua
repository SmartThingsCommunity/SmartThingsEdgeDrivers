-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local FAN_3_SPEED_FINGERPRINTS = {
  {mfr = 0x001D, prod = 0x1001, model = 0x0334}, -- Leviton 3-Speed Fan Controller
  {mfr = 0x0063, prod = 0x4944, model = 0x3034}, -- GE In-Wall Smart Fan Control
  {mfr = 0x0063, prod = 0x4944, model = 0x3131}, -- GE In-Wall Smart Fan Control
  {mfr = 0x0039, prod = 0x4944, model = 0x3131}, -- Honeywell Z-Wave Plus In-Wall Fan Speed Control
  {mfr = 0x0063, prod = 0x4944, model = 0x3337}, -- GE In-Wall Smart Fan Control
}

return FAN_3_SPEED_FINGERPRINTS
