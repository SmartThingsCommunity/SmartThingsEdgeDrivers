-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_ezviz_button = function(opts, driver, device)
  local support_button_cluster = device:supports_server_cluster(EZVIZ_PRIVATE_BUTTON_CLUSTER)
  local support_standard_cluster = device:supports_server_cluster(EZVIZ_PRIVATE_STANDARD_CLUSTER)
  if device:get_manufacturer() == EZVIZ_MFR and support_button_cluster and support_standard_cluster then
    return true, require("ezviz")
  end
end

return is_ezviz_button
