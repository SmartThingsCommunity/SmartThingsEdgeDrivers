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



local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local dkjson = require "dkjson"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })


local sensor_endpoints = {
    {
        command_classes = {
            {value = zw.CONFIGURATION}
        }
    }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("motion-switch-color-illuminance-temperature.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x001E,
    zwave_product_type = 0x0004,
    zwave_product_id = 0x0001,
})

local function test_init()
    test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "infoChanged() and doConfigure() should send the SET command for Configuation value",
    function()

        local onTime = math.random(0,127)
        local onLevel = math.random(0,100) - 1
        local liteMin = math.random(0,127)
        local tempMin = math.random(0,127)
        local tempAdj = math.random(1,256) - 128

        test.socket.zwave:__set_channel_ordering("relaxed")

        test.wait_for_events()
        test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed(
            {
                preferences = {
                    onTime = onTime,
                    onLevel = onLevel,
                    liteMin = liteMin,
                    tempMin = tempMin,
                    tempAdj = tempAdj
                }
            }
        ))

        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=1, size=1, configuration_value=onTime})
            )
        )

        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=2, size=1, configuration_value=onLevel})
            )
        )

        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=3, size=1, configuration_value=liteMin})
            )
        )
        
        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=4, size=1, configuration_value=tempMin})
            )
        )

        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=5, size=1, configuration_value=tempAdj})
            )
        )

        test.socket.device_lifecycle():__queue_receive({mock_device.id, "doConfigure"})

        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=1, size=1, configuration_value=onTime})
            )
        )

        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=2, size=1, configuration_value=onLevel})
            )
        )
        
        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=3, size=1, configuration_value=liteMin})
            )
        )
        
        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=4, size=1, configuration_value=tempMin})
            )
        )

        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_device,
                Configuration:Set({parameter_number=5, size=1, configuration_value=tempAdj})
            )
        )
        mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()
