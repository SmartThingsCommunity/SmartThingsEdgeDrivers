local log = require('log')
local json = require('st.json')

local Devices = {}
Devices.__index = Devices


--device
----wiser_index_code
----id
----uuid
----name
----type
----roomid
----location
----productId
----productType
----roomName
----dps
------dpId
------dpName
------name
------dataType
------value
------protocolObjId

--protocols
----protocolObjId
----feedbackList
------addr
------dataType
------value
------min
------max
----sendList
------addr
------dataType
------value
------min
------max

-----------
-- convert knx addr from 'a/b/c' to integer
-- bits     5  3  8
-- knx      a  b  c
-- a is high bits  c is low bits
-----------
function Devices.parse_addr(addr)
  local tmp = addr
  local b,e = string.find(tmp, '/')
  local fir = tonumber(string.sub(tmp, 1, b-1))
  tmp = string.sub(tmp, e+1)
  b,e = string.find(tmp, '/')
  local sec = tonumber(string.sub(tmp, 1, b-1))
  local thr = tonumber(string.sub(tmp, e+1))
  if (fir > 15) then
    return ((fir << 12)&0xF000) | (0x800|(sec << 8)) | thr;
  else
    return (fir << 12) | (sec << 8) | thr;
  end
end

---------------
-- load config from wiser
-- old_config is the prev config, config will be compared with old_config to find add/dev devs
---------------
function Devices.load_config(wiser_index_code, config, old_config, add_devs, del_devs)
  local device = setmetatable({
    wiser_index_code = wiser_index_code,
    devices = {},
    scenes = {},
    protocols = {},
    protocol2dps = {},
    addrs = {}
  }, Devices)
  if (config == nil) then
    return device
  end
  -- if config has no devices then just return
  local _,js = pcall(json.decode, config)
  if (js == nil or js.devices == nil) then
    log.trace('parse config nil')
    return device
  end
  -- make protocols to protocol map
  for i,v in pairs(js.protocolObjs) do
    log.trace('parse protocolObj '..v.id)
    device.protocols[v.id] = v
  end
  -- parse all devs
  for i,v in pairs(js.devices) do
    local id = v.id
    local pid = v.productId
    if (pid == nil) then
      goto continue
    end
    -- use wiser:pid:id as the unique dev id
    local dev_id = wiser_index_code..':'..pid..':'..id
    v.dev_id = dev_id
    v.wiser_index_code = wiser_index_code
    v.dpids = {}
    device.devices[dev_id] = v
    log.trace('parse dev id '..id..' pid '..pid..' devId '..dev_id)
    if (v.dps == nil) then
      goto continue
    end
    -- parse dev all dps
    for _,dp in pairs(v.dps) do
      log.trace('parse dev id '..dev_id..' dpid '..dp.dpId)
      local dpid = tonumber(dp.dpId)
      v.dpids[dpid] = dp
      -- if dp has no protocol then we just ignore
      -- protocol is the read/write knx config for cur dp
      if (dp.protocolObjId ~= nil) then
        local dpmap = device.protocol2dps[dp.protocolObjId]
        if (dpmap == nil) then
          device.protocol2dps[dp.protocolObjId] = {}
          dpmap = device.protocol2dps[dp.protocolObjId]
        end
        local dp_info = {}
        dp_info.dev_id = dev_id
        dp_info.dpid = dpid
        dpmap[#dpmap+1] = dp_info
        -- addr
        -- find protocol by protocolObjId
        local protocol = device.protocols[dp.protocolObjId]
        if (protocol ~= nil) then
          if (protocol.sendList ~= nil) then
            for i1,v1 in pairs(protocol.sendList) do
              local addr = Devices.parse_addr(v1.addr)
              v1.addr_int = addr
              log.trace('protocol '..dp.protocolObjId..' sendList addr '..v1.addr..' val '..addr)
              local addr_map = device.addrs[addr]
              if (addr_map == nil) then
                device.addrs[addr] = {}
                addr_map = device.addrs[addr]
              end
              addr_map[#addr_map+1] = dp_info
            end
          end -- sendList
          if (protocol.feedbackList ~= nil) then
            for i1,v1 in pairs(protocol.feedbackList) do
              local addr = Devices.parse_addr(v1.addr)
              v1.addr_int = addr
              log.trace('protocol '..dp.protocolObjId..' feedbackkList addr '..v1.addr..' val '..addr)
              local addr_map = device.addrs[addr]
              if (addr_map == nil) then
                device.addrs[addr] = {}
                addr_map = device.addrs[addr]
              end
              local exist = false
              for _,v in pairs(addr_map) do
                if (v.dev_id == dp_info.dev_id and v.dpid == dp_info.dpid) then
                  exist = true
                  break;
                end
              end
              if (not exist) then
                addr_map[#addr_map+1] = dp_info
              end
            end
          end -- feedbackList
        end -- if protocol exists
      end -- if dp has protocol
    end -- end dev dps terator
    ::continue::
  end -- end devs iterator
  -- make all load devices as new devices
  -- add same device(same device_neywork_id) will do nothing for samsung hub
  -- if hub delete some device from app. Reload config will make the deleted device to normal device
  if (true and add_devs ~= nil) then
    for _,dev in pairs(device.devices) do
      add_devs[dev.dev_id] = dev
      log.trace('dev '..dev.dev_id..' add')
    end
  end
  -- compare with old_config to find the del_devs
  -- ie. old config has device A,B,C,D
  -- new config has device A,B,E, then C&&D should delete from hub
  if (del_devs ~= nil and add_devs ~= nil and old_config ~= nil and old_config.devices ~= nil) then
    for _,dev in pairs(old_config.devices) do
      if (add_devs[dev.dev_id] == nil) then
        log.info('dev '..dev.dev_id..' is deleted')
        del_devs[dev.dev_id] = dev
      end
    end
  end
  return device
end
------------------
function Devices:get_device(id)
  return self.devices[id]
end


function Devices:get_addr_dev_dpid(addr)
  return self.addrs[addr]
end

function Devices:get_dev_dpid_addr(dev_id, dpid)
  local device = self:get_device(dev_id)
  if (device == nil) then
    log.warn('dev '..dev_id..' is not exist')
    return nil,nil
  end
  for i,dp in pairs(device.dps) do
    log.trace('dev '..dev_id..' dpId '..dp.dpId..' params dpid '..dpid)
    if (dp.dpId == tostring(dpid)) then
      local protocolObjId = dp.protocolObjId
      if (protocolObjId == nil) then
        log.trace('dev '..dev_id..' dp '..dpid..' protocol is nil')
        return nil,nil
      end
      log.trace('dpid '..dpid..' protocol '..protocolObjId)
      -- get protocols
      local protocol = self.protocols[protocolObjId]
      if (protocol == nil) then
        log.warn('protocol '..protocolObjId..' is not exist')
        return nil,nil
      end
      -- find sendList && feedbackList
      local send_list = {}
      local feedback_list = {}
      if (protocol.sendList ~= nil) then
        for _,v in pairs(protocol.sendList) do
          log.trace('add send addr '..v.addr)
          send_list[v.addr] = v
        end
      end
      if (protocol.feedbackList ~= nil) then
        for _,v in pairs(protocol.feedbackList) do
          log.trace('add recv addr '..v.addr)
          feedback_list[v.addr] = v
        end
        log.trace('sendlist count '..#send_list..' feedback_list count '..#feedback_list)
        return send_list,feedback_list
      end
    end
  end
  return nil,nil
end


function Devices:get_dev_addrs(dev_id)
  local device = self:get_device(dev_id)
  if (device == nil) then
    log.warn('device '..dev_id..' is not exist')
    return nil,nil
  end
  local send_list = {}
  local feedback_list = {}
  for i,dp in pairs(device.dpids) do
    local send,recv = self:get_dev_dpid_addr(dev_id, dp.dpId)
    if (send ~= nil) then
      for addr,v in pairs(send) do
        send_list[dp.dpId] = v
        log.trace('get dev '..dev_id..' dpid '..dp.dpId..' send addr '..addr)
      end
    end
    if (recv ~= nil) then
      for addr,v in pairs(recv) do
        feedback_list[dp.dpId] = v
        log.trace('get dev '..dev_id..' dpid '..dp.dpId..' recv addr '..addr)
      end
    end
  end
  return send_list,feedback_list
end

return Devices
