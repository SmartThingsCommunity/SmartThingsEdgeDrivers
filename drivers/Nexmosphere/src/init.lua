-- require st provided libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local log = require "log"
-- local socket = require("socket")
local socket = require("cosock.socket")
local udp_client
local nexmoDriver

-- require custom handlers from driver package
--local command_handlers = require "command_handlers"
local discovery = require "discovery"
local settingsSend = false
local sensorSwap = false
local UDPDebugMode = false

local controllerLabel = "A"

local controllerIP
local controllerPort
local hubIp
local hubPort

local networkSettingsGenerated = false

local deviceForPort = {}

local deviceController

local storedSettingPresenceMode = {}
local storedSettingPresenceChangeForTrigger = {}
local storedSettingPresenceRangeOfInterest = {}

local storedSettingAmbientMode = {}
local storedSettingAmbientChangeForTrigger = {}

local storedSettingNFCMode = {}


local nfcUID
local nfcNumber
local nfcLabel1
local nfcLabel2
local nfcLabel3


local callOnSchedule
local consecutiveMessageCounter = 0
local noComCounter = 0
local noResponseCounter = 0
local checkIfControllerAlive = false

local genericSensorNexmosphereOutputMode = capabilities["mode"]
local genericSensorNexmosphereRefresh = capabilities["refresh"]
local genericSensorNexmosphereSummary = capabilities["nexmosphere.summary"]
local presenceSensorNexmosphereChangeForTrigger = capabilities["nexmosphere.changeForTrigger"]
local presenceSensorNexmosphereDistanceZone = capabilities["nexmosphere.distanceZone"]
local presenceSensorNexmosphereAbsoluteDistance = capabilities["nexmosphere.absoluteDistance"]
local presenceSensorNexmosphereRangeOfInterest = capabilities["nexmosphere.rangeOfInterest"]
local genericSensorNexmosphereNumberAndStatus = capabilities["nexmosphere.numberAndStatus"]
local ambientLightSensorNexmosphereChangeForTrigger = capabilities["nexmosphere.lightChangeForTrigger"]
local ambientLightSensorNexmosphereLuxValue = capabilities["nexmosphere.luxValue"]
local ambientLightSensorNexmosphereLuxRange = capabilities["nexmosphere.luxRange"]
local tempHumiSensorNexmosphereTemperatureMeasurement = capabilities["temperatureMeasurement"]
local tempHumiSensorNexmosphereHumidityMeasurement = capabilities["relativeHumidityMeasurement"]
local nfcReaderNexmosphereUID = capabilities["nexmosphere.uid"]
local nfcReaderNexmosphereTagNumber = capabilities["nexmosphere.number"]
local nfcReaderNexmosphereLabel1 = capabilities["nexmosphere.label1"]
local nfcReaderNexmosphereLabel2 = capabilities["nexmosphere.label2"]
local nfcReaderNexmosphereLabel3 = capabilities["nexmosphere.label3"]

local xtalk = {}
xtalk["001"] = capabilities["nexmosphere.xtalk001"]
xtalk["002"] = capabilities["nexmosphere.xtalk002"]
xtalk["003"] = capabilities["nexmosphere.xtalk003"]
xtalk["004"] = capabilities["nexmosphere.xtalk004"]
xtalk["005"] = capabilities["nexmosphere.xtalk005"]
xtalk["006"] = capabilities["nexmosphere.xtalk006"]
xtalk["007"] = capabilities["nexmosphere.xtalk007"]
xtalk["008"] = capabilities["nexmosphere.xtalk008"]
local hubPortSet = capabilities["nexmosphere.hubPort"]
local hubIPSet = capabilities["nexmosphere.hubIp"]
local connectionStatus = capabilities["nexmosphere.connectionStatus"]
local supportedDevices = {"None", "Presence", "Temperature", "NFC", "Lidar", "RFID", "Ambient light"}

local supportedModesForPresence = {"Absolute distance", "Distance zones"}
local supportedModesForAmbient = {"Lux value", "Lux range"}
local supportedModesForLidar = {"Single Detection", "Multi Detection"}
local supportedModesForNFC = {"UID", "Number", "Label 1", "Label 2", "Label 3", "UID, Number and Label 1", "Label 1, 2 and 3"}

local initiateSensors
local startUDPCommunication
local handle_udp_read_loop
local handler_xtalk
local set_Mode_handler
local set_Change_handler_presence
local set_Change_handler_ambient
local set_Range_handler_presence
local refresh_handler

local function stable_delay()
  --socket.sleep(0.2)
end

-----------------------------------------------------------------
-- local functions
-----------------------------------------------------------------
-- this is called once a device is added by the cloud and synchronized down to the hub
local function device_added(driver, device)
  log.info("[" .. device.id .. "] Adding new Nexmosphere device")

  -- set default values for Controller parameters
  if string.find(tostring(device), "controller") then
    for i = 1, 8 do
      local xtalkport = tostring("00" ..i)
      device:emit_event(xtalk[xtalkport].supportedDevices(supportedDevices))
      stable_delay()
      device:emit_event(xtalk[xtalkport].device("None"))
      stable_delay()
    end
    device:emit_event(hubIPSet.hubip("0.0.0.0"))
    stable_delay()
    device:emit_event(hubPortSet.hubport("00000"))
    stable_delay()
    device:emit_event(connectionStatus.UDP("Unconnected"))
    stable_delay()

    controllerIP = device.preferences.controllerIP
    controllerPort =  tonumber(device.preferences.controllerPort)

    deviceController = device
  end

-- bookeeping of sensor device to xtalkport mapping when a a sensor device is added
  local xtalkport
  if string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false) then
    log.info("device.device_network_id is " ..device.device_network_id)
    local i, j = string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false)
    xtalkport = string.sub(device.device_network_id, i+2, j-1)
    --Check if X-talk port was set already set to another device, if so, remove old device
    if deviceForPort[xtalkport] ~= nil then 
      sensorSwap = true
      log.info("trying to delete device " ..deviceForPort[xtalkport].id)
      driver:try_delete_device(deviceForPort[xtalkport].id)
    end
    deviceForPort[xtalkport] = device
    log.info("deviceForPort " ..xtalkport.. " is " ..tostring(deviceForPort[xtalkport]))
  end

  log.info(device)

  -- set a default or queried state for each capability attribute
  -- also, send default settings, but only if UDP connection is already established
  if string.find(tostring(device), "Presence") then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.supportedModes(supportedModesForPresence))
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("0 cm, zone XX")) -- Default summary for Presence sensor
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Distance zones")) -- Default output mode for Presence sensor
    stable_delay()
    deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereDistanceZone.distanceZone("XX")) -- Default distance zone
    stable_delay()
    deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereAbsoluteDistance.absoluteDistance(0)) -- Default absolute value
    stable_delay()
    deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereChangeForTrigger.change({value = 10, unit = "cm"})) -- Default Change for trigger in cm
    stable_delay()
    deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereRangeOfInterest.range(170)) -- Default Range of interest
    stable_delay()
    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "B[ZONE?]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "B[TEMP?] request send to UDP controller")
      socket.sleep(0.5)
    end

  elseif string.find(tostring(device), "RFID") then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.status("lifted")) -- Default RFID status
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.number(0)) -- Default RFID Tag number
    stable_delay()

  elseif string.find(tostring(device), "Ambient") then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.supportedModes(supportedModesForAmbient))
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("0 lux, range 0")) -- Default summary for Presence sensor
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Lux value")) -- Default output mode for Ambient light sensor
    stable_delay()
    deviceForPort[xtalkport]:emit_event(ambientLightSensorNexmosphereLuxValue.luxValue(0)) -- Default Lux Value
    stable_delay()
    deviceForPort[xtalkport]:emit_event(ambientLightSensorNexmosphereLuxRange.luxRange(0)) -- Default Lux Range
    stable_delay()
    deviceForPort[xtalkport]:emit_event(ambientLightSensorNexmosphereChangeForTrigger.change({value = 20, unit = "%"})) -- Default Change for trigger in %
    stable_delay()
    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[4:2]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[4:2] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "S[5:20]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[5:10] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "B[LUX?]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "B[LUX?] request send to UDP controller")
      socket.sleep(0.5)
    end

  elseif string.find(tostring(device), "Temperature") then
    deviceForPort[xtalkport]:emit_event(tempHumiSensorNexmosphereTemperatureMeasurement.temperature({value = 0.0, unit = "C"})) -- Default temperature
    stable_delay()
    deviceForPort[xtalkport]:emit_event(tempHumiSensorNexmosphereHumidityMeasurement.humidity({value = 0.0, unit = "%"})) -- Default humidity level
    stable_delay()
    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[4:3]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[4:3] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "S[5:3]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[5:3] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "B[TEMP?]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "B[TEMP?] request send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "B[HUMI?]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "B[HUMI?] request send to UDP controller")
      socket.sleep(0.5)
    end

  elseif string.find(tostring(device), "NFC") then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.supportedModes(supportedModesForNFC))
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("UID")) -- Default output mode for Presence sensor
    stable_delay()
    deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereUID.UID("XXXXXXXXXXXXXX")) -- Default UID
    stable_delay()
    deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereTagNumber.number(0)) -- Default TagNumber
    stable_delay()
    deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel1.text("-")) -- Default label 1
    stable_delay()
    deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel2.text("-")) -- Default label 2
    stable_delay()
    deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel3.text("-")) -- Default label 3
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("-"))
    stable_delay()
    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[10:1]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[10:1] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "S[19:2]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[19:2] setting send to UDP controller")
      socket.sleep(0.5)
    end

  elseif string.find(tostring(device), "Lidar") then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.supportedModes(supportedModesForLidar))
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Single Detection")) -- Default output mode for Lidar sensor
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.status("exit")) -- Default Zone status
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.number(0)) -- Default Zone number
    stable_delay()
    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[4:1]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[4:1] setting send to UDP controller")
      socket.sleep(0.5)
    end
  end
end


local function device_removed(driver, device)
  log.info("Removing "..device.device_network_id)
  
  -- bookeeping of sensor device to xtalkport mapping when a a sensor device is added
  local xtalkport
  if string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false) then
    local i, j = string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false)
    xtalkport = string.sub(device.device_network_id, i+2, j-1)
    if sensorSwap == false then
      deviceForPort[xtalkport] = nil
      if deviceController ~= nil then
        deviceController:emit_event(xtalk[xtalkport].device("None"))
        stable_delay()
      end
    end
    log.info("deviceForPort " ..xtalkport.. " is " ..tostring(deviceForPort[xtalkport]))
  end
  sensorSwap = false
end


-- this is called both when a device is added (but after `added`) and after a hub reboots.
local function device_init(driver, device)

  log.info("device init " .. device.device_network_id)

  -- After hub reboots, check if Nexmosphere Controller device has been added
  if string.find(tostring(device), "controller") then
    controllerIP = device.preferences.controllerIP
    controllerPort =  tonumber(device.preferences.controllerPort)
    deviceController = device
    -- after hub reboots, check if the IP has been configured
    -- if yes, autostart UDP communication
    if controllerIP ~= "0.0.0.0" then 
      startUDPCommunication()
    end
  end
  initiateSensors(driver, device)
end

function initiateSensors(driver, device)
  -- After hub reboots, check if Sensor device have been added
  local xtalkport
  if string.find(device.device_network_id, controllerLabel .. "%[(.-)%]", 0, false) then
    log.info("device.device_network_id is " ..device.device_network_id)
    local i, j = string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false)
    xtalkport = string.sub(device.device_network_id, i+2, j-1)
    deviceForPort[xtalkport] = device
    log.info("deviceForPort " ..xtalkport.. " is " ..tostring(deviceForPort[xtalkport]))
    log.info("[" .. device.id .. "] Initializing Nexmosphere device")
    device:online()
  end

  if string.find(tostring(device), "Presence") then
    local settingsValue

    settingsValue = deviceForPort[xtalkport]:get_latest_state("main", genericSensorNexmosphereOutputMode.ID, "mode", "no value", "no value")
    if settingsValue == "Distance zones" then
      storedSettingPresenceMode[xtalkport] = "1"
    elseif settingsValue == "Absolute distance" then
      storedSettingPresenceMode[xtalkport] = "2"
    end
   
    settingsValue = deviceForPort[xtalkport]:get_latest_state("main", presenceSensorNexmosphereChangeForTrigger.ID, "change", "no value", "no value")
    storedSettingPresenceChangeForTrigger[xtalkport] = settingsValue

    settingsValue = deviceForPort[xtalkport]:get_latest_state("main", presenceSensorNexmosphereRangeOfInterest.ID, "range", "no value", "no value")
    local i, j = string.find(settingsValue, "0")
    local settingsValueForSensor= string.sub(settingsValue, 0, i-1)
    storedSettingPresenceRangeOfInterest[xtalkport] = settingsValueForSensor


    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[4:" .. storedSettingPresenceMode[xtalkport] .."]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[4:" .. storedSettingPresenceMode[xtalkport] .."] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "S[5:" .. storedSettingPresenceChangeForTrigger[xtalkport] .."]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[5:" .. storedSettingPresenceChangeForTrigger[xtalkport] .."] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "S[6:" .. storedSettingPresenceRangeOfInterest[xtalkport] .."]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[6:" .. storedSettingPresenceRangeOfInterest[xtalkport] .."] setting send to UDP controller")
      socket.sleep(0.5)
      if settingsValue == "Distance zones" then
        udp_client:sendto("X" .. xtalkport .. "B[ZONE?]", controllerIP, controllerPort)
        log.info("X" .. xtalkport .. "B[ZONE?] request send to UDP controller")
        socket.sleep(0.5)
      elseif settingsValue == "Absolute distance" then
        udp_client:sendto("X" .. xtalkport .. "B[DIST?]", controllerIP, controllerPort)
        log.info("X" .. xtalkport .. "B[DIST?] request send to UDP controller")
        socket.sleep(0.5)
      end
    end

  elseif string.find(tostring(device), "RFID") then

  elseif string.find(tostring(device), "Ambient") then
    local settingsValue
    settingsValue = deviceForPort[xtalkport]:get_latest_state("main", genericSensorNexmosphereOutputMode.ID, "mode", "no value", "no value")
    if settingsValue == "Lux range" then
      storedSettingAmbientMode[xtalkport] = "1"
    elseif settingsValue == "Lux value" then
      storedSettingAmbientMode[xtalkport] = "2"
    end
   
    settingsValue = deviceForPort[xtalkport]:get_latest_state("main", ambientLightSensorNexmosphereChangeForTrigger.ID, "change", "no value", "no value")
    storedSettingAmbientChangeForTrigger[xtalkport] = settingsValue

    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[4:" .. storedSettingAmbientMode[xtalkport] .."]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[4:" .. storedSettingAmbientMode[xtalkport] .."] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "S[5:" .. storedSettingAmbientChangeForTrigger[xtalkport] .."]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[5:" .. storedSettingAmbientChangeForTrigger[xtalkport] .."] setting send to UDP controller")
      socket.sleep(0.5)
      if settingsValue == "Lux value" then
        udp_client:sendto("X" .. xtalkport .. "B[LUX?]", controllerIP, controllerPort)
        log.info("X" .. xtalkport .. "B[LUX?] request send to UDP controller")
        socket.sleep(0.5)
      end
    end

  elseif string.find(tostring(device), "Temperature") then
    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[4:3]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[4:3] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "S[5:3]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[5:3] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "B[TEMP?]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "B[TEMP?] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "B[HUMI?]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "B[HUMI?] setting send to UDP controller")
      socket.sleep(0.5)
    end

  elseif string.find(tostring(device), "NFC") then
    local settingsValue
    settingsValue = deviceForPort[xtalkport]:get_latest_state("main", genericSensorNexmosphereOutputMode.ID, "mode", "no value", "no value")
    
    if settingsValue == "UID" then
      storedSettingNFCMode[xtalkport] = "1"
    elseif settingsValue == "Number" then
      storedSettingNFCMode[xtalkport] = "2"
    elseif settingsValue == "Label 1" then
      storedSettingNFCMode[xtalkport] = "3"
    elseif settingsValue == "Label 2" then
      storedSettingNFCMode[xtalkport] = "4"
    elseif settingsValue == "Label 3" then
      storedSettingNFCMode[xtalkport] = "5"
    elseif settingsValue == "UID, Number and Label 1" then
      storedSettingNFCMode[xtalkport] = "6"
    elseif settingsValue == "Label 1, 2 and 3" then
      storedSettingNFCMode[xtalkport] = "7"
    end
    
    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[10:" .. storedSettingNFCMode[xtalkport] .."]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[10:" .. storedSettingNFCMode[xtalkport] .."] setting send to UDP controller")
      socket.sleep(0.5)
      udp_client:sendto("X" .. xtalkport .. "S[19:2]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[19:2] setting send to UDP controller")
      socket.sleep(0.5)
    end

  elseif string.find(tostring(device), "Lidar") then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Single Detection")) -- Default output mode for Lidar sensor
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.status("exit")) -- Default Zone status
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.number(0)) -- Default Zone number
    stable_delay()
    if udp_client ~= nil then
      udp_client:sendto("X" .. xtalkport .. "S[4:1]", controllerIP, controllerPort)
      log.info("X" .. xtalkport .. "S[4:1] setting send to UDP controller")
      socket.sleep(0.5)
    end
  end
end

function startUDPCommunication()
  if networkSettingsGenerated == false then -- only generate newSettings when a hub reboots
    log.info("*** Create UDP socket ***")
    udp_client = socket.udp()
    udp_client:settimeout("1")
    udp_client:setsockname('*', 0)
    udp_client:setoption('broadcast', true)
    log.info(udp_client)
    log.info(udp_client:getsockname())
    hubIp, hubPort = udp_client:getsockname()
    networkSettingsGenerated = true
  end

  log.info("IP of Hub is " .. hubIp)
  log.info("Port of Hub is " .. tostring(hubPort))
  log.info("IP of Controller is set to " .. controllerIP)
  log.info("Port of Contoller is set to " .. controllerPort)
  log.info("Intializing UDP communication settings of Nexmosphere controller")
  deviceController:emit_event(hubIPSet.hubip(tostring(hubIp)))
  stable_delay()
  deviceController:emit_event(hubPortSet.hubport(tostring(hubPort)))
  stable_delay()

  -- Set Nexmosphere controller Destination IP and port
  udp_client:sendto("N000B[PORTOUT=".. hubPort .."]", controllerIP, controllerPort)
  socket.sleep(0.5)
  udp_client:sendto("N000B[DESTIP=".. hubIp .."]", controllerIP, controllerPort)
  socket.sleep(0.5)
  udp_client:sendto("N000B[SAVE!]", controllerIP, controllerPort)
  socket.sleep(0.5)

  callOnSchedule = nexmoDriver:call_on_schedule(1, handle_udp_read_loop)
  stable_delay()

  if UDPDebugMode == false then
    deviceController:emit_event(connectionStatus.UDP("Connecting..."))
    stable_delay()
  else
    -- To simulate the sensor value when no sensor is connected.
    -- Always connected.
    checkIfControllerAlive = true
    noResponseCounter = 0
    settingsSend = true
    noComCounter = 0
    deviceController:emit_event(connectionStatus.UDP("Connected"))
    stable_delay()
  end
end

-- Called when changing settings in SmartThings mobile app
local function prefs_update(driver, device, event, args)
  if args.old_st_store.preferences.controllerIP ~= device.preferences.controllerIP then
    controllerIP = device.preferences.controllerIP
  end

  if args.old_st_store.preferences.controllerPort ~= device.preferences.controllerPort then
    controllerPort = tonumber(device.preferences.controllerPort)
  end

  if args.old_st_store.preferences.setupCom ~= device.preferences.setupCom then
    log.info(tostring(device.preferences.setupCom))
  end

  if (device.preferences.setupCom == "START") then
      startUDPCommunication()
  elseif (device.preferences.setupCom == "STOP" and  udp_client ~= nil) then
      log.info("close udp communication")
      --udp_client:close()
      nexmoDriver:cancel_timer(callOnSchedule)
      deviceController:emit_event(connectionStatus.UDP("Unconnected"))
      stable_delay()
      settingsSend = false
  end

  if args.old_st_store.preferences.setDebug ~= device.preferences.setDebug then
    if (device.preferences.setDebug == "START") then
      UDPDebugMode = true
      print("Debug Mode ON")
    elseif (device.preferences.setDebug == "STOP") then
      UDPDebugMode = false
      print("Debug Mode OFF")
    end
  end

  if string.find(tostring(device), "Lidar") then
    print(driver, device, event, args)

    local k, l = string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false)
    local xtalkport = string.sub(device.device_network_id, k+2, l-1)
  
    if args.old_st_store.preferences.RECALFOI ~= device.preferences.RECALFOI then
      if (device.preferences.RECALFOI == "SET") then
        print("ReCALFOI Callded")
        -- Example input string
        local input = device.preferences.DFOI
        -- Table to store extracted coordinates
        local coordinates = {}
        -- Extract coordinates using pattern matching
        for x, y in input:gmatch("%(?%s*([%-+]?%d+)%s*,%s*([%-+]?%d+)%s*%)") do
          if #coordinates < 10 then
            table.insert(coordinates, {x = tonumber(x), y = tonumber(y)})
          else
            break
          end
        end

        -- Output the formatted result
        for i, coord in ipairs(coordinates) do
          -- Format with sing and 3 digits (e.g., +010, -005)
          local x_str = string.format("%+04d", coord.x)
          local y_str = string.format("%+04d", coord.y)
          -- Format and print the output line
          local index = string.format("%02d", i)
          local foi = "X" .. xtalkport .. "B[FOICORNER" .. index .. "=" .. x_str .. "," .. y_str .. "]"
          print(foi)
          udp_client:sendto(foi, controllerIP, controllerPort)
          socket.sleep(0.5)
        end

        local recalfoi = "X" .. xtalkport .. "B[RECALCULATEFOI]"      
        print(recalfoi)
        udp_client:sendto(recalfoi, controllerIP, controllerPort)
        socket.sleep(0.5)
      end
    end

    if args.old_st_store.preferences.SETAZ ~= device.preferences.SETAZ then
      if (device.preferences.SETAZ == "SET") then
        print("setAZ Callded")

        -- Example input string
        local input = device.preferences.DAZ
        -- Table to store parsed data
        local data_list = {}

        -- Extract up to 24 sets of (x, y, a, b)
        for x, y, a, b in input:gmatch("%(?%s*([%-+]?%d+)%s*,%s*([%-+]?%d+)%s*,%s*([%-+]?%d+)%s*,%s*([%-+]?%d+)%s*%)") do
          if #data_list < 24 then
            table.insert(data_list, {
              x = tonumber(x),
              y = tonumber(y),
              a = tonumber(a),
              b = tonumber(b)
            })
          else
            break
          end
        end

        -- Format each entry
        for i, item in ipairs(data_list) do
          local x_str = string.format("%+04d", item.x)
          local y_str = string.format("%+04d", item.y)          
          local a_str = string.format("%03d", item.a)
          local b_str = string.format("%03d", item.b)          
          local index = string.format("%02d", i)
          local activezone = "X" .. xtalkport .. "B[ZONE" .. index .. "=" .. x_str .. "," .. y_str .. "," .. a_str .. "," .. b_str .. "]"
          print(activezone)
          udp_client:sendto(activezone, controllerIP, controllerPort)
          socket.sleep(0.5)
        end
      end
    end
  end
end

local function initializeNFC(xtalkport)
  deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereUID.UID("-", {state_change = true})) 
  stable_delay()
  deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereTagNumber.number(0, {state_change = true}))
  stable_delay()
  deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel1.text("-", {state_change = true})) 
  stable_delay()
  deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel2.text("-", {state_change = true})) 
  stable_delay()
  deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel3.text("-", {state_change = true})) 
  stable_delay()
  deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("-", {state_change = true})) 
  stable_delay()
end

-- Interval loop for reading broadcasted messages
function handle_udp_read_loop()
  log.info("Start UDP read loop")

  while true do
    if consecutiveMessageCounter == 10 then 
        consecutiveMessageCounter = 0
        break
    end
    local data, dataIP, dataPort = udp_client:receivefrom()
    local xtalkport
    log.info(data)

    -- To simulate the sensor value when no sensor is connected.
    -- Always connected.
    log.info("UDP Debug Mode = " .. tostring(UDPDebugMode))
    if UDPDebugMode == true then
      checkIfControllerAlive = true
      noResponseCounter = 0
      noComCounter = 0
    end

-- check X-talk address of data, so that events can be send to the correct device
    if data ~= nil and string.find(data, "X(.-)%[", 0, false) then
      local i, j = string.find(data, "X(.-)%[", 0, false)
      xtalkport = string.sub(data, i+1, j-2)
      if i+1 == j-1 then -- in case no X-talk address X00x but instead XR (RFID sensor)
        xtalkport = "XR" 
      end
      log.info("Incoming data from xtalk port " ..xtalkport.. " belonging to device " ..tostring(deviceForPort[xtalkport]))
      consecutiveMessageCounter = consecutiveMessageCounter + 1
      noComCounter = 0
    end

 -- Data coming from device that has not yet been created.
    if data ~= nil and xtalkport ~= nil and xtalkport ~= "XR" and deviceForPort[xtalkport] == nil then 
      log.info("Incoming data from a sensor for which no device has been created (yet)")

 -- Presence sensor
    -- Distance in zones
    elseif data ~= nil and string.find(data, "Dz=") then
      local i, j = string.find(data, "Dz=")
      local sensorValue = string.sub(data, j+1, j+2)
      deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereDistanceZone.distanceZone(sensorValue))
      stable_delay()
      if sensorValue == "AB" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("0-10 cm, zone AB")) -- Summary for Presence sensor
      elseif sensorValue == "01" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("11-25 cm, zone 01")) -- Summary for Presence sensor
      elseif sensorValue == "02" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("25-50 cm, zone 02")) -- Summary for Presence sensor
      elseif sensorValue == "03" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("50-75 cm, zone 03")) -- Summary for Presence sensor
      elseif sensorValue == "04" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("75-100 cm, zone 04")) -- Summary for Presence sensor
      elseif sensorValue == "05" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("100-125 cm, zone 05")) -- Summary for Presence sensor
      elseif sensorValue == "06" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("125-150 cm, zone 06")) -- Summary for Presence sensor
      elseif sensorValue == "07" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("150-175 cm, zone 07")) -- Summary for Presence sensor
      elseif sensorValue == "08" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("175-200 cm, zone 08")) -- Summary for Presence sensor
      elseif sensorValue == "09" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("200-225 cm, zone 09")) -- Summary for Presence sensor
      elseif sensorValue == "10" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("225-250 cm, zone 10")) -- Summary for Presence sensor
      elseif sensorValue == "XX" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("Out of range, zone XX")) -- Summary for Presence sensor
      end
      stable_delay()

    -- Distance in absolute values
    elseif data ~= nil and string.find(data, "Dv=") then
      local i, j = string.find(data, "Dv=")
      local sensorValue = string.sub(data, j+1, j+3)
      local sensorValueNumber = tonumber(sensorValue)

      if sensorValue == "XXX" then
        deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereAbsoluteDistance.absoluteDistance(251))
        stable_delay()
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("Out of range, zone XX")) -- Summary for Presence sensor
      else
        deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereAbsoluteDistance.absoluteDistance(tonumber(sensorValue)))
        stable_delay()

        if sensorValueNumber >= 0 and sensorValueNumber <= 10 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone AB")) 
        elseif sensorValueNumber >= 11 and sensorValueNumber <= 25 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 01")) 
        elseif sensorValueNumber >= 26 and sensorValueNumber <= 50 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 02"))
        elseif sensorValueNumber >= 51 and sensorValueNumber <= 75 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 03")) 
        elseif sensorValueNumber >= 76 and sensorValueNumber <= 100 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 04"))
        elseif sensorValueNumber >= 101 and sensorValueNumber <= 125 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 05")) 
        elseif sensorValueNumber >= 126 and sensorValueNumber <= 150 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 06")) 
        elseif sensorValueNumber >= 151 and sensorValueNumber <= 175 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 07")) 
        elseif sensorValueNumber >= 176 and sensorValueNumber <= 200 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 08")) 
        elseif sensorValueNumber >= 201 and sensorValueNumber <= 225 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 09")) 
        elseif sensorValueNumber >= 226 and sensorValueNumber <= 250 then
          deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." cm, zone 10")) 
        end
        stable_delay()
      end

 -- RFID sensor

    -- Tag Lifted
    elseif data ~= nil and string.find(data, "PU") then
      local i, j = string.find(data, "PU")
      local sensorValue = string.sub(data, j+1, j+3)

      -- In case of multiple RFID sensors, these sensors will act as 1 sensor.
      -- This means all RFID sensors get updated in case a tag is lifted or placed.
      -- IMPROVE: try to implement mechanism that RFID sensors can work as separate units
      for i = 1, 8 do
        local xtalkportRFID = tostring("00" ..i)
        if string.find(tostring(deviceForPort[xtalkportRFID]), "RFID") then
          deviceForPort[xtalkportRFID]:emit_event(genericSensorNexmosphereNumberAndStatus.number(tonumber(sensorValue)))
          stable_delay()
          deviceForPort[xtalkportRFID]:emit_event(genericSensorNexmosphereNumberAndStatus.status("lifted"))
          stable_delay()
        end
      end

    -- Tag Placed
    elseif data ~= nil and string.find(data, "PB") then
      local i, j = string.find(data, "PB")
      local sensorValue = string.sub(data, j+1, j+3)

      -- In case of multiple RFID sensors, these sensors will act as 1 sensor.
      -- This means all RFID sensors get updated in case a tag is lifted or placed.
      -- IMPROVE: try to implement mechanism that RFID sensors can work as separate units
        
      for i = 1, 8 do
        local xtalkportRFID = tostring("00" ..i)
        if string.find(tostring(deviceForPort[xtalkportRFID]), "RFID") then
          deviceForPort[xtalkportRFID]:emit_event(genericSensorNexmosphereNumberAndStatus.number(tonumber(sensorValue)))
          stable_delay()
          deviceForPort[xtalkportRFID]:emit_event(genericSensorNexmosphereNumberAndStatus.status("placed"))
          stable_delay()
        end
      end
  -- Ambient light sensor

    -- Lux Value
    elseif data ~= nil and string.find(data, "Av=") then
      local i, j = string.find(data, "Av=")
      local sensorValue = string.sub(data, j+1, j+6)
      local sensorValueNumber = tonumber(sensorValue)
      deviceForPort[xtalkport]:emit_event(ambientLightSensorNexmosphereLuxValue.luxValue(tonumber(sensorValue)))
      stable_delay()
      if sensorValueNumber >= 0 and sensorValueNumber <= 1 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 1"))
      elseif sensorValueNumber >= 2 and sensorValueNumber <= 50 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 2"))
      elseif sensorValueNumber >= 51 and sensorValueNumber <= 250 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 3"))
      elseif sensorValueNumber >= 251 and sensorValueNumber <= 1000 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 4")) 
      elseif sensorValueNumber >= 1000 and sensorValueNumber <= 5000 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 5")) 
      elseif sensorValueNumber >= 5000 and sensorValueNumber <= 15000 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 6")) 
      elseif sensorValueNumber >= 15000 and sensorValueNumber <= 40000 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 7")) 
      elseif sensorValueNumber >= 40000 and sensorValueNumber <= 80000 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 8")) 
      elseif sensorValueNumber >= 80000 and sensorValueNumber <= 120000 then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("".. sensorValue .." lux, range 9")) 
      end
      stable_delay()

    -- Lux Range
    elseif data ~= nil and string.find(data, "Ar=") then
      local i, j = string.find(data, "Ar=")
      local sensorValue = string.sub(data, j+1, j+1)
      deviceForPort[xtalkport]:emit_event(ambientLightSensorNexmosphereLuxRange.luxRange(tonumber(sensorValue)))
      stable_delay()
      if sensorValue == "1" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("0-1 lux, range 1"))
      elseif sensorValue == "2" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("1-50 lux, range 2"))
      elseif sensorValue == "3" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("50-250 lux, range 3"))
      elseif sensorValue == "4" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("250-1K lux, range 4")) 
      elseif sensorValue == "5" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("1K-5K lux, range 5")) 
      elseif sensorValue == "6" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("5K-15K lux, range 6")) 
      elseif sensorValue == "7" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("15K-40K lux, range 7")) 
      elseif sensorValue == "8" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("50K-80K lux, range 8")) 
      elseif sensorValue == "9" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text("80K-120K lux, range 9")) 
      end
      stable_delay()
  -- Temperature and Humidity sensor

    -- Temperature measurement
    elseif data ~= nil and string.find(data, "Tv=") then
      local i, j = string.find(data, "Tv=")
      local rawSensorValue = string.sub(data, j+1, j+5)
      local sensorValue = rawSensorValue:gsub( ",", ".")
      deviceForPort[xtalkport]:emit_event(tempHumiSensorNexmosphereTemperatureMeasurement.temperature({value = tonumber(sensorValue), unit = "C"}))
      stable_delay()
 
    -- Humidity Measurement
    elseif data ~= nil and string.find(data, "Hv=") then
      local i, j = string.find(data, "Hv=")
      local sensorValue = string.sub(data, j+1, j+2)
      deviceForPort[xtalkport]:emit_event(tempHumiSensorNexmosphereHumidityMeasurement.humidity({value = tonumber(sensorValue), unit = "%"}))
      stable_delay()
          

  -- NFC Reader

    -- UID
    elseif data ~= nil and string.find(data, "TD=UID:") then
      local i, j = string.find(data, "TD=UID:")
      local sensorValue = string.sub(data, j+1, j+14)
      print(data)
      deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereUID.UID(sensorValue))
      stable_delay()
      nfcUID = sensorValue

    -- Tag number
    elseif data ~= nil and string.find(data, "TD=TNR:") then
      local i, j = string.find(data, "TD=TNR:")
      local sensorValue = string.sub(data, j+1, j+5)
      deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereTagNumber.number(tonumber(sensorValue)))
      stable_delay()
      nfcNumber = sensorValue


    -- Text label 1
    elseif data ~= nil and string.find(data, "TD=LB1:") then
      local i, j = string.find(data, "TD=LB1:")
      local k, l = string.find(data, "]")
      local sensorValue = string.sub(data, j+1, k-1)
      if j+1 == k then
        sensorValue = "<empty>"
      end
      deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel1.text(sensorValue))
      stable_delay()
      nfcLabel1 = sensorValue


    -- Text label 2
    elseif data ~= nil and string.find(data, "TD=LB2:") then
      local i, j = string.find(data, "TD=LB2:")
      local k, l = string.find(data, "]")
      local sensorValue = string.sub(data, j+1, k-1)
      if j+1 == k then
        sensorValue = "<empty>"
      end
      deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel2.text(sensorValue))
      stable_delay()
      nfcLabel2 = sensorValue


    -- Text label 3
    elseif data ~= nil and string.find(data, "TD=LB3:") then
      local i, j = string.find(data, "TD=LB3:")
      local k, l = string.find(data, "]")
      local sensorValue = string.sub(data, j+1, k-1)
      if j+1 == k then
        sensorValue = "<empty>"
      end
      deviceForPort[xtalkport]:emit_event(nfcReaderNexmosphereLabel3.text(sensorValue))
      stable_delay()
      nfcLabel3 = sensorValue

    -- update Summary on tag removal
    elseif data ~= nil and string.find(data, "TR=") then
      initializeNFC(xtalkport)



 -- Lidar sensor
      -- Zone enter
    elseif data ~= nil and string.find(data, "ENTER") then
      local i, j = string.find(data, "ZONE")
      local sensorValue = string.sub(data, j+1, j+2)
      deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.number(tonumber(sensorValue)))
      stable_delay()
      deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.status("enter"))
      stable_delay()

    -- Zone exit
    elseif data ~= nil and string.find(data, "EXIT") then
      local i, j = string.find(data, "ZONE")
      local sensorValue = string.sub(data, j+1, j+2)
      deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.number(tonumber(sensorValue)))
      stable_delay()
      deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereNumberAndStatus.status("exit"))
      stable_delay()


    -- Check if controller alive at startup
    elseif data == nil and settingsSend == false then
      udp_client:sendto("N000B[IDENTIFY=ALL]", controllerIP, controllerPort)
      log.info("Identifying Nexmosphere UDP controllers...")
      break

    -- Check if controller alive at startup
    elseif data == nil and checkIfControllerAlive == true then
      udp_client:sendto("N000B[MAC?]", controllerIP, controllerPort)
      log.info("Checking if controller is still alive...")
      noResponseCounter = noResponseCounter + 1

      if noResponseCounter > 2 then
        settingsSend = false
        checkIfControllerAlive = false
        noResponseCounter = 0
        deviceController:emit_event(connectionStatus.UDP("Connection lost. Trying to reconnect..."))
        stable_delay()
      end
      break

    elseif data ~= nil and string.find(data, "MAC") then
      checkIfControllerAlive = false
      noResponseCounter = 0
      noComCounter = 0
      log.info("Controller connection verified")

    -- Send sensor settings once at startup
    elseif data ~= nil and string.find(data, "N000B[IP=", 1, true) then
      log.info("*** UDP Controller Identified ***")
      log.info("Sending sensor settings in case:")
      log.info("- sensors were added before UDP connection was alive")
      log.info("- the Nexmosphere controller repowered")

      deviceController:emit_event(connectionStatus.UDP("Initiating settings"))
      stable_delay()

      for i = 1, 8 do

        local xtalkportSet = tostring("00" ..i)

        if string.find(tostring(deviceForPort[xtalkportSet]), "Presence") then
          udp_client:sendto("X" .. xtalkportSet .. "S[4:"..storedSettingPresenceMode[xtalkportSet].."]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[4:"..storedSettingPresenceMode[xtalkportSet].."] setting send to UDP controller")
          socket.sleep(0.5)
          udp_client:sendto("X" .. xtalkportSet .. "S[5:"..storedSettingPresenceChangeForTrigger[xtalkportSet].."]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[5:"..storedSettingPresenceChangeForTrigger[xtalkportSet].."] setting send to UDP controller")
          socket.sleep(0.5)
          udp_client:sendto("X" .. xtalkportSet .. "S[6:"..storedSettingPresenceRangeOfInterest[xtalkportSet].."]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[6:"..storedSettingPresenceRangeOfInterest[xtalkportSet].."] setting send to UDP controller")
          socket.sleep(0.5)
          if storedSettingPresenceMode[xtalkportSet] == "1" then
            udp_client:sendto("X" .. xtalkportSet .. "B[ZONE?]", controllerIP, controllerPort)
            log.info("X" .. xtalkportSet .. "B[ZONE?] request send to UDP controller")
            socket.sleep(0.5)
           elseif storedSettingPresenceMode[xtalkportSet] == "2" then
            udp_client:sendto("X" .. xtalkportSet .. "B[DIST?]", controllerIP, controllerPort)
            log.info("X" .. xtalkportSet .. "B[DIST?] request send to UDP controller")
            socket.sleep(0.5)

          end
        elseif string.find(tostring(deviceForPort[xtalkportSet]), "Ambient") then
          udp_client:sendto("X" .. xtalkportSet .. "S[4:"..storedSettingAmbientMode[xtalkportSet].."]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[4:"..storedSettingAmbientMode[xtalkportSet].."] setting send to UDP controller")
          socket.sleep(0.5)
          udp_client:sendto("X" .. xtalkportSet .. "S[5:"..storedSettingAmbientChangeForTrigger[xtalkportSet].."]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[5:"..storedSettingAmbientChangeForTrigger[xtalkportSet].."] setting send to UDP controller")
          socket.sleep(0.5)
          if storedSettingAmbientMode[xtalkportSet] == "2" then
            udp_client:sendto("X" .. xtalkportSet .. "B[LUX?]", controllerIP, controllerPort)
            log.info("X" .. xtalkportSet .. "B[LUX?] request send to UDP controller")
            socket.sleep(0.5)
          end
        elseif string.find(tostring(deviceForPort[xtalkportSet]), "Temperature") then
          udp_client:sendto("X" .. xtalkportSet .. "S[4:3]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[4:3] setting send to UDP controller")
          socket.sleep(0.5)
          udp_client:sendto("X" .. xtalkportSet .. "S[5:3]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[5:3] setting send to UDP controller")
          socket.sleep(0.5)
          udp_client:sendto("X" .. xtalkportSet .. "B[TEMP?]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "B[TEMP?] request send to UDP controller")
          socket.sleep(0.5)
          udp_client:sendto("X" .. xtalkportSet .. "B[HUMI?]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "B[HUMI?] request send to UDP controller")
          socket.sleep(0.5)
        elseif string.find(tostring(deviceForPort[xtalkportSet]), "NFC") then
          udp_client:sendto("X" .. xtalkportSet .. "S[10:" .. storedSettingNFCMode[xtalkportSet] .."]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[10:" .. storedSettingNFCMode[xtalkportSet] .."] setting send to UDP controller")
          socket.sleep(0.5)
          udp_client:sendto("X" .. xtalkportSet .. "S[19:2]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[19:2] setting send to UDP controller")
          socket.sleep(0.5)
        elseif string.find(tostring(deviceForPort[xtalkportSet]), "Lidar") then
          udp_client:sendto("X" .. xtalkportSet .. "S[4:1]", controllerIP, controllerPort)
          log.info("X" .. xtalkportSet .. "S[4:1] setting send to UDP controller")
          socket.sleep(0.5)
        end
      end
      settingsSend = true
      noComCounter = 0
      deviceController:emit_event(connectionStatus.UDP("Connected"))
      stable_delay()

    else
      consecutiveMessageCounter = 0

      if settingsSend == true and noComCounter >= 5 and checkIfControllerAlive == false then
        checkIfControllerAlive = true
      else
        noComCounter = noComCounter + 1
      end
      break
    end

    --NFC Summary
    if data ~= nil and xtalkport ~= nil and string.find(data, "TD=") then
      local settingsValue = deviceForPort[xtalkport]:get_latest_state("main", genericSensorNexmosphereOutputMode.ID, "mode", "no value", "no value")
      if settingsValue == "UID" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text(nfcUID)) 
      elseif settingsValue == "Number" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text(nfcNumber)) 
      elseif settingsValue == "Label 1" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text(nfcLabel1)) 
      elseif settingsValue == "Label 2" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text(nfcLabel2)) 
      elseif settingsValue == "Label 3" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text(nfcLabel3)) 
      elseif settingsValue == "UID, Number and Label 1" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text(nfcUID.." / "..nfcNumber.." / "..nfcLabel1)) 
      elseif settingsValue == "Label 1, 2 and 3" then
        deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereSummary.text(nfcLabel1.." / "..nfcLabel2.." / "..nfcLabel3)) 
      end
      stable_delay()
    end
  end
end



local cap2xtalk = {
  [xtalk["001"].ID] = "001",
  [xtalk["002"].ID] = "002",
  [xtalk["003"].ID] = "003",
  [xtalk["004"].ID] = "004",
  [xtalk["005"].ID] = "005",
  [xtalk["006"].ID] = "006",
  [xtalk["007"].ID] = "007",
  [xtalk["008"].ID] = "008",

}


function handler_xtalk(driver, device, command)
  log.info("handler_xtalk")
  log.debug(command)

  local newdevice = command.args.device
  device:emit_event(capabilities[command.capability].device(newdevice, {state_change = true}))
  stable_delay()

  local xtalk
  xtalk = cap2xtalk[command.capability]

  if newdevice == "Presence" then
    local metadata_Presence = {
      type = "LAN",
      device_network_id = controllerLabel .."[" .. xtalk .. "] NEX_XY241",
      label = controllerLabel .."[" .. xtalk .. "]" .. " Presence sensor",
      profile = "XY200SERIES.v5",
      manufacturer = "Nexmosphere",
      model = "v1",
      vendor_provided_label = nil
    }
    driver:try_create_device(metadata_Presence)

  elseif newdevice == "RFID" then
    local metadata_rfid = {
      type = "LAN",
      device_network_id = controllerLabel .."[" .. xtalk .. "] NEX_XRDR1",
      label = controllerLabel .."[" .. xtalk .. "]" .. " RFID sensor",
      profile = "XRDR1.v4",
      manufacturer = "Nexmosphere",
      model = "v1",
      vendor_provided_label = nil
    }
    driver:try_create_device(metadata_rfid)


  elseif newdevice == "Ambient light" then
    local metadata_ambientlight = {
      type = "LAN",
      device_network_id = controllerLabel .."[" .. xtalk .. "] NEX_XEA20",
      label = controllerLabel .."[" .. xtalk .. "] Ambient light sensor",
      profile = "XEA20.v4",
      manufacturer = "Nexmosphere",
      model = "v1",
      vendor_provided_label = nil
  }
  driver:try_create_device(metadata_ambientlight)

  elseif newdevice == "Temperature" then
    local metadata_temphumi = {
      type = "LAN",
      device_network_id = controllerLabel .."[" .. xtalk .. "] NEX_XET50",
      label = controllerLabel .."[" .. xtalk .. "] Temperature sensor",
      profile = "XET50.v4",
      manufacturer = "Nexmosphere",
      model = "v1",
      vendor_provided_label = nil
  }
  driver:try_create_device(metadata_temphumi)

  elseif newdevice == "NFC" then
    local metadata_nfc = {
      type = "LAN",
      device_network_id = controllerLabel .. "[" .. xtalk .. "] NEX_XRDR2",
      label = controllerLabel .. "[" .. xtalk .. "] NFC Reader",
      profile = "XRDR2.v4",
      manufacturer = "Nexmosphere",
      model = "v1",
      vendor_provided_label = nil
  }
  driver:try_create_device(metadata_nfc)


  elseif newdevice == "Lidar" then
    local metadata_lidar = {
    type = "LAN",
    device_network_id = controllerLabel .."[" .. xtalk .. "]" .. "NEX_XQL2",
    label = controllerLabel .."[" .. xtalk .. "]" .. " Lidar sensor",
    profile = "XQL2.v6",
    manufacturer = "Nexmosphere",
    model = "v1",
    vendor_provided_label = nil
  }
  driver:try_create_device(metadata_lidar)


  elseif newdevice == "None" then
    if deviceForPort[xtalk] ~= nil then
      log.info("trying to delete device " ..deviceForPort[xtalk].id)
      driver:try_delete_device(deviceForPort[xtalk].id)
    end
  end
end

function set_Mode_handler(driver, device, command)
  log.debug("set_Mode_handler")

  local k, l = string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false)
  local xtalkport = string.sub(device.device_network_id, k+2, l-1)

--Presence sensor
  if command.args.mode == "Distance zones" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Distance zones", {state_change = true}))
    stable_delay()
    udp_client:sendto("X" .. xtalkport .. "S[4:1]", controllerIP, controllerPort)
    storedSettingPresenceMode[xtalkport] = "1"
  end

  if  command.args.mode == "Absolute distance" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Absolute distance", {state_change = true}))
    stable_delay()
    udp_client:sendto("X" .. xtalkport .. "S[4:2]", controllerIP, controllerPort)
    storedSettingPresenceMode[xtalkport] = "2"
  end

--Ambient light sensor
  if command.args.mode == "Lux value" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Lux value", {state_change = true}))
    stable_delay()
    udp_client:sendto("X" .. xtalkport .. "S[4:2]", controllerIP, controllerPort)
    storedSettingAmbientMode[xtalkport] = "2"
  end

  if  command.args.mode == "Lux range" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Lux range", {state_change = true}))
    stable_delay()
    udp_client:sendto("X" .. xtalkport .. "S[4:1]", controllerIP, controllerPort)
    storedSettingAmbientMode[xtalkport] = "1"
  end

--NFC Reader
  if  command.args.mode == "UID" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("UID", {state_change = true}))
    stable_delay()
    initializeNFC(xtalkport)
    udp_client:sendto("X" .. xtalkport .. "S[10:1]", controllerIP, controllerPort)
    storedSettingNFCMode[xtalkport] = "1"
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[UID?]", controllerIP, controllerPort)
  end

  if  command.args.mode == "Number" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Number", {state_change = true}))
    stable_delay()
    initializeNFC(xtalkport)
    udp_client:sendto("X" .. xtalkport .. "S[10:2]", controllerIP, controllerPort)
    storedSettingNFCMode[xtalkport] = "2"
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[TNR?]", controllerIP, controllerPort)
  end

  if  command.args.mode == "Label 1" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Label 1", {state_change = true}))
    stable_delay()
    initializeNFC(xtalkport)
    udp_client:sendto("X" .. xtalkport .. "S[10:3]", controllerIP, controllerPort)
    storedSettingNFCMode[xtalkport] = "3"
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[LB1?]", controllerIP, controllerPort)
  end

  if  command.args.mode == "Label 2" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Label 2", {state_change = true}))
    stable_delay()
    initializeNFC(xtalkport)
    udp_client:sendto("X" .. xtalkport .. "S[10:4]", controllerIP, controllerPort)
    storedSettingNFCMode[xtalkport] = "4"
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[LB2?]", controllerIP, controllerPort)
  end

  if  command.args.mode == "Label 3" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Label 3", {state_change = true}))
    stable_delay()
    initializeNFC(xtalkport)
    initializeNFC(xtalkport)
    udp_client:sendto("X" .. xtalkport .. "S[10:5]", controllerIP, controllerPort)
    storedSettingNFCMode[xtalkport] = "5"
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[LB3?]", controllerIP, controllerPort)
  end

  if  command.args.mode == "UID, Number and Label 1" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("UID, Number and Label 1", {state_change = true}))
    stable_delay()
    initializeNFC(xtalkport)
    udp_client:sendto("X" .. xtalkport .. "S[10:6]", controllerIP, controllerPort)
    storedSettingNFCMode[xtalkport] = "6"
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[UID?]", controllerIP, controllerPort)
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[TNR?]", controllerIP, controllerPort)
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[LB1?]", controllerIP, controllerPort)
  end

  if  command.args.mode == "Label 1, 2 and 3" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Label 1, 2 and 3", {state_change = true}))
    stable_delay()
    initializeNFC(xtalkport)
    udp_client:sendto("X" .. xtalkport .. "S[10:7]", controllerIP, controllerPort)
    storedSettingNFCMode[xtalkport] = "7"
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[LB1?]", controllerIP, controllerPort)
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[LB2?]", controllerIP, controllerPort)
    socket.sleep(0.5)
    udp_client:sendto("X" .. xtalkport .. "B[LB3?]", controllerIP, controllerPort)
  end

  --Lidar sensor
  if  command.args.mode == "Single Detection" then
    stable_delay()
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Single Detection", {state_change = true}))
    udp_client:sendto("X" .. xtalkport .. "S[4:1]", controllerIP, controllerPort)
  end

  if  command.args.mode == "Multi Detection" then
    deviceForPort[xtalkport]:emit_event(genericSensorNexmosphereOutputMode.mode("Multi Detection", {state_change = true}))
    stable_delay()
    udp_client:sendto("X" .. xtalkport .. "S[4:2]", controllerIP, controllerPort)
  end

end


function set_Change_handler_presence(driver, device, command)
  log.debug("set_Change_handler_presence")

  local k, l = string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false)
  local xtalkport = string.sub(device.device_network_id, k+2, l-1)

  --Presence sensor
  local settingValue = command.args.change
  deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereChangeForTrigger.change({value = tonumber(settingValue), unit = "cm"}))
  stable_delay()
  udp_client:sendto("X" .. xtalkport .. "S[5:".. settingValue .."]", controllerIP, controllerPort)
  log.info("X" .. xtalkport .. "S[5:".. settingValue .."] setting send to UDP controller")
  storedSettingPresenceChangeForTrigger[xtalkport] = settingValue
end


function set_Change_handler_ambient(driver, device, command)
  log.debug("set_Change_handler_ambient")

  local k, l = string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false)
  local xtalkport = string.sub(device.device_network_id, k+2, l-1)

  --Ambient light sensor
  local settingValue = command.args.change
  deviceForPort[xtalkport]:emit_event(ambientLightSensorNexmosphereChangeForTrigger.change({value = tonumber(settingValue), unit = "%"}))
  stable_delay()
  udp_client:sendto("X" .. xtalkport .. "S[5:".. settingValue .."]", controllerIP, controllerPort)
  log.info("X" .. xtalkport .. "S[5:".. settingValue .."] setting send to UDP controller")
  storedSettingAmbientChangeForTrigger[xtalkport] = settingValue
end



function set_Range_handler_presence(driver, device, command)
  log.debug("set_Range_handler_presence")

  local k, l = string.find(device.device_network_id, controllerLabel .."%[(.-)%]", 0, false)
  local xtalkport = string.sub(device.device_network_id, k+2, l-1)

  local rawSettingValue = command.args.range
  local i, j = string.find(rawSettingValue, "0")
  local settingValue = string.sub(rawSettingValue, 0, i-1)
  deviceForPort[xtalkport]:emit_event(presenceSensorNexmosphereRangeOfInterest.range(tonumber(rawSettingValue)))
  stable_delay()
  udp_client:sendto("X" .. xtalkport .. "S[6:".. settingValue .."]", controllerIP, controllerPort)
  log.info("X" .. xtalkport .. "S[6:".. settingValue .."] setting send to UDP controller")
  storedSettingPresenceRangeOfInterest[xtalkport] = settingValue
end


function refresh_handler(driver, device, command)
  log.debug("refresh_handler")
  initiateSensors(driver, device)
end


-- create the driver object
nexmoDriver = Driver("NexmoSensors", {
  discovery = discovery.handle_discovery,
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    removed = device_removed,
    infoChanged = prefs_update
  },
  capability_handlers = {
    [xtalk["001"].ID] = {
      [xtalk["001"].commands.setDevice.NAME] = handler_xtalk
    },
    [xtalk["002"].ID] = {
      [xtalk["002"].commands.setDevice.NAME] = handler_xtalk
    },
    [xtalk["003"].ID] = {
      [xtalk["003"].commands.setDevice.NAME] = handler_xtalk
    },
    [xtalk["004"].ID] = {
      [xtalk["004"].commands.setDevice.NAME] = handler_xtalk
    },
    [xtalk["005"].ID] = {
      [xtalk["005"].commands.setDevice.NAME] = handler_xtalk
    },
    [xtalk["006"].ID] = {
      [xtalk["006"].commands.setDevice.NAME] = handler_xtalk
    },
    [xtalk["007"].ID] = {
      [xtalk["007"].commands.setDevice.NAME] = handler_xtalk
    },
    [xtalk["008"].ID] = {
      [xtalk["008"].commands.setDevice.NAME] = handler_xtalk
    },

    [genericSensorNexmosphereOutputMode.ID] = {
      [genericSensorNexmosphereOutputMode.commands.setMode.NAME] = set_Mode_handler
      },
    [presenceSensorNexmosphereChangeForTrigger.ID] = {
      [presenceSensorNexmosphereChangeForTrigger.commands.setChange.NAME] = set_Change_handler_presence
      },
    [ambientLightSensorNexmosphereChangeForTrigger.ID] = {
      [ambientLightSensorNexmosphereChangeForTrigger.commands.setChange.NAME] = set_Change_handler_ambient
      },
    [presenceSensorNexmosphereRangeOfInterest.ID] = {
      [presenceSensorNexmosphereRangeOfInterest.commands.setRange.NAME] = set_Range_handler_presence
      },
    [genericSensorNexmosphereRefresh.ID] = {
      [genericSensorNexmosphereRefresh.commands.refresh.NAME] = refresh_handler
      }
  }
})

-- run the driver
nexmoDriver:run()
