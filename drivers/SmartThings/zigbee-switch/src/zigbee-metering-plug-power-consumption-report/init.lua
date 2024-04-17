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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local bind_request = require "st.zigbee.zdo.bind_request"
local zdo_messages = require "st.zigbee.zdo"
local zigbee_constants = require "st.zigbee.constants"

local OnOff = clusters.OnOff
local SimpleMetering = clusters.SimpleMetering

local function energy_meter_handler(driver, device, value, zb_rx)
  local raw_value = value.value
  local multiplier = device:get_field(constants.SIMPLE_METERING_MULTIPLIER_KEY) or 1
  local divisor = device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) or 1000
  local converted_value = raw_value * multiplier/divisor

  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({energy = raw_value, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'

  device:emit_event(capabilities.energyMeter.energy({value = converted_value, unit = "kWh"}))
end

local function build_bind_request(device, cluster, hub_zigbee_eui, src_endpoint)
  local addr_header = messages.AddressHeader(constants.HUB.ADDR, constants.HUB.ENDPOINT, device:get_short_address(), device.fingerprinted_endpoint_id, constants.ZDO_PROFILE_ID, bind_request.BindRequest.ID)
  local bind_req = bind_request.BindRequest(device.zigbee_eui, src_endpoint, cluster, bind_request.ADDRESS_MODE_64_BIT, hub_zigbee_eui, constants.HUB.ENDPOINT)
  local message_body = zdo_messages.ZdoMessageBody({
    zdo_body = bind_req
  })
  local bind_cmd = messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = message_body
  })
  return bind_cmd
end

local do_configure = function(self, device)
  device:configure()
  device:refresh()
  for comp_id, comp in pairs(device.profile.components) do
    local src_ep = device:get_endpoint_for_component_id(comp_id)
    device:send(build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui, src_ep))
  end
end

local device_init = function(self, device)
  device:set_field(zigbee_constants.SIMPLE_METERING_DIVISOR_KEY, 1000, {persist = true})
end

local zigbee_metering_plug_power_conumption_report = {
  NAME = "zigbee metering plug power conumption report",
  zigbee_handlers = {
    attr = {
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure
  },
  can_handle = function(opts, driver, device, ...)
    local can_handle = device:get_manufacturer() == "DAWON_DNS"
    if can_handle then
      local subdriver = require("zigbee-metering-plug-power-consumption-report")
      return true, subdriver
    else
      return false
    end
  end
}

return zigbee_metering_plug_power_conumption_report
