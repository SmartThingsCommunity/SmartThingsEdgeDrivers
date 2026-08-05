-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local utils = {}

utils.epoch_to_iso8601 = function(time)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

return utils