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
local cluster_base = require "st.zigbee.cluster_base"
local custom_clusters = require "shus-mattress/custom_clusters"
local custom_capabilities = require "shus-mattress/custom_capabilities"

local FINGERPRINTS = {
  { mfr = "SHUS", model = "SX-1" }
}

-- #############################
-- # Attribute handlers define #
-- #############################
local function process_switch_attr_factory(cmd)
  return function(driver, device, value, zb_rx)
    if value.value == false then
      device:emit_event(cmd.off())
    elseif value.value == true then
      device:emit_event(cmd.on())
    end
  end
end

local function process_control_attr_factory(cmd)
  return function(driver, device, value, zb_rx)
    device:emit_event(cmd("idle", { visibility = { displayed = false }}))
  end
end

local function process_level_factory(cmd)
  return function(driver, device, value, zb_rx)
    device:emit_event(cmd(value.value))
  end
end

local function yoga_attr_handler(driver, device, value, zb_rx)
  if value.value == 0 then
    device:emit_event(custom_capabilities.yoga.state.stop())
  elseif value.value == 1 then
    device:emit_event(custom_capabilities.yoga.state.left())
  elseif value.value == 2 then
    device:emit_event(custom_capabilities.yoga.state.right())
  elseif value.value == 3 then
    device:emit_event(custom_capabilities.yoga.state.both())
  end
end

-- ##############################
-- # Capability handlers define #
-- ##############################

local function send_read_attr_request(device, cluster, attr)
  device:send(
    cluster_base.read_manufacturer_specific_attribute(
      device,
      cluster.id,
      attr.id,
      cluster.mfg_specific_code
    )
  )
end

local function do_refresh(driver, device)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.left_ai_mode)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.right_ai_mode)

  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.auto_inflation)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.strong_exp_mode)

  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.left_back)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.left_waist)

  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.left_hip)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.right_back)

  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.right_waist)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.right_hip)

  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.yoga)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.left_back_level)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.left_waist_level)

  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.left_hip_level)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.right_back_level)

  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.right_waist_level)
  send_read_attr_request(device, custom_clusters.shus_smart_mattress, custom_clusters.shus_smart_mattress.attributes.right_hip_level)
end

local function process_capabilities_factory(cap,attrs)
  return function(driver, device, cmd)
    device:send(
      cluster_base.write_manufacturer_specific_attribute(
        device,
        custom_clusters.shus_smart_mattress.id,
        custom_clusters.shus_smart_mattress.attributes[attrs].id,
        custom_clusters.shus_smart_mattress.mfg_specific_code,
        custom_clusters.shus_smart_mattress.attributes[attrs].value_type,
        custom_clusters.shus_smart_mattress.attributes[attrs].value[cmd.args[cap]]
      )
    )
  end
end

local function process_capabilities_hardness_factory(cap,attrs,cap_attr)
  return function(driver, device, cmd)
    device:send(
      cluster_base.write_manufacturer_specific_attribute(
        device,
        custom_clusters.shus_smart_mattress.id,
        custom_clusters.shus_smart_mattress.attributes[attrs].id,
        custom_clusters.shus_smart_mattress.mfg_specific_code,
        custom_clusters.shus_smart_mattress.attributes[attrs].value_type,
        custom_clusters.shus_smart_mattress.attributes[attrs].value[cmd.args[cap]]
      )
    )
    --A button that can be triggered continuously
    local evt_ctrl = cap_attr.soft()
    local evt_idle = cap_attr("idle", { visibility = { displayed = false }})
    if cmd.args[cap] == "hard" then
      evt_ctrl = cap_attr.hard()
    end
    device:emit_event(evt_ctrl)
    device.thread:call_with_delay(1, function(d)
      device:emit_event(evt_idle)
    end)
  end
end

-- #############################
-- # Lifecycle handlers define #
-- #############################

local function device_init(driver, device)
end

local function device_added(driver, device)
   device:emit_event(custom_capabilities.yoga.supportedYogaState({"stop", "left", "right"}, { visibility = { displayed = false }}))
   do_refresh(driver, device)
end

local function do_configure(driver, device)
end

local function is_shus_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

-- #################
-- # Handlers bind #
-- #################

local shus_smart_mattress = {
  NAME = "Shus Smart Mattress",
  supported_capabilities = {
    capabilities.refresh
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [custom_clusters.shus_smart_mattress.id] = {
        [custom_clusters.shus_smart_mattress.attributes.left_ai_mode.id] = process_switch_attr_factory(custom_capabilities.ai_mode.left),
        [custom_clusters.shus_smart_mattress.attributes.right_ai_mode.id] = process_switch_attr_factory(custom_capabilities.ai_mode.right),
        [custom_clusters.shus_smart_mattress.attributes.auto_inflation.id] = process_switch_attr_factory(custom_capabilities.auto_inflation.inflationState),
        [custom_clusters.shus_smart_mattress.attributes.strong_exp_mode.id] = process_switch_attr_factory(custom_capabilities.strong_exp_mode.expState),
        [custom_clusters.shus_smart_mattress.attributes.left_back.id] = process_control_attr_factory(custom_capabilities.left_control.leftback),
        [custom_clusters.shus_smart_mattress.attributes.left_waist.id] = process_control_attr_factory(custom_capabilities.left_control.leftwaist),
        [custom_clusters.shus_smart_mattress.attributes.left_hip.id] = process_control_attr_factory(custom_capabilities.left_control.lefthip),
        [custom_clusters.shus_smart_mattress.attributes.right_back.id] = process_control_attr_factory(custom_capabilities.right_control.rightback),
        [custom_clusters.shus_smart_mattress.attributes.right_waist.id] = process_control_attr_factory(custom_capabilities.right_control.rightwaist),
        [custom_clusters.shus_smart_mattress.attributes.right_hip.id] = process_control_attr_factory(custom_capabilities.right_control.righthip),
        [custom_clusters.shus_smart_mattress.attributes.yoga.id] = yoga_attr_handler,
        [custom_clusters.shus_smart_mattress.attributes.left_back_level.id] = process_level_factory(custom_capabilities.mattressHardness.leftBackHardness),
        [custom_clusters.shus_smart_mattress.attributes.left_waist_level.id] = process_level_factory(custom_capabilities.mattressHardness.leftWaistHardness),
        [custom_clusters.shus_smart_mattress.attributes.left_hip_level.id] = process_level_factory(custom_capabilities.mattressHardness.leftHipHardness),
        [custom_clusters.shus_smart_mattress.attributes.right_back_level.id] = process_level_factory(custom_capabilities.mattressHardness.rightBackHardness),
        [custom_clusters.shus_smart_mattress.attributes.right_waist_level.id] = process_level_factory(custom_capabilities.mattressHardness.rightWaistHardness),
        [custom_clusters.shus_smart_mattress.attributes.right_hip_level.id] = process_level_factory(custom_capabilities.mattressHardness.rightHipHardness)
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [custom_capabilities.ai_mode.ID] = {
      ["leftControl"] = process_capabilities_factory("leftControl","left_ai_mode"),
      ["rightControl"] = process_capabilities_factory("rightControl","right_ai_mode")
    },
    [custom_capabilities.auto_inflation.ID] = {
      ["stateControl"] = process_capabilities_factory("stateControl","auto_inflation")
    },
    [custom_capabilities.strong_exp_mode.ID] = {
      ["stateControl"] = process_capabilities_factory("stateControl","strong_exp_mode")
    },
    [custom_capabilities.left_control.ID] = {
      ["backControl"] = process_capabilities_hardness_factory("backControl","left_back",custom_capabilities.left_control.leftback),
      ["waistControl"] = process_capabilities_hardness_factory("waistControl","left_waist",custom_capabilities.left_control.leftwaist),
      ["hipControl"] = process_capabilities_hardness_factory("hipControl","left_hip",custom_capabilities.left_control.lefthip)
    },
    [custom_capabilities.right_control.ID] = {
      ["backControl"] = process_capabilities_hardness_factory("backControl","right_back",custom_capabilities.right_control.rightback),
      ["waistControl"] = process_capabilities_hardness_factory("waistControl","right_waist",custom_capabilities.right_control.rightwaist),
      ["hipControl"] = process_capabilities_hardness_factory("hipControl","right_hip",custom_capabilities.right_control.righthip)
    },
    [custom_capabilities.yoga.ID] = {
      ["stateControl"] = process_capabilities_factory("stateControl","yoga")
    }
  },
  can_handle = is_shus_products
}

return shus_smart_mattress
