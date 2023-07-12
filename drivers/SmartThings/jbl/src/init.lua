--  Copyright 2022 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.
--
--  ===============================================================================================

local log = require "log"

local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local json = require "st.json"
local utils = require "st.utils"

local discovery = require "discovery"
local fields = require "fields"

local jbl_discovery_helper = require "jbl.discovery_helper"
local jbl_device_manager = require "jbl.device_manager"
local jbl_capability_handler = require "jbl.capability_handler"

local EventSource = require "lunchbox.sse.eventsource"

local DEFAULT_MONITORING_INTERVAL = 300
local CREDENTIAL_KEY_HEADER = "Authorization"

local function handle_sse_event(driver, device, msg)
  driver.device_manager.handle_sse_event(driver, device, msg.type, msg.data)
end

local function create_sse(driver, device, credential)
  log.info("create_sse : dni = " .. tostring(device.device_network_id))
  local conn_info = device:get_field(fields.CONN_INFO)

  if not driver.device_manager.is_valid_connection(driver, device, conn_info) then
    log.error("create_sse : invalid connection")
    return
  end

  local sse_url = driver.device_manager.get_sse_url(driver, device, conn_info)
  if not sse_url then
    log.error("failed to get sse_url")
  else
    log.trace("Creating SSE EventSource for " .. device.device_network_id .. ", sse_url = " .. sse_url)
    local eventsource = EventSource.new(sse_url, {[CREDENTIAL_KEY_HEADER] = credential}, nil)

    eventsource.onmessage = function(msg)
      if msg then
        handle_sse_event(driver, device, msg)
      end
    end

    eventsource.onerror = function(msg)
      log.error("Eventsource error: dni = " .. tostring(device.device_network_id) .. ", Error=" .. tostring(msg))
      device:offline()
    end

    eventsource.onopen = function(msg)
      log.info("Eventsource open: dni = " .. tostring(device.device_network_id))
      device:online()
    end

    local old_eventsource = device:get_field(fields.EVENT_SOURCE)
    if old_eventsource then
      log.info("Eventsource Close: dni = " .. tostring(device.device_network_id))
      old_eventsource:close()
    end
    device:set_field(fields.EVENT_SOURCE, eventsource)
  end
end

local function update_connection(driver, device, device_ip, device_info)
  local device_dni = device.device_network_id
  log.info("update connection, dni = " .. tostring(device_dni))

  local conn_info = driver.discovery_helper.get_connection_info(driver, device_dni, device_ip, device_info)

  local credential = device:get_field(fields.CREDENTIAL)

  conn_info:add_header(CREDENTIAL_KEY_HEADER, credential)

  if driver.device_manager.is_valid_connection(driver, device, conn_info) then
    device:set_field(fields.CONN_INFO, conn_info)

    create_sse(driver,device, credential)
  end
end


local function find_new_connetion(driver, device)
  log.info("find new connection for dni=" .. tostring(device.device_network_id))
  local ip_table = discovery.find_ip_table(driver)
  local ip = ip_table[device.device_network_id]
  if ip then
    device:set_field(fields.DEVICE_IPV4, ip, {persist = true})
    local device_info = device:get_field(fields.DEVICE_INFO)
    update_connection(driver, device, ip, device_info)
  end
end

local function check_and_update_connection(driver, device)
  local conn_info = device:get_field(fields.CONN_INFO)
  if not driver.device_manager.is_valid_connection(driver, device, conn_info) then
    device:offline()
    find_new_connetion(driver, device)
    conn_info = device:get_field(fields.CONN_INFO)
  end

  if driver.device_manager.is_valid_connection(driver, device, conn_info) then
    device:online()
  end
end

local function create_monitoring_thread(driver, device, device_info)
  local old_timer = device:get_field(fields.MONITORING_TIMER)
  if old_timer ~= nil then
    log.info("monitoring_timer: dni=" .. device.device_network_id .. ", remove old timer")
    device.thread:cancel_timer(old_timer)
  end

  local monitoring_interval = DEFAULT_MONITORING_INTERVAL

  log.info("create_monitoring_thread: dni=" .. device.device_network_id)
  local new_timer = device.thread:call_on_schedule(monitoring_interval, function()
    check_and_update_connection(driver, device)
    driver.device_manager.device_monitor(driver, device, device_info)
    end, "monitor_timer")
  device:set_field(fields.MONITORING_TIMER, new_timer)
end

local function refresh(driver, device, cmd)
  log.info("refresh : dni =  " .. tostring(device.device_network_id))
  check_and_update_connection(driver, device)
  driver.device_manager.refresh(driver, device)
end

local function device_init(driver, device)
  log.info("device_init : dni = " .. tostring(device.device_network_id))

  local device_dni = device.device_network_id

  driver.controlled_devices[device_dni] = device

  local device_ip = device:get_field(fields.DEVICE_IPV4)
  local device_info = device:get_field(fields.DEVICE_INFO)
  local credential = device:get_field(fields.CREDENTIAL)

  if not credential then
    log.error("failed to find credential.")
    device:offline()
    return
  end

  log.trace("Creating device monitoring for " .. device.device_network_id)
  create_monitoring_thread(driver, device, device_info)

  update_connection(driver, device, device_ip, device_info)
  refresh(driver, device, nil)
end

local lan_driver = Driver("jbl",
  {
    discovery = discovery.do_network_discovery,
    lifecycle_handlers = {added = discovery.device_added, init = device_init},
    capability_handlers = {
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = refresh,
      },
      [capabilities.audioMute.ID] = {
        [capabilities.audioMute.commands.setMute.NAME] = jbl_capability_handler.set_mute_handler,
        [capabilities.audioMute.commands.mute.NAME] = jbl_capability_handler.mute_handler,
        [capabilities.audioMute.commands.unmute.NAME] = jbl_capability_handler.unmute_handler,
      },
      [capabilities.audioVolume.ID] = {
        [capabilities.audioVolume.commands.setVolume.NAME] = jbl_capability_handler.set_volume_handler,
      },
      [capabilities.mediaTrackControl.ID] = {
        [capabilities.mediaTrackControl.commands.nextTrack.NAME] = jbl_capability_handler.next_track_handler,
        [capabilities.mediaTrackControl.commands.previousTrack.NAME] = jbl_capability_handler.previous_track_handler,
      },
      [capabilities.mediaPlayback.ID] = {
        [capabilities.mediaPlayback.commands.play.NAME] = jbl_capability_handler.playback_play_handler,
        [capabilities.mediaPlayback.commands.pause.NAME] = jbl_capability_handler.playback_pause_handler,
      },
      [capabilities.audioNotification.ID] = {
        [capabilities.audioNotification.commands.playTrack.NAME] = jbl_capability_handler.audioNotification_handler,
        [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = jbl_capability_handler.audioNotification_handler,
        [capabilities.audioNotification.commands.playTrackAndResume.NAME] = jbl_capability_handler.audioNotification_handler,
      },
    },

    discovery_helper = jbl_discovery_helper,
    device_manager = jbl_device_manager,
    controlled_devices = {},
  }
)

log.info("Starting lan driver")
lan_driver:run()
log.warn("lan driver exiting")