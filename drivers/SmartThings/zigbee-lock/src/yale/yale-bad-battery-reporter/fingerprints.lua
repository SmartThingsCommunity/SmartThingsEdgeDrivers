-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local BAD_YALE_LOCK_FINGERPRINTS = {
  { mfr = "Yale", model = "YRD220/240 TSDB" },
  { mfr = "Yale", model = "YRL220 TS LL" },
  { mfr = "Yale", model = "YRD210 PB DB" },
  { mfr = "Yale", model = "YRL210 PB LL" },
  { mfr = "ASSA ABLOY iRevo", model = "c700000202" },
  { mfr = "ASSA ABLOY iRevo", model = "06ffff2027" }
}

return BAD_YALE_LOCK_FINGERPRINTS
