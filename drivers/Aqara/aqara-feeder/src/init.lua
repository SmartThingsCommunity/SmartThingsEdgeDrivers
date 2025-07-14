local ZigbeeDriver = require "st.zigbee"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"

-- [[ Definition ]]
local SEQ_NUM = "SeqNumber"
local FEED_SOURCE = "FeedingSource"
local BTN_LOCK = "stse.buttonLock"
local FEED_TIMER = "FeedingTimer"
local FEED_TIME = 1

local OP_WRITE = 0x02
local OP_REPORT = 0x05

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTR_ID = 0xFFF1
local MFG_CODE = 0x115F

local function reload_portion(device)
  local lastPortion = device:get_latest_state("main", capabilities.feederPortion.ID,
    capabilities.feederPortion.feedPortion.NAME) or 0
  device:emit_event(capabilities.feederPortion.feedPortion({ value = lastPortion, unit = "servings" }))
end
local callback_feed = function(device)
  return function()
    device:emit_event(capabilities.feederOperatingState.feederOperatingState("idle"))
  end
end

local function delete_timer(device)
  local timer = device:get_field(FEED_TIMER)
  if timer then
    device.thread:cancel_timer(timer)
    device:set_field(FEED_TIMER, nil, { persist = true })
  end
end

local function conv_data(param)
  -- convert param to data length & value
  local data_length = string.byte(param, 8)
  local data = 0
  for i = 1, data_length do
    data = (data << 8) + string.byte(param, 8 + i)
  end

  return data
end

-- payload format
-- 0x00 + OP_CODE + seq_num + FuncID A + FuncID B + FuncID C + Data length + Data + ....
local function do_payload(device, funcA, funcB, funcC, op_code, length, value)
  local seq_num = 1
  if device:get_field(SEQ_NUM) ~= nil and device:get_field(SEQ_NUM) < 255 then
    seq_num = device:get_field(SEQ_NUM) + 1
  end
  local data = "\x00" .. string.char(0xFF & op_code) .. string.char(0xFF & seq_num) .. string.char(0xFF & funcA)
      .. string.char(0xFF & funcB) .. string.char(0xFF & (funcC >> 8)) ..
      string.char(0xFF & funcC) .. string.char(0xFF & length)
  for i = length - 1, 0, -1 do
    local tmp = 0xFF & (value >> (i * 8))
    data = data .. string.char(tmp)
  end
  device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTR_ID, MFG_CODE,
    data_types.OctetString, data))
  device:set_field(SEQ_NUM, seq_num, { persist = true })
end

-- [[ capability_handlers ]]
local function do_refresh(driver, device)
  -- refresh
  reload_portion(device)
  do_payload(device, 8, 0, 2001, OP_REPORT, 1, 0)
  device:emit_event(capabilities.feederOperatingState.feederOperatingState("idle"))
end

local function feedingState_handler(driver, device, cmd)
  -- feeding
  do_payload(device, 4, 21, 85, OP_WRITE, 1, 1)
end

local function feedPortion_handler(driver, device, cmd)
  -- set feed portion value
  do_payload(device, 14, 92, 85, OP_WRITE, 4, cmd.args.portion)
end

local function petFeeder_handler(driver, device, value, zb_rx)
  local param = value.value
  local seq_num = string.byte(param, 3)
  local funcID = string.byte(param, 4) ..
      "." .. string.byte(param, 5) .. "." .. ((string.byte(param, 6) << 8) + (string.byte(param, 7)))

  device:set_field(SEQ_NUM, seq_num, { persist = true })

  if funcID == "4.21.85" then
    -- feeding
    device:set_field(FEED_SOURCE, 1, { persist = true })
    device:emit_event(capabilities.feederOperatingState.feederOperatingState("feeding"))
  elseif funcID == "13.9.85" then
    -- power source
    local power_source = "dc"
    if conv_data(param) == 1 then -- 0: adapter / 1: batt
      power_source = "battery"
    end
    device:emit_event(capabilities.powerSource.powerSource(power_source))
  elseif funcID == "14.92.85" then
    -- feed portion
    device:emit_event(capabilities.feederPortion.feedPortion({ value = conv_data(param), unit = "servings" }))
  elseif funcID == "13.104.85" and conv_data(param) ~= 0 then
    local feed_source = device:get_field(FEED_SOURCE) or 0
    if feed_source == 0 then
      device:emit_event(capabilities.feederOperatingState.feederOperatingState("feeding"))
    end
    device:set_field(FEED_SOURCE, 0, { persist = true })
    delete_timer(device)
    device:set_field(FEED_TIMER, device.thread:call_with_delay(FEED_TIME, callback_feed(device)))
  elseif funcID == "13.11.85" then
    -- error
    delete_timer(device)
    local evt = "idle"
    if conv_data(param) == 1 then evt = "error" end
    device:emit_event(capabilities.feederOperatingState.feederOperatingState(evt))
  end
end

-- [[ lifecycle_handlers ]]
local function device_added(driver, device)
  do_payload(device, 4, 24, 85, OP_WRITE, 1, 0)
  device:emit_event(capabilities.feederOperatingState.feederOperatingState("idle"))
  device:emit_event(capabilities.feederPortion.feedPortion({ value = 1, unit = "servings" }))
  device:emit_event(capabilities.powerSource.powerSource("dc"))

  -- init variable
  device:set_field(SEQ_NUM, 1, { persist = true })
  device:set_field(FEED_SOURCE, 0, { persist = true })
end

local function device_info_changed(driver, device, event, args)
  if device.preferences ~= nil and device.preferences[BTN_LOCK] ~= args.old_st_store.preferences[BTN_LOCK] then
    -- BTN_LOCK_MODE
    local state = 0
    if device.preferences[BTN_LOCK] == true then
      state = 1
    end
    do_payload(device, 4, 22, 85, OP_WRITE, 1, state)
  end
end

local function device_configure(driver, device)
  -- private protocol enable
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, 0x0009, MFG_CODE, data_types.Uint8, 1))
  do_payload(device, 4, 24, 85, OP_WRITE, 1, 0)
end

-- [[ Registration ]]
local aqara_pet_feeder_handler = {
  NAME = "Aqara Smart Pet Feeder C1",
  supported_capabilities = {
    capabilities.feederOperatingState,
    capabilities.feederPortion,
    capabilities.refresh
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [capabilities.feederOperatingState.ID] = {
      [capabilities.feederOperatingState.commands.startFeeding.NAME] = feedingState_handler
    },
    [capabilities.feederPortion.ID] = {
      [capabilities.feederPortion.commands.setPortion.NAME] = feedPortion_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_ATTR_ID] = petFeeder_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    infoChanged = device_info_changed,
    doConfigure = device_configure
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "aqara.feeder.acn001"
  end
}

local aqara_strip_driver = ZigbeeDriver("aqara_pet_feeder", aqara_pet_feeder_handler)
aqara_strip_driver:run()
