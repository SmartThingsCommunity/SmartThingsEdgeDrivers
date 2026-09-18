-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function load_helper(api, lazy_loader, legacy_module)
  package.loaded["version"] = { api = api }
  package.loaded["st.zigbee"] = {
    lazy_load_sub_driver = function(name)
      assert(name == legacy_module)
      return lazy_loader
    end,
    lazy_load_sub_driver_v2 = function(name)
      assert(name == legacy_module)
      return lazy_loader
    end,
  }
  package.preload[legacy_module] = function()
    return legacy_module
  end

  return dofile("lazy_load_subdriver.lua")
end

local legacy_module = "test-sub-driver"
local marker = {}

print('Running test "lazy loader supports all API branches"')

local helper = load_helper(16, marker, legacy_module)
assert(helper(legacy_module) == marker)

helper = load_helper(10, marker, legacy_module)
assert(helper(legacy_module) == marker)

helper = load_helper(8, marker, legacy_module)
assert(helper(legacy_module) == legacy_module)

package.preload[legacy_module] = nil
package.loaded["version"] = nil
package.loaded["st.zigbee"] = nil

print("PASSED")
print("Passed 1 of 1 tests")
