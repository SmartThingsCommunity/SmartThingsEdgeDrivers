local clusters = require "st.zigbee.zcl.clusters"
local Groups = clusters.Groups
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"
local log = require "log"
local utils = require "st.utils"

local function zdo_binding_table_handler(driver, device, zb_rx)
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    log.debug("### binding_table: " .. utils.stringify_table(binding_table, "binding_table table", true))
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
      return
    end
  end
  driver:add_hub_to_zigbee_group(0x0000) -- fallback if no binding table entries found
  device:send(Groups.commands.AddGroup(device, 0x0000))
end

local robb = {
  NAME = "ROBB",
  zigbee_handlers = {
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    }
  },
  sub_drivers = {
    --require("zigbee-multi-button.robb.wireless_smarrt_switch_2"),
    --require("zigbee-multi-button.robb.wireless_smarrt_switch_4"),
    require("zigbee-multi-button.robb.wireless_smarrt_switch_8")
  },
  can_handle = function(opts, driver, device, ...)
    log.debug("### manufacturer: " .. device:get_manufacturer())
    return device:get_manufacturer() == "ROBB smarrt"
  end
}

return robb
