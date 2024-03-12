local log = require "log"

local fields = require "fields"
local discovery_mdns = require "discovery_mdns"

local socket = require "cosock.socket"
local st_utils = require "st.utils"

local discovery = {}

-- mapping from device DNI to info needed at discovery/init time
local joined_device = {}

function discovery.set_device_field(driver, device)

  log.info(string.format("set_device_field : %s", device.device_network_id))
  local device_cache_value = driver.datastore.discovery_cache[device.device_network_id]

  -- persistent fields
  device:set_field(fields.DEVICE_IPV4, device_cache_value.ip, {persist = true})
  device:set_field(fields.CREDENTIAL, device_cache_value.credential , {persist = true})
  device:set_field(fields.DEVICE_INFO, device_cache_value.device_info , {persist = true})
  driver.datastore.discovery_cache[device.device_network_id] = nil
end

local function update_device_discovery_cache(driver, dni, ip, credential)
  log.info(string.format("update_device_discovery_cache for device dni: %s, %s", dni, ip))
  local device_info = driver.discovery_helper.get_device_info(driver, dni, ip)
  driver.datastore.discovery_cache[dni] = {
    ip = ip,
    device_info = device_info,
    credential = credential,
  }
end

local function try_add_device(driver, device_dni, device_ip)
  log.trace(string.format("try_add_device : dni=%s, ip=%s", device_dni, device_ip))

  local credential  = driver.discovery_helper.get_credential(driver, device_dni, device_ip)

  if not credential then
    log.error(string.format("failed to get credential. dni=%s, ip=%s", device_dni, device_ip))
    joined_device[device_dni] = nil
    return
  end

  update_device_discovery_cache(driver, device_dni, device_ip, credential)
  local create_device_msg = driver.discovery_helper.get_device_create_msg(driver, device_dni, device_ip)
  driver:try_create_device(create_device_msg)
end

function discovery.device_added(driver, device)
  log.info("device_added : dni = " .. tostring(device.device_network_id))

  discovery.set_device_field(driver, device)
  joined_device[device.device_network_id] = nil
  driver.lifecycle_handlers.init(driver, device)
end

function discovery.find_ip_table(driver)
  local ip_table= discovery_mdns.find_ip_table_by_mdns(driver)
  return ip_table
end


local function discovery_device(driver)
  local known_devices = {}

  for _, device in pairs(driver:get_devices()) do
    known_devices[device.device_network_id] = device
  end

  local ip_table = discovery.find_ip_table(driver)

  log.debug(st_utils.stringify_table(ip_table, "DNI IP Table after processing mDNS Discovery Response", true))

  for dni, ip in pairs(ip_table) do
    log.info(string.format("discovery_device dni, ip = %s, %s", dni, ip))
    if not known_devices or not known_devices[dni] then
      log.trace(string.format("unknown dni= %s, ip= %s", dni, ip))
      if not joined_device[dni] then
        try_add_device(driver, dni, ip)
        joined_device[dni] = true
      end
    else
      log.trace(string.format("known dni= %s, ip= %s", dni, ip))
    end
  end
end

function discovery.do_network_discovery(driver, _, should_continue)
  log.info("discovery.do_network_discovery  :Starting mDNS discovery")

  while should_continue() do
    discovery_device(driver)
    socket.sleep(0.2)
  end
  log.info("discovery.do_network_discovery: Ending mDNS discovery")
end

return discovery
