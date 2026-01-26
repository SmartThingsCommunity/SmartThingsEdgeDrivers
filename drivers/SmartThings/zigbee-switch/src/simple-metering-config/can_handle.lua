-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local can_handle_simple_metering_config = function(opts, driver, device)
  -- 检查设备是否支持 Simple Metering 集群 (0x0702)
  for _, cluster in ipairs(device.server_clusters) do
    if cluster == 0x0702 then
      return true
    end
  end
  return false
end

return can_handle_simple_metering_config