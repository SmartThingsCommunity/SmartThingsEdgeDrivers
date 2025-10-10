
-- There are reports of at least one device (SONOFF 01MINIZB) which occasionally
-- reports this value as an Int8, rather than a Boolean, as per the spec
return function(opts, driver, device, zb_rx, ...)
  local zcl_clusters = require "st.zigbee.zcl.clusters"
  local data_types = require "st.zigbee.data_types"
  local can_handle = opts.dispatcher_class == "ZigbeeMessageDispatcher" and
    device:get_manufacturer() == "SONOFF" and
    zb_rx.body and
    zb_rx.body.zcl_body and
    zb_rx.body.zcl_body.attr_records and
    zb_rx.address_header.cluster.value == zcl_clusters.OnOff.ID and
    zb_rx.body.zcl_body.attr_records[1].attr_id.value == zcl_clusters.OnOff.attributes.OnOff.ID and
    zb_rx.body.zcl_body.attr_records[1].data_type.value ~= data_types.Boolean.ID
  if can_handle then
    local subdriver = require("bad_on_off_data_type")
    return true, subdriver
  else
    return false
  end
end
