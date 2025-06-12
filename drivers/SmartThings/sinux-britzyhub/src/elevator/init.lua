-- SinuxSoft (c) 2025
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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local log = require "log"

local subscribed_attributes = {
  [capabilities.elevatorCall.ID] = {
    clusters.OnOff.attributes.OnOff
  },
}

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.elevatorCall.callStatus.called())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.elevatorCall.callStatus.standby())
  end
end

local function handle_elevator_call(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)

  -- 3초 후 called 상태로 전환
  driver:call_with_delay(3, function()
    device:emit_event_for_endpoint(endpoint_id, capabilities.elevatorCall.callStatus.called())

    -- 10초 후 standby 상태로 자동 초기화
    driver:call_with_delay(10, function()
      device:emit_event_for_endpoint(endpoint_id, capabilities.elevatorCall.callStatus.standby())
    end)
  end)
end

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name)
  return find_default_endpoint(device, clusters.OnOff.ID)
end

local function device_init(driver, device)
  device:subscribe()
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function do_configure(driver, device)
  -- do nothing
end

local function info_changed(driver, device, event, args)
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

local function can_handle(opts, driver, device)
  return device.label:find("엘리베이터") ~= nil
end

local elevator_handler = {
  NAME = "Elevator Handler",
  can_handle = can_handle,
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      }
    }
  },
  subscribed_attributes = subscribed_attributes,
  capability_handlers = {
    [capabilities.elevatorCall.ID] = {
      [capabilities.elevatorCall.commands.call.NAME] = handle_elevator_call,
    }
  },
  supported_capabilities = {
    capabilities.elevatorCall,
  },
}

return elevator_handler
