local log = require('log')
local Wisers = require "deepsmart.wisers"
local ssdp = require('ssdp')
local net_utils = require('st.net_utils')

local disco = {}
-----------------------
-- app discover new bridges or new devices
disco.ssdp_discovery_callback = function(uuid, ip)
  if (not net_utils.validate_ipv4_string(ip) or uuid == nil) then
    log.warn(string.format('ip (%s) or uuid (%s) is invalid', ip, uuid))
    return
  end
  -- add discovered wiser
  Wisers.add_wiser(uuid, ip, nil)
  Wisers.refresh_wiser(uuid)
end
-- check whether bridge ip changed
disco.ssdp_checkip_callback = function(uuid, ip)
  if (not net_utils.validate_ipv4_string(ip) or uuid == nil) then
    log.warn(string.format('ip (%s) or uuid (%s) is invalid', ip, uuid))
    return
  end
  -- check uuid(if added)
  Wisers.update_wiser_ip(uuid, ip)
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
  ssdp.search(disco.ssdp_discovery_callback)
  log.info('===== DEVICE DISCOVER DEVICES OVER')
end

return disco
