local lan_test_utils = require "integration_test.utils.lan_utils"
local helpers = require "test.helpers"

local Response = require "luncheon.response"

local raw_403_html = [[
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>
<head>
    <title>hue personal wireless lighting</title>
    <link rel="stylesheet" type="text/css" href="/index.css">
</head>
<body>
    <div class="philips-header">
      <img src="/philips-blue.png" class="philips-logo" alt="Philips" />
    </div>
    <div class="header">
      <img class="header-logo" src="/hue-logo.png" alt="hue personal wireless lighting" />

      <img src="/hue-color-line.png" class="colorline" />

    </div>
    <div class="error">Oops, there appears to be no lighting here</div>
</body>
</html>
]]

---@class MockHueBridgeRestServer
---@field public bridge_info HueBridgeInfo?
---@field public registered_types { [string]: table }
---@field public mock_server MockRestServer?
---@field public server_spec ServerHarnessSpec?
---@field public server_spec_builder ServerHarnessSpecBuilder?
---@field public socket table
local m = {}

---comment
---@param bridge_info HueBridgeInfo
---@return MockHueBridgeRestServer
function m.new(bridge_info)
  local out = {
    server_spec_builder =
        lan_test_utils.ServerHarnessSpecBuilder.new()
        :server_host(bridge_info.ip)
        :server_port(443),
    socket = helpers.socket.mock_remote_cosock_tcp(),
    bridge_info = bridge_info,
    registered_types = {}
  }

  -- The Hue API will always return JSON, so we don't use any of the
  -- builder API variants that will enforce an Accepts header.
  out.server_spec_builder = out.server_spec_builder:add_resource(
    function(builder, serializers, deserializers)
      return builder
          :add_get("/api/config")
          :with_response(200, 'application/json', serializers['application/json'](bridge_info))
          :build_spec(serializers, deserializers)
    end
  )

  return setmetatable(out, { __index = m })
end

function m:register_hue_resource(resource)
  assert(self.server_spec_builder, "no builder to add resource to")
  assert(self.server_spec == nil, "server spec already generated")

  if not self.registered_types[resource.type] then
    self.registered_types[resource.type] = {}
    self.server_spec_builder = self.server_spec_builder:add_resource(
      function(builder, serializers, deserializers)
        return builder
            :add_get(string.format("/clip/v2/resource/%s", resource.type))
            :with_response(function(req, _ser, _de)
              if req:get_headers():get_one('hue-application-key') ~= self.application_key then
                error('403 forbidden')
                return
                ---@diagnostic disable-next-line: return-type-mismatch
                    Response.new(403)
                    :add_header('content-type', 'text/html')
                    :append_body(raw_403_html)
              end
              ---@diagnostic disable-next-line: return-type-mismatch
              local out_json = {
                errors = {},
                data = self.registered_types[resource.type]
              }
              ---@diagnostic disable-next-line: return-type-mismatch
              return Response.new(200)
                  :add_header('content-type', 'application/json')
                  :append_body(serializers['application/json'](out_json))
            end)
            :build_spec(serializers, deserializers)
      end
    )
  end

  table.insert(self.registered_types[resource.type], resource)

  self.server_spec_builder = self.server_spec_builder:add_resource(
    function(builder, serializers, deserializers)
      return builder
          :add_get(string.format("/clip/v2/resource/%s/%s", resource.type, resource.id))
          :with_response(function(req, _ser, _de)
            if req:get_headers():get_one('hue-application-key') ~= self.application_key then
              error('403 forbidden')
              return
              ---@diagnostic disable-next-line: return-type-mismatch
                  Response.new(403)
                  :add_header('content-type', 'text/html')
                  :append_body(raw_403_html)
            end
            ---@diagnostic disable-next-line: return-type-mismatch
            local out_json = {
              errors = {},
              data = { resource }
            }
            ---@diagnostic disable-next-line: return-type-mismatch
            return Response.new(200)
                :add_header('content-type', 'application/json')
                :append_body(serializers['application/json'](out_json))
          end)
          :build_spec(serializers, deserializers)
    end
  )
end

function m:set_hue_application_key(key)
  self.application_key = key
end

function m:start()
  assert(self.server_spec == nil and self.mock_server == nil,
    "called start on an already started server")
  assert(self.server_spec_builder, "called start on a mock hue bridge server without a spec builder")
  self.server_spec = assert(self.server_spec_builder:build_server_spec())
  local mock_server = assert(lan_test_utils.make_server(self.server_spec, self.socket))
  self.server_spec_builder = nil

  self.mock_server = mock_server
  self.mock_server:start()
end

function m:stop()
  assert(self.mock_server, "Called stop without calling start")
  self.mock_server:stop()
end

return m
