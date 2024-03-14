local cc = require "st.zwave.CommandClass"
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

-- doing refresh would cause incorrect state for device, see comments in wakeup-no-poll
local NORTEK_FP = {mfr = 0x014F, prod = 0x2001, model = 0x0102} -- NorTek open/close sensor
local POPP_THERMOSTAT_FP = {mfr = 0x0002, prod = 0x0115, model = 0xA010} --Popp thermostat
local AEOTEC_MULTISENSOR_6_FP = {mfr = 0x0086, model = 0x0064} --Aeotec multisensor 6
local AEOTEC_MULTISENSOR_7_FP = {mfr = 0x0371, model = 0x0018} --Aeotec multisensor 7
local ENERWAVE_MOTION_FP = {mfr = 0x011A} --Enerwave motion sensor
local HOMESEER_MULTI_SENSOR_FP = {mfr = 0x001E, prod = 0x0002, model = 0x0001} -- Homeseer multi sensor HSM100
local SENSATIVE_STRIP_FP = {mfr = 0x019A, model = 0x000A}
local FPS = {NORTEK_FP, POPP_THERMOSTAT_FP,
             AEOTEC_MULTISENSOR_6_FP, AEOTEC_MULTISENSOR_7_FP,
             ENERWAVE_MOTION_FP, HOMESEER_MULTI_SENSOR_FP, SENSATIVE_STRIP_FP}

local function can_handle(opts, driver, device, cmd, ...)
  local version = require "version"
  if version.api == 6 and
    cmd.cmd_class == cc.WAKE_UP and
    cmd.cmd_id == WakeUp.NOTIFICATION then

    for _, fp in ipairs(FPS) do
      if device:id_match(fp.mfr, fp.prod, fp.model) then return false end
    end
    return true
  else
    return false
  end
end

local function wakeup_notification(driver, device, cmd)
  device:refresh()
end

local apiv6_bugfix = {
  zwave_handlers = {
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  NAME = "apiv6_bugfix",
  can_handle = can_handle
}

return apiv6_bugfix
