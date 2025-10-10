-- Copyright (c) 2025 SmartThings, Inc.  All rights reserved.
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

--- @class st.utils.lazy_require
---
--- This module allows one to lazily load a named module.
---
--- For example, to load some module, "st.my_module", replace
---
--- @usage
--- local my_module = require "st.my_module"
---
--- with
---
--- @usage
--- local my_module = lazy_require "st.my_module"
---
--- Then, the module will only be loaded in when it is either indexed (like ``my_module.hello``),
--- called (like ``my_module("howdy")``), or participates in field assignment (like
--- ``my_module["hi"] = 123``).
---
--- After the module is either indexed or called, there will no longer be any string references to
--- the module, so it will be GC'd if the ``package.loaded`` table is in ``"v"`` mode, which is the
--- case for us at the time of writing.
---
--- On the other hand, after field assignment, the module will be cached so that it cannot be GC'd
--- immediately after.
---
--- To always cache after the first index or call, append ``{ caching = true }`` to the construction
--- of the ``lazy_require``. For example,
---
--- @usage
--- local my_module = lazy_require("st.my_module", { caching = true })
---
--- Returned ``lazy_require``s also have a member function ``load`` which can be used to manually
--- load the module. You can call it like ``my_module:load()``. It is hidden from EmmyLua
--- annotations due to limitations of the language server.
---
--- For usage by EmmyLua, the type of the constructed ``lazy_require`` is captured from the
--- ``name`` argument. If, in the above example, the content of ``st.my_module`` includes
---
--- @usage
--- --- @class st.my_module
---
--- Then, ``my_module`` will appear to be of type ``st.my_module``. Note that the ``@class``
--- declaration _must_ exist somewhere.

local lazy_require = {}

local function load(self)
  local module = rawget(self, "_lazy_require_cached_module")
  if not module then
    module = require(rawget(self, "_lazy_require_name"))

    local options = rawget(self, "_lazy_require_options")
    if options and options.caching then
      rawset(self, "_lazy_require_cached_module", module)
    end
  end

  return module
end

function lazy_require:__index(key)
  return self:load()[key]
end

function lazy_require:__newindex(key, value)
  local module = self:load()
  module[key] = value
  -- Usage of this function implies caching.
  rawset(self, "_lazy_require_cached_module", module)
end

function lazy_require:__call(...)
  return self:load()(...)
end

--- @generic MODULE
--- @param name MODULE
--- @param options table|nil { caching: boolean? }?
--- @return MODULE
--- @see st.utils.lazy_require
local function __lazy_require(name, options)
  return setmetatable({
    load = load,
    _lazy_require_name = name,
    _lazy_require_options = options,
  }, lazy_require)
end

-- Put the function we are returning into the table we are assigning to everyone so that this
-- module doesn't get GC'd. We do it this way rather than just defining ``__call`` on its own
-- purely because EmmyLua has trouble with generic operator functions. This way, the language
-- server is able to correctly link to the module we want to load in.
setmetatable(lazy_require, {
  __call = function(_self, name, options)
     return __lazy_require(name, options)
   end
})

return __lazy_require
