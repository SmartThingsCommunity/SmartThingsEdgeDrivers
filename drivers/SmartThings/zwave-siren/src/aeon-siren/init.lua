-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=1 })

local AEON_MFR = 0x0086
local AEON_SIREN_PRODUCT_ID = 0x0050

local SOUND_TYPE_AND_VOLUME_PARAMETER_NUMBER = 37
local CONFIGURE_SOUND_TYPE = "type"
local SOUND_TYPE_DEFAULT = 1
local CONFIGURE_VOLUME = "volume"
local VOLUME_DEFAULT = 3

local function can_handle_aeon_siren(opts, driver, device, ...)
  return device.zwave_manufacturer_id == AEON_MFR and device.zwave_product_id == AEON_SIREN_PRODUCT_ID
end

local function configure_sound(device, sound_type, volume)
  if sound_type == nil then sound_type = SOUND_TYPE_DEFAULT end
  if volume == nil then volume = VOLUME_DEFAULT end
  -- MSB defines sound's type, LSB defines volume
  local value = sound_type << 8 | volume
  device:send(Configuration:Set(
    {
      parameter_number = SOUND_TYPE_AND_VOLUME_PARAMETER_NUMBER,
      size = 2,
      configuration_value = value
    }
  ))
  local delayed_command = function()
    device:send(Basic:Set({value=0x00}))
  end
  device.thread:call_with_delay(1, delayed_command)
end

local function do_configure(driver, device)
  -- Send BASIC Report Command to associated devices
  device:send(Configuration:Set({parameter_number = 80, size = 1, configuration_value = 2}))
  configure_sound(device, SOUND_TYPE_DEFAULT, VOLUME_DEFAULT)
end

local function info_changed(driver, device, event, args)
  -- check if user triggered sound type or volume configuration
  local sound_type = device.preferences[CONFIGURE_SOUND_TYPE]
  local volume = device.preferences[CONFIGURE_VOLUME]
  if ((sound_type and args.old_st_store.preferences[CONFIGURE_SOUND_TYPE] ~= sound_type) or
      (volume and args.old_st_store.preferences[CONFIGURE_VOLUME] ~= volume)) then
    configure_sound(device, sound_type, volume)
  end
end

local aeon_siren = {
  NAME = "aeon-siren",
  can_handle = can_handle_aeon_siren,
  lifecycle_handlers = {
    doConfigure = do_configure,
    infoChanged = info_changed
  }
}

return aeon_siren
