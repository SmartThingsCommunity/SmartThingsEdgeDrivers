local Path = require "path".Path

---@class test.helpers
local m = {
  socket = require "test.helpers.socket",
  net = require "test.helpers.net",
  hue_bridge = require "test.helpers.hue_bridge"
}

---Given a relative path in a `Path` table, convert to absolute
---@param path_table Path
---@return Path
function m.convert_relative_path_table_to_absolute(path_table)
  local caller_path = Path(assert(arg[0]))
  local test_dir_path = assert(
    caller_path:get_dir_pos("src") and caller_path:to_dir("src"),
    "Couldn't figure out location of test directory"
  )
  local ret = test_dir_path:append("test"):append(path_table:to_string())
  return ret
end

---Given a path string or `Path`, convert it to an absolute path
---@param filepath string|Path
---@return Path
function m.to_absolute_path(filepath)
  assert(
    type(filepath) == "string" or
    (type(filepath) == "table" and filepath.init == Path.init),
    "bad argument #1 to 'load_test_data_json_file (string or Path table expected)"
  )
  local path_table
  if type(filepath) == "string" then
    path_table = Path(filepath)
  else
    path_table = filepath
  end
  if path_table._is_abs then
    return path_table
  else
    return m.convert_relative_path_table_to_absolute(path_table)
  end
end

---Load a JSON file to a table. If `json_file` is a string, and it is a relative path,
---it should be relative to the driver's `./src/test` directory.
---
---For example, if you have a JSON file at `./src/test/test_data/foo.json`, you should use
---`test_data/foo.json` as the parameter.
---
---This function also accepts absolute paths and `Path` tables.
---@see Path
---@param json_file string|Path path to the data file
function m.load_test_data_json_file(json_file)
  local abs_json_file_path = m.to_absolute_path(json_file)
  local file = assert(io.open(abs_json_file_path:to_string()))
  local contents = assert(file:read("a"))
  assert(file:close())

  local json = require "st.json"
  return assert(json.decode(contents))
end

return m
