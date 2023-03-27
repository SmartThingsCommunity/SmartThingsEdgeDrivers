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

local capabilities = require "st.capabilities"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass.BarrierOperator
local BarrierOperator = (require "st.zwave.CommandClass.BarrierOperator")({ version = 1 })
--- @type st.zwave.constants
local constants = require "st.zwave.constants"

local GDO_ENDPOINT_NUMBER = 1
local CONTACTSENSOR_ENDPOINT_NAME = "sensor"

--- Handle Door control
local set_doorControl_factory = function(doorControl_attribute)
  return function(driver, device, cmd)
    if (
      device:get_latest_state(
              CONTACTSENSOR_ENDPOINT_NAME,
              capabilities.tamperAlert.ID,
              capabilities.tamperAlert.tamper.NAME) == "clear"
      ) then
      device:send(BarrierOperator:Set({ target_value = doorControl_attribute }))
      device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, function(d)
        device:send(BarrierOperator:Get({}))end)
    else
      device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER,
                                    capabilities.doorControl.door.unknown()
                                    )
    end
  end
end

local driver_template = {
  capability_handlers = {
    [capabilities.doorControl.ID] = {
      [capabilities.doorControl.commands.open.NAME] = set_doorControl_factory(BarrierOperator.state.OPEN)
  },
    [capabilities.doorControl.ID] = {
      [capabilities.doorControl.commands.close.NAME] = set_doorControl_factory(BarrierOperator.state.CLOSED)
  }
  },
  supported_capabilities = {
    capabilities.doorControl,
    capabilities.contactSensor,
  },
  sub_drivers = {
    require("mimolite-garage-door"),
    require("ecolink-zw-gdo")
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local garage_door_opener = ZwaveDriver("zwave_garage_door_opener", driver_template)
garage_door_opener:run()
