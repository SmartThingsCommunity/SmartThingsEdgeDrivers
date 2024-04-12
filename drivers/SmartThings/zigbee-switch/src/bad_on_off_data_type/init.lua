-- Copyright 2023 SmartThings
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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"

-- There are reports of at least one device (SONOFF 01MINIZB) which occasionally
-- reports this value as an Int8, rather than a Boolean, as per the spec
local function incorrect_data_type_detected(opts, driver, device, zb_rx, ...)
  local can_handle = opts.dispatcher_class == "ZigbeeMessageDispatcher" and
    device:get_manufacturer() == "SONOFF" and
    zb_rx.body and
    zb_rx.body.zcl_body and
    zb_rx.body.zcl_body.attr_records and
    zb_rx.address_header.cluster.value == zcl_clusters.OnOff.ID and
    zb_rx.body.zcl_body.attr_records[1].attr_id.value == zcl_clusters.OnOff.attributes.OnOff.ID and
    zb_rx.body.zcl_body.attr_records[1].data_type.value ~= data_types.Boolean.ID
  if can_handle then
    local subdriver = require("bad_on_off_data_type")
    return true, subdriver
  else
    return false
  end
end

local function on_off_attr_handler(driver, device, value, zb_rx)
  local attr = capabilities.switch.switch
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, value.value == 0 and attr.off() or attr.on())
end

local bad_on_off_data_type = {
  NAME = "Bad OnOff Data Type",
  zigbee_handlers = {
    attr = {
      [zcl_clusters.OnOff.ID] = {
        [zcl_clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler
      }
    }
  },
  can_handle = incorrect_data_type_detected
}

return bad_on_off_data_type