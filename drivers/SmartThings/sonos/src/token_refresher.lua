local cosock = require "cosock"
local utils = require "utils"
local security = require "st.security"
local log = require "log"

local module = {}

local STATES = {
  -- OAuth is not connected.
  DISCONNECTED       = 1,
  -- Driver has a valid token.
  WAITING_FOR_EXPIRE = 2,
  -- Driver either doesn't have a token or it is invalid.
  REQUEST_TOKEN      = 3,
}

local STATE_STRINGIFY = {
  [STATES.DISCONNECTED] = "disconnected",
  [STATES.WAITING_FOR_EXPIRE] = "waiting for expire",
  [STATES.REQUEST_TOKEN] = "requesting token",
}

local Refresher = {}
Refresher.__index = Refresher

--- Determine which state the refresher should be in.
--- Any state can go to any state so this just depends on:
--- - Is Oauth connected?
--- - Do we have a valid token?
function Refresher:determine_state()
  if not self.driver:oauth_is_connected() then
    -- Oauth is disconnected so no point in trying to request a token until we are connected.
    return STATES.DISCONNECTED
  end
  local token, _ = self.driver:get_oauth_token()
  if token then
    local now = os.time()
    local expiration = math.floor(token.expiresAt / 1000)
    if (expiration - now) > 60 then
      -- Token is valid and not expiring in the next 60 seconds.
      return STATES.WAITING_FOR_EXPIRE
    end
  end
  -- We don't have a valid token or it is about to expire soon.
  return STATES.REQUEST_TOKEN
end

--- Waits for a token event with a timeout.
function Refresher:receive_token(timeout)
  local token_bus, _ = self.driver:oauth_token_event_subscribe()
  if token_bus then
    token_bus:settimeout(timeout)
    token_bus:receive()
  end
end

--- Waits for either a new token to arrive or the current one to expire.
function Refresher:wait_for_expire()
  local maybe_token, err = self.driver:get_oauth_token()
  if not maybe_token then
    -- Something got funky in the state machine
    log.warn(string.format("Tried to wait for expiration of non-existent token: %s", err))
    return
  end
  -- The token will be refreshed if requested within 1 minute of expiration
  local expiration = math.floor(maybe_token.expiresAt / 1000) - 60
  local now = os.time()
  local timeout = math.max(expiration - now, 0)

  log.debug(string.format("Token will refresh in %d seconds", timeout))
  -- Wait while trying to receive the token in case it gets updated for some reason.
  self:receive_token(timeout)
end

--- Waits for an oauth info event.
function Refresher:disconnected()
  local info_sub = self.driver:oauth_info_event_subscribe()
  if info_sub then
    info_sub:receive()
  end
end

--- Requests a token then waits for it to arrive.
function Refresher:request_token()
  local result, err = security.get_sonos_oauth()
  if not result then
    log.warn(string.format("Failed to request oauth token: %s", err))
  end
  -- Try to receive token even if the request failed.
  self:receive_token(10)
  local maybe_token, _ = self.driver:get_oauth_token()
  if maybe_token then
    -- token is valid, reset backoff
    self.token_backoff = utils.backoff_builder(5 * 60, 5, 0.1)
  else
    -- We either didn't receive a token or it is not valid.
    -- Backoff and maybe we will receive it in that time, or we retry.
    cosock.socket.sleep(self.token_backoff())
  end
end

function module.spawn_token_refresher(driver)
  local refresher = setmetatable({ driver = driver,
                                   token_backoff = utils.backoff_builder(5 * 60, 5, 0.1),
                                  },
                                  Refresher)
  cosock.spawn(function ()
    while true do
      -- We can always determine what we should be doing based off the information we have,
      -- any state can go to any state depending on what needs to be done.
      local state = refresher:determine_state()
      log.info(string.format("Token refresher state: %s", STATE_STRINGIFY[state]))
      if state == STATES.DISCONNECTED then
        refresher:disconnected()
      elseif state == STATES.WAITING_FOR_EXPIRE then
        refresher:wait_for_expire()
      elseif state == STATES.REQUEST_TOKEN then
        refresher:request_token()
      else
        log.warn(string.format("Bad token refresher state: %s", state))
      end
    end
  end, "token refresher task")
end

return module


