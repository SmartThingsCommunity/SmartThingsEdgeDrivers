-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

return function(_, _, device)
  if device ~= nil and device:get_manufacturer() == "_TZ3000_hurauima"
      and device:get_model() == "TS0726" then
    return true, require("zemismart-kes606")
  end
  return false
end
