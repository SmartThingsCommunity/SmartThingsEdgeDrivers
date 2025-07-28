local api_version = require "version".api
local capabilities = require "st.capabilities"
local cosock = require "cosock"
local json = require "st.json"
local log = require "log"
local net_url = require "net.url"
local st_utils = require "st.utils"

local sonos_ssdp = require "api.sonos_ssdp_discovery"
local utils = require "utils"

local CmdHandlers = require "api.cmd_handlers"
local PlayerFields = require("fields").SonosPlayerFields
local SonosApi = require "api"
local SonosDisco = require "disco"
local SonosDriverLifecycleHandlers = require "lifecycle_handlers"
local SonosState = require "sonos_state"

local security_load_success, security = pcall(require, "st.security")
if not security_load_success then
  log.warn_with(
    { hub_logs = true },
    string.format("Unable to load `st.security` module: %s", security)
  )
  security = nil
end

local ONE_HOUR_IN_SECONDS = 3600

---@class SonosDriver: Driver
---
---@field public datastore table<string, any> driver persistent store
---@field public hub_augmented_driver_data table<string, any> augmented data store
---@field public dni_to_device_id table<string,string>
---@field public get_devices fun(self: SonosDriver): SonosDevice[]
---@field public get_device_info fun(self: SonosDriver, id: string): SonosDevice?
---
---@field public sonos SonosState Local state related to the sonos systems
---@field public discovery fun(driver: SonosDriver, opts: table, should_continue: fun(): boolean)
---@field private oauth_token_bus cosock.Bus.Sender bus for broadcasting new oauth tokens that arrive on the environment channel
---@field private oauth { token: {accessToken: string, expiresAt: number}, endpoint_app_info: { state: "connected"|"disconnected" }, force_oauth: boolean? } cached OAuth info
---@field private waiting_for_oauth_token boolean
---@field private startup_state_received boolean
---@field private devices_waiting_for_startup_state SonosDevice[]
---@field package bonded_devices table<string, boolean> map of Device device_network_id to a boolean indicating if the device is currently known as a bonded device.
---
---@field public ssdp_task SonosPersistentSsdpTask?
---@field private ssdp_event_thread_handle table?
local SonosDriver = {}

---@param device SonosDevice
function SonosDriver:update_bonded_device_tracking(device)
  local already_bonded = self.bonded_devices[device.device_network_id]
  local currently_bonded = device:get_field(PlayerFields.BONDED)
  self.bonded_devices[device.device_network_id] = currently_bonded

  if currently_bonded and not already_bonded then
    device:offline()
  end

  if already_bonded and not currently_bonded then
    SonosDriverLifecycleHandlers.initialize_device(self, device)
  end
end

function SonosDriver:has_received_startup_state()
  return self.startup_state_received
end

function SonosDriver:queue_device_init_for_startup_state(device)
  table.insert(self.devices_waiting_for_startup_state, device)
end

---@param household_id HouseholdId
---@param player_id PlayerId
---@return SonosDevice?
function SonosDriver:device_for_player(household_id, player_id)
  local maybe_device_id = self.sonos:get_device_id_for_player(household_id, player_id)
  if maybe_device_id then
    return self:get_device_info(maybe_device_id)
  end
end

---@param dni string
---@return SonosDevice|nil
---@return string?
function SonosDriver:get_device_by_dni(dni)
  local cached_device_id = self.dni_to_device_id[dni]
  if cached_device_id then
    return self:get_device_info(cached_device_id)
  end

  for _, device in ipairs(self:get_devices() or {}) do
    if utils.mac_address_eq(device.device_network_id, dni) then
      self.dni_to_device_id[dni] = device.id
      return device
    end
  end

  return nil, string.format("Unable to find device record for DNI %s", dni)
end

---@param update_key string
---@param decoded any
function SonosDriver:handle_augmented_data_change(update_key, decoded)
  if update_key == "endpointAppInfo" then
    self.oauth.endpoint_app_info = decoded
  elseif update_key == "sonosOAuthToken" then
    self.oauth.token = decoded
    self.waiting_for_oauth_token = false
    self.oauth_token_bus:send(decoded)
  elseif update_key == "force_oauth" then
    self.oauth.force_oauth = decoded
  else
    log.debug(string.format("received upsert of unexpected key: %s", update_key))
  end
end

---@return boolean
function SonosDriver:is_waiting_for_oauth_token()
  return (api_version >= 14 and security ~= nil) and self.waiting_for_oauth_token
end

---@return (cosock.Bus.Subscription)? receiver the subscription receiver if the bus hasn't been closed, nil if closed
---@return nil|"not supported"|"closed" err_msg "not supported" on old API versions, "closed" if the bus is closed, nil on success
function SonosDriver:oauth_token_event_subscribe()
  if api_version < 14 or security == nil then
    return nil, "not supported"
  end
  return self.oauth_token_bus:subscribe()
end

function SonosDriver:update_after_startup_state_received()
  for k, v in pairs(self.hub_augmented_driver_data) do
    local decode_success, decoded = pcall(json.decode, v)
    if decode_success then
      self:handle_augmented_data_change(k, decoded)
    end
  end
end

---@param update_key "endpointAppInfo"|"sonosOAuthToken"|string
function SonosDriver:handle_augmented_store_delete(update_key)
  if update_key == "endpointAppInfo" then
    if update_key == "endpointAppInfo" then
      log.trace("deleting endpoint app info")
      self.oauth.endpoint_app_info = nil
    elseif update_key == "sonosOAuthToken" then
      log.trace("deleting OAuth Token")
      self.oauth.token = nil
    elseif update_key == "force_oauth" then
      log.trace("deleting Force OAuth")
      self.oauth.force_oauth = nil
    else
      log.debug(string.format("received delete of unexpected key: %s", update_key))
    end
  end
end

---@param update_key "endpointAppInfo"|"sonosOAuthToken"|string
---@param update_value string
function SonosDriver:handle_augmented_store_upsert(update_key, update_value)
  local decode_success, decoded = pcall(json.decode, update_value)
  if not decode_success then
    log.warn(
      string.format(
        "Unable to decode augmented data update payload: %s",
        st_utils.stringify_table {
          key = update_key,
          decode_result = decoded,
        }
      )
    )
    return
  end
  self:handle_augmented_data_change(update_key, decoded)
end

---@param update_kind "snapshot"|"upsert"|"delete"
---@param update_key "endpointAppInfo"|"sonosOAuthToken"
---@param update_value string
function SonosDriver:notify_augmented_data_changed(update_kind, update_key, update_value)
  local already_connected = self.oauth
    and self.oauth.endpoint_app_info
    and self.oauth.endpoint_app_info.state == "connected"
  log.info(string.format("Already connected? %s", already_connected))
  if update_kind == "snapshot" then
    self:update_after_startup_state_received()
  elseif update_kind == "delete" then
    self:handle_augmented_store_delete(update_key)
  elseif update_kind == "upsert" then
    self:handle_augmented_store_upsert(update_key, update_value)
  else
    log.debug(
      st_utils.stringify_table(
        { kind = update_kind, key = update_key, value = "..." },
        "unexpected event kind in augmented data change event",
        true
      )
    )
  end

  if
    self.oauth.endpoint_app_info
    and self.oauth.endpoint_app_info.state == "connected"
    and not already_connected
  then
    local _, err = self:request_oauth_token()
    if err then
      log.error(string.format("Request OAuth token error: %s", err))
    end
  end
end

function SonosDriver:handle_startup_state_received()
  self:start_ssdp_event_task()
  self:notify_augmented_data_changed "snapshot"
  self.startup_state_received = true
  for _, device in pairs(self.devices_waiting_for_startup_state) do
    SonosDriverLifecycleHandlers.initialize_device(self, device)
  end
  self.devices_waiting_for_startup_state = {}
end

function SonosDriver:get_fallback_api_key()
  if api_version < 14 or security == nil then
    return SonosApi.api_keys.s1_key
  end

  if self.oauth and self.oauth.force_oauth then
    return SonosApi.api_keys.oauth_key
  end

  return SonosApi.api_keys.s1_key
end

--- Check if the driver is able to authenticate against the given household_id
--- with what credentials it currently possesses.
---@param info_or_device SonosDevice | { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo, force_refresh: boolean }
---@return boolean? auth_success true if the driver can authenticate against the provided arguments, false otherwise
---@return string? api_key_or_err if `auth_success` is true, this will be the API key that is known to auth. If `auth_success` is false, this will be nil. If `auth_success` is `nil`, this will be an error message.
function SonosDriver:check_auth(info_or_device)
  local maybe_token, _ = self:get_oauth_token()

  local token_valid = (api_version >= 14 and security ~= nil)
    and self.oauth
    and self.oauth.endpoint_app_info
    and self.oauth.endpoint_app_info.state == "connected"
    and maybe_token ~= nil
  if token_valid then
    return true, SonosApi.api_keys.oauth_key
  elseif self.oauth.force_oauth then
    return false
  end

  local rest_url, household_id, sw_gen
  if type(info_or_device) == "table" then
    if
      type(info_or_device.ssdp_info) == "table" and type(info_or_device.discovery_info) == "table"
    then
      ---@cast info_or_device { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo }
      rest_url = net_url.parse(info_or_device.discovery_info.restUrl)
      household_id = info_or_device.ssdp_info.household_id
      sw_gen = info_or_device.discovery_info.device.swGen
    elseif
      type(info_or_device.get_field) == "function"
      and type(info_or_device.set_field) == "function"
      and info_or_device.id
    then
      ---@cast info_or_device SonosDevice
      rest_url = net_url.parse(info_or_device:get_field(PlayerFields.REST_URL))
      household_id = self.sonos:get_sonos_ids_for_device(info_or_device)
      sw_gen = info_or_device:get_field(PlayerFields.SW_GEN)
    end
  end

  if not (rest_url and household_id) then
    return nil,
      string.format(
        "unable to determine REST API call to check auth for %s",
        (
          (
            type(info_or_device) == "table"
            and (
              info_or_device.label
              or info_or_device.id
              or info_or_device.discovery_info.device.name
            )
          ) or "<unknown Sonos device>"
        )
      )
  end

  if sw_gen == nil or sw_gen == 1 then
    local api_key = SonosApi.api_keys.s1_key
    local headers = SonosApi.make_headers(api_key)
    local response, response_err = SonosApi.RestApi.get_groups_info(rest_url, household_id, headers)
    if not response or response_err then
      return nil,
        string.format("Error while making REST API call: %s", (response_err or "<unknown error>"))
    end

    if type(response) == "table" and response.groups and response.players then
      return true, api_key
    end
  end

  local unauthorized = false
  for _, api_key in pairs(SonosApi.api_keys) do
    local headers = SonosApi.make_headers(api_key, maybe_token and maybe_token.accessToken)
    local response, response_err = SonosApi.RestApi.get_groups_info(rest_url, household_id, headers)

    if response and response._objectType == "globalError" then
      unauthorized = (response.errorCode == "ERROR_NOT_AUTHORIZED")
      if not unauthorized then
        return nil, string.format("Unexpected error body: %s", st_utils.stringify_table(response))
      end
    end

    if not response or response_err then
      return nil,
        string.format("Error while making REST API call: %s", (response_err or "<unknown error>"))
    end

    if response._objectType == "groups" then
      return true, api_key
    end
  end

  if unauthorized then
    return false
  end

  return nil,
    string.format(
      "Unable to determine Authentication Status for %s",
      st_utils.stringify_table(info_or_device)
    )
end

---@return any? ret nil on permissions violation
---@return string? error nil on success
function SonosDriver:request_oauth_token()
  if api_version < 14 or security == nil then
    return nil, "not supported"
  end
  local maybe_token, maybe_err = self:get_oauth_token()
  if maybe_err then
    log.warn(string.format("get oauth token error: %s", maybe_err))
  end
  if type(maybe_token) == "table" and type(maybe_token.accessToken) == "string" then
    self.oauth_token_bus:send(maybe_token)
  end
  local result, err = security.get_sonos_oauth()
  if not result then
    return nil, string.format("Error requesting OAuth token via Security API: %s", err)
  end
  self.waiting_for_oauth_token = true
  return result, err
end

---@return { accessToken: string, expiresAt: number }? the token if a currently valid token is available, nil if not
---@return "token expired"|"no token"|"not supported"|nil reason the reason a token was not provided, nil if there is a valid token available
function SonosDriver:get_oauth_token()
  if api_version < 14 or security == nil then
    return nil, "not supported"
  end
  self.hub_augmented_driver_data = self.hub_augmented_driver_data or {}
  local decode_success, maybe_token =
    pcall(json.decode, self.hub_augmented_driver_data.sonosOAuthToken)
  if
    decode_success
    and type(maybe_token) == "table"
    and type(maybe_token.accessToken) == "string"
    and type(maybe_token.expiresAt) == "number"
  then
    self.oauth.token = maybe_token
  elseif self.hub_augmented_driver_data.sonosOAuthToken ~= nil then
    log.warn(string.format("Unable to JSON decode token from hub augmented data: %s", maybe_token))
  end

  if self.oauth.token then
    local expiration = math.floor(self.oauth.token.expiresAt / 1000)
    local now = os.time()
    -- token has not expired yet
    if now < expiration then
      -- token is expiring soon, so we pre-emptively refresh
      if math.abs(expiration - now) < ONE_HOUR_IN_SECONDS then
        local result, err = security.get_sonos_oauth()
        if not result then
          log.warn(string.format("Error requesting OAuth token via Security API: %s", err))
        end
      end
      return self.oauth.token
    else
      return nil, "token expired"
    end
  end

  return nil, "no token"
end

---Create a cosock task that handles events from the persistent SSDP task.
---@param driver SonosDriver
---@param discovery_event_subscription cosock.Bus.Subscription
---@param oauth_token_subscription cosock.Bus.Subscription?
local function make_ssdp_event_handler(
  driver,
  discovery_event_subscription,
  oauth_token_subscription
)
  return function()
    local unauthorized = {}
    local discovered = {}
    local receivers = { discovery_event_subscription }
    if oauth_token_subscription ~= nil then
      table.insert(receivers, oauth_token_subscription)
    end
    while true do
      local recv_ready, _, select_err = cosock.socket.select(receivers, nil, nil)

      if recv_ready then
        for _, receiver in ipairs(recv_ready) do
          if oauth_token_subscription ~= nil and receiver == oauth_token_subscription then
            local token_evt, receive_err = oauth_token_subscription:receive()
            if not token_evt then
              log.warn(string.format("Error on token event bus receive: %s", receive_err))
            else
              for _, event in pairs(unauthorized) do
                -- shouldn't need a nil check on the ssdp_task here since this whole function
                -- won't get called unless the task is successfully spawned.
                driver.ssdp_task:publish(event)
              end
              unauthorized = {}
            end
          end
          if receiver == discovery_event_subscription then
            ---@type { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo, force_refresh: boolean }?
            local event, recv_err = discovery_event_subscription:receive()

            if event then
              local mac_addr = utils.extract_mac_addr(event.discovery_info.device)
              local unique_key = utils.sonos_unique_key_from_ssdp(event.ssdp_info)
              if
                event.force_refresh
                or not (
                  unauthorized[unique_key]
                  or discovered[unique_key]
                  or driver.bonded_devices[mac_addr]
                )
              then
                local _, api_key = driver:check_auth(event)
                local success, handle_err, err_code =
                  driver:handle_player_discovery_info(api_key, event)
                if not success then
                  if err_code == "ERROR_NOT_AUTHORIZED" then
                    unauthorized[unique_key] = event
                  end
                  log.warn_with(
                    { hub_logs = false },
                    string.format("Failed to handle discovered speaker: %s", handle_err)
                  )
                else
                  discovered[unique_key] = true
                end
              end
            else
              log.warn(string.format("Discovery event receive error: %s", recv_err))
            end
          end
        end
      else
        log.warn(string.format("SSDP Event Handler Select Error: %s", select_err))
      end
    end
  end,
    "SSDP Event Handler"
end

function SonosDriver:start_ssdp_event_task()
  local ssdp_task, err = sonos_ssdp.spawn_persistent_ssdp_task()
  if err then
    log.error_with({ hub_logs = true }, string.format("Unable to create SSDP task: %s", err))
  end
  if ssdp_task then
    self.ssdp_task = ssdp_task
    local ssdp_task_subscription = ssdp_task:subscribe()
    local oauth_token_subscription, subscribe_err = self:oauth_token_event_subscribe()
    if subscribe_err then
      log.warn(string.format("Couldn't subscribe to OAuth Token Events: %s", subscribe_err))
    end
    self.ssdp_event_thread_handle =
      cosock.spawn(make_ssdp_event_handler(self, ssdp_task_subscription, oauth_token_subscription))
  end
end

---@param api_key string
---@param info { ssdp_info: SonosSSDPInfo, discovery_info: SonosDiscoveryInfo, force_refresh: boolean }
---@param device SonosDevice?
---@return boolean|nil response nil or false on failure
---@return nil|string error the error reason on failure, nil on success
---@return nil|string error_code the Sonos error code, if available
function SonosDriver:handle_player_discovery_info(api_key, info, device)
  -- If the SSDP Group Info is an empty string, then that means it's the non-primary
  -- speaker in a bonded set (e.g. a home theater system, a stereo pair, etc).
  -- These aren't the same as speaker groups, and bonded speakers can't be controlled
  -- via websocket at all. So we ignore all bonded non-primary speakers if they are not
  -- already onboarded.

  local discovery_info_mac_addr = utils.extract_mac_addr(info.discovery_info.device)
  local bonded = (#info.ssdp_info.group_id == 0)
  self.bonded_devices[discovery_info_mac_addr] = bonded

  local maybe_device = self:get_device_by_dni(discovery_info_mac_addr)
  if maybe_device then
    maybe_device:set_field(PlayerFields.BONDED, bonded, { persist = false })
    self:update_bonded_device_tracking(maybe_device)
  end

  api_key = api_key or self:get_fallback_api_key()

  local rest_url = net_url.parse(info.discovery_info.restUrl)
  local maybe_token, no_token_reason = self:get_oauth_token()
  local headers = SonosApi.make_headers(api_key, maybe_token and maybe_token.accessToken)
  local response, response_err =
    SonosApi.RestApi.get_groups_info(rest_url, info.ssdp_info.household_id, headers)

  if response_err then
    return nil, string.format("Error while making REST API call: %s", response_err)
  end

  if response and response._objectType == "globalError" then
    local additional_info = response.reason or response.wwwAuthenticate
    local error_string = string.format(
      '`getGroups` response error for player "%s":\n\tError Code: %s',
      info.discovery_info.device.name,
      response.errorCode
    )

    if additional_info then
      error_string =
        string.format("%s\n\tadditional information: %s", error_string, additional_info)
    end

    if no_token_reason then
      error_string =
        string.format("%s\n\tinvalid token information: %s", error_string, no_token_reason)
    end

    return nil, error_string, response.errorCode
  end

  local sw_gen = info.discovery_info.device.swGen
  local is_s1 = sw_gen == 1
  local response_valid
  if is_s1 then
    response_valid = type(response) == "table"
      and type(response.groups) == "table"
      and type(response.players) == "table"
  else
    response_valid = response and response._objectType == "groups"
  end
  if not response_valid then
    return nil,
      string.format(
        "Unexpected response type to group info request: %s",
        st_utils.stringify_table(response)
      )
  end

  --- @cast response SonosGroupsResponseBody
  self.sonos:update_household_info(info.ssdp_info.household_id, response, self)

  local device_to_update, device_mac_addr

  local maybe_device_id =
    self.sonos:get_device_id_for_player(info.ssdp_info.household_id, info.discovery_info.playerId)

  if device then
    device_to_update = device
    device_mac_addr = device_to_update.device_network_id
  elseif maybe_device_id then
    local maybe_device_from_uuid = self:get_device_info(maybe_device_id)
    if maybe_device_from_uuid then
      device_to_update = maybe_device_from_uuid
      device_mac_addr = device_to_update.device_network_id
    end
  end

  if not device_mac_addr then
    if not (info and info.discovery_info and info.discovery_info.device) then
      return nil, st_utils.stringify_table(info, "Sonos Discovery Info has unexpected structure")
    end
    device_mac_addr = discovery_info_mac_addr
  end

  if not device_to_update then
    local maybe_device_from_dni = self:get_device_by_dni(device_mac_addr)
    if maybe_device_from_dni then
      device_to_update = maybe_device_from_dni
    end
  end

  if device_to_update then
    self.dni_to_device_id[device_mac_addr] = device_to_update.id
    self.sonos:associate_device_record(device_to_update, info)
  elseif not bonded then
    local name = info.discovery_info.device.name
      or info.discovery_info.device.modelDisplayName
      or "Unknown Sonos Player"
    local model = info.discovery_info.device.modelDisplayName or "Unknown Sonos Model"
    local try_create_message = {
      type = "LAN",
      device_network_id = device_mac_addr,
      manufacturer = "Sonos",
      label = name,
      model = model,
      profile = "sonos-player",
      vendor_provided_label = info.discovery_info.device.model,
    }

    self:try_create_device(try_create_message)
  end
  return true
end

---@param driver SonosDriver
---@param device SonosDevice
---@param cmd any
local function do_refresh(driver, device, cmd)
  log.trace("Refreshing " .. device.label)
  local sonos_conn = device:get_field(PlayerFields.CONNECTION)
  if sonos_conn == nil then
    log.error(
      string.format("Failed to do refresh, no sonos connection for device: [%s]", device.label)
    )
    return
  end

  if not sonos_conn:is_running() then
    sonos_conn:start()
  end

  -- refreshing subscriptions should refresh all relevant data on those channels as well
  -- via the subscription confirmation events.
  sonos_conn:refresh_subscriptions()
end

function SonosDriver.new_driver_template()
  local oauth_token_bus = cosock.bus()

  local template = {
    sonos = SonosState.instance(),
    discovery = SonosDisco.discover,
    oauth_token_bus = oauth_token_bus,
    oauth = {},
    waiting_for_oauth_token = false,
    startup_state_received = false,
    devices_waiting_for_startup_state = {},
    bonded_devices = utils.new_mac_address_keyed_table(),
    dni_to_device_id = utils.new_mac_address_keyed_table(),
    lifecycle_handlers = SonosDriverLifecycleHandlers,
    capability_handlers = {
      [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = do_refresh,
      },
      [capabilities.audioMute.ID] = {
        [capabilities.audioMute.commands.mute.NAME] = CmdHandlers.handle_mute,
        [capabilities.audioMute.commands.unmute.NAME] = CmdHandlers.handle_unmute,
        [capabilities.audioMute.commands.setMute.NAME] = CmdHandlers.handle_set_mute,
      },
      [capabilities.audioNotification.ID] = {
        [capabilities.audioNotification.commands.playTrack.NAME] = CmdHandlers.handle_audio_notification,
        [capabilities.audioNotification.commands.playTrackAndResume.NAME] = CmdHandlers.handle_audio_notification,
        [capabilities.audioNotification.commands.playTrackAndRestore.NAME] = CmdHandlers.handle_audio_notification,
      },
      [capabilities.audioVolume.ID] = {
        [capabilities.audioVolume.commands.volumeUp.NAME] = CmdHandlers.handle_volume_up,
        [capabilities.audioVolume.commands.volumeDown.NAME] = CmdHandlers.handle_volume_down,
        [capabilities.audioVolume.commands.setVolume.NAME] = CmdHandlers.handle_set_volume,
      },
      [capabilities.mediaGroup.ID] = {
        [capabilities.mediaGroup.commands.groupVolumeUp.NAME] = CmdHandlers.handle_group_volume_up,
        [capabilities.mediaGroup.commands.groupVolumeDown.NAME] = CmdHandlers.handle_group_volume_down,
        [capabilities.mediaGroup.commands.setGroupVolume.NAME] = CmdHandlers.handle_group_set_volume,
        [capabilities.mediaGroup.commands.muteGroup.NAME] = CmdHandlers.handle_group_mute,
        [capabilities.mediaGroup.commands.unmuteGroup.NAME] = CmdHandlers.handle_group_unmute,
        [capabilities.mediaGroup.commands.setGroupMute.NAME] = CmdHandlers.handle_group_set_mute,
      },
      [capabilities.mediaPlayback.ID] = {
        [capabilities.mediaPlayback.commands.play.NAME] = CmdHandlers.handle_play,
        [capabilities.mediaPlayback.commands.pause.NAME] = CmdHandlers.handle_pause,
        [capabilities.mediaPlayback.commands.stop.NAME] = CmdHandlers.handle_pause,
      },
      [capabilities.mediaPresets.ID] = {
        [capabilities.mediaPresets.commands.playPreset.NAME] = CmdHandlers.handle_play_preset,
      },
      [capabilities.mediaTrackControl.ID] = {
        [capabilities.mediaTrackControl.commands.nextTrack.NAME] = CmdHandlers.handle_next_track,
        [capabilities.mediaTrackControl.commands.previousTrack.NAME] = CmdHandlers.handle_previous_track,
      },
    },
  }

  for k, v in pairs(SonosDriver) do
    template[k] = v
  end

  return template
end

return SonosDriver
