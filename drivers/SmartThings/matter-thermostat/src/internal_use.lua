local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local log = require "log"

-- TemperatureMeasurement and RelativeHumidityMeasurement are clusters included in 
-- Air Quality Sensor that are not included in this bitmap for legacy reasons.
local AIR_QUALITY_BIT_MAP = {
    [capabilities.airQualityHealthConcern.ID]       = {0, {clusters.AirQuality}},
    [capabilities.carbonDioxideMeasurement.ID]      = {1, {clusters.CarbonDioxideConcentrationMeasurement}},
    [capabilities.carbonDioxideHealthConcern.ID]    = {2, {clusters.CarbonDioxideConcentrationMeasurement}},
    [capabilities.carbonMonoxideMeasurement.ID]     = {3, {clusters.CarbonMonoxideConcentrationMeasurement}},
    [capabilities.carbonMonoxideHealthConcern.ID]   = {4, {clusters.CarbonMonoxideConcentrationMeasurement}},
    [capabilities.dustSensor.ID]                    = {5, {clusters.Pm10ConcentrationMeasurement, clusters.Pm25ConcentrationMeasurement}},
    [capabilities.dustHealthConcern.ID]             = {6, {clusters.Pm10ConcentrationMeasurement, clusters.Pm25ConcentrationMeasurement}},
    [capabilities.fineDustSensor.ID]                = {7, {clusters.Pm25ConcentrationMeasurement}},
    [capabilities.fineDustHealthConcern.ID]         = {8, {clusters.Pm25ConcentrationMeasurement}},
    [capabilities.formaldehydeMeasurement.ID]       = {9, {clusters.FormaldehydeConcentrationMeasurement}},
    [capabilities.formaldehydeHealthConcern.ID]     = {10, {clusters.FormaldehydeConcentrationMeasurement}},
    [capabilities.nitrogenDioxideHealthConcern.ID]  = {11, {clusters.NitrogenDioxideConcentrationMeasurement}},
    [capabilities.nitrogenDioxideMeasurement.ID]    = {12, {clusters.NitrogenDioxideConcentrationMeasurement}},
    [capabilities.ozoneHealthConcern.ID]            = {13, {clusters.OzoneConcentrationMeasurement}},
    [capabilities.ozoneMeasurement.ID]              = {14, {clusters.OzoneConcentrationMeasurement}},
    [capabilities.radonHealthConcern.ID]            = {15, {clusters.RadonConcentrationMeasurement}},
    [capabilities.radonMeasurement.ID]              = {16, {clusters.RadonConcentrationMeasurement}},
    [capabilities.tvocHealthConcern.ID]             = {17, {clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement}},
    [capabilities.tvocMeasurement.ID]               = {18, {clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement}},
    [capabilities.veryFineDustHealthConcern.ID]     = {19, {clusters.Pm1ConcentrationMeasurement}},
    [capabilities.veryFineDustSensor.ID]            = {20, {clusters.Pm1ConcentrationMeasurement}},
  }

local function split_by_whitespace(line)
    local tokens = {}
    for token in string.gmatch(line, "%S+") do
        table.insert(tokens, token)
    end
    return tokens
end

local function read_and_process(profile_name)
    local path = "../profiles/"  .. profile_name
    local file = io.open(path, "r")
    if not file then
        error("Could not open file.")
    end

    local bitmap = 0
    for line in file:lines() do
        local tokens = split_by_whitespace(line)
        if (tokens[1] == "-" and tokens[2] == "id:") then
            local cap = AIR_QUALITY_BIT_MAP[tokens[3]]
            -- print(cap)
            if cap then
                bitmap = bitmap | (1 << cap[1])
            end
        end
    end

    file:close()
    local hex_bitmap = string.format("%x", bitmap)
    print(profile_name .. ": " .. hex_bitmap)
    return hex_bitmap
end

local function read_and_process_all_files(path)
    local command = 'ls "' .. path .. '"'
    local listed = io.popen(command)
    if not listed then
        print("Could not open directory: " .. path)
    end
    for file in listed:lines() do
        read_and_process(file)
    end
end

read_and_process_all_files("../profiles")