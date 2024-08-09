local log = require('log')
local json = require('st.json')
local caps = require('st.capabilities')
local api = require('deepsmart.api')
local Devices = require('deepsmart.devices')
local dp2knx = require('deepsmart.dp2knx')
local dpenum = require('deepsmart.dpenum')
local config = require('config')
local ssdp = require('ssdp')
local Wisers = {}


Wisers.wisers = {}
Wisers.idmap = {}
Wisers.ips = {}
----------
-- parse device_network_id to dev_id,idx
-- deepsmart device's device_network_id is defined as wiser:pid:id[_idx], _idx is optional
-- if one deepsmart device convert to one hub device then idx is ignored
-- else one deepsmart device convert to several hub devices then idx is needed,
-- as wiser:pid:id_1 -> first device
-- as wiser:pid:id_2 -> second device
-- as wiser:pid:id_n -> nth device
----------
function Wisers.parse_device_network_id(device_network_id)
  local dev_id = device_network_id
  local idx = 1
  -- if _ exists then idx exists
  local beginpos,endpos = string.find(dev_id, '_')
  if (beginpos ~= nil) then
    dev_id = string.sub(device_network_id, 1, beginpos-1)
    local str = string.sub(device_network_id, endpos+1)
    idx = tonumber(str)
  end
  -- find pid
  local pid = nil
  beginpos,endpos = string.find(dev_id, ':')
  if (beginpos ~= nil) then
    local str = string.sub(device_network_id, endpos+1)
    local pos,_ = string.find(str, ':')
    if (pos ~= nil) then
      pid = string.sub(device_network_id, 1, pos-1)
    end
  end
  return dev_id,pid,idx
end
---------------
-- Parse protocol
function Wisers.get_wiser(wiser_index_code)
  return Wisers.wisers[wiser_index_code]
end


-- check if device is bridge
function Wisers.is_device_bridge(device)
  if (device.parent_assigned_child_key == nil) then
    return true
  end
  return false
end
-------------
-- it runs every 30s
-- it will find new wisers around and refresh the binded wiser info when wiser is online
-------------
function Wisers.check_ip(discovery)
  -- find all wisers
  ssdp.search(discovery.ssdp_checkip_callback)
end

-- try update wiser(if added) ip
function Wisers.update_wiser_ip(uuid, ip)
  local wiser = Wisers.get_wiser(uuid)
  if (wiser == nil) then
    log.warn('wiser '..uuid..' not exist')
    return
  end
  if (wiser.ip ~= ip) then
    log.info('wiser '..uuid..' change ip to '..(ip or ''))
    wiser["ip"] = ip
    if (wiser.api ~= nil) then
      wiser.api:shutdown()
    end
    if (wiser.loopapi ~= nil) then
      wiser.loopapi:shutdown()
    end
    wiser["api"] = api.client(uuid, ip)
    wiser["loopapi"] = api.client(uuid, ip)
  end
end

function Wisers.wiser_loop(wiser_index_code)
  local wiser = Wisers.get_wiser(wiser_index_code)
  if (wiser == nil) then
    log.warn('wiser '..wiser_index_code..' not exist')
    return
  end
  if (wiser.config == nil) then
    log.trace('wiser has no devices')
    return
  end
  if (wiser.loopapi == nil) then
    log.trace('wiser api is not inited')
    return
  end
  -- get wiser
  -- query changed devs
  local ret,res = wiser.loopapi:load_changeddevs(wiser.last_active_time)
  if (ret) then
    log.trace('load changed devs '..res..' old state '..wiser.state)
    -- parse changed devs
    local _,js = pcall(json.decode, res)
    if (js ~= nil and js.data ~= nil and js.data.last ~= nil and js.data.devs ~= nil) then
      wiser.last_active_time = js.data.last
      log.trace('change wiser '..wiser_index_code..' last time '..wiser.last_active_time)
      for _,v in pairs(js.data.devs) do
        -- dev empty is wiser
        if (v == '') then
          -- refresh subdevice status
          Wisers.driver:inject_capability_command(wiser.bridge, {
            capability = caps.refresh.ID,
            command = caps.refresh.commands.refresh.NAME,
            args = {}
          })
        else
          log.trace('query changed dev '..v)
          Wisers.query_deviceid(v, true)
        end
      end
    end
    -- has response means bridge is online
    wiser.bridge:online()
    if (wiser.state == 0) then
      log.trace('wiser '..wiser_index_code..' online')
      wiser.state = 1
      Wisers.refresh_wiser_devices(wiser_index_code)
    end
  else
    log.trace('load changed devs nil old state '..wiser.state)
    -- no response means bridge is offline
    if (wiser.state == 1) then
      wiser.state = 0
      log.trace('wiser '..wiser_index_code..' offline')
      wiser.bridge:offline()
    end
  end
end


function Wisers.create_device(device)
  log.info('===== CREATING DEVICE...')
  local wiser = Wisers.get_wiser(device.wiser_index_code)
  if (wiser == nil) then
    log.warn('device '..device.dev_id..' wiser '..device.wiser_index_code..' not exist')
    return 0
  end
  if (wiser.bridge == nil) then
    log.warn('device '..device.dev_id..' wiser '..device.wiser_index_code..' bridge not inited')
    return 0
  end
  if (device.productId == nil) then
    log.trace('ignore device '..device.dev_id..' with null pid')
    return 0
  end
  -- parse type
  local dev_type = wiser.dp2knx:get_pid_type(device.productId)
  if (dev_type == nil) then
    log.warn('device '..device.dev_id..' productId '..device.productId..' is not configed')
    return 0
  end
  log.trace('dev '..device.dev_id..' productId '..device.productId..' dev_type '..dev_type)
  if (config.DEVICE_PROFILE[dev_type] == nil)  then
    log.warn('device type '..dev_type..' is not supported now')
    return 0
  end
  -- find device count
  local dev_count = wiser.dp2knx:get_dev_count(device.productId)
  if (dev_count == nil or dev_count == 0) then
    log.warn('pid '..device.productId..' has no devs configed')
    return 0
  end
  log.info('pid '..device.productId..' has dev count '..dev_count)
  for i = 1,dev_count do
    local dev_name = device.name
    local dev_id = device.dev_id
    if (dev_count > 1) then
      dev_name = device.name..'_'..i
      dev_id = device.dev_id..'_'..i
    end
    log.info('create device '..dev_id..' i '..i..' name '..dev_name)
    -- device metadata table
    local metadata = {
      type = 'EDGE_CHILD',
      label = dev_name,
      profile = config.DEVICE_PROFILE[dev_type],
      manufacturer = 'deepsmart',
      model = 'deepsmart',
      vendor_provided_label = device.name,
      parent_device_id = wiser.bridge.id,
      parent_assigned_child_key = dev_id
    }
    Wisers.driver:try_create_device(metadata)
  end
  return 0
end

------------
-- refresh single wiser
-- load wiser all configs and create new device
------------
function Wisers.refresh_wiser(wiser_index_code)
  log.info('refresh wiser '..wiser_index_code)
  local wiser = Wisers.get_wiser(wiser_index_code)
  if (wiser == nil) then
    log.warn(' wiser '..wiser_index_code..' not exist')
    return 0
  end
  local add_devs = {}
  local del_devs = {}
  Wisers.reload(wiser_index_code, add_devs, del_devs)
  log.trace('refresh_wiser '..wiser_index_code..' add '..#add_devs..' del '..#del_devs)
  -- add devices
  for _,v in pairs(add_devs) do
    Wisers.create_device(v)
  end
  log.trace('refresh_wiser '..wiser_index_code..' after create device')
  -- del devices
  for dev_id,_ in pairs(del_devs) do
    local id = Wisers.idmap[dev_id]
    if (id == nil) then
      log.trace('dev '..dev_id..' has no hub device')
      goto delretry
    end
    log.trace('get dev '..dev_id..' hub devid '..id)
    local dev = Wisers.driver:get_device_info(id)
    if (dev == nil) then
      log.warn('dev '..id..' is not in hub')
      goto delretry
    else
      log.info('del dev_id '..dev_id..' hub id '..id..' device')
      dev:set_field(config.FIELD.INVALID, 1, { persist = true})
    end
    ::delretry::
  end
  -- save device_network_id->id
  local devices = Wisers.driver:get_devices()
  for i,v in pairs(devices) do
    if (v.parent_assigned_child_key ~= nil) then
      log.debug('save dev '..i..' id '..v.id..' networkid '..v.parent_assigned_child_key)
      Wisers.idmap[v.parent_assigned_child_key] = v.id
    end
  end
  -- refresh wiser devices online
  Wisers.refresh_wiser_devices(wiser_index_code)
  log.info('refresh wiser success')
  return true,nil
end

function Wisers.refresh_wiser_devices(wiser_index_code)
  log.info('refresh wiser '..wiser_index_code)
  local wiser = Wisers.get_wiser(wiser_index_code)
  if (wiser == nil) then
    log.warn(' wiser '..wiser_index_code..' not exist')
    return false,'wiser not exist'
  end
  -- refresh wiser devices online
  if (wiser.config ~= nil and wiser.config.devices ~= nil) then
    for dev_id,_ in pairs(wiser.config.devices) do
      -- find hub dev
      local id = Wisers.idmap[dev_id]
      if (id == nil) then
        log.warn('dev '..dev_id..' is not in hub idmap')
        goto devretry
      end
      log.trace('get dev '..dev_id..' hub devid '..id)
      local dev = Wisers.driver:get_device_info(id)
      if (dev == nil) then
        log.warn('dev '..id..' is not in hub')
        goto devretry
      end
      local flag = dev:get_field(config.FIELD.INVALID)
      if (flag == nil or flag == 0) then
        log.trace('dev '..dev_id..' online')
        dev:online()
      else
        log.trace('dev '..dev_id..' offline')
        dev:offline()
      end
      ::devretry::
    end
  end
  log.info('refresh wiser devices success')
  return true,nil
end

------------------
-- add wiser
-- create wiser client(https)
-- api: load device configs, dp2knx config, dpenum config
------------------
function Wisers.add_wiser(uuid, ip, bridge)
  -- init all wisers
  log.info('add wiser '..uuid..' ip('..(ip or 'nil')..')')
  local wiser = Wisers.get_wiser(uuid)
  -- first check wiser ip, if ip is same then do nothing
  -- in case the wiser's ip changed by dhcp or router restart or router changed or mannal static ip change
  if (wiser ~= nil and wiser.ip == ip) then
    log.trace('wiser '..uuid..' is same')
    return
  end
  -- if wiser is new then create new wiser
  if (wiser == nil) then
    -- create bridge device
    -- if bridge is nil then new bridge is added
    -- after try_create_device just return(in lifecycle added func will add new wiser)
    if (bridge == nil) then
      local wiser_device_msg = {
        type = "LAN",
        device_network_id = uuid,
        label = "DEEPSMART KNX bridge-"..uuid,
        profile = "Deepsmart.bridge",
        manufacturer = "DEEPSMART",
        model = "KNX gateway",
        vendor_provided_label = "DEEPSMART KNX bridge"
      }
      -- save wiser ip
      Wisers.ips[uuid] = ip
      log.trace('create bridge device')
      Wisers.driver:try_create_device(wiser_device_msg)
      return
    end
    log.debug('create wiser '..uuid)
    Wisers.wisers[uuid] = {}
    wiser = Wisers.wisers[uuid]
    wiser.bridge = bridge
    wiser.state = 1
    wiser.ctrlmap = {}
    wiser["wiser_index_code"] = uuid
    wiser["last_active_time"] = "0"
    wiser["ip"] = ip
    -- wiser online
    bridge:online()
    if (ip ~= nil) then
      wiser["api"] = api.client(uuid, ip)
      wiser["loopapi"] = api.client(uuid, ip)
    end
    local config_str = bridge:get_field(config.FIELD.DEVICES)
    local dp2knx_str = bridge:get_field(config.FIELD.DP2KNX)
    local dpenum_str = bridge:get_field(config.FIELD.DPENUM)
    wiser["config"] = Devices.load_config(uuid, config_str, nil, nil, nil)
    wiser["dp2knx"] = dp2knx.load_config(uuid, dp2knx_str)
    wiser["dpenum"] = dpenum.load_config(uuid, dpenum_str)
  end
  -- wiser loop for get updated devices from wiser
  -- every 2second use https api to get updated devices from given time
  -- after get results save the last time for next request
  Wisers.driver:call_on_schedule(
  2,
  function ()
    return Wisers.wiser_loop(uuid)
  end,
  'wiser loop')
  log.info('add wisers over')
end
------------
-- del device
------------
function Wisers.del_device_by_id(devid)
  local id = Wisers.idmap[devid]
  if (id == nil) then
    log.warn('dev '..devid..' is not in hub')
    return false
  end
  log.info('dev '..devid..' hub id '..id..' delete from hub')
  Wisers.driver:try_delete_device(id)
  return true
end
function Wisers.del_device(device)
  local parent_assigned_child_key = device.parent_assigned_child_key
  log.info('del device device_network_id '..device.device_network_id)
  if (parent_assigned_child_key == nil) then
    log.info('del bridge '..device.device_network_id)
    Wisers.del_wiser(device.device_network_id)
    Wisers.driver:try_delete_device(device.id)
  else
    -- del device from hub
    log.info('del device '..device.id)
    Wisers.driver:try_delete_device(device.id)
    local dev_id,_,idx = Wisers.parse_device_network_id(parent_assigned_child_key)
    log.trace('del device '..parent_assigned_child_key..' -> dev_id '..dev_id..' idx '..idx)
    -- get device wiser
    local wiser,_ = Wisers.get_device_wiser(dev_id)
    if (wiser == nil) then
      log.warn('device '..dev_id..' is not exist for del device')
      return false,'wiser is nil'
    end
    -- del config dev
    if (wiser.config ~= nil and wiser.config.devices ~= nil) then
      wiser.config.devices[dev_id] = nil
    end
  end
end
------------
-- unbind the wiser
-- it's not used now(no scene to use)
------------
function Wisers.del_wiser(wiser_index_code)
  local wiser = Wisers.get_wiser(wiser_index_code)
  if (wiser == nil) then
    return false
  end
  wiser.state = 0
  Wisers.wisers[wiser_index_code] = nil
  log.info('wiser '..wiser_index_code..' del over')
  return true
end
---------------
-- get device wiser
-- returns
--    wiser,device
---------------
function Wisers.get_device_wiser(dev_id)
  -- check all wisers to find the device
  for i,wiser in pairs(Wisers.wisers) do
    if (wiser.config ~= nil and wiser.config.devices ~= nil) then
      local device = wiser.config.devices[dev_id]
      if (device ~= nil) then
        return wiser,device
      end
    end
  end
  return nil,nil
end


-- reload devices&&dps
function Wisers.reload(uuid, add_devs, del_devs)
  local wiser = Wisers.get_wiser(uuid)
  if (wiser == nil or wiser.bridge == nil) then
    log.warn('wiser '..uuid..' is not exist for reload')
    return true
  end
  log.info('reload wiser '..wiser.wiser_index_code..' ip('..(wiser.ip or '')..')')
  -- if wiser ip is not changed then do nothing
  local deepsmartapi = wiser.api
  if (deepsmartapi == nil) then
    log.trace('wiser api is not inited')
    return false
  end
  -- get devices
  local configret,configstr = deepsmartapi:load_config()
  log.trace(string.format('load config (%s)', configstr))
  if (configret and configstr ~= wiser.bridge:get_field(config.FIELD.DEVICES)) then
    local old_config = wiser.config
    wiser["config"] = Devices.load_config(wiser.wiser_index_code, configstr, old_config, add_devs, del_devs)
    wiser.bridge:set_field(config.FIELD.DEVICES, configstr, { persist = true})
  end
  -- get dp info
  local dp2knxret,dp2knx_config = deepsmartapi:load_dp2knx()
  if (dp2knxret and dp2knx_config ~= wiser.bridge:get_field(config.FIELD.DP2KNX)) then
    wiser["dp2knx"] = dp2knx.load_config(wiser.wiser_index_code, dp2knx_config)
    wiser.bridge:set_field(config.FIELD.DP2KNX, dp2knx_config, { persist = true})
  end
  -- get enum info
  local dpenumret,dpenum_config = deepsmartapi:load_dpenum()
  if (dpenumret and dpenum_config ~= wiser.bridge:get_field(config.FIELD.DPENUM)) then
    wiser["dpenum"] = dpenum.load_config(wiser.wiser_index_code, dpenum_config)
    wiser.bridge:set_field(config.FIELD.DPENUM, dpenum_config, { persist = true})
  end
  return true
end

--------------
-- refresh hub device
-- just query deepsmart device
--------------
function Wisers.refresh(device)
  return Wisers.query(device, false)
end


------------
-- process deepsmart knx control command
-- same with response
------------
function Wisers.knx_control(wiser_index_code, addr, dataType, value, delay)
  local vals = {[addr] = value}
  log.info('control addr '..addr..' dataType '..dataType..' value '..value)
  return Wisers.knx_response(wiser_index_code, vals)
end

------------
-- process deepsmart knx response
-- refresh hub device status
------------
function Wisers.knx_response(wiser_index_code, knxes)
  local wiser = Wisers.get_wiser(wiser_index_code)
  if (wiser == nil) then
    log.warn('wiser '..wiser_index_code..' is not exist for response addrs')
    return 0
  end
  -- deal all knxes one by one
  for addr,value in pairs(knxes) do
    log.info('wiser '..wiser_index_code..' response addr '..addr..' value '..value)
    if (wiser.config == nil) then
      log.warn('wiser '..wiser_index_code..' has no config')
      goto knxretry
    end
    -- get dps by addr
    local dps = wiser.config:get_addr_dev_dpid(addr)
    if (dps == nil) then
      log.warn('addr '..addr..' has no dps')
      goto knxretry
    end
    log.trace('wiser '..wiser_index_code..' response addr '..addr..' get dps count '..#dps)
    for i,dp in pairs(dps) do
      local dpid = dp.dpid
      log.trace(' addr '..addr..' -> dev_id '..dp.dev_id..' dpid '..dpid)
      -- convert val to smartthings
      local device = wiser.config:get_device(dp.dev_id)
      if (device == nil) then
        log.warn('dev '..dp.dev_id..' is not exist for response')
        goto dpretry
      end
      local dev_id = dp.dev_id
      local dev_count = wiser.dp2knx:get_dev_count(device.productId)
      log.trace('pid '..device.productId..' get dev count '..dev_count)
      local devtype,addrtype,idx = wiser.dp2knx:get_addrtype_by_pid_dpid(device.productId, dpid)
      if (dev_count > 1) then
        dev_id = dp.dev_id..'_'..idx
      end
      -- find hub dev
      local id = Wisers.idmap[dev_id]
      if (id == nil) then
        log.warn('dev '..dev_id..' is not in hub idmap')
        goto dpretry
      end
      log.trace('get dev '..dev_id..' hub devid '..id)
      local dev = Wisers.driver:get_device_info(id)
      if (dev == nil) then
        log.warn('dev '..id..' is not in hub')
        goto dpretry
      end
      if (devtype ~= nil and addrtype ~= nil) then
        log.trace('dev '..dev_id..' pid '..device.productId..' convert to devtype '..devtype..' addrtype '..addrtype)
        if (devtype == config.ENUM.AC) then
          if (addrtype == 0) then
            local on_off = 'off'
            if (value ~= 0) then
              on_off = 'on'
            end
            Wisers.driver:set_switch(dev, on_off)
          elseif (addrtype == 1) then
            local mode = wiser.dpenum:get_dev_val_by_pid_val(device.productId, dpid, value)
            Wisers.driver:ac_report(dev, nil, mode, nil,nil, nil,nil)
          elseif (addrtype == 2) then
            local fan = wiser.dpenum:get_dev_val_by_pid_val(device.productId, dpid, value)
            Wisers.driver:ac_report(dev, nil,nil,fan,nil, nil,nil)
          elseif (addrtype == 3) then
            Wisers.driver:ac_report(dev, nil,nil,nil,value/100, nil,nil)
          elseif (addrtype == 4) then
            Wisers.driver:ac_report(dev, nil,nil,nil,nil, value/100,nil)
          end
        elseif (devtype == config.ENUM.HEATER) then
          if (addrtype == 0) then
            local on_off = 'off'
            if (value ~= 0) then
              on_off = 'on'
            end
            Wisers.driver:heater_report(dev, on_off, nil,nil,nil)
          elseif (addrtype == 2) then
            Wisers.driver:heater_report(dev, nil,value/100,nil,nil)
          elseif (addrtype == 3) then
            Wisers.driver:heater_report(dev, nil,nil,value/100,nil)
          end
        elseif (devtype == config.ENUM.NEWFAN) then
          if (addrtype == 0) then
            local on_off = 'off'
            if (value ~= 0) then
              on_off = 'on'
            end
            Wisers.driver:set_switch(dev, on_off)
          elseif (addrtype == 1) then
            local fan = wiser.dpenum:get_dev_val_by_pid_val(device.productId, dpid, value)
            Wisers.driver:ac_report(dev, nil,nil,fan,nil, nil,nil)
          end
        end
      else
        log.trace('pid '..device.productId..' dpid '..dpid..' convert to devtype addrtype nil')
      end
      ::dpretry::
    end
    ::knxretry::
  end
  return 0
end

--------------
-- get devtype by device_network_id
--------------
function Wisers.get_dev_type(device)
  log.trace('get device '..(device.parent_assigned_child_key or 'nil')..' devtype')
  if (device.profile.components.main.capabilities.airConditionerMode ~= nil) then
    log.trace('get device '..(device.parent_assigned_child_key or 'nil')..' devtype ac')
    return config.ENUM.AC
  elseif (device.profile.components.main.capabilities.thermostatMode ~= nil) then
    log.trace('get device '..(device.parent_assigned_child_key or 'nil')..' devtype heater')
    return config.ENUM.HEATER
  else
    log.trace('get device '..(device.parent_assigned_child_key or 'nil')..' devtype newfan')
    return config.ENUM.NEWFAN
  end
end

---------------
-- test code
-- report default value to control device
---------------
function Wisers.default_report(driver, device)
  local uuid = device.parent_assigned_child_key
  local dev_id,_,idx = Wisers.parse_device_network_id(uuid)
  log.trace('device '..uuid..' -> dev_id '..dev_id..' idx '..idx..' default report')
  local wiser,dev = Wisers.get_device_wiser(dev_id)
  if (wiser == nil) then
    log.warn('device '..device.parent_assigned_child_key..' is not exist for read')
    return false,'device not exist'
  end
  if (dev == nil) then
    log.warn('device '..device.dev_id..' is not in wiser devs')
    return false,'device is not in wisers'
  end
  local devtype = wiser.dp2knx:get_pid_type(dev.productId)
  log.trace('dev '..dev.productId..' get type '..devtype)
  if (devtype == config.ENUM.AC) then
    driver:ac_report(device, "off", "auto", "auto", 25, 25, nil)
  elseif (devtype == config.ENUM.HEATER) then
    driver:ac_report(device, "off", nil, nil, 25, 25, nil)
  elseif (devtype == config.ENUM.NEWFAN) then
    driver:ac_report(device, "off", nil, "low", nil,nil, nil)
  end
  return true,nil
end

--------------
-- query hub device
-- 1 find wiser
-- 2 get all feedback addrs
-- 3 query all addrs
--------------
function Wisers.query_deviceid(uuid, use_loop)
  local dev_id,_,idx = Wisers.parse_device_network_id(uuid)
  log.trace('device '..uuid..' -> dev_id '..dev_id..' idx '..idx..' query')
  local wiser = Wisers.get_device_wiser(dev_id)
  if (wiser == nil) then
    log.warn('device '..uuid..' is not exist for read')
    return false,'device not exist'
  end
  -- find all feedback addrs
  local sendlist,recv = wiser.config:get_dev_addrs(dev_id)
  if (recv ~= nil) then
    local addrs = {}
    local recv2send = {}
    local ignore_recv = {}
    for dpid,addr in pairs(recv) do
      addrs[#addrs+1] = addr.addr_int
      log.trace('query dev '..dev_id..' recv addr '..addr.addr_int)
      if (sendlist ~= nil and sendlist[dpid] ~= nil) then
        local send_addr = sendlist[dpid]
        if (send_addr.addr_int ~= addr.addr_int) then
          if (wiser.ctrlmap[send_addr.addr_int] ~= nil) then
            ignore_recv[addr.addr_int] = 1
            log.trace('ignore recv addr '..addr.addr_int..' as send addr '..send_addr.addr_int..' control is just used')
          end
          recv2send[addr.addr_int] = send_addr.addr_int
          addrs[#addrs+1] = send_addr.addr_int
          log.trace('query dev '..dev_id..' send addr '..send_addr.addr_int)
        end
      end
    end
    log.trace('query dev '..dev_id..' idx '..idx..' addrs count '..#addrs)
    local deepsmartapi = wiser.api
    if (use_loop) then
      deepsmartapi = wiser.loopapi
    end
    if (deepsmartapi == nil) then
      log.trace('wiser api is not inited')
      return false,'api is not inited'
    end
    --send query
    local res = deepsmartapi:query(addrs)
    if (res == nil) then
      log.warn('query device '..uuid..' empty')
    else
      log.trace('query device '..uuid..' res '..res)
      -- parse res(json)
      local _,js = pcall(json.decode, res)
      if (js == nil or js.data == nil) then
        log.trace('parse query res nil')
        return false,'parse query res error'
      end
      -- make protocols to protocol map
      local knxes = {}
      local ignore_addrs = {}
      for i,v in pairs(js.data) do
        -- ignore recv when ctrlmap has send once
        if (v ~= nil and v.regaddr ~= nil and v.value ~= nil and ignore_addrs[v.regaddr] == nil and ignore_recv[v.regaddr] == nil) then
          knxes[v.regaddr] = v.value
          if (recv2send[v.regaddr] ~= nil) then
            ignore_addrs[recv2send[v.regaddr]] = 1
            log.trace('recv addr '..v.regaddr..' recv data ignore send addr '..recv2send[v.regaddr])
          end
          log.trace('get query res addr '..v.regaddr..' value '..v.value)
        end
      end
      wiser.ctrlmap = {}
      -- parse knx response
      Wisers.knx_response(wiser.wiser_index_code, knxes)
      return true,nil
    end
  end
  return false,'query error'
end

function Wisers.query(device, use_loop)
  local uuid = device.parent_assigned_child_key
  return Wisers.query_deviceid(uuid, use_loop)
end
--------------
-- convert hub command to deepsmart commands and control deepsmart devices
-- device: hub device who is controled
-- command: control params
-- addrtypes: device control type
--------------
function Wisers.control(device, command, addrtypes)
  local capability = command.capability
  local cmd = command.command
  local uuid = device.parent_assigned_child_key
  log.trace('device '..device.parent_assigned_child_key..' capability '..command.capability..' cmd '..command.command)
  local dev_id,_,idx = Wisers.parse_device_network_id(uuid)
  log.trace('device '..uuid..' -> dev_id '..dev_id..' idx '..idx)
  -- get device wiser
  local wiser,dev = Wisers.get_device_wiser(dev_id)
  if (wiser == nil) then
    log.warn('device '..dev_id..' is not exist for control')
    return false,'wiser is nil'
  end
  if (dev == nil) then
    log.warn('device '..device.dev_id..' is not in wiser devs')
    return false,'device is nil'
  end
  local ret = false
  local deepsmartapi = wiser.api
  if (deepsmartapi == nil) then
    log.trace('wiser api is not inited')
    return false,'api is not inited'
  end
  for _,addrtype in pairs(addrtypes) do
    local dpid = wiser.dp2knx:get_dpid_by_pid_addrtype(dev.productId, idx, addrtype)
    if (dpid == nil) then
      log.warn('get pid '..dev.productId..' idx '..idx..' addrtype '..addrtype..' dpid nil')
      goto addrtype_retry
    end
    log.trace('get pid '..dev.productId..' idx '..idx..' addrtype '..addrtype..' dpid '.. dpid)
    -- get dpid addr
    local send_list,_ = wiser.config:get_dev_dpid_addr(dev_id, dpid)
    if (send_list == nil) then
      log.warn('get pid '..dev.productId..' idx '..idx..' addrtype '..addrtype..' dpid '.. dpid..' has no send addrs')
      goto addrtype_retry
    end
    if (capability == 'switch') then
      local value = 0
      if (cmd == 'on') then
        value = 1
      end
      for i,addr in pairs(send_list) do
        log.info('device '..uuid..' control to addr '..addr.addr_int..' value '..value)
        -- save control to wiser ctrlmap
        wiser.ctrlmap[addr.addr_int] = value
        deepsmartapi:control(addr.addr_int, addr.dataType, value, 0)
      end
      ret = true
    elseif (capability == 'airConditionerMode') then
      local mode = wiser.dpenum:get_pid_val_by_dev_val(dev.productId, dpid, command.args.mode)
      if (mode ~= nil) then
        for i,addr in pairs(send_list) do
          log.info('device '..uuid..' control to addr '..addr.addr_int..' value '..mode)
          -- save control to wiser ctrlmap
          wiser.ctrlmap[addr.addr_int] = mode
          deepsmartapi:control(addr.addr_int, addr.dataType, mode, 0)
        end
      end
      ret = true
    elseif (capability == 'airConditionerFanMode') then
      local fan = wiser.dpenum:get_pid_val_by_dev_val(dev.productId, dpid, command.args.fanMode)
      if (fan ~= nil) then
        for i,addr in pairs(send_list) do
          log.info('device '..uuid..' control to addr '..addr.addr_int..' value '..fan)
          -- save control to wiser ctrlmap
          wiser.ctrlmap[addr.addr_int] = fan
          deepsmartapi:control(addr.addr_int, addr.dataType, fan, 0)
        end
      end
      ret = true
    elseif (capability == 'thermostatHeatingSetpoint') then
      -- samsung temperature is xx
      -- deepsmart temperature is xx00, temperature/100 is the real value
      for i,addr in pairs(send_list) do
        log.info('device '..uuid..' control to addr '..addr.addr_int..' value '..command.args.setpoint*100)
        -- save control to wiser ctrlmap
        wiser.ctrlmap[addr.addr_int] = command.args.setpoint*100
        deepsmartapi:control(addr.addr_int, addr.dataType, command.args.setpoint*100, 0)
      end
      ret = true
    elseif (capability == 'thermostatMode') then
      local value = 0
      if (command.args.mode == 'heat') then
        value = 1
      end
      for i,addr in pairs(send_list) do
        log.info('device '..uuid..' control to addr '..addr.addr_int..' value '..value)
        -- save control to wiser ctrlmap
        wiser.ctrlmap[addr.addr_int] = value
        deepsmartapi:control(addr.addr_int, addr.dataType, value, 0)
      end
      ret = true
    end
    ::addrtype_retry::
  end
  return ret,nil
end

return Wisers
