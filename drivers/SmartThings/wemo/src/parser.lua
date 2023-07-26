local capabilities = require "st.capabilities"
local log = require "log"

local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"

local tablefind = require "util".tablefind

local parser = {}

function parser.parse_http_request(request)
  -- pattern matching for responses, possibly save for later
  -- local stat_line, stat, head, body = response:match("^(HTTP/1.1 (%d%d%d) [%l%u]*)\r\n(.+)\r\n\r\n(.*)%s*$")
  local req_line, hdrs, body = request:match("^(.* HTTP/1.1)\r\n(.+\r\n)\r\n(.*)%s*$")

  local headers = {}
  if hdrs == nil then
    log.warn("Couldn't parse Wemo's request")
    return nil
  end

  for k, v in hdrs:gmatch("([%a%p]+):%s*([%a%p%d]+)\r\n") do
    if #v == 0 then
      v = nil
    end
    headers[k] = v
  end
  return req_line, headers, body
end

local function handle_binary_state(device, value)
  -- parses wemo insight style ("8|1611850428|58|...") state, works just fine for a single value too
  local result = {}
  local lut = {
      "state",
      "last_changed_timestamp",
      "last_on_for_s",
      "on_today_s",
      "on_total_s",
      "timespan_s",
      "avg_power_W",
      "current_power_mW",
      "energy_today_Wh",
      "energy_total_Wh",
      "standby_limit_mW",
  }
  -- Parse the data and insert into the result_table
  local iter = value:gmatch("([^|]+)")
  for _, name in ipairs(lut) do
      result[name] = tonumber(iter() or 0)
  end

  -- power state
  local state = result.state
  if state == 0 then
    if device:supports_capability_by_id("switch") then
      device:emit_event(capabilities.switch.switch("off"))
    elseif device:supports_capability_by_id("motionSensor") then
      device:emit_event(capabilities.motionSensor.motion("inactive"))
    else
      log.warn("parse| BinaryState event on device that supports neither `switch` nor `motionSensor`")
    end
  else
    -- have observed 1 and 8 as values while different switches were on, don't know what they mean
    if device:supports_capability_by_id("switch") then
      device:emit_event(capabilities.switch.switch("on"))
    elseif device:supports_capability_by_id("motionSensor") then
      device:emit_event(capabilities.motionSensor.motion("active"))
    else
      log.warn("parse| BinaryState event on device that supports neither `switch` nor `motionSensor`")
    end
  end

  if result.current_power_mW ~= nil and result.energy_today_Wh ~= nil and
    device:supports_capability_by_id("powerMeter") and device:supports_capability_by_id("energyMeter") then
    device:emit_event(capabilities.powerMeter.power(result.current_power_mW / 1000)) --ST uses watts by default
    --Sometimes total energy reported is way off, in that case use the daily energy reported
    if result.energy_today_Wh > result.energy_total_Wh then
      device:emit_event(capabilities.energyMeter.energy({value = result.energy_today_Wh, unit = "Wh"}))
    else
      device:emit_event(capabilities.energyMeter.energy({value = result.energy_total_Wh, unit = "Wh"}))
    end
  end
end

local function handle_brightness(device, value)
  local utils = require "st.utils"
  local level = utils.clamp_value(tonumber(value), 0, 100)
  if level then
    device:emit_event(capabilities.switchLevel.level(level))
  else
    log.warn("parse| Received invalid brightness value: " .. value)
  end
end

function parser.parse_subscription_resp_xml(device, xml)
  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  local success, err = pcall(xml_parser.parse, xml_parser, xml)

  if not handler.root or not success then
    log.warn("parse| unable to parse subscription response xml: ", err)
    return
  end

  local parsed_xml = handler.root

  local binarystate = tablefind(parsed_xml, "e:propertyset.e:property.BinaryState")
  if binarystate then
    log.trace("parse| binary state", binarystate)
    handle_binary_state(device, binarystate)
  end

  local brightness = tablefind(parsed_xml, "e:propertyset.e:property.Brightness")
  if brightness then
    log.trace("parse| brightness", brightness)
    handle_brightness(device, brightness)
  end
end

function parser.parse_get_state_resp_xml(device, xml)
  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(xml)

  local parsed_xml = handler.root

  local binarystate = tablefind(parsed_xml, "s:Envelope.s:Body.u:GetBinaryStateResponse.BinaryState")
  if binarystate then
    log.trace("parse| binary state", binarystate)
    handle_binary_state(device, binarystate)
  end

  local brightness = tablefind(parsed_xml, "s:Envelope.s:Body.u:GetBinaryStateResponse.brightness")
  if brightness then
    log.trace("parse| brightness", brightness)
    handle_brightness(device, brightness)
  end

  local insight = tablefind(parsed_xml, "s:Envelope.s:Body.u:GetInsightParamsResponse.InsightParams")
  if insight then
    log.trace("parse| insight_params", insight)
    handle_binary_state(device, insight)
  end
end

return parser
