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
    log.debug("binary state value=", value)
    local vals = string.gmatch(value, "%d+")
    -- map all values to numbers
    -- note: this really does need `or nil`, `tonumber()` is an error, `tonumber(nil)` returns nil
    local numvals = function() return tonumber(vals() or 0) end
    log.debug("binary state numvals=", numvals)

    -- power state
    local state = numvals()
    log.debug("binary state power state=", state)
    if state == 0 then
	if device:supports_capability_by_id("switch") then
	  log.debug("binary state power switch off")
          device:emit_event(capabilities.switch.switch("off"))
        elseif device:supports_capability_by_id("motionSensor") then
          log.debug("binary state power motionSensor inactive")
          device:emit_event(capabilities.motionSensor.motion("inactive"))
        else
          log.warn("BinaryState event on device that supports neither `switch` nor `motionSensor`")
        end
    else
        -- have observed 1 and 8 as values while different switches were on, don't know what they mean
	log.debug("non-zero binary state, assume means on", state)
	if device:supports_capability_by_id("switch") then
          log.debug("binary state power switch on")
          device:emit_event(capabilities.switch.switch("on"))
        elseif device:supports_capability_by_id("motionSensor") then
          log.debug("binary state power motionSensor active")
          device:emit_event(capabilities.motionSensor.motion("active"))
        else
          log.warn("BinaryState event on device that supports neither `switch` nor `motionSensor`")
        end
    end

    -- TODO: there's a bunch more values from insight plugs, what do they mean?
end

local function handle_brightness(device, value)
    -- TODO: Is bounds checking automatically handled by CapACE generation?
    local level = tonumber(value)
    if level then
        device:emit_event(capabilities.switchLevel.level(level))
    else
        log.warn("Received invalid brightness value: " .. value)
    end
end

function parser.parse_subscription_resp_xml(device, xml)
    local handler = xml_handler:new()
    local xml_parser = xml2lua.parser(handler)
    xml_parser:parse(xml)

    local parsed_xml = handler.root

    local binarystate = tablefind(parsed_xml, "e:propertyset.e:property.BinaryState")
    if binarystate then
	log.trace("binary state", binarystate)
        handle_binary_state(device, binarystate)
    end

    local brightness = tablefind(parsed_xml, "e:propertyset.e:property.Brightness")
    if brightness then
	log.trace("brightness", brightness)
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
	log.trace("binary state", binarystate)
        handle_binary_state(device, binarystate)
    end

    local brightness = tablefind(parsed_xml, "s:Envelope.s:Body.u:GetBinaryStateResponse.brightness")
    if brightness then
	log.trace("brightness", brightness)
        handle_brightness(device, brightness)
    end
end

return parser
