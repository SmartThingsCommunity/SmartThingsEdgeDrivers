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

local MatterDriver = require "st.matter.driver"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"
local discoBall = require "DiscoBall"

local log = require "log"

local discoBallId = "adminmirror01019.discoBall"


local subscribed_attributes = {
  [discoBallId] = {
    discoBall.attributes.Run,
    discoBall.attributes.Speed,
  }
}


local function device_init(driver, device)
  device:subscribe()
end



local function device_added(driver, device)

end


local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  matter_handlers = {
    attr = {
      [DiscoBall.ID] = {
        [DiscoBall.attributes.Run.ID] = air_quality_attr_handler,
      }
    }
  },
  subscribed_attributes = subscribed_attributes,
}

local matter_driver = MatterDriver("matter-disco-ball", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
