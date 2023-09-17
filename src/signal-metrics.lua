------- signal metrics emit event----

local capabilities = require "st.capabilities"

local signal_Metrics = capabilities["legendabsolute60149.signalMetrics"]

local signal ={}

  -- emit signal metrics
  function signal.metrics(device, zb_rx)
    local visible_satate = false
    if device.preferences.signalMetricsVisibles == "Yes" then
      visible_satate = true
    end
    --local metrics = string.format("dni: 0x%04X", zb_rx.address_header.src_addr.value)..", lqi: "..zb_rx.lqi.value..", rssi: "..zb_rx.rssi.value.."dBm"
    local gmt = os.date("%Y/%m/%d Time: %H:%M",os.time())
    local dni = string.format("0x%04X", zb_rx.address_header.src_addr.value)
    --local metrics = "<em table style='font-size:70%';'font-weight: bold'</em>".. <b>DNI: </b>".. dni .. "  ".."<b> LQI: </b>" .. zb_rx.lqi.value .."  ".."<b>RSSI: </b>".. zb_rx.rssi.value .. "dbm".."</em>".."<BR>"
    local metrics = "<em table style='font-size:70%';'font-weight: bold'</em>".. "<b>GMT: </b>".. gmt .."<BR>"
    metrics = metrics .. "<b>DNI: </b>".. dni .. "  ".."<b> LQI: </b>" .. zb_rx.lqi.value .."  ".."<b>RSSI: </b>".. zb_rx.rssi.value .. "dbm".."</em>".."<BR>"
    device:emit_event(signal_Metrics.signalMetrics({value = metrics}, {visibility = {displayed = visible_satate }}))
  end

return signal