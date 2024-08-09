local json = require('st.json')

local DpEnum = {}
DpEnum.__index = DpEnum

----------------
-- dpenum default config
-- ac&&newfan are default configed
-- for ac:
--  mode
--      samsung      cool  heat  fan  dry  auto
--      deepsmart     3     1     9    0    2
--  fanspeed
--      samsung      low   medium  high  auto
--      deepsmart     1     3       5     0
-- for newfan
--  fanspeed
--      samsung      low   medium  high  auto
--      deepsmart     1     3       5     0
----------------
DpEnum.pids = {
  ['cekfhkz5'] = {pid='cekfhkz5',dpids={{dpid=4,devDp='mode',enums={['3']='cool',['1']='heat',['9']='fan',['0']='dry',['2']='auto'}},{dpid=5,devDp='fanMode',enums={['1']='low',['3']='medium',['5']='high',['0']='auto'}}}},
  ['w35ineur'] = {pid='w35ineur',dpids={{dpid=12,devDp='fanMode',enums={['1']='low',['3']='medium',['5']='high',['0']='auto'}}}}
}
--dpenum
----dpid:cmd
----dpid_enum
------[dpEnum:devEnum]
---------------
-- load dpenum from wiser
-- for same pid config, wiser dpenum will cover the hub initial config
---------------
function DpEnum.load_config(wiser_index_code, data)
  local ret = setmetatable({
    wiser_index_code = wiser_index_code,
    pids = DpEnum.pids
  }, DpEnum)
  if (data ~= nil) then
    -- parse data
    local _,js = pcall(json.decode, data)
    if (js ~= nil and js.pids ~= nil) then
      -- cover pid config to pids
      for k,v in pairs(js.pids) do
        local pid = v.pid
        ret.pids[pid] = v
      end
    end
  end
  return ret
end

------------------
-- get pid dpenum
------------------
function DpEnum:get_pid(pid)
  local pidenum = self.pids[pid]
  return pidenum
end

------------------
-- dpid+dpid+dev_val->pid_val
-- get deepsmart enum value by samsung enum val
------------------
function DpEnum:get_pid_val_by_dev_val(pid, dpid, dev_val)
  local pidenum = self.pids[pid]
  if (pidenum == nil) then
    return nil
  end
  for i,v in pairs(pidenum.dpids) do
    if (tostring(v.dpid) == tostring(dpid)) then
      for i1,v1 in pairs(v.enums) do
        if (tostring(v1) == tostring(dev_val)) then
          return i1
        end
      end
      return nil
    end
  end
  return nil
end
-- get pid addrtype dpid
------------------
-- dpid+dpid+pid_val->dev_val
-- get samsung enum value by deepsmart enum val
------------------
function DpEnum:get_dev_val_by_pid_val(pid, dpid, pid_val)
  local pidenum = self.pids[pid]
  if (pidenum == nil) then
    return nil
  end
  for i,v in pairs(pidenum.dpids) do
    if (tostring(v.dpid) == tostring(dpid)) then
      return v.enums[tostring(pid_val)]
    end
  end
  return nil
end

return DpEnum
