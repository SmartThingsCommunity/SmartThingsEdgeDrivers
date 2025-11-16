local cosock = require "cosock"
local log = require "log"
local net_url = require "net.url"
local ssdp = require "ssdp"
local st_utils = require "st.utils"

local utils = require "utils"

local SonosApi = require "api"
local SSDP_SCAN_INTERVAL_SECONDS = 600

local SONOS_DEFAULT_PORT = 1443
local SONOS_DEFAULT_WSS_PATH = "websocket/api"
local SONOS_DEFAULT_REST_PATH = "api/v1"

--- Cached information gathered during discovery scanning, created from a subset of the
--- found [SonosSSDPInfo](lua://SonosSSDPInfo) and [SonosDiscoveryInfoObject](lua://SonosDiscoveryInfoObject)
---
--- @class SpeakerDiscoveryInfo
--- @field public unique_key UniqueKey
--- @field public mac_addr string
--- @field public expires_at integer
--- @field public ipv4 string
--- @field public port integer
--- @field public household_id HouseholdId
--- @field public player_id PlayerId
--- @field public name string
--- @field public model string
--- @field public model_display_name string
--- @field public sw_gen integer
--- @field public wss_url table
--- @field public rest_url table
--- @field public is_group_coordinator boolean
--- @field public group_name string? nil if a speaker is the non-primary in a bonded set
--- @field public group_id GroupId? nil if a speaker is the non-primary in a bonded set
--- @field package wss_path string? nil if equivalent to the default value; does not include leading slash!
--- @field package rest_path string? nil if equivalent to the default value; does not include leading slash!
local SpeakerDiscoveryInfo = {}

local proxy_index = function(self, k)
  if k == "rest_url" and not rawget(self, "rest_url") then
    rawset(
      self,
      "rest_url",
      net_url.parse(
        string.format(
          "https://%s:%s/%s",
          self.ipv4,
          self.port,
          self.rest_path or SONOS_DEFAULT_REST_PATH
        )
      )
    )
  end

  if k == "wss_url" and not rawget(self, "wss_url") then
    rawset(
      self,
      "wss_url",
      net_url.parse(
        string.format(
          "https://%s:%s/%s",
          self.ipv4,
          self.port,
          self.wss_path or SONOS_DEFAULT_WSS_PATH
        )
      )
    )
  end

  return rawget(self, k)
end

local proxy_newindex = function(_, _, _)
  error("attempt to index a read-only table", 2)
end

---@param ssdp_info SonosSSDPInfo
---@param discovery_info SonosDiscoveryInfoObject
---@return SpeakerDiscoveryInfo info
function SpeakerDiscoveryInfo.new(ssdp_info, discovery_info)
  local mac_addr = utils.extract_mac_addr(discovery_info.device)
  local port, rest_path = string.match(discovery_info.restUrl, "^.*:(%d*)/(.*)$")
  local _, wss_path = string.match(discovery_info.websocketUrl, "^.*:(%d*)/(.*)$")
  port = tonumber(port) or SONOS_DEFAULT_PORT

  local ret = {
    unique_key = utils.sonos_unique_key_from_ssdp(ssdp_info),
    expires_at = ssdp_info.expires_at,
    ipv4 = ssdp_info.ip,
    port = port,
    mac_addr = mac_addr,
    household_id = ssdp_info.household_id,
    player_id = ssdp_info.player_id,
    name = discovery_info.device.name,
    model = discovery_info.device.model,
    model_display_name = discovery_info.device.modelDisplayName,
    sw_gen = discovery_info.device.swGen,
    is_group_coordinator = ssdp_info.is_group_coordinator,
  }

  if type(ssdp_info.group_name) == "string" and #ssdp_info.group_name > 0 then
    ret.group_name = ssdp_info.group_name
  end

  if type(ssdp_info.group_id) == "string" and #ssdp_info.group_id > 0 then
    ret.group_id = ssdp_info.group_id
  end

  if type(wss_path) == "string" and #wss_path > 0 and wss_path ~= SONOS_DEFAULT_WSS_PATH then
    ret.wss_path = wss_path
  end

  if type(rest_path) == "string" and #rest_path > 0 and rest_path ~= SONOS_DEFAULT_REST_PATH then
    ret.rest_path = rest_path
  end

  for k, v in pairs(SpeakerDiscoveryInfo or {}) do
    rawset(ret, k, v)
  end

  return setmetatable(ret, { __index = proxy_index, __newindex = proxy_newindex })
end

function SpeakerDiscoveryInfo:is_bonded()
  return (self.group_id == nil)
end

---@return SonosSSDPInfo
function SpeakerDiscoveryInfo:as_ssdp_info()
  ---@type SonosSSDPInfo
  return {
    ip = self.ipv4,
    group_id = self.group_id or "",
    group_name = self.group_name or "",
    expires_at = self.expires_at,
    player_id = self.player_id,
    wss_url = self.wss_url:build(),
    household_id = self.household_id,
    is_group_coordinator = self.is_group_coordinator,
  }
end

local sonos_ssdp = {}
sonos_ssdp.SpeakerDiscoveryInfo = SpeakerDiscoveryInfo

---@module 'luncheon.headers'

---@param response Headers
---@return boolean is_valid
local function validate_sonos_ssdp_response(response)
  local ip = response:get_one("location"):match("http://([^,/]+):[^/]+/.+%.xml")
  local is_group_coordinator, group_id, group_name =
    response:get_one("groupinfo.smartspeaker.audio"):match('gc=(.*); gid=(.*); gname="(.*)"')
  local household_id = response:get_one("household.smartspeaker.audio")
  local wss_url = response:get_one("websock.smartspeaker.audio")
  local expires_in = response:get_one("cache-control"):match("max%-age%s*=%s*(%d*)")
  local has_server = response:get_one("server"):find("Sonos") ~= nil
  local player_id, redundant_st = response:get_one("usn"):match("uuid:([^:]*)::(urn:.*)$")
  return has_server
    and ip
    and is_group_coordinator
    and group_id
    and group_name
    and household_id
    and wss_url
    and expires_in
    and tonumber(expires_in)
    and player_id
    and (redundant_st == sonos_ssdp.SearchTerm)
    and true
end

---We know that these matches have already been validated so we don't need nil checking.
---@param response Headers
---@return SonosSSDPInfo
local function post_process_response(response)
  local ip = response:get_one("location"):match("http://([^,/]+):[^/]+/.+%.xml")
  local is_group_coordinator, group_id, group_name =
    response:get_one("groupinfo.smartspeaker.audio"):match('gc=(.*); gid=(.*); gname="(.*)"')
  local household_id = response:get_one("household.smartspeaker.audio")
  local wss_url = response:get_one("websock.smartspeaker.audio")
  local player_id = response:get_one("usn"):match("uuid:([^:]*)::(urn:.*)$")
  local expires_in = tonumber(response:get_one("cache-control"):match("max%-age%s*=%s*(%d*)"))
  ---@type SonosSSDPInfo
  local ret = setmetatable({
    ip = ip,
    is_group_coordinator = (tonumber(is_group_coordinator) == 1),
    group_id = group_id,
    group_name = group_name,
    household_id = household_id,
    wss_url = wss_url,
    expires_at = os.time() + expires_in,
    player_id = player_id,
  }, {
    __tostring = function(tbl)
      return st_utils.stringify_table(tbl, nil, true)
    end,
  })
  return ret
end

---@enum _ControlMessageType
local _ControlMessageType = {
  SEARCH = 0,
}

---@param ssdp_search_handle SsdpSearchHandle
---@param control_rx table
---@param status_tx table
---@param on_search_result_cb fun(result: SonosSSDPInfo)
---@return function
local function make_persistent_task_impl(
  ssdp_search_handle,
  control_rx,
  status_tx,
  on_search_result_cb
)
  return function()
    ssdp_search_handle:multicast_m_search()
    local interval_timer = cosock.timer.create_interval(SSDP_SCAN_INTERVAL_SECONDS)
    while true do
      local recv_ready, _, select_err =
        cosock.socket.select({ ssdp_search_handle, control_rx, interval_timer })

      if type(recv_ready) ~= "table" or (select_err and select_err ~= "timeout") then
        log.warn(string.format("Select error: %s", select_err))
      end

      for _, receiver in ipairs(recv_ready or {}) do
        if receiver == interval_timer then
          interval_timer:handled()
          ssdp_search_handle:multicast_m_search()
        elseif receiver == control_rx then
          local recv, recv_err = receiver:receive()
          if not recv then
            log.warn(string.format("control channel receive error: %s", recv_err))
          else
            if recv._type == _ControlMessageType.SEARCH then
              ssdp_search_handle:multicast_m_search()
            end
          end
        end

        if receiver == ssdp_search_handle then
          local response = ssdp_search_handle:next_msearch_response()
          if response then
            if response:is_ok() then
              local new_info = response:unwrap()
              on_search_result_cb(new_info)
            end
          end
        end
      end
    end
  end
end

sonos_ssdp.SearchTerm = "urn:smartspeaker-audio:service:SpeakerGroup:1"
sonos_ssdp.required_headers = {
  "usn",
  "server",
  "location",
  "groupinfo.smartspeaker.audio",
  "websock.smartspeaker.audio",
  "household.smartspeaker.audio",
}

---compares two SSDP Info tables, ignoring their expiration time tags that might be different
---@param a SonosSSDPInfo
---@param b SonosSSDPInfo
---@return boolean is_eq
function sonos_ssdp.ssdp_info_eq(a, b)
  return (a.group_id == b.group_id)
    and (a.group_name == b.group_name)
    and (a.household_id == b.household_id)
    and (a.ip == b.ip)
    and (a.is_group_coordinator == b.is_group_coordinator)
    and (a.player_id == b.player_id)
    and (a.wss_url == b.wss_url)
end

---@param disco_info SpeakerDiscoveryInfo
---@param ssdp_info SonosSSDPInfo
function sonos_ssdp.known_speaker_matches_ssdp_info(disco_info, ssdp_info)
  return (disco_info.group_id == ssdp_info.group_id)
    and (disco_info.group_name == ssdp_info.group_name)
    and (disco_info.household_id == ssdp_info.household_id)
    and (disco_info.ipv4 == ssdp_info.ip)
    and (disco_info.is_group_coordinator == ssdp_info.is_group_coordinator)
    and (disco_info.player_id == ssdp_info.player_id)
    and (disco_info.wss_url:build() == ssdp_info.wss_url)
end

---@return SsdpSearchTerm the Sonos ssdp search term
---@return SsdpSearchKwargs the default set of keyword arguments for Sonos
function sonos_ssdp.new_search_term_context()
  return sonos_ssdp.SearchTerm,
    {
      required_headers = sonos_ssdp.required_headers,
      validator = validate_sonos_ssdp_response,
      post_processor = post_process_response,
    }
end

---@class SonosPersistentSsdpTask
---@field package ssdp_search_handle SsdpSearchHandle
---@field package player_info_by_sonos_ids table<UniqueKey, SpeakerDiscoveryInfo>
---@field package player_info_by_mac_addrs table<string, SpeakerDiscoveryInfo>
---@field package waiting_for_unique_key table<UniqueKey, table[]>
---@field package waiting_for_mac_addr table<string, table[]>
---@field package control_tx table
---@field package status_rx table
---@field package event_bus cosock.Bus.Sender
---@field package cosock_thread_handle table
local SonosPersistentSsdpTask = {}
SonosPersistentSsdpTask.__index = SonosPersistentSsdpTask
sonos_ssdp.SonosPersistentSsdpTask = SonosPersistentSsdpTask

function SonosPersistentSsdpTask:get_current_mx_seconds()
  return self.ssdp_search_handle:get_current_mx_seconds()
end

function SonosPersistentSsdpTask:refresh()
  self.control_tx:send({
    _type = _ControlMessageType.SEARCH,
  })
end

function SonosPersistentSsdpTask:get_all_known()
  -- make a shallow copy of the table so it doesn't get clobbered
  -- the player info itself is a read-only proxy table as well
  local known = {}
  for id, info in pairs(self.player_info_by_sonos_ids or {}) do
    known[id] = info
  end
  return known
end

---@param reply_tx table
---@param ... unknown
---@override fun(self: SonosPersistentSsdpTask, reply_tx: table, mac_addr: string)
---@override fun(self: SonosPersistentSsdpTask, reply_tx: table, household_id: string, player_id: string)
function SonosPersistentSsdpTask:get_player_info(reply_tx, ...)
  local household_id_or_mac = select(1, ...)
  local player_id = select(2, ...)

  local wait_table_key, lookup_table, lookup_key, bad_key_part

  if player_id ~= nil and type(player_id) == "string" then
    wait_table_key = "waiting_for_unique_key"
    lookup_table = self.player_info_by_sonos_ids
    lookup_key, bad_key_part = utils.sonos_unique_key(household_id_or_mac, player_id)
  else
    wait_table_key = "waiting_for_mac_addr"
    lookup_table = self.player_info_by_mac_addrs
    lookup_key = household_id_or_mac
  end

  if not lookup_key and bad_key_part then
    log.error(string.format("Invalid Unique Key Part: %s", bad_key_part))
  end

  local maybe_existing = lookup_table[lookup_key]
  if maybe_existing and maybe_existing.expires_at > os.time() then
    reply_tx:send(maybe_existing)
    return
  end

  local waiting_for_player = self[wait_table_key][lookup_key] or {}
  table.insert(waiting_for_player, reply_tx)
  self[wait_table_key][lookup_key] = waiting_for_player
  self:refresh()
end

function SonosPersistentSsdpTask:subscribe()
  return self.event_bus:subscribe()
end

function SonosPersistentSsdpTask:publish(msg)
  self.event_bus:send(msg)
end

---@return SonosPersistentSsdpTask? task nil on failure to spawn task
---@return string? err nil on success
function sonos_ssdp.spawn_persistent_ssdp_task()
  local control_tx, control_rx = cosock.channel.new()
  local status_tx, status_rx = cosock.channel.new()
  local event_bus = cosock.bus()
  -- use the default MX value
  local ssdp_search_handle, make_handle_err = ssdp.new_search_instance()
  if not ssdp_search_handle then
    return nil, string.format("start search error: %s", make_handle_err)
  end
  ssdp_search_handle:register_search_term(sonos_ssdp.new_search_term_context())

  ---@type SonosPersistentSsdpTask
  local task_handle = setmetatable({
    ssdp_search_handle = ssdp_search_handle,
    player_info_by_sonos_ids = {},
    player_info_by_mac_addrs = utils.new_mac_address_keyed_table(),
    waiting_for_unique_key = {},
    waiting_for_mac_addr = utils.new_mac_address_keyed_table(),
    control_tx = control_tx,
    status_rx = status_rx,
    event_bus = event_bus,
  }, SonosPersistentSsdpTask)

  ---@type fun(sonos_ssdp_info: SonosSSDPInfo)
  local callback = function(sonos_ssdp_info)
    local unique_key = utils.sonos_unique_key_from_ssdp(sonos_ssdp_info)
    local maybe_known = task_handle.player_info_by_sonos_ids[unique_key]
    local is_new_information = not (
      maybe_known
      and maybe_known.expires_at > os.time()
      and sonos_ssdp.known_speaker_matches_ssdp_info(maybe_known, sonos_ssdp_info)
    )

    local speaker_info
    local event_bus_msg

    if is_new_information then
      local headers = SonosApi.make_headers()
      local discovery_info, err = SonosApi.RestApi.get_player_info(
        net_url.parse(
          string.format("https://%s:%s", sonos_ssdp_info.ip, SonosApi.DEFAULT_SONOS_PORT)
        ),
        headers
      )
      if not discovery_info then
        log.error(string.format("Error getting discovery info from SSDP response: %s", err))
      elseif discovery_info._objectType == "globalError" then
        log.error(string.format("Error message in discovery info: %s", discovery_info.errorCode))
      else
        speaker_info = SpeakerDiscoveryInfo.new(sonos_ssdp_info, discovery_info)
        task_handle.player_info_by_sonos_ids[unique_key] = speaker_info
        event_bus_msg = { speaker_info = speaker_info, force_refresh = true }
      end
    else
      speaker_info = maybe_known
      event_bus_msg = { speaker_info = speaker_info, force_refresh = false }
    end

    if speaker_info then
      event_bus:send(event_bus_msg)
      local mac_addr = speaker_info.mac_addr
      local waiting_handles = task_handle.waiting_for_unique_key[unique_key] or {}

      log.debug(st_utils.stringify_table(waiting_handles, "waiting for unique keys", true))
      for _, v in pairs(task_handle.waiting_for_mac_addr[mac_addr] or {}) do
        table.insert(waiting_handles, v)
      end

      log.debug(
        st_utils.stringify_table(waiting_handles, "waiting for unique keys and mac addresses", true)
      )
      for _, reply_tx in ipairs(waiting_handles or {}) do
        reply_tx:send(speaker_info)
      end

      task_handle.waiting_for_unique_key[unique_key] = {}
      task_handle.waiting_for_mac_addr[mac_addr] = {}
    end
  end

  local thread = cosock.spawn(
    make_persistent_task_impl(ssdp_search_handle, control_rx, status_tx, callback),
    "Sonos Persistent SSDP Task"
  )
  task_handle.cosock_thread_handle = thread

  return task_handle, nil
end

return sonos_ssdp
