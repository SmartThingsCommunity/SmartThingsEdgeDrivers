local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local device_management = require "st.zigbee.device_management"

local PowerConfiguration = clusters.PowerConfiguration
local IASZone = clusters.IASZone

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.magnet.agl02" }
}

local is_aqara_products = function(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local do_configure = function(self, device)
  device:configure()

  device:send(device_management.build_bind_request(device, IASZone.ID, self.environment_info.hub_zigbee_eui))
  device:send(IASZone.attributes.ZoneStatus:configure_reporting(device, 30, 300, 1))

  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
end

local event_from_zone_status = function(driver, device, zone_status, zb_rx)
  if zone_status.value == 0x0021 then
    device:emit_event(capabilities.contactSensor.contact.open())
  elseif zone_status.value == 0x0020 then
    device:emit_event(capabilities.contactSensor.contact.closed())
  end
end

local zone_status_change_handler = function(driver, device, zb_rx)
  event_from_zone_status(driver, device, zb_rx.body.zcl_body.zone_status, zb_rx)
end

local function zone_status_attr_handler(driver, device, zone_status, zb_rx)
  event_from_zone_status(driver, device, zone_status, zb_rx)
end

local aqara_contact_handler = {
  NAME = "Aqara Contact Handler",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.6, 3.0),
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = zone_status_attr_handler
      }
    },
  },
  can_handle = is_aqara_products
}

return aqara_contact_handler
