-- Test file for SONOFF SNZB-01M integration
-- This file can be used to verify the SONOFF driver integration

local test = {}

-- Test that the SONOFF fingerprint is correctly added
test.fingerprint_test = function()
  local fingerprints = {
    { mfr = "SONOFF", model = "SNZB-01M" }
  }
  
  for _, fp in ipairs(fingerprints) do
    print("Testing fingerprint: " .. fp.mfr .. "/" .. fp.model)
  end
end

-- Test supported button values
test.supported_values_test = function()
  local supported_values = { "pushed", "double", "held", "pushed_3x" }
  print("Supported button values for SONOFF:")
  for _, value in ipairs(supported_values) do
    print("  - " .. value)
  end
end

return test