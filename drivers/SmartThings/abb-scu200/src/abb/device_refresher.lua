local log = require("log")
local caps = require('st.capabilities')

-- Local imports
local utils = require("utils")
local config = require("config")
local fields = require('fields')

-- Controller for refreshing device data
local device_refresher = {}

local function refresh_current_sensor(driver, device, values)
    local dni = utils.get_dni_from_device(device)
    log.info("refresh_current_sensor(): Refreshing data of Current Sensor, dni = " .. dni)
    
    -- Refresh Current Measurement
    local current = values.current

    if current ~= nil then
        log.trace("refresh_current_sensor(): Refreshing Current Measurement, dni = " .. dni)
        device.profile.components["main"]:emit_event(caps.currentMeasurement.current({value=current, unit="A"}))
    end

    -- Refresh Active Power
    local activePower = values.activePower

    if activePower ~= nil then
        log.trace("refresh_current_sensor(): Refreshing Active Power, dni = " .. dni)
        device.profile.components["main"]:emit_event(caps.powerMeter.power({value=activePower, unit="W"}))
    end

    -- Refresh Active Energy
    local activeEnergy = values.activeEnergy

    if activeEnergy ~= nil then
        -- Refresh Active Energy
        log.trace("refresh_current_sensor(): Refreshing Active Energy, dni = " .. dni)
        device.profile.components["main"]:emit_event(caps.energyMeter.energy({value=activeEnergy, unit="kWh"}))
    
        -- Verify whether the appropriate time have elapsed to report the energy values
        local last_energy_report = device:get_field(fields.LAST_ENERGY_REPORT) or 0.0

        if (os.time() - last_energy_report) >= config.EDGE_CHILD_ENERGY_REPORT_INTERVAL then  -- Report the energy consumption/production periodically
            local current_consumption_production_report = device:get_latest_state("main", caps.powerConsumptionReport.ID, caps.powerConsumptionReport.powerConsumption.NAME)
        
            -- Calculate delta consumption/production energy
            local delta_consumption_production_report = 0.0
            if current_consumption_production_report ~= nil then
                delta_consumption_production_report = math.max((activeEnergy * 1000) - current_consumption_production_report.energy, 0.0)
            end

            -- Refresh Power Energy Report
            log.trace("refresh_current_sensor(): Refreshing Energy Report, dni = " .. dni)
            device.profile.components["main"]:emit_event(caps.powerConsumptionReport.powerConsumption({energy=activeEnergy * 1000, deltaEnergy=delta_consumption_production_report}))

            -- Save date of the last energy report
            local current_energy_report = last_energy_report + config.EDGE_CHILD_ENERGY_REPORT_INTERVAL
            if (current_energy_report + config.EDGE_CHILD_ENERGY_REPORT_INTERVAL) < os.time() then
                current_energy_report = os.time()
            end

            device:set_field(fields.LAST_ENERGY_REPORT, current_energy_report, {persist=false})
        else
            log.debug("refresh_current_sensor(): " .. config.EDGE_CHILD_ENERGY_REPORT_INTERVAL .. " seconds haven't elapsed yet! Last consumption was at " .. last_energy_report .. ", dni = " .. dni)
        end
    end

    return true
end

local function refresh_energy_meter(driver, device, values)
    local dni = utils.get_dni_from_device(device)
    log.info("refresh_energy_meter(): Refreshing data of Energy Meter, dni = " .. dni)

    -- Refresh Voltage Measurement
    local voltage = values.voltage

    if voltage ~= nil then
        log.trace("refresh_energy_meter(): Refreshing Voltage Measurement, dni = " .. dni)
        device.profile.components["main"]:emit_event(caps.voltageMeasurement.voltage({value=voltage, unit="V"}))
    end

    -- Refresh Current Measurement
    local current = values.current

    if current ~= nil then
        log.trace("refresh_energy_meter(): Refreshing Current Measurement, dni = " .. dni)
        device.profile.components["main"]:emit_event(caps.currentMeasurement.current({value=current, unit="A"}))
    end

    -- Refresh Active Power
    local activePower = values.activePowerTotal

    if activePower ~= nil then
        log.trace("refresh_energy_meter(): Refreshing Active Power, dni = " .. dni)
        device.profile.components["main"]:emit_event(caps.powerMeter.power({value=activePower, unit="W"}))
    end

    -- Refresh Active Energy Net, Import & Export Total
    local activeEnergyNetTotal = values.activeEnergyNetTotal
    local activeEnergyImportTotal = values.activeEnergyImportTotal
    local activeEnergyExportTotal = values.activeEnergyExportTotal

    if activeEnergyNetTotal == nil then
        if activeEnergyImportTotal ~= nil and activeEnergyExportTotal ~= nil then
            -- If only Import and Export Total are available, calculate Net Total
            activeEnergyNetTotal = activeEnergyImportTotal - activeEnergyExportTotal
        end
    end

    local activeEnergyNetPositive = math.max(activeEnergyNetTotal, 0.0)
    local activeEnergyNetNegative = math.min(activeEnergyNetTotal, 0.0) * -1  -- Convert to positive value

    if activeEnergyNetTotal ~= nil and activeEnergyImportTotal ~= nil and activeEnergyExportTotal ~= nil then
        -- Refresh Active Energy Net Positive
        log.trace("refresh_energy_meter(): Refreshing Active Energy Net Positive, dni = " .. dni)
        device.profile.components["main"]:emit_event(caps.energyMeter.energy({value=activeEnergyNetPositive, unit="kWh"}))

        -- Refresh Active Energy Import Total
        log.trace("refresh_energy_meter(): Refreshing Active Energy Import Total, dni = " .. dni)
        device.profile.components["consumptionMeter"]:emit_event(caps.energyMeter.energy({value=activeEnergyImportTotal, unit="kWh"}))
        
        -- Refresh Active Energy Export Total
        log.trace("refresh_energy_meter(): Refreshing Active Energy Export Total, dni = " .. dni)
        device.profile.components["productionMeter"]:emit_event(caps.energyMeter.energy({value=activeEnergyExportTotal, unit="kWh"}))

        -- Refresh Active Energy Net Negative
        log.trace("refresh_energy_meter(): Refreshing Active Energy Net Negative, dni = " .. dni)
        device.profile.components["surplus"]:emit_event(caps.energyMeter.energy({value=activeEnergyNetNegative, unit="kWh"}))
    
        -- Verify whether the appropriate time have elapsed to report the energy net, consumption and production
        local last_energy_report = device:get_field(fields.LAST_ENERGY_REPORT) or 0.0

        if (os.time() - last_energy_report) >= config.EDGE_CHILD_ENERGY_REPORT_INTERVAL then  -- Report the energy net, consumption and production periodically
            local current_net_positive_report = device:get_latest_state("main", caps.powerConsumptionReport.ID, caps.powerConsumptionReport.powerConsumption.NAME)
            local current_consumption_report = device:get_latest_state("consumptionMeter", caps.powerConsumptionReport.ID, caps.powerConsumptionReport.powerConsumption.NAME)
            local current_production_report = device:get_latest_state("productionMeter", caps.powerConsumptionReport.ID, caps.powerConsumptionReport.powerConsumption.NAME)
            local current_net_negative_report = device:get_latest_state("surplus", caps.powerConsumptionReport.ID, caps.powerConsumptionReport.powerConsumption.NAME)

            -- Calculate delta net, consumption and production energy
            local delta_net_positive_report = 0.0
            if current_net_positive_report ~= nil then
                delta_net_positive_report = math.max((activeEnergyNetPositive * 1000) - current_net_positive_report.energy, 0.0)
            end

            local delta_consumption_energy = 0.0
            if current_consumption_report ~= nil then
                delta_consumption_energy = math.max((activeEnergyImportTotal * 1000) - current_consumption_report.energy, 0.0)
            end

            local delta_production_energy = 0.0
            if current_production_report ~= nil then
                delta_production_energy = math.max((activeEnergyExportTotal * 1000) - current_production_report.energy, 0.0)
            end

            local delta_net_negative_report = 0.0
            if current_net_negative_report ~= nil then
                delta_net_negative_report = math.max((activeEnergyNetNegative * 1000) - current_net_negative_report.energy, 0.0)
            end

            -- Refresh Power Net Positive, Consumption, Production & Net Negative Report
            log.trace("refresh_energy_meter(): Refreshing Power Net Positive, Consumption, Production & Net Negative Report, dni = " .. dni)
            device.profile.components["main"]:emit_event(caps.powerConsumptionReport.powerConsumption({energy=activeEnergyNetPositive * 1000, deltaEnergy=delta_net_positive_report}))
            device.profile.components["consumptionMeter"]:emit_event(caps.powerConsumptionReport.powerConsumption({energy=activeEnergyImportTotal * 1000, deltaEnergy=delta_consumption_energy}))
            device.profile.components["productionMeter"]:emit_event(caps.powerConsumptionReport.powerConsumption({energy=activeEnergyExportTotal * 1000, deltaEnergy=delta_production_energy}))
            device.profile.components["surplus"]:emit_event(caps.powerConsumptionReport.powerConsumption({energy=activeEnergyNetNegative * 1000, deltaEnergy=delta_net_negative_report}))

            -- Save date of the last consumption
            local current_energy_report = last_energy_report + config.EDGE_CHILD_ENERGY_REPORT_INTERVAL
            if (current_energy_report + config.EDGE_CHILD_ENERGY_REPORT_INTERVAL) < os.time() then
                current_energy_report = os.time()
            end

            device:set_field(fields.LAST_ENERGY_REPORT, current_energy_report, {persist=false})
        else
            log.debug("refresh_energy_meter(): " .. config.EDGE_CHILD_ENERGY_REPORT_INTERVAL .. " seconds haven't elapsed yet! Last consumption was at " .. last_energy_report .. ", dni = " .. dni)
        end
    end

    return true
end

local function refresh_auxiliary_contact(driver, device, values)
    local dni = utils.get_dni_from_device(device)
    log.info("refresh_auxiliary_contact(): Refreshing data of Auxiliary Contact, dni = " .. dni)

    -- Refresh Contact Sensor
    local isClosed = values.isClosed

    if isClosed ~= nil then
        log.trace("refresh_auxiliary_contact(): Refreshing Switch, dni = " .. dni)

        if isClosed == 1 then
            isClosed = true
        else
            isClosed = false
        end

        if isClosed then
            device:emit_event(caps.switch.switch.on())
        else
            device:emit_event(caps.switch.switch.off())
        end
    end

    return true
end

local function refresh_output_module(driver, device, values)
    local dni = utils.get_dni_from_device(device)
    log.info("refresh_output_module(): Refreshing data of Output Module, dni = " .. dni)

    -- Refresh Switch
    local isClosed = values.isClosed
    log.trace("refresh_output_module(): Refreshing Switch, dni = " .. dni)

    if isClosed == 1 then
        isClosed = true
    else
        isClosed = false
    end

    if isClosed then
        device:emit_event(caps.switch.switch.on())
    else
        device:emit_event(caps.switch.switch.off())
    end

    return true
end

local function refresh_water_meter(driver, device, values)
    local dni = utils.get_dni_from_device(device)
    log.info("refresh_water_meter(): Refreshing data of Water Meter, dni = " .. dni)

    local unit = values.unit
    if unit == nil then
        log.error("refresh_water_meter(): The unit of the water meter is not set, dni = " .. dni)
        return false
    end

    -- Refresh Water Meter: last hour
    local lastHourFlow = values.lastHourFlow

    if lastHourFlow ~= nil then
        log.trace("refresh_water_meter(): Refreshing Water Meter: last hour, dni = " .. dni)
        device:emit_event(caps.waterMeter.lastHour({value=lastHourFlow, unit=unit}))
    end
    
    -- Refresh Water Meter: last 24 hours
    local lastTwentyFourHoursFlow = values.lastTwentyFourHoursFlow

    if lastTwentyFourHoursFlow ~= nil then
        log.trace("refresh_water_meter(): Refreshing Water Meter: last 24 hours, dni = " .. dni)
        device:emit_event(caps.waterMeter.lastTwentyFourHours({value=lastTwentyFourHoursFlow, unit=unit}))
    end

    -- Refresh Water Meter: last 7 days
    local lastSevenDaysFlow = values.lastSevenDaysFlow

    if lastSevenDaysFlow ~= nil then
        log.trace("refresh_water_meter(): Refreshing Water Meter: last 7 days, dni = " .. dni)
        device:emit_event(caps.waterMeter.lastSevenDays({value=lastSevenDaysFlow, unit=unit}))
    end
    
    return true
end

local function refresh_gas_meter(driver, device, values)
    local dni = utils.get_dni_from_device(device)
    log.info("refresh_gas_meter(): Refreshing data of Gas Meter, dni = " .. dni)

    local gasMeterVolumeUnit = values.gasMeterVolumeUnit
    if gasMeterVolumeUnit == nil then
        log.error("refresh_gas_meter(): The unit of the gas meter is not set, dni = " .. dni)
        return false
    end

    -- Correct the unit if necessary
    if gasMeterVolumeUnit == "m3" then
        gasMeterVolumeUnit = "m^3"
    end

    -- Refresh Gas Meter
    local gasMeterVolume = values.gasMeterVolume
    
    if gasMeterVolume ~= nil then
        log.trace("refresh_gas_meter(): Refreshing Gas Meter, dni = " .. dni)
        device:emit_event(caps.gasMeter.gasMeterVolume({value=gasMeterVolume, unit=gasMeterVolumeUnit}))
    end

    return true
end

local function refresh_usb_energy_meter(driver, device, values)
    local dni = utils.get_dni_from_device(device)
    log.info("refresh_usb_energy_meter(): Refreshing data of USB Energy Meter, dni = " .. dni)

    -- Refresh Active Power Import Total
    local activePowerImportTotal = values.activePowerImportTotal

    if activePowerImportTotal ~= nil then
        log.trace("refresh_usb_energy_meter(): Refreshing Active Power Import Total, dni = " .. dni)
        device:emit_event(caps.powerMeter.power({value=activePowerImportTotal, unit="W"}))
    end

    -- Refresh Active Energy Import Total
    local activeEnergyImportTotal = values.activeEnergyImportTotal

    if activeEnergyImportTotal ~= nil then
        log.trace("refresh_usb_energy_meter(): Refreshing Active Energy Import Total, dni = " .. dni)
        device:emit_event(caps.energyMeter.energy({value=activeEnergyImportTotal, unit="kWh"}))

        -- Verify whether the appropriate time have elapsed to report the energy consumption and production
        local last_energy_report = device:get_field(fields.LAST_ENERGY_REPORT) or 0.0

        if (os.time() - last_energy_report) >= config.EDGE_CHILD_ENERGY_REPORT_INTERVAL then  -- Report the energy consumption periodically
            local current_consumption_report = device:get_latest_state("main", caps.powerConsumptionReport.ID, caps.powerConsumptionReport.powerConsumption.NAME)

            -- Calculate delta consumption energy
            local delta_consumption_energy = 0.0
            if current_consumption_report ~= nil then
                delta_consumption_energy = math.max((activeEnergyImportTotal * 1000) - current_consumption_report.energy, 0.0)
            end

            -- Refresh Power Consumption Report
            log.trace("refresh_usb_energy_meter(): Refreshing Power Consumption Report, dni = " .. dni)
            device:emit_event(caps.powerConsumptionReport.powerConsumption({energy=activeEnergyImportTotal * 1000, deltaEnergy=delta_consumption_energy}))

            -- Save date of the last consumption
            local current_energy_report = last_energy_report + config.EDGE_CHILD_ENERGY_REPORT_INTERVAL
            if (current_energy_report + config.EDGE_CHILD_ENERGY_REPORT_INTERVAL) < os.time() then
                current_energy_report = os.time()
            end

            device:set_field(fields.LAST_ENERGY_REPORT, current_energy_report, {persist=false})
        else
            log.debug("refresh_usb_energy_meter(): " .. config.EDGE_CHILD_ENERGY_REPORT_INTERVAL .. " seconds haven't elapsed yet! Last consumption was at " .. last_energy_report .. ", dni = " .. dni)
        end
    end

    return true
end

function device_refresher.refresh_device(driver, device, values)
    local dni, device_type = utils.get_dni_from_device(device)
    log.info("device_refresher.refresh_device(): Refreshing data of device, dni = " .. dni)

    if device_type == fields.DEVICE_TYPE_BRIDGE then
        log.debug("device_refresher.refresh_device(): Cannot refresh bridge device, dni = " .. dni)
        return
    end

    log.debug("device_refresher.refresh_device(): Provided values: " .. utils.dump(values))

    local refresh_methods = {
        [utils.get_thing_exact_type(config.EDGE_CHILD_CURRENT_SENSOR_TYPE)]      = refresh_current_sensor,
        [utils.get_thing_exact_type(config.EDGE_CHILD_ENERGY_METER_MODULE_TYPE)] = refresh_energy_meter,
        [utils.get_thing_exact_type(config.EDGE_CHILD_AUXILIARY_CONTACT_TYPE)]   = refresh_auxiliary_contact,
        [utils.get_thing_exact_type(config.EDGE_CHILD_OUTPUT_MODULE_TYPE)]       = refresh_output_module,
        [utils.get_thing_exact_type(config.EDGE_CHILD_ENERGY_METER_TYPE)]        = refresh_energy_meter,
        [utils.get_thing_exact_type(config.EDGE_CHILD_WATER_METER_TYPE)]         = refresh_water_meter,
        [utils.get_thing_exact_type(config.EDGE_CHILD_GAS_METER_TYPE)]           = refresh_gas_meter,
        [utils.get_thing_exact_type(config.EDGE_CHILD_USB_ENERGY_METER_TYPE)]    = refresh_usb_energy_meter
    }

    local device_model = utils.get_device_model(device)
    if device_model == nil then
        log.error("device_refresher.refresh_device(): No device model found for device, dni = " .. dni)
        return
    end

    local refresh_method = refresh_methods[device_model]
    if refresh_method == nil then
        log.error("device_refresher.refresh_device(): No refresh method found for device, dni = " .. dni .. ", model = " .. device_model)
        return
    end

    return refresh_method(driver, device, values)
end

return device_refresher