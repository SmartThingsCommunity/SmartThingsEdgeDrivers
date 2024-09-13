local event_mt = {}
event_mt.__event_cache = {}
event_mt.__index = function(self, key)
  if event_mt.__event_cache[key] == nil then
    local req_loc = string.format("ElectricalPowerMeasurement.server.events.%s", key)
    local raw_def = require(req_loc)
    local cluster = rawget(self, "_cluster")
    raw_def:set_parent_cluster(cluster)
    event_mt.__event_cache[key] = raw_def
  end
  return event_mt.__event_cache[key]
end

local ElectricalPowerMeasurementEvents = {}

function ElectricalPowerMeasurementEvents:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

setmetatable(ElectricalPowerMeasurementEvents, event_mt)

return ElectricalPowerMeasurementEvents

