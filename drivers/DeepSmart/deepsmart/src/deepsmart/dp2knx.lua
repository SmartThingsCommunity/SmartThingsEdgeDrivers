local log = require('log')
local json = require('st.json')
local config = require('config')

local Dp2Knx = {}
Dp2Knx.__index = Dp2Knx
Dp2Knx.pids = {
 ['cekfhkz5'] = {pid='cekfhkz5',type=config.ENUM.AC, devs={[1]={[1]=0,[4]=1,[5]=2,[2]=3,[3]=4,[101]=5}}},
 ['drrearrq'] = {pid='drrearrq',type=config.ENUM.HEATER, devs={[1]={[1]=0,[24]=2,[16]=3}}},
 ['w35ineur'] = {pid='w35ineur',type=config.ENUM.NEWFAN, devs={[1]={[1]=0,[12]=1}}}
}
------------------
-- load wiser dp2knx config
-- for same pid, dp2knx loaded from wiser will cover the default config
------------------
function Dp2Knx.load_config(wiser_index_code, data)
  local ret = setmetatable({
    wiser_index_code = wiser_index_code,
    pids = Dp2Knx.pids
  }, Dp2Knx)
  if (data ~= nil) then
    -- parse data
    local _,js = pcall(json.decode, data)
    if (js ~= nil and js.pids ~= nil) then
      for k,v in pairs(js.pids) do
        local pid = v.pid
        log.info('load dp2knx pid '..pid)
        ret.pids[pid] = v
      end
    end
  end
  return ret
end
------------------
-- get pid type
------------------
function Dp2Knx:get_pid_type(pid)
  log.trace('get pid '..pid..' devtype')
  local dp2knx = self.pids[pid]
  if (dp2knx == nil) then
    log.warn('pid '..pid..' not configed')
    return nil
  end
  return dp2knx.type
end
-------------------
-- pid+dpid->addrtype
-- get dev addrtype by pid&&dpid
-- returns:
--    devtype,addrtype,idx(dev index)
-------------------
function Dp2Knx:get_addrtype_by_pid_dpid(pid, dpid)
  local dp2knx = self.pids[pid]
  if (dp2knx == nil) then
    log.warn('pid '..pid..' not exist in dp2knx')
    return nil,nil,nil
  end
  for i,v in pairs(dp2knx.devs) do
    -- i1->dpid v1->addrtype
    for i1,v1 in pairs(v) do
      if (tostring(i1) == tostring(dpid)) then
        return dp2knx.type,v1,i
      end
    end
  end
  log.trace('pid '..pid..' dpid '..dpid..' is not configed')
  return dp2knx.type,nil,nil
end
-- get pid addrtype dpid
function Dp2Knx:get_dpid_by_pid_addrtype(pid, idx, addrtype)
  local dp2knx = self.pids[pid]
  if (dp2knx == nil) then
    return nil
  end
  local dev = dp2knx.devs[idx]
  if (dev == nil) then
    return nil
  end
  for i,v in pairs(dev) do
    if (v == addrtype) then
      if (type(i) == "string") then
        return tonumber(i)
      else
        return i
      end
    end
  end
  return nil
end

function Dp2Knx:get_dev_addr_types(pid, idx)
  local dp2knx = self.pids[pid]
  if (dp2knx == nil) then
    return nil
  end
  local dev = dp2knx.devs[idx]
  if (dev == nil) then
    return nil
  end
  local addr_types = {}
  local idx = 1
  for i,v in pairs(dev) do
    addr_types[idx] = v
    idx = idx + 1
  end
  return addr_types
end


function Dp2Knx:get_dev_count(pid)
  local dp2knx = self.pids[pid]
  if (dp2knx == nil) then
    return 0
  end
  if (dp2knx.devs == nil) then
    return 0
  end
  return #dp2knx.devs
end


function Dp2Knx:get_dev_addr_dpids(pid, idx)
  local dp2knx = self.pids[pid]
  if (dp2knx == nil) then
    return nil
  end
  local dev = dp2knx.devs[idx]
  if (dev == nil) then
    return nil
  end
  return dev
end

function Dp2Knx:get_dev_dpids(pid, idx)
  local dp2knx = self.pids[pid]
  if (dp2knx == nil) then
    return nil
  end
  local dev = dp2knx.devs[idx]
  if (dev == nil) then
    return nil
  end
  local dpids = {}
  local idx = 1
  for i,v in pairs(dev) do
    if (type(i) == "string") then
      dpids[idx] = tonumber(i)
    else
      dpids[idx] = i
    end
    idx = idx + 1
  end
  return dpids
end




return Dp2Knx
