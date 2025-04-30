local cosock = require "cosock"
local socket = require "cosock.socket"
local log = require "log"
local st_utils = require "st.utils"

local ssdp = require "ssdp"

--- @class SsdpTask
local SsdpTask = {}

---Spawn a new Cosock task that handles SSDP activity, returning
---a handle to the task.
---
---@param cosock_name string? the optional name to assign to the cosock task
function SsdpTask.new(cosock_name)
  local control_tx, control_rx = cosock.channel.new()
  local status_tx, status_rx = cosock.channel.new()
  local event_bus = cosock.bus()
end

return SsdpTask
