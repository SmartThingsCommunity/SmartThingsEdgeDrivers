-- Copyright 2024 SmartThings
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
local cluster_base = require "st.matter.cluster_base"
local data_types = require "yeelight/data_types"
local device_lib = require "st.device"
local log = require "log"

local lightingEffect = capabilities["amberwonder26407.lightingEffect"]
local YEELIGHT_MANUFACTURER_ID = 0x1312
local PRIVATE_CLUSTER_ENDPOINT_ID = 0x02
local PRIVATE_CLUSTER_ID = 0x1312FC05
local PRIVATE_LIGHTING_EFFECT_ATTR_ID = 0x13120000
local PRIVATE_LIGHTING_EFFECT_CMD_ID = 0x1312000e
local LIGHTING_EFFECT_ID = {
  ["streamer"]      = 0x03, -- ribbon
  ["starrySky"]     = 0x05,
  ["aurora"]        = 0x0F,
  ["spectrum"]      = 0x11,
  ["waterfall"]     = 0x20,
  ["bonfire"]       = 0x22, -- fire
  ["rainbow"]       = 0x27,
  ["waves"]         = 0x2A,
  ["pinball"]       = 0x25, -- bouncingBall
  ["hacking"]       = 0x2E,
  ["meteor"]        = 0x2F,
  ["tide"]          = 0x30,
  ["buildingBlock"] = 0x31
}

local function is_yeelight_products(opts, driver, device)
  -- this sub driver does not support child devices
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
      device.manufacturer_info.vendor_id == YEELIGHT_MANUFACTURER_ID then
    return true
  end

  return false
end

local function device_init(driver, device)
  device:subscribe()
  device:send(
    cluster_base.subscribe(device, PRIVATE_CLUSTER_ENDPOINT_ID, PRIVATE_CLUSTER_ID, PRIVATE_LIGHTING_EFFECT_ATTR_ID, nil)
  )
end

local function device_added(driver, device)
  device:emit_event(lightingEffect.state("custom"))
end

local function lighting_effect_attr_handler(driver, device, ib, zb_rx)
  for key, value in pairs(LIGHTING_EFFECT_ID) do
    if value == ib.data.value then
      device:emit_event(lightingEffect.state(key))
      return
    end
  end
  log.error("can not find matched light effect: " .. ib.data.value)
end

local function hue_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local hue = math.floor((ib.data.value / 0xFE * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(hue))
    device:emit_event(lightingEffect.state("custom"))
  end
end

local function sat_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local sat = math.floor((ib.data.value / 0xFE * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(sat))
    device:emit_event(lightingEffect.state("custom"))
  end
end

local function lighting_effect_cap_handler(driver, device, cmd)
  local effectId = data_types.validate_or_build_type(LIGHTING_EFFECT_ID[cmd.args.stateControl], data_types.Uint64, "effectId")
  effectId.field_id = 1

  device:send(
    cluster_base.build_cluster_command(
      driver,
      device,
      {
        ["effectId"] = effectId
      },
      0x02,
      PRIVATE_CLUSTER_ID,
      PRIVATE_LIGHTING_EFFECT_CMD_ID,
      nil
    )
  )
end

local yeelight_smart_lamp = {
  NAME = "Yeelight Smart Lamp",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  matter_handlers = {
    attr = {
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_LIGHTING_EFFECT_ATTR_ID] = lighting_effect_attr_handler
      },
      [clusters.ColorControl.ID] = {
        [clusters.ColorControl.attributes.CurrentHue.ID] = hue_attr_handler,
        [clusters.ColorControl.attributes.CurrentSaturation.ID] = sat_attr_handler,
      },
    }
  },
  capability_handlers = {
    [lightingEffect.ID] = {
      ["stateControl"] = lighting_effect_cap_handler
    }
  },
  can_handle = is_yeelight_products
}

return yeelight_smart_lamp
