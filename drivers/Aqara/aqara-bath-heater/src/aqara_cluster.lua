-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
local M                   = {}

M.CLUSTER_ID              = 0xFCC0
M.MFG_CODE                = 0x115F -- Lumi/Aqara manufacturer code

M.ATTR_AC_CODE            = 0x024F
M.ATTR_THERMOSTAT_CTRL_SW = 0x02BE
M.ATTR_DND_BEEP           = 0x0256
M.ATTR_DND_TIME           = 0x0257
M.ATTR_NIGHT_LIGHT        = 0x0518

return M
