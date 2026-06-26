-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--The number of children determines the number of sub-devices to be created. Each sub-device has the capability to switch between a switch and a button.
--The number of buttons determines how many buttons devices will be created.
--The driver supports a series of device combinations, such as 4+4, 3+3, 2+2, 4+0, etc., of switch and button type products.
return {
  { mfr = "FIRSTLED", model = "M4S4BAC", children = 4, buttons = 4, child_profile = "switch-wireless" },
  { mfr = "FIRSTLED", model = "P3S3BAC", children = 3, buttons = 3, child_profile = "switch-wireless" }
}
