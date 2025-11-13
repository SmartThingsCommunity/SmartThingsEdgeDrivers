--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-04-25 13:38:25
LastEditors: liangjia
LastEditTime: 2024-04-25 13:53:04
--]]
--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-04-25 13:38:25
LastEditors: liangjia
LastEditTime: 2024-04-25 13:47:42
--]]
--[[
Description: 
Version: 2.0
Autor: liangjia
Date: 2024-01-19 18:05:31
LastEditors: liangjia
LastEditTime: 2024-01-20 10:41:41
--]]
local capabilities = require "st.capabilities"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local sonoff_utils = require "sonoff/sonoff_utils"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local OccupancySensing = zcl_clusters.OccupancySensing
local log = require "log"
local zb_const = require "st.zigbee.constants"
local write_attr_response = require "st.zigbee.zcl.global_commands.write_attribute_response"
local data_types = require "st.zigbee.data_types"
local Status = (require "st.zigbee.zcl.types").ZclStatus
local IASZone = (require "st.zigbee.zcl.clusters").IASZone


local tamper = capabilities["samplereturn62595.tamperStatus"]


local PREF_TAMPER_INSTALL = 0
local PREF_TAMPER_REMOVE  = 1

local FINGERPRINTS = {
  { mfr = "SONOFF", model = "SNZB-04P" },
  { mfr = "SONOFF", model = "SNZB-04PR2" }
}

local is_sonoff_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function spilt_attr_handler(driver, device, value, zb_rx)
  log.debug("<<< Tamper Value >>>",value.value)
  local raw_value = value.value
  if raw_value == PREF_TAMPER_INSTALL then
    device:emit_event(tamper.tamperProof.Normal())
    log.debug("<<< -Tamper Value- >>>",value.value)
  elseif raw_value == PREF_TAMPER_REMOVE then
    device:emit_event(tamper.tamperProof.Tampered())
    log.debug("<<< -Tamper Value- >>>",value.value)
  end
end

-- local function contact_status_handler(self, device, value, zb_rx)
--     log.debug("<<< ZoneStatus Value >>>",value.value)
--     if value.value == 1 or value.value == true then
-- 		device:emit_event(capabilities.contactSensor.contact.open())
--     log.debug("<<< -ZoneStatus Value- >>>",value.value)
--     elseif value.value == 0 or value.value == false then
-- 		device:emit_event(capabilities.contactSensor.contact.closed())
--     log.debug("<<< -ZoneStatus Value- >>>",value.value)
--     end
-- end
local function contact_status_handler(driver, device, zb_rx)
    local zone_status_value = zb_rx.body.zcl_body.zone_status.value
    log.debug("<<< ZoneStatus Value >>>", zone_status_value)
    
    if zone_status_value ~= nil then
        local contact_bit = zone_status_value & 0x0001
        if contact_bit == 0x0001 then
            device:emit_event(capabilities.contactSensor.contact.open())
            log.debug("<<< -Contact OPEN - >>>")
        else
            device:emit_event(capabilities.contactSensor.contact.closed())
            log.debug("<<< -Contact CLOSED - >>>")
        end
    else
        log.warn("Zone status value is nil")
    end
end



local function added_handler(self, device)
  --update UI 
  device:emit_event(tamper.tamperProof.Normal())
end

local function device_init(driver, device)
--do notthing
end

local sonoff_contact_handler = {
  NAME = "Sonoff contact Handler",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler
  },
  zigbee_handlers = {
    attr = {
      [sonoff_utils.SONOFF_PRIVITE_CLUSTER_ID] = {
        [sonoff_utils.SONOFF_SPILT_ATTRIBUTE_ID] = spilt_attr_handler
      }
    },
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = contact_status_handler
      }
    }
  },
  sub_drivers = {
    require("sonoff/SNZB-04PR2")
  },
  can_handle = is_sonoff_products
  -- can_handle = function(opts, driver, device, ...)
  --   return device:get_model() == "SNZB-04P"
  -- end
}

return sonoff_contact_handler
