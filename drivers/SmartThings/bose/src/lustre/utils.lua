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

--- Print binary string as ascii hex
---@param str string
---@return string ascii hex string
local function get_print_safe_string(str)
  if str:match("^[%g ]+$") ~= nil then
    return string.format("%s", str)
  else
    return string.format(string.rep("\\x%02X", #str), string.byte(str, 1, #str))
  end
end

local key_order_cmp = function(key1, key2)
  local type1 = type(key1)
  local type2 = type(key2)
  if type1 ~= type2 then
    return type1 < type2
  elseif type1 == "number" or type1 == "string" then -- comparable types
    return key1 < key2
  elseif type1 == "boolean" then
    return key1 == true
  else
    return tostring(key1) < tostring(key2)
  end
end

local stringify_table_helper

stringify_table_helper = function(val, name, multi_line, indent, previously_printed)
  local tabStr = multi_line and string.rep(" ", indent) or ""

  if name then tabStr = tabStr .. tostring(name) .. "=" end

  local multi_line_str = ""
  if multi_line then multi_line_str = "\n" end

  if type(val) == "table" then
    if not previously_printed[val] then
      tabStr = tabStr .. "{" .. multi_line_str
      -- sort keys for repeatability of print
      local tkeys = {}
      for k in pairs(val) do table.insert(tkeys, k) end
      table.sort(tkeys, key_order_cmp)

      for _, k in ipairs(tkeys) do
        local v = val[k]
        previously_printed[val] = name
        if #val > 0 and type(k) == "number" then
          tabStr = tabStr ..
                     stringify_table_helper(v, nil, multi_line, indent + 2, previously_printed) ..
                     ", " .. multi_line_str
        else
          tabStr = tabStr ..
                     stringify_table_helper(v, k, multi_line, indent + 2, previously_printed) ..
                     ", " .. multi_line_str
        end
      end
      if tabStr:sub(#tabStr, #tabStr) == "\n" and tabStr:sub(#tabStr - 1, #tabStr - 1) == "{" then
        tabStr = tabStr:sub(1, -2) .. "}"
      elseif tabStr:sub(#tabStr - 1, #tabStr - 1) == "," then
        tabStr = tabStr:sub(1, -3) .. (multi_line and string.rep(" ", indent) or "") .. "}"
      else
        tabStr = tabStr .. (multi_line and string.rep(" ", indent) or "") .. "}"
      end
    else
      tabStr = tabStr .. "RecursiveTable: " .. previously_printed[val]
    end
  elseif type(val) == "number" then
    tabStr = tabStr .. tostring(val)
  elseif type(val) == "string" then
    tabStr = tabStr .. "\"" .. get_print_safe_string(val) .. "\""
  elseif type(val) == "boolean" then
    tabStr = tabStr .. (val and "true" or "false")
  elseif type(val) == "function" then
    tabStr = tabStr .. tostring(val)
  else
    tabStr = tabStr .. "\"[unknown datatype:" .. type(val) .. "]\""
  end

  return tabStr
end

--- Convert value to string
---@param val table Value to stringify
---@param name string Print a name along with value [Optional]
---@param multi_line boolean use newlines to provide a more easily human readable string [Optional]
---@returns string String representation of `val`
local function table_string(val, name, multi_line)
  return stringify_table_helper(val, name, multi_line, 0, {})
end

return {
  table_string = table_string
}
