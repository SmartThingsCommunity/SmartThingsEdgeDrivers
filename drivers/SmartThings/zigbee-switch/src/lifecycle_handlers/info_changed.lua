return function(self, device, event, args)
  local preferences = require "preferences"
  preferences.update_preferences(self, device, args)
end
