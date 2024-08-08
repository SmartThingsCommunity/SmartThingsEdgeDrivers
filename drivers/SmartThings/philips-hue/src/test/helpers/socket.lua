local test = require "integration_test.cosock_runner"
local cosock_tcp = require "cosock.socket.tcp"
local log = require "log"

---@class test.helpers.socket
local m = {}

--- We manually craft our cosock TCP socket using the same logic as the
--- `__call` metamethod on `cosock.socket.tcp`; we want to be able to set
--- the "remote" argument on the inner mock socket without exposing the
--- test-specific behavior to the cosock API.
function m.mock_remote_cosock_tcp()
  local mock_inner_socket = test.socket.tcp({ remote = true, remote_peers = false })
  assert(mock_inner_socket:settimeout(0))
  return setmetatable({ inner_sock = mock_inner_socket, class = "tcp{master}" },
    { __index = cosock_tcp })
end

function m.mock_local_cosock_tcp()
  local mock_inner_socket = test.socket.tcp({ remote = false, remote_peers = true })
  assert(mock_inner_socket:settimeout(0))
  return setmetatable({ inner_sock = mock_inner_socket, class = "tcp{master}" },
    { __index = cosock_tcp })
end

--- To be used as the `socket_builder` argument to the REST utilities.
---@param label string?
---@param remote boolean?
---@return function
function m.mock_labeled_socket_builder(label, remote)
  label = (label or "")

  return function(host, port)
    log.info(
      string.format(
        "%sCreating TCP socket for Hue REST Connection", label
      )
    )
    local sock
    if remote then
      sock = m.mock_remote_cosock_tcp()
    else
      sock = m.mock_local_cosock_tcp()
    end
    assert(sock, "couldn't create socket")

    log.info(
      string.format(
        "%sSetting TCP socket timeout for Hue REST Connection", label
      )
    )
    assert(sock:settimeout(0), "couldn't set timeout on socket")

    log.info(
      string.format(
        "%sConnecting TCP socket for Hue REST Connection", label
      )
    )
    local conn_err = select(2, sock:connect(host, port))
    assert(conn_err == nil or conn_err == 'already connected', 'unexpected connection error: ' .. tostring(conn_err))

    log.info(
      string.format(
        "%sSet Keepalive for TCP socket for Hue REST Connection", label
      )
    )
    assert(sock:setoption("keepalive", true))

    log.info(
      string.format(
        "%sSuccessfully created TCP connection for Hue", label
      )
    )

    return sock, nil
  end
end

return m
