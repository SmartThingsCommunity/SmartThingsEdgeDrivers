-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local types_mt = {}
types_mt.__types_cache = {}
types_mt.__index = function(self, key)
  if types_mt.__types_cache[key] == nil then
    types_mt.__types_cache[key] = require("embedded_clusters.SmokeCoAlarm.types." .. key)
  end
  return types_mt.__types_cache[key]
end

local SmokeCoAlarmTypes = {}

setmetatable(SmokeCoAlarmTypes, types_mt)

return SmokeCoAlarmTypes

