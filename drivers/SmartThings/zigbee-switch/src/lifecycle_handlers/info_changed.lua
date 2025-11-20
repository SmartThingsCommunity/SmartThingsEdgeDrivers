-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(self, device, event, args)
  local preferences = require "preferences"
  preferences.update_preferences(self, device, args)
end
