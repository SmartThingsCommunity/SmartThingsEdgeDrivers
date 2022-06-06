local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })
local log = require "log"
local LAST_SEQ_NUMBER_KEY = "last_sequence_number"
local utils = require "st.utils"
local constants = require "st.zwave.constants"

local ZOOZ_ZEN_30_DIMMER_RELAY_FINGERPRINTS = {
  {mfr = 0x027A, prod = 0xA000, model = 0xA008} -- Zooz Zen 30 Dimmer Relay Double Switch
}

local function can_handle_zooz_zen_30_dimmer_relay_double_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZOOZ_ZEN_30_DIMMER_RELAY_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local BUTTON_VALUES = {
  "up_hold", "down_hold", "held",
  "up","up_2x","up_3x","up_4x","up_5x",
  "down","down_2x","down_3x","down_4x","down_5x",
  "pushed", "pushed_2x","pushed_3x","pushed_4x","pushed_5x"
}

local map_key_attribute_to_capability = {
  [CentralScene.key_attributes.KEY_PRESSED_1_TIME] = {
    [0x01] = capabilities.button.button.up(),
    [0x02] = capabilities.button.button.down(),
    [0x03] = capabilities.button.button.pushed()
  },
  [CentralScene.key_attributes.KEY_PRESSED_2_TIMES] = {
    [0x01] = capabilities.button.button.up_2x(),
    [0x02] = capabilities.button.button.down_2x(),
    [0x03] = capabilities.button.button.pushed_2x()
  },
  [CentralScene.key_attributes.KEY_PRESSED_3_TIMES] = {
    [0x01] = capabilities.button.button.up_3x(),
    [0x02] = capabilities.button.button.down_3x(),
    [0x03] = capabilities.button.button.pushed_3x()
  },
  [CentralScene.key_attributes.KEY_PRESSED_4_TIMES] = {
    [0x01] = capabilities.button.button.up_4x(),
    [0x02] = capabilities.button.button.down_4x(),
    [0x03] = capabilities.button.button.pushed_4x()
  },
  [CentralScene.key_attributes.KEY_PRESSED_5_TIMES] = {
    [0x01] = capabilities.button.button.up_5x(),
    [0x02] = capabilities.button.button.down_5x(),
    [0x03] = capabilities.button.button.pushed_5x()
  },
  [CentralScene.key_attributes.KEY_HELD_DOWN] = {
    [0x01] = capabilities.button.button.up_hold(),
    [0x02] = capabilities.button.button.down_hold(),
    [0x03] = capabilities.button.button.held()
  }
}

local function endpoint_to_component(device, endpoint)
  if endpoint == 1 then
    return "switch1"
  elseif endpoint == 0 then
    return "main"
  end
end

local function component_to_endpoint(device, component)
  if component == "switch1" then
    return {1}
  elseif component == "main" then
    return {0}
  end
end

local function central_scene_notification_handler(driver, device, cmd)
  if(cmd.args.key_attributes == 0x01) then
    log.error("Button Value 'released' is not supported by SmartThings")
    return
  end

  if device:get_field(LAST_SEQ_NUMBER_KEY) ~= cmd.args.sequence_number then
    device:set_field(LAST_SEQ_NUMBER_KEY, cmd.args.sequence_number)
    local event_map = map_key_attribute_to_capability[cmd.args.key_attributes]
    local event = event_map and event_map[cmd.args.scene_number]
    if event ~= nil then
      device:emit_event_for_endpoint("main", event)
    end
  end
end

local function added_handler(self, device)
  device:emit_event(capabilities.button.supportedButtonValues(BUTTON_VALUES))
  device:emit_event(capabilities.button.numberOfButtons({value = 3}))
end

local function device_init(self, device)
  device:set_field(LAST_SEQ_NUMBER_KEY, -1)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function switch_level_set(driver, device, cmd)
  local level = utils.round(cmd.args.level)
  level = utils.clamp_value(level, 0, 99)

  device:emit_event(level > 0 and capabilities.switch.switch.on() or capabilities.switch.switch.off())

  local dimmingDuration = cmd.args.rate or constants.DEFAULT_DIMMING_DURATION
  device:send(SwitchMultilevel:Set({ value=level, duration=dimmingDuration }))
  local query_level = function()
    device:send(SwitchMultilevel:Get({}))
  end
  local delay = math.max(dimmingDuration + constants.DEFAULT_POST_DIMMING_DELAY , constants.MIN_DIMMING_GET_STATUS_DELAY)
  device.thread:call_with_delay(delay, query_level)
end

local do_refresh = function(self, device)
  device:send_to_component(SwitchBinary:Get({}), "main")
  device:send_to_component(SwitchMultilevel:Get({}), "main")
  device:send_to_component(SwitchBinary:Get({}), "switch1")
end


local zooz_zen_30_dimmer_relay_double_switch = {
  NAME = "Zooz Zen 30",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_set
    }
  },
  zwave_handlers = {
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  can_handle = can_handle_zooz_zen_30_dimmer_relay_double_switch
}

return zooz_zen_30_dimmer_relay_double_switch
