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
local discoBallCluster = require "generated.DiscoBall"

local log = require "log"

local discoBallCapabilityId = "summertalent21965.discoBall"
local discoBallCapability = capabilities[discoBallCapabilityId]

local DEFAULT_ENDPOINT_ID = 1

local ROTATION_TYPE = "__rotation_type"
local ROTATION_SPEED = "__rotation_speed"

local subscribed_attributes = {
    [discoBallCapabilityId] = {discoBallCluster.attributes.Run, discoBallCluster.attributes.Rotate,
                               discoBallCluster.attributes.Speed}
}

local function running_attr_handler(driver, device, ib, response)
    log.info(string.format("running_attr_handler: ib.data.value: %s", ib.data.value))
    if ib.data.value then
        device:emit_event(discoBallCapability.running(true))
    else
        device:emit_event(discoBallCapability.running(false))
    end
end

local function rotation_attr_handler(driver, device, ib, response)
    log.info(string.format("rotation_attr_handler: ib.data.value: %s", ib.data.value))
    if ib.data.value == 1 then
        device:emit_event(discoBallCapability.rotation("clockwise"))
    elseif ib.data.value == 2 then
        device:emit_event(discoBallCapability.rotation("counterClockwise"))
    end
end

local function speed_attr_handler(driver, device, ib, response)
    log.info(string.format("speed_attr_handler: ib.data.value: %s", ib.data.value))
    if ib.data.value ~= nil then
        device:emit_event(discoBallCapability.speed(ib.data.value))
    end
end

local function handle_start(driver, device, cmd)
    local speed = device:get_field(ROTATION_SPEED) or 0
    local rotate = device:get_field(ROTATION_TYPE) or 1
    local req = discoBallCluster.commands.StartRequest(device, DEFAULT_ENDPOINT_ID, speed, rotate)
    device:send(req)
end

local function handle_stop(driver, device, cmd)
    local req = discoBallCluster.commands.StopRequest(device, DEFAULT_ENDPOINT_ID)
    device:send(req)
end

local function handle_set_rotation(driver, device, cmd)
    log.info(string.format("handle_set_rotation: cmd.args.rotation: %s", cmd.args.rotation))
    local rotation = 0
    if cmd.args.rotation == "clockwise" then
        rotation = 1
    elseif cmd.args.rotation == "counterClockwise" then
        rotation = 2
    end
    device:set_field(ROTATION_TYPE, rotation, {
        persist = true
    })
    local req = discoBallCluster.commands.ReverseRequest(device, DEFAULT_ENDPOINT_ID)
    device:send(req)
end

local function handle_set_speed(driver, device, cmd)
    log.info(string.format("handle_set_speed: cmd.args.speed: %s", cmd.args.speed))
    -- Do we need to stop and then start?
    device:set_field(ROTATION_SPEED, cmd.args.speed, {
        persist = true
    })
    handle_start(driver, device, cmd)
end

local function handle_refresh(driver, device, cmd)
    device:send(discoBallCluster.attributes.Run:read(device))
    device:send(discoBallCluster.attributes.Rotate:read(device))
    device:send(discoBallCluster.attributes.Speed:read(device))
end

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
            [discoBallCluster.ID] = {
                [discoBallCluster.attributes.Run.ID] = running_attr_handler,
                [discoBallCluster.attributes.Rotate.ID] = rotation_attr_handler,
                [discoBallCluster.attributes.Speed.ID] = speed_attr_handler
            }
        }
    },
    capability_handlers = {
        [discoBallCapability.ID] = {
            [discoBallCapability.commands.start.NAME] = handle_start,
            [discoBallCapability.commands.stop.NAME] = handle_stop,
            [discoBallCapability.commands.setRotation.NAME] = handle_set_rotation,
            [discoBallCapability.commands.setSpeed.NAME] = handle_set_speed
        },
        [capabilities.refresh.ID] = {
            [capabilities.refresh.commands.refresh.NAME] = handle_refresh
        }
    },
    subscribed_attributes = subscribed_attributes
}

local matter_driver = MatterDriver("matter-disco-ball", matter_driver_template)
log.info_with({
    hub_logs = true
}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
