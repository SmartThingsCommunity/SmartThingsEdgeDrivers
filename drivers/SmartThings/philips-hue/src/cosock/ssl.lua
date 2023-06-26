-- Copyright 2021 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
local luasec = require "ssl"
local internals = require "cosock.socket.internals"

local m = {}

local recvmethods = {
  receive = { wantread = true, timeout = true },
}

local sendmethods = {
  dohandshake = { wantwrite = true, wantread = true, timeout = true },
  send = { wantwrite = true, timeout = true },
}

local passthrough = internals.passthroughbuilder(recvmethods, sendmethods)

m.class = function(self)
  return self.inner_sock.class()
end

m.close = passthrough("close")

m.config = passthrough("config")

m.dirty = passthrough("dirty")

m.dohandshake = passthrough("dohandshake")

m.getalpn = passthrough("getalpn")

m.getfinished = passthrough("getfinished")

m.getpeercertificate = passthrough("getpeercertificate")

m.getpeerchain = passthrough("getpeerchain")

m.getpeerverification = passthrough("getpeerverification")

m.getpeerfinished = passthrough("getpeerfinished")

m.getsniname = passthrough("getsniname")

m.getstats = passthrough("getstats")

m.loadcertificate = passthrough("loadcertificate")

m.newcontext = passthrough("newcontext")

m.receive = passthrough("receive", {
  output = function(bytes, err, ...)
    if err == "timeout" then
      err = "wantread"
    end
    return bytes, err, ...
  end
})

m.send = passthrough("send", {
  output = function(success, err, ...)
    if err == "timeout" then
      err = "wantwrite"
    end
    return success, err, ...
  end
})

m.setdane = passthrough("setdane")

m.setstats = passthrough("setstats")

m.settlsa = passthrough("settlsa")

m.sni = passthrough("sni")

m.want = passthrough("want")

m.wrap = function(tcp_socket, config)
  assert(tcp_socket.inner_sock, "tcp inner_sock is null")
  local inner_sock, err = luasec.wrap(tcp_socket.inner_sock, config)
  if not inner_sock then
    return inner_sock, err
  end
  inner_sock:settimeout(0)
  return setmetatable({ inner_sock = inner_sock, class = "tls{}", timeout = tcp_socket.timeout }, { __index = m })
end

function m:settimeout(timeout)
  self.timeout = timeout
end

internals.setuprealsocketwaker(m)

return m
