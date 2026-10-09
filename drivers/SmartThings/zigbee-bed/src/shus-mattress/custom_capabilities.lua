-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"

local custom_capabilities = {
    ai_mode = capabilities["stse.aiMode"],
    auto_inflation = capabilities["stse.autoInflation"],
    strong_exp_mode = capabilities["stse.strongExpMode"],
    left_control = capabilities["stse.leftControl"],
    right_control = capabilities["stse.rightControl"],
    yoga = capabilities["stse.yoga"],
    mattressHardness = capabilities["stse.mattressHardness"]
}

return custom_capabilities
