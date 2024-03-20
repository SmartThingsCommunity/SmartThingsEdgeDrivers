local socket = require('socket')
local cosock = require "cosock"
local log = require('log')
local config = require('config')
local Wisers = require "deepsmart.wisers"
local utils = require('utils.utils')
local ssdp = require('ssdp')
local disco = {}
-----------------------
disco.ssdp_discovery_callback = function(uuid, ip, port, is_add)
  local wisers = {{uuid=uuid, ip=ip,port=port}}
  Wisers.add_wisers(wisers, is_add)
  -- load devices
  local add_devs = {}
  local del_devs = {}
  Wisers.reload(uuid, add_devs, del_devs)
  for i,v in pairs(add_devs) do
    log.info('device found to add in wiser '..uuid)
    Wisers.create_device(v)
  end
end
-- Discovery service which will
-- invoke the above private functions.
--    - find_device
--    - parse_ssdp
--    - fetch_device_info
--    - create_device
--
-- This resource is linked to
-- driver.discovery and it is
-- automatically called when
-- user scan devices from the
-- SmartThings App.
function disco.start(driver, opts, cons)
  log.info('in discover start...')
  ssdp.search(DEEPSMART_SSDP_SEARCH_TERM, disco.ssdp_discovery_callback, true)
  log.info('===== DEVICE DISCOVER DEVICES OVER')
  -- save device_network_id->id
  local devices = driver:get_devices()
  for i,v in pairs(devices) do
    if (v.parent_assigned_child_key ~= nil) then
      log.debug('save dev '..i..' id '..v.id..' networkid '..v.parent_assigned_child_key)
      Wisers.idmap[v.parent_assigned_child_key] = v.id
    end
  end
end

return disco
