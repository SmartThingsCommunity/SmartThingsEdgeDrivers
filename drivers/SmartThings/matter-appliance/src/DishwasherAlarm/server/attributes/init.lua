local attr_mt = {}
attr_mt.__attr_cache = {}
attr_mt.__index = function(self, key)
  if attr_mt.__attr_cache[key] == nil then
    local req_loc = string.format("DishwasherAlarm.server.attributes.%s", key)
    local raw_def = require(req_loc)
    local cluster = rawget(self, "_cluster")
    raw_def:set_parent_cluster(cluster)
    attr_mt.__attr_cache[key] = raw_def
  end
  return attr_mt.__attr_cache[key]
end

local DishwasherAlarmServerAttributes = {}

function DishwasherAlarmServerAttributes:set_parent_cluster(cluster)
  self._cluster = cluster
  return self
end

setmetatable(DishwasherAlarmServerAttributes, attr_mt)

return DishwasherAlarmServerAttributes
