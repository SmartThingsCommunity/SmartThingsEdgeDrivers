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


--- @class st.utils.lazy_loader
--- @field prefix string the path prefix for loaded modules
--- @field caching boolean determines whether returned ``lazy_require``s will use caching.
local lazy_loader = {}

--- @param options table { prefix: string, caching: boolean? }
function lazy_loader:new(options)
  options.prefix = options.prefix or ""
  return setmetatable(options, lazy_loader)
end

--- @param key string
--- @return st.utils.lazy_require
function lazy_loader:__index(key)
  local req_str = rawget(self, "prefix") .. key
  return lazy_require(req_str, { caching = rawget(self, "caching") })
end

return lazy_loader
