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

--- @type st.capabilities
local capabilities = require "st.capabilities"
local log = require "log"

--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.BarrierOperator
local BarrierOperator = (require "st.zwave.CommandClass.BarrierOperator")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })
--- @type st.zwave.CommandClass.SensorMultilevel
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 11 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 8 })

-- Ecolink garage door operator
local ECOLINK_GARAGE_DOOR_FINGERPRINTS = {
  { manufacturerId = 0x014A, productType = 0x0007, productId = 0x4731 }
}

local GDO_ENDPOINT_NAME = "main"
local CONTACTSENSOR_ENDPOINT_NAME = "sensor"
local GDO_ENDPOINT_NUMBER = 1
local CONTACTSENSOR_ENDPOINT_NUMBER = 2

local CONTACTSENSOR_BATTERY_LEVEL_NORMAL = 100
local CONTACTSENSOR_BATTERY_LEVEL_LOW = 1
local CONTACTSENSOR_BATTERY_LEVEL_DEAD = 0

local GDO_CONFIG_PARAM_NO_UNATTENDED_WAIT = 1
local GDO_CONFIG_PARAM_NO_ACTIVATION_TIME = 2
local GDO_CONFIG_PARAM_NO_OPEN_TIMEOUT = 3
local GDO_CONFIG_PARAM_NO_CLOSE_TIMEOUT = 4
local GDO_CONFIG_PARAM_NO_SHAKE_SENSE = 5
local GDO_CONFIG_PARAM_NO_APP_RETRY = 6

--- Determine whether the passed device is an Ecolink garage door operator
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_ecolink_garage_door(opts, driver, device, ...)
  for _, fingerprint in ipairs(ECOLINK_GARAGE_DOOR_FINGERPRINTS) do
    if
    device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId)
    then
      return true
    end
  end
  return false
end

local function component_to_endpoint(device, component_id)
  if (CONTACTSENSOR_ENDPOINT_NAME == component_id)  then
    --contactSensor is 2 
    return CONTACTSENSOR_ENDPOINT_NUMBER
  end
  -- main endpoint is garage door
  return GDO_ENDPOINT_NUMBER
end

local function endpoint_to_component(device, ep)
  if ( CONTACTSENSOR_ENDPOINT_NUMBER == ep ) then
    return CONTACTSENSOR_ENDPOINT_NAME
  end
  return GDO_ENDPOINT_NAME
end

--- Handle BarrierOperator Report
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.BarrierOperator.Report
local function barrieroperator_report_handler(driver, device, cmd)
  local barrier_event = nil
  log.info_with
  (
    {hub_logs=true}, 
    "barrieroperator_report_handler> device:%s, cmd:%s", tostring(device), tostring(cmd)
  )
  if cmd.args.state == BarrierOperator.state.CLOSED then
    barrier_event = capabilities.doorControl.door.closed()
  elseif cmd.args.state == BarrierOperator.state.CLOSING then
    barrier_event = capabilities.doorControl.door.closing()
  elseif cmd.args.state == BarrierOperator.state.STOPPED then
    barrier_event = capabilities.doorControl.door.unknown()
  elseif cmd.args.state == BarrierOperator.state.OPENING then
    barrier_event = capabilities.doorControl.door.opening()
  elseif cmd.args.state == BarrierOperator.state.OPEN then
    barrier_event = capabilities.doorControl.door.open()
  end

  if (barrier_event ~= nil) then
    device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER, barrier_event)
  end

end

local function send_open_to_gdo(driver, device, command)
  if (
    device:get_latest_state(
            CONTACTSENSOR_ENDPOINT_NAME,
            capabilities.tamperAlert.ID,
            capabilities.tamperAlert.tamper.NAME) == "clear"
    ) then
    log.info_with({hub_logs=true}, "<<send_open_to_gdo>> - SUCCESS")

    device:send(BarrierOperator:Set({ target_value = BarrierOperator.state.OPEN }))
    device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, function(d)
      device:send(BarrierOperator:Get({}))
    end)

  else
    log.info_with({hub_logs=true}, "<<send_open_to_gdo>> FAILED - SENSOR IN TAMPER")

    device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER,
                                  capabilities.doorControl.door.unknown()
                                  )
  end
end

local function send_close_to_gdo(driver, device, command)
  if (
    device:get_latest_state(CONTACTSENSOR_ENDPOINT_NAME,
                            capabilities.tamperAlert.ID,
                            capabilities.tamperAlert.tamper.NAME) == "clear"
  ) then
    log.info_with({hub_logs=true}, "<<send_close_to_gdo>> - SUCCESS")

    device:send(BarrierOperator:Set({ target_value = BarrierOperator.state.CLOSED }))
    device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, function(d)
      device:send(BarrierOperator:Get({}))
    end)
else
  log.info_with({hub_logs=true}, "<<send_close_to_gdo>> FAILED - SENSOR IN TAMPER")

  device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER,
                                capabilities.doorControl.door.unknown()
                                )
end
end


--- Handle Device Instantiated Event
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
local function device_instatiated(driver, device)
  log.info_with({hub_logs=true}, "device init")
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)
  -- device:subscribe()

  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, function(d)
    device:send(BarrierOperator:Get({}))
  end)
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY*2, function(d)
    device:send(SensorMultilevel:Get({}))
  end)  
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY*3, function(d)
    device:send(Configuration:BulkGetV2({parameter_offset = 1, number_of_parameters = 6}) )
  end)

  -- Reset contact sensor battery level... This should be pollable on the GDO side.
  device:emit_event_for_endpoint(CONTACTSENSOR_ENDPOINT_NUMBER,
                                capabilities.battery.battery(CONTACTSENSOR_BATTERY_LEVEL_NORMAL)
                                )
  -- Reset contact sensor fields
  device:emit_event_for_endpoint(CONTACTSENSOR_ENDPOINT_NUMBER,
                                capabilities.tamperAlert.tamper.clear()
                                )
  device:emit_event_for_endpoint(CONTACTSENSOR_ENDPOINT_NUMBER,
                                capabilities.contactSensor.contact.closed()
                                )

  -- Init barrier door state
  device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER,
                                capabilities.doorControl.door.closed()
                                )

end

--- Handle Device Added Event
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
local function device_added(driver, device)
  log.info_with({hub_logs=true}, "Ecolink GDO device_added")
  device:send(BarrierOperator:Get({}))
end

--- Configuration Report Handler
---
--- @param device st.zwave.Device
local function configure_device_with_updated_config(device)
  local updated_params = {}
  updated_params[GDO_CONFIG_PARAM_NO_UNATTENDED_WAIT]
                                            = {parameter = device.preferences.closeWaitPeriodSec}
  updated_params[GDO_CONFIG_PARAM_NO_ACTIVATION_TIME] 
                                            = {parameter = device.preferences.activationTimeMS}
  updated_params[GDO_CONFIG_PARAM_NO_OPEN_TIMEOUT]
                                            = {parameter = device.preferences.doorOpenTimeoutSec}
  updated_params[GDO_CONFIG_PARAM_NO_CLOSE_TIMEOUT]
                                            = {parameter = device.preferences.doorCloseTimeoutSec}
  updated_params[GDO_CONFIG_PARAM_NO_SHAKE_SENSE]
                                            = {parameter = device.preferences.shakeSensitivity}
  updated_params[GDO_CONFIG_PARAM_NO_APP_RETRY]
                                            = {parameter = device.preferences.applicationLevelRetries}

  device:send(Configuration:BulkSetV2({
                                        parameter_offset = 1, 
                                        size = 2, 
                                        handshake = false, 
                                        default = false,
                                        parameters = updated_params
                                      }))
end

--- Handle Device Needs Configuring Event
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
local function do_configure(driver, device)
  log.info_with({hub_logs=true}, "do_configure")
  configure_device_with_updated_config(device)
end

local function device_preferences_updated(driver, device, event, args)
  -- Did my preference value change
  log.info_with({hub_logs=true}, 
                string.format("device_preferences_updated> device:%s event:%s args:%s", 
                tostring(device), tostring(event), tostring(args)))
  configure_device_with_updated_config(device)
end

--- Notification Report Handler
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Notification.Report
local function notification_report_handler(driver, device, cmd)
  local notificationType = cmd.args.notification_type
  local notificationEvent = cmd.args.event
  local barrier_event = nil
  local contact_event = nil

  log.info_with({hub_logs=true}, 
                string.format("notification_report_handler> Type:%d Event:%d", 
                notificationType, notificationEvent) )

  if ( 0 == notificationEvent ) then
    -- Clear Notifications
    -- First byte of the parameters is the notification being cleared
    -- so reuse notificationEvent variable as the event being cleared
    if (0 ~= string.len(cmd.args.event_parameter)) then
      notificationEvent = string.byte(cmd.args.event_parameter)
      log.info_with({hub_logs=true}, string.format("NOTIFICATION CLEARED EVENT"))

    end

    if (notificationType == Notification.notification_type.SYSTEM) then

      if (notificationEvent == Notification.event.system.TAMPERING_PRODUCT_COVER_REMOVED) then
        log.info_with({hub_logs=true}, "NOTIFICATION[DEBUG] TAMPER CLEAR!")
        contact_event = capabilities.tamperAlert.tamper.clear()
      else
        log.info_with({hub_logs=true},
                      string.format("NOTIFICATION[DEBUG] UNHANDLED SYSTEM CLEAR EVENT:%d", 
                      notificationEvent))
      end

    elseif (notificationType == Notification.notification_type.ACCESS_CONTROL) then

      if (notificationEvent == 
          Notification.event.access_control.BARRIER_SENSOR_LOW_BATTERY_WARNING) then
        barrier_event = capabilities.doorControl.door.closed()
        contact_event = capabilities.healthCheck.healthStatus.online()
        contact_event = capabilities.battery.battery(CONTACTSENSOR_BATTERY_LEVEL_NORMAL)
        log.info_with({hub_logs=true},
                      string.format("NOTIFICATION ACCESS CONTROL - SENSOR LOW BATT WARNING"))

      elseif (notificationEvent == 
              Notification.event.access_control.BARRIER_SENSOR_NOT_DETECTED_SUPERVISORY_ERROR) then
        barrier_event = capabilities.doorControl.door.closed()
        contact_event = capabilities.healthCheck.healthStatus.online()
        log.info_with({hub_logs=true},
              string.format("NOTIFICATION ACCESS CONTROL - SENSOR NOT DETECTED SUPERVISORY ERROR"))

      else
        log.info_with({hub_logs=true},
                      string.format("NOTIFICATION[DEBUG] UNHANDLED ACCESS CONTROL CLEAR EVENT:%d", 
                      notificationEvent))
      end

    end

  else
    -- Handle Notification events
    if (notificationType == Notification.notification_type.SYSTEM) then
      if (notificationEvent == Notification.event.system.TAMPERING_PRODUCT_COVER_REMOVED) then
        contact_event = capabilities.tamperAlert.tamper.detected()
        log.info_with({hub_logs=true}, string.format("NOTIFICATION SYSTEM - TAMPER DETECTED"))
      end

    elseif (notificationType == Notification.notification_type.ACCESS_CONTROL) then

      if (notificationEvent == Notification.event.access_control.WINDOW_DOOR_IS_OPEN) then
        barrier_event = capabilities.doorControl.door.open()
        contact_event = capabilities.contactSensor.contact.open()
        log.info_with({hub_logs=true},
                      string.format("NOTIFICATION ACCESS CONTROL - DOOR IS OPEN"))

      elseif (notificationEvent == Notification.event.access_control.WINDOW_DOOR_IS_CLOSED) then
        barrier_event = capabilities.doorControl.door.closed()
        contact_event = capabilities.contactSensor.contact.closed()
        log.info_with({hub_logs=true},
                      string.format("NOTIFICATION ACCESS CONTROL - DOOR IS CLOSED"))

      elseif (notificationEvent ==
      Notification.event.access_control.BARRIER_MOTOR_HAS_EXCEEDED_MANUFACTURERS_OPERATIONAL_TIME_LIMIT) then
        barrier_event = capabilities.doorControl.door.unknown()
        log.info_with({hub_logs=true},
                      string.format("NOTIFICATION ACCESS CONTROL - MOTOR EXCEEDED TIME LIMIT"))

      elseif (notificationEvent ==
      Notification.event.access_control.BARRIER_UNABLE_TO_PERFORM_REQUESTED_OPERATION_DUE_TO_UL_REQUIREMENTS) then
        barrier_event = capabilities.doorControl.door.unknown()
        log.info_with({hub_logs=true},
                      string.format("NOTIFICATION ACCESS CONTROL - UNABLE TO PERFORM DUE TO UL"))

      elseif (notificationEvent ==
      Notification.event.access_control.BARRIER_FAILED_TO_PERFORM_REQUESTED_OPERATION_DEVICE_MALFUNCTION) then
        barrier_event = capabilities.doorControl.door.unknown()
        log.info_with({hub_logs=true},
              string.format("NOTIFICATION ACCESS CONTROL - UNABLE TO PERFORM DUE TO DEVICE MALFUNCTION"))

      elseif (notificationEvent ==
              Notification.event.access_control.BARRIER_SENSOR_NOT_DETECTED_SUPERVISORY_ERROR) then
        barrier_event = capabilities.doorControl.door.closed()
        contact_event = capabilities.healthCheck.healthStatus.online()
        log.info_with({hub_logs=true},
                    string.format("NOTIFICATION ACCESS CONTROL - SENSOR NOT DETECTED SUPERVISORY ERROR"))

      elseif (notificationEvent ==
              Notification.event.access_control.BARRIER_SENSOR_LOW_BATTERY_WARNING) then
        barrier_event = capabilities.doorControl.door.closed()
        contact_event = capabilities.battery.battery(CONTACTSENSOR_BATTERY_LEVEL_LOW)
        log.info_with({hub_logs=true},
                      string.format("NOTIFICATION ACCESS CONTROL - SENSOR LOW BATTERY WARNING"))

      end

    end
  end

  -- If we are going to emit an event to the device, from a notification, do it.
  if (barrier_event ~= nil) then
    device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER, barrier_event)
  end

  if (contact_event ~= nil) then 
    device:emit_event_for_endpoint(CONTACTSENSOR_ENDPOINT_NUMBER, contact_event)
  end

end

--- Multilevel Sensor Report Handler
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.SensorMultilevel.Report
local function sensor_multilevel_report_handler(driver, device, cmd)
  log.info_with({hub_logs=true}, 
                string.format("sensor_multilevel_report_handler> Type:%d Value:%s", 
                cmd.args.sensor_type, cmd.args.sensor_value) )
  -- Handle Temperature Report
  if (SensorMultilevel.sensor_type.TEMPERATURE == cmd.args.sensor_type) then
    local scale = 'C'
    if (SensorMultilevel.scale.temperature.FAHRENHEIT == cmd.args.scale) then
      scale = 'F'
    end
    log.info_with({hub_logs=true}, 
                  string.format("Temperature> Value:%s Scale:%s", 
                  tostring(cmd.args.sensor_value), scale) )
    local event = capabilities.temperatureMeasurement.temperature(
                                          {value = cmd.args.sensor_value, unit = scale})
    device:emit_event_for_endpoint(GDO_ENDPOINT_NUMBER, event)
  end

end

local function do_refresh(driver, device)
  -- State of garage door
  device:send_to_component(BarrierOperator:Get({}))

  -- State of tilt sensor
  device:send_to_component(Notification:Get({
                                        v1_alarm_type = 0, 
                                        notification_type = Notification.notification_type.SYSTEM, 
                                        event = 0}))
  device:send_to_component(Notification:Get({
                                        v1_alarm_type = 0, 
                                        notification_type = Notification.notification_type.ACCESS_CONTROL, 
                                        event = 0}))

  -- State of Temperature Sensor
  device:send_to_component(SensorMultilevel:Get({}))
end

local ecolink_garage_door_operator = {
  NAME = "Ecolink Garage Door Controller",
  zwave_handlers = {
    [cc.BARRIER_OPERATOR] = {
      [BarrierOperator.REPORT] = barrieroperator_report_handler
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report_handler
    }
  },
  capability_handlers = {
    [capabilities.doorControl.ID] = {
      [capabilities.doorControl.commands.open.NAME] = send_open_to_gdo,
      [capabilities.doorControl.commands.close.NAME] = send_close_to_gdo
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  lifecycle_handlers = {
    init = device_instatiated,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_preferences_updated
  },
  can_handle = can_handle_ecolink_garage_door
}

log.info_with({hub_logs=true}, "Starting Ecolink Garage Door Opener driver...")
return ecolink_garage_door_operator
