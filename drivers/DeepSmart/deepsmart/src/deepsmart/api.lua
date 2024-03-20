local log = require('log')
local RestClient = require "lunchbox.rest"
local utils = require "utils"
local json = require('st.json')

local Api = {}
Api.__index = Api
---------------
--------------------
local SSL_CONFIG = {
  mode = "client",
  protocol = "any",
  verify = "peer",
  options = "all",
  cafile = "./selfSignedRoot.crt"
}

local ADDITIONAL_HEADERS = {
  ["Accept"] = "application/json",
  ["Content-Type"] = "application/json",
}


function Api.client(wiser_index_code, ip)
  local ret = setmetatable({
    wiser_index_code = wiser_index_code,
    ip = ip,
    client = RestClient.new("https://"..ip, utils.labeled_socket_builder(wiser_index_code, SSL_CONFIG))
  }, Api)

  return ret
end

local function process_rest_response(response, err, partial)
  if err ~= nil then
    return response, err, nil
  elseif response ~= nil then
    return response:get_body(), nil, response.status
  else
    return nil, "no response or error received", nil
  end
end

local function retry_fn(retry_attempts)
  local count = 0
  return function()
    count = count + 1
    return count < retry_attempts
  end
end

function Api:do_get(url)
  -- get url
  local client = self.client
  if (client == nil) then
    log.warn('do_get url '..url..' client is nil')
    return nil,'client nil',404
  end
  log.debug('do_get '..url)
  local response,err,partial = client:get(url, ADDITIONAL_HEADERS, retry_fn(3))
  if (err ~= nil) then
    client:shutdown()
    self.client = RestClient.new("https://"..self.ip, utils.labeled_socket_builder(self.wiser_index_code, SSL_CONFIG))
  end
  return process_rest_response(response,err,partial)
end

function Api:do_post(url, content)
  -- get url
  local client = self.client
  if (client == nil) then
    log.warn('do_post url '..url..' client is nil')
    return nil,'client nil',404
  end
  log.debug('do_post '..url..' content '..content)
  local response,err,partial = client:post(url, content, ADDITIONAL_HEADERS, retry_fn(3))
  if (err ~= nil) then
    log.warn('post url '..url..' content '..content..' error '..err)
    client:shutdown()
    self.client = RestClient.new("https://"..self.ip, utils.labeled_socket_builder(self.wiser_index_code, SSL_CONFIG))
  else
    if (response == nil or response:get_body() == nil) then
      log.warn('post url '..url..' content '..content..' res nil')
    else
      log.trace('post url '..url..' content '..content..' res '..response:get_body())
    end
  end
  return process_rest_response(response,err,partial)
end

------------
-- load config from wiser
------------
function Api:load_config()
  local dest_url = 'https://'..self.ip..'/homecontroller/api/v1/config/devices'
  local retry = 2
  while (retry > 0) do
    log.trace('begin to load devices '..dest_url..' retry '..retry)
    local res_body,_,code = self:do_get(dest_url)
    -- Handle response
    if code == 200 then
      if (res_body == nil) then
        log.trace('load config {}')
        return true,'{}'
      end
      return true,res_body
    end
    retry = retry - 1
    if (code ~= nil) then
      log.warn('load config error code '..code)
    else
      log.warn('load config code nil')
    end
  end
  return false,nil
end
------------
-- load dp2knx config from wiser
------------
function Api:load_dp2knx()
  local dest_url = 'https://'..self.ip..'/homecontroller/api/v1/config/dp2knx'
  local retry = 2
  while (retry > 0) do
    local res_body,_,code = self:do_get(dest_url)
    -- Handle response
    if code == 200 then
      if (res_body == nil) then
        log.trace('load config {}')
        return true,'{}'
      end
      return true,res_body
    end
    retry = retry - 1
    if (code ~= nil) then
      log.warn('load dp2knx code '..code)
    else
      log.warn('load dp2knx code nil')
    end
  end
  return false,nil
end
------------
-- load dpenum config from wiser
------------
function Api:load_dpenum(wiser)
  local dest_url = 'https://'..self.ip..'/homecontroller/api/v1/config/dpsamenum'
  local retry = 2
  while (retry > 0) do
    local res_body,_,code = self:do_get(dest_url)
    -- Handle response
    if code == 200 then
      if (res_body == nil) then
        log.trace('load config {}')
        return true,'{}'
      end
      return true,res_body
    end
    retry = retry - 1
  end
  return false,nil
end
------------
-- load changed devs
------------
function Api:load_changeddevs(last_time)
  local dest_url = 'https://'..self.ip..'/homecontroller/api/v1/config/changeddevs'
  local t = last_time
  if (t == nil) then
    t = "0"
  end
  local content = '{\"command\":\"getchangeddevs\","params":{"time":"'..t..'"}}'
  local res_body,_,code = self:do_post(dest_url, content)
  -- Handle response
  if code == 200 then
    if (res_body == nil) then
      log.trace('load changeddevs {}')
      return true,'{}'
    end
    return true,res_body
  end
  return false,nil
end
------------
-- query devs
------------
function Api:query(addrs)
  local dest_url = 'https://'..self.ip..'/homecontroller/api/v1/query'
  local req = {command='query',addrs=addrs}
  local content = json.encode(req)
  local retry = 2
  while (retry > 0) do
    local res_body,_,code = self:do_post(dest_url, content)
    -- Handle response
    if code == 200 then
      if (res_body == nil) then
        log.trace('load changeddevs {}')
        return '{}'
      end
      return res_body
    end
    retry = retry - 1
  end
  return nil
end
------------
-- control devs
------------
function Api:control(addr, type, val)
  local dest_url = 'https://'..self.ip..'/homecontroller/api/v1/control'
  local cmdlist = {}
  cmdlist[1] = {addr=addr,type=type,val=tonumber(val),delay=0}
  local req = {command='control',cmdlist=cmdlist}
  local content = json.encode(req)
  local retry = 2
  while (retry > 0) do
    local _,_,code = self:do_post(dest_url, content)
    -- Handle response
    if code == 200 then
      return true
    end
    retry = retry - 1
  end
  return false
end



return Api

