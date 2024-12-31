--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--
--  ===============================================================================================
--  Up to date API references are available here:
--  https://developers.meethue.com/develop/hue-api-v2/
--
--  Improvements to be made:
--
--  ===============================================================================================
local logjam = require "logjam"
logjam.enable_passthrough()
logjam.inject_global()

local log = require "log"

local Driver = require "st.driver"
local st_utils = require "st.utils"
-- trick to fix the VS Code Lua Language Server typechecking
---@type fun(val: any?, name: string?, multi_line: boolean?): string
st_utils.stringify_table = st_utils.stringify_table

local Discovery = require "disco"
local HueDriverTemplate = require "hue_driver_template"

--- @type HueDriver
local hue = Driver("hue", HueDriverTemplate.new_driver_template())

if hue.datastore["bridge_netinfo"] == nil then
  hue.datastore["bridge_netinfo"] = {}
end

if hue.datastore["dni_to_device_id"] == nil then
  hue.datastore["dni_to_device_id"] = {}
end


if hue.datastore["api_keys"] == nil then
  hue.datastore["api_keys"] = {}
end

Discovery.api_keys = setmetatable({}, {
  __newindex = function (self, k, v)
    assert(
      type(v) == "string" or type(v) == "nil",
      string.format("Attempted to store value of type %s in application_key table which expects \"string\" types",
        type(v)
      )
    )
    hue.datastore.api_keys[k] = v
    hue.datastore:save()
    if hue.datastore.commit then
      -- Because we never actually store keys on the metatable target itself,
      -- __newindex is invoked for ever mutation; values for a new key, updating
      -- the value for an existing key, and setting an existing key to `nil` will
      -- all hit this path.
      local commit_result = table.pack(hue.datastore:commit())
      log.trace(st_utils.stringify_table(commit_result, "[DataStoreCommit] commit result", true))
    end
  end,
  __index = function(self, k)
    return hue.datastore.api_keys[k]
  end
})

-- Kick off a scan right away to attempt to populate some information
hue:call_with_delay(3, Discovery.do_mdns_scan, "Philips Hue mDNS Initial Scan")

-- re-scan every minute
local MDNS_SCAN_INTERVAL_SECONDS = 600
hue:call_on_schedule(MDNS_SCAN_INTERVAL_SECONDS, Discovery.do_mdns_scan, "Philips Hue mDNS Scan Task")

log.info("Starting Hue driver")
hue:run()
log.warn("Hue driver exiting")
