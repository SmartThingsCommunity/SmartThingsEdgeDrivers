local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local aqara_utils = require "aqara/aqara_utils"

local OnOff = clusters.OnOff
local AnalogInput = clusters.AnalogInput

local ENDPOINT_POWER_METER = 0x15
local ENDPOINT_ENERGY_METER = 0x1F

local APPLICATION_VERSION = "application_version"

local function is_aqara_version(opts, driver, device)
  local softwareVersion = device:get_field(APPLICATION_VERSION)
  return softwareVersion and softwareVersion == 32
end

local function round(num)
  local mult = 10
  return math.floor(num * mult + 0.5) / mult
end

local function present_value_handler(driver, device, value, zb_rx)
  local src_endpoint = zb_rx.address_header.src_endpoint.value
  if src_endpoint == ENDPOINT_POWER_METER then
    -- powerMeter
    local raw_value = value.value -- 'W'
    aqara_utils.emit_power_meter_event(device, { value = round(raw_value) })
  elseif src_endpoint == ENDPOINT_ENERGY_METER then
    -- energyMeter, powerConsumptionReport
    local raw_value = value.value -- 'kWh'
    aqara_utils.emit_energy_meter_event(device, { value = round(raw_value * 1000) })
    aqara_utils.emit_power_consumption_report_event(device, { value = round(raw_value * 1000) })
  end
end

local function on_off_handler(driver, device, value, zb_rx)
  if value.value == true then
    device:emit_event(capabilities.switch.switch.on())
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_POWER_METER))
    device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_ENERGY_METER))
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_POWER_METER))
  device:send(AnalogInput.attributes.PresentValue:read(device):to_endpoint(ENDPOINT_ENERGY_METER))
end

local aqara_smart_plug_version_handler = {
  NAME = "Aqara Smart Plug Version Handler",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = on_off_handler
      },
      [AnalogInput.ID] = {
        [AnalogInput.attributes.PresentValue.ID] = present_value_handler
      }
    }
  },
  can_handle = is_aqara_version,
}

return aqara_smart_plug_version_handler
