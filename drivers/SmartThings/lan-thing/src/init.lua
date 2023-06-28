local capabilities = require "st.capabilities"
local Driver = require "st.driver"

--should anything beyond refresh be added?
local lan_thing_template = {
  supported_capabilities = {
    capabilities.refresh,
  },
}

local lan_thing = Driver("lan_thing", lan_thing_template)
lan_thing:run()
