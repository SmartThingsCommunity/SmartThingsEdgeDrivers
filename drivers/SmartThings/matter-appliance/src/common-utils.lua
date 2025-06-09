-- Copyright 2025 SmartThings
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

local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"

local common_utils = {}

common_utils.COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"

common_utils.setpoint_limit_device_field = {
  MIN_TEMP = "MIN_TEMP",
  MAX_TEMP = "MAX_TEMP",
}

function common_utils.query_setpoint_limits(device)
  local setpoint_limit_read = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if device:get_field(common_utils.setpoint_limit_device_field.MIN_TEMP) == nil then
    setpoint_limit_read:merge(clusters.TemperatureControl.attributes.MinTemperature:read())
  end
  if device:get_field(common_utils.setpoint_limit_device_field.MAX_TEMP) == nil then
    setpoint_limit_read:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
  end
  if #setpoint_limit_read.info_blocks ~= 0 then
    device:send(setpoint_limit_read)
  end
end

return common_utils
