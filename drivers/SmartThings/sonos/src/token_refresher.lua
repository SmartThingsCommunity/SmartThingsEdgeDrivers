local cosock = require "cosock"
local utils = require "utils"
local security = require "st.security"
local log = require "log"

local module = {}

local ACTIONS = {
  -- This action waits for an event via the oauth endpoint app info bus in order to determine
  -- when the driver goes from a disconnected to connected state.
  WAIT_FOR_CONNECTED = 1,
  -- This action will wait for the current valid token to expire. It will also handle a new token
  -- event to redetermine the current action. New tokens that come in during this action will likely
  -- be from debug testing.
  WAIT_FOR_EXPIRE = 2,
  -- This action requests a new token and waits for it to come in.
  REQUEST_TOKEN = 3,
}

local ACTION_STRINGIFY = {
  [ACTIONS.WAIT_FOR_CONNECTED] = "wait for connected",
  [ACTIONS.WAIT_FOR_EXPIRE] = "wait for expire",
  [ACTIONS.REQUEST_TOKEN] = "request token",
}

local Refresher = {}
Refresher.__index = Refresher

--- Determine which action the refresher should take.
--- This just depends on:
--- - Is Oauth connected?
--- - Do we have a valid token?
function Refresher:determine_action()
  if not self.driver:oauth_is_connected() then
    -- Oauth is disconnected so no point in trying to request a token until we are connected.
    return ACTIONS.WAIT_FOR_CONNECTED
  end
  local token, _ = self.driver:get_oauth_token()
  if token then
    local now = os.time()
    local expiration = math.floor(token.expiresAt / 1000)
    if (expiration - now) > 60 then
      -- Token is valid and not expiring in the next 60 seconds.
      return ACTIONS.WAIT_FOR_EXPIRE
    end
  end
  -- We don't have a valid token or it is about to expire soon.
  return ACTIONS.REQUEST_TOKEN
end

--- Waits for a token event with a timeout.
--- @param timeout number How long the function will wait for a new token
function Refresher:try_wait_for_token_event(timeout)
  local token_bus, err = self.driver:oauth_token_event_subscribe()
  if err == "closed" then
    self.token_bus_closed = true
  end
  if token_bus then
    token_bus:settimeout(timeout)
    token_bus:receive()
  end
end

--- Waits for the current token to expire or a new token event.
---
--- The likely outcome of this function is to wait the entire expiration timeout. It will
--- also listen for token events just in case a new token with a new expiration is sent to the driver.
--- A new token would most likely come from developer testing, but since the new token requests are
--- not synchronous one could come from an earlier request.
function Refresher:wait_for_expire_or_token_event()
  local maybe_token, err = self.driver:get_oauth_token()
  if not maybe_token then
    -- Something got funky in the state machine, return and re-determine our next action
    log.warn(string.format("Tried to wait for expiration of non-existent token: %s", err))
    return
  end
  -- The token will be refreshed if requested within 1 minute of expiration
  local expiration = math.floor(maybe_token.expiresAt / 1000) - 60
  local now = os.time()
  local timeout = math.max(expiration - now, 0)

  log.debug(string.format("Token will refresh in %d seconds", timeout))
  -- Wait while trying to receive a token event in case it gets updated for some reason.
  self:try_wait_for_token_event(timeout)
end

--- Waits for an oauth endpoint app info event indefinitely.
---
--- A new info event indicates that `Refresher:determine_action` should be called to check if oauth
--- is now connected.
function Refresher:wait_for_info_event()
  local info_sub, err = self.driver:oauth_info_event_subscribe()
  if err == "closed" then
    self.info_bus_closed = true
  end
  if info_sub then
    info_sub:receive()
  end
end

--- Requests a token then waits for a new token event.
function Refresher:request_token()
  local result, err = security.get_sonos_oauth()
  if not result then
    log.warn(string.format("Failed to request oauth token: %s", err))
  end
  -- Try to receive token even if the request failed.
  self:try_wait_for_token_event(10)
  local maybe_token, _ = self.driver:get_oauth_token()
  if maybe_token then
    -- token is valid, reset backoff
    self.token_backoff = utils.backoff_builder(30 * 60, 5, 0.1)
  else
    -- We either didn't receive a token or it is not valid.
    -- Backoff and maybe we will receive it in that time, or we retry.
    cosock.socket.sleep(self.token_backoff())
  end
end

function module.spawn_token_refresher(driver)
  local refresher = setmetatable({ driver = driver,
                                   token_backoff = utils.backoff_builder(30 * 60, 5, 0.1),
                                  },
                                  Refresher)
  cosock.spawn(function ()
    while true do
      -- We can always determine what we should be doing based off the information we have,
      -- any action can proceed action depending on what needs to be done.
      local action = refresher:determine_action()
      log.info(string.format("Token refresher action: %s", ACTION_STRINGIFY[action]))
      if action == ACTIONS.WAIT_FOR_CONNECTED then
        refresher:wait_for_info_event()
      elseif action == ACTIONS.WAIT_FOR_EXPIRE then
        refresher:wait_for_expire_or_token_event()
      elseif action == ACTIONS.REQUEST_TOKEN then
        refresher:request_token()
      else
        log.error(string.format("Token refresher task exiting due to bad token refresher action: %s", action))
        return
      end
      if refresher.token_bus_closed or refresher.info_bus_closed then
        log.error(string.format("Token refresher task exiting. Token bus closed: %s Info bus close: %s",
          refresher.token_bus_closed, refresher.info_bus_closed))
        return
      end
    end
  end, "token refresher task")
end

return module


