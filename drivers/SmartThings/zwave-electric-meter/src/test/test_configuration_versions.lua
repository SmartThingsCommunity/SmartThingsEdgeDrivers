-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"

test.register_coroutine_test(
    "V1 requires signed integer",
    function ()
      local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
      local status, msg = pcall(Configuration.Set, Configuration, {parameter_number = 13, size = 1, configuration_value = 255})
      assert(type(msg) == "string")
      assert(not status)
    end
)

test.register_coroutine_test(
    "V3 handles unsigned value",
    function ()
      local Configuration = (require "st.zwave.CommandClass.Configuration")({version=3})
      local status, msg = pcall(Configuration.Set, Configuration, {
        parameter_number = 13,
        size = 1,
        configuration_value = 255,
        format = Configuration.format.UNSIGNED_INTEGER
      })
      assert(type(msg) == "table")
      assert(status)
    end
)

test.register_coroutine_test(
    "V4 handles unsigned value",
    function ()
      local Configuration = (require "st.zwave.CommandClass.Configuration")({version=4})
      local status, msg = pcall(Configuration.Set, Configuration, {
        parameter_number = 13,
        size = 1,
        configuration_value = 255,
        format = Configuration.format.UNSIGNED_INTEGER
      })
      assert(type(msg) == "table")
      assert(status)
    end
)

test.register_coroutine_test(
    "V2 requires signed integer (should error)",
    function ()
      local Configuration = (require "st.zwave.CommandClass.Configuration")({version=2})
      local status, msg = pcall(Configuration.Set, Configuration, {
        parameter_number = 13,
        size = 1,
        configuration_value = 255,
        format = Configuration.format.UNSIGNED_INTEGER
      })
    assert(type(msg) == "string")
    assert(not status)
    end
)

test.register_coroutine_test(
    "V3 handles enum value",
    function ()
      local Configuration = (require "st.zwave.CommandClass.Configuration")({version=3})
      local status, msg = pcall(Configuration.Set, Configuration, {
        parameter_number = 13,
        size = 2,
        configuration_value = 0xFFFF,
        format = Configuration.format.ENUMERATED
      })
      assert(type(msg) == "table")
      assert(status)
    end
)

test.register_coroutine_test(
    "V1 cant handle format argument",
    function ()
      local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
      local status, msg = pcall(Configuration.Set, Configuration, {
        parameter_number = 13,
        size = 1,
        configuration_value = 0xff,
        format = Configuration.format.ENUMERATED
      })
      assert(type(msg) == "string")
      assert(not status)
    end
)

test.register_coroutine_test(
    "V4 handles bitmap value",
    function ()
      local Configuration = (require "st.zwave.CommandClass.Configuration")({version=4})
      local status, msg = pcall(Configuration.Set, Configuration, {
        parameter_number = 13,
        size = 1,
        configuration_value = "\xFE",
        format = Configuration.format.BIT_FIELD
      })
      assert(type(msg) == "table")
      assert(status)
    end
)

test.run_registered_tests()
