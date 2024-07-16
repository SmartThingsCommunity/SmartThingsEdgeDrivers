local helpers = require "test.helpers"
local rest_api = require "test.mock_hue_bridge.rest_api"

local path = require "path"
local Path = path.Path

local st_utils = require "st.utils"

local function _get_all_template_files(template_dir)
  local template_dir_path = helpers.to_absolute_path(template_dir)
  local find_json_files_command = string.format(
    "find %s -type f -name \"*.json\" -print0",
    template_dir_path
  )
  local iter_files_command = find_json_files_command .. " | xargs -0 -I {} printf \"%s\n\" {}"

  local templates = {}
  for file in assert(io.popen(iter_files_command)):lines()
  do
    local filename = assert(table.remove(path.split_path(tostring(file))))
    local service_type = assert(select(1, string.match(filename, "(.+)%.(.+)")))
    local template = Path(file)
    templates[service_type] = template
  end
  return templates
end

local function _new_uuid(self)
  while true do
    local maybe_uuid = st_utils.generate_uuid_v4()
    if not self._used_uuids[maybe_uuid] then
      self._used_uuids[maybe_uuid] = true
      return maybe_uuid
    end
  end
end

local function _new_v1_id(self, device_type)
  local id_fmt_string = "%s/%d"
  while true do
    local maybe_id = string.format(id_fmt_string, device_type, math.random(255))
    if not self._used_v1_ids[maybe_id] then
      self._used_v1_ids[maybe_id] = true
      return maybe_id
    end
  end
end

---@class MockHueBridge
---@field public bridge_info HueBridgeInfo,
---@field public rest_api_server MockHueBridgeRestServer
---@field private used_uuids { [string]: boolean }
---@field private used_v1_ids { [string]: boolean }
local m = {}

---@param mock_bridge_info HueBridgeInfo
---@return MockHueBridge
function m.new(mock_bridge_info)
  local out = {
    bridge_info = mock_bridge_info,
    rest_api_server = rest_api.new(mock_bridge_info),
    _used_uuids = {},
    _used_v1_ids = {}
  }
  return setmetatable(out, { __index = m })
end

function m:register_hue_resource(resource)
  assert(self.rest_api_server)
  self.rest_api_server:register_hue_resource(resource)
end

local UUID_TEMPLATE_KEY = "{{uuid}}"
local ID_V1_TEMPLATE_KEY = "{{id_v1}}"

---@param device_type HueDeviceTypes
---@param template_dir string|Path
function m:add_device_from_template(device_type, template_dir)
  local templates = _get_all_template_files(template_dir)
  local device_template = assert(templates["device"],
    "cannot mock a device without a \"device\" service template")
  local device_data = assert(helpers.load_test_data_json_file(device_template)).data[1]

  if device_data.id == UUID_TEMPLATE_KEY then
    device_data.id = _new_uuid(self)
  end

  if device_data.id_v1 and device_data.id_v1 == ID_V1_TEMPLATE_KEY then
    device_data.id_v1 = _new_v1_id(self, device_type)
  end

  self:register_hue_resource(device_data)
  for _, svc in ipairs(device_data.services) do
    if svc.rid == UUID_TEMPLATE_KEY then
      svc.rid = _new_uuid(self)
    end
    if templates[svc.rtype] then
      local svc_data = assert(helpers.load_test_data_json_file(templates[svc.rtype])).data[1]
      if svc_data.id_v1 and svc_data.id_v1 == ID_V1_TEMPLATE_KEY then
        svc_data.id_v1 = device_data.id_v1
      end

      if svc_data.id == UUID_TEMPLATE_KEY then
        svc_data.id = svc.rid
      end

      if
          svc_data.owner and
          svc_data.owner.rid == UUID_TEMPLATE_KEY
          and svc_data.owner.rtype == "device"
      then
        svc_data.owner.rid = device_data.id
      end
      self:register_hue_resource(svc_data)
    end
  end
  return device_data
end

---@param key string
function m:set_hue_application_key(key)
  self.application_key = key
  self.rest_api_server:set_hue_application_key(key)
end

function m:start()
  self.rest_api_server:start()
end

function m:stop()
  self.rest_api_server:stop()
end

return m
