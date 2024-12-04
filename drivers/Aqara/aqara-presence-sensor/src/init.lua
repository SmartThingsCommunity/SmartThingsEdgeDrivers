local log = require "log"
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local discovery = require "discovery"
local fields = require "fields"
local fp2_discovery_helper = require "fp2.discovery_helper"
local fp2_device_manager = require "fp2.device_manager"
local fp2_api = require "fp2.api"
local multipleZonePresence = require "multipleZonePresence"
local EventSource = require "lunchbox.sse.eventsource"

local DEFAULT_MONITORING_INTERVAL = 300
local CREDENTIAL_KEY_HEADER = "Authorization"

local function handle_sse_event(driver, device, msg)
  driver.device_manager.handle_sse_event(driver, device, msg.type, msg.data)
end

local function status_update(driver, device)
  local conn_info = device:get_field(fields.CONN_INFO)
  if not conn_info then
    log.warn(string.format("refresh : failed to find conn_info, dni = %s", device.device_network_id))
    return false, "failed to find conn_info"
  else
    local resp, err, status = conn_info:get_attr()

    if err or status ~= 200 then
      log.error(string.format("refresh : failed to get attr, dni= %s, err= %s, status= %s", device.device_network_id, err,
        status))
      return false, "failed to get attr"
    else
      driver.device_manager.handle_status(driver, device, resp)
    end
  end
  return true
end

local function create_sse(driver, device, credential)
  local conn_info = device:get_field(fields.CONN_INFO)

  local sse_url = driver.device_manager.get_sse_url(driver, device, conn_info)
  if not sse_url then
    log.error_with({ hub_logs = true }, "failed to get sse_url")
  else
    log.trace(string.format("Creating SSE EventSource for %s, sse_url= %s", device.device_network_id, sse_url))
    local label = string.format("%s-SSE", device.device_network_id)
    local eventsource = EventSource.new(sse_url, { [CREDENTIAL_KEY_HEADER] = credential },
      fp2_api.labeled_socket_builder(label))

    eventsource.onmessage = function(msg)
      if msg then
        handle_sse_event(driver, device, msg)
      end
    end

    eventsource.onerror = function()
      log.error(string.format("Eventsource error: dni= %s", device.device_network_id))
      device:offline()
    end

    eventsource.onopen = function()
      log.info_with({ hub_logs = true }, string.format("Eventsource open: dni= %s", device.device_network_id))
      device:online()
      local success, err = status_update(driver, device)
      if not success then
        log.warn(string.format("Failed to status_update during eventsource.onopen, err = %s dni= %s", err, device.device_network_id))
        success, err = status_update(driver, device)
        if not success then
          log.error_with({ hub_logs = true }, string.format("Failed to status_update during eventsource.onopen again, err = %s dni= %s", err, device.device_network_id))
        end
      end
    end

    local old_eventsource = device:get_field(fields.EVENT_SOURCE)
    if old_eventsource then
      old_eventsource:close()
    end
    device:set_field(fields.EVENT_SOURCE, eventsource)
  end
end

local function update_connection(driver, device, device_ip, device_info)
  local device_dni = device.device_network_id
  local conn_info = driver.discovery_helper.get_connection_info(driver, device_dni, device_ip, device_info)
  local credential = device:get_field(fields.CREDENTIAL)

  conn_info:add_header(CREDENTIAL_KEY_HEADER, credential)

  if driver.device_manager.is_valid_connection(driver, device, conn_info) then
    device:set_field(fields.CONN_INFO, conn_info)

    create_sse(driver, device, credential)
  end
end


local function find_new_connection(driver, device)
  local ip_table = discovery.find_ip_table(driver)
  local ip = ip_table[device.device_network_id]
  if ip then
    device:set_field(fields.DEVICE_IPV4, ip, { persist = true })
    local device_info = device:get_field(fields.DEVICE_INFO)
    update_connection(driver, device, ip, device_info)
  else
    log.warn("find new conneciton : ip is nil")
  end
end

local function check_and_update_connection(driver, device)
  local conn_info = device:get_field(fields.CONN_INFO)
  local eventsource = device:get_field(fields.EVENT_SOURCE)
  if eventsource and eventsource.ready_state == eventsource.ReadyStates.OPEN then
    log.info(string.format("SSE connection is being maintained well, dni = %s", device.device_network_id))
  elseif not driver.device_manager.is_valid_connection(driver, device, conn_info) then
    find_new_connection(driver, device)
  end
end

local function create_monitoring_thread(driver, device, device_info)
  local old_timer = device:get_field(fields.MONITORING_TIMER)
  if old_timer ~= nil then
    device.thread:cancel_timer(old_timer)
  end

  local monitoring_interval = DEFAULT_MONITORING_INTERVAL
  local new_timer = device.thread:call_on_schedule(monitoring_interval, function()
    check_and_update_connection(driver, device)
    driver.device_manager.device_monitor(driver, device, device_info)
  end, "monitor_timer")
  device:set_field(fields.MONITORING_TIMER, new_timer)
end



local function do_refresh(driver, device, cmd)
  local success, err = status_update(driver, device)
  if not success then
    log.info(string.format("Failed to status_update during do_refresh, err = %s dni= %s", err, device.device_network_id))
    check_and_update_connection(driver, device)
  end
  driver.device_manager.init_presence(driver, device)
  driver.device_manager.init_movement(driver, device)
  driver.device_manager.init_activity(driver, device)
end

local function device_removed(driver, device)
  local conn_info = device:get_field(fields.CONN_INFO)
  if not conn_info then
    log.warn(string.format("remove : failed to find conn_info, dni = %s", device.device_network_id))
  else
    local _, err, status = conn_info:get_remove()

    if err or status ~= 200 then
      log.error(string.format("remove : failed to get remove, dni= %s, err= %s, status= %s", device.device_network_id,
        err,
        status))
    end
  end

  local eventsource = device:get_field(fields.EVENT_SOURCE)
  if eventsource then
    eventsource:close()
  end
end

local function device_init(driver, device)
  if device:get_field(fields._INIT) then
    return
  end
  device:set_field(fields._INIT, true, { persist = false })

  local device_dni = device.device_network_id
  driver.controlled_devices[device_dni] = device

  if driver.datastore.discovery_cache[device_dni] then
    log.warn("set unsaved device field")
    discovery.set_device_field(driver, device)
  end

  local device_ip = device:get_field(fields.DEVICE_IPV4)
  local device_info = device:get_field(fields.DEVICE_INFO)
  local credential = device:get_field(fields.CREDENTIAL)

  if not credential then
    log.error_with({ hub_logs = true }, "failed to find credential.")
    device:offline()
    return
  end

  driver.device_manager.set_zone_info_to_latest_state(driver, device)

  log.trace(string.format("Creating device monitoring for %s", device.device_network_id))
  create_monitoring_thread(driver, device, device_info)

  update_connection(driver, device, device_ip, device_info)

  do_refresh(driver, device, nil)
end

local function device_info_changed(driver, device, event, args)
  do_refresh(driver, device, nil)
end

local lan_driver = Driver("aqara-fp2",
  {
    discovery = discovery.do_network_discovery,
    lifecycle_handlers = {
      added = discovery.device_added,
      init = device_init,
      infoChanged = device_info_changed,
      removed = device_removed
    },
    capability_handlers = {
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = do_refresh,
      },
      [multipleZonePresence.id] = {
        [multipleZonePresence.commands.updateZoneName.name] = multipleZonePresence.commands.updateZoneName.handler,
      }
    },
    discovery_helper = fp2_discovery_helper,
    device_manager = fp2_device_manager,
    controlled_devices = {},
  }
)

if lan_driver.datastore.discovery_cache == nil then
  lan_driver.datastore.discovery_cache = {}
end

lan_driver:run()
