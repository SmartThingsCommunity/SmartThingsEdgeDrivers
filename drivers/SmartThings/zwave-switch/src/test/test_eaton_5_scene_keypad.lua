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
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Indicator = (require "st.zwave.CommandClass.Indicator")({ version=1 })
local t_utils = require "integration_test.utils"
local SceneActivation = (require "st.zwave.CommandClass.SceneActivation")({ version=1 })
local SceneControllerConf = (require "st.zwave.CommandClass.SceneControllerConf")({ version=1 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })

local INDICATOR_SWITCH_STATES = "Indicator_switch_states"

local eaton_scene_switch_endpoint = {
    {
        command_classes = {
            { value = zw.BASIC },
            { value = zw.INDICATOR },
            { value = zw.SCENE_ACTIVATION },
            { value = zw.SCENE_CONTROLLER_CONF },
        }
    }
}

local mock_scene_keypad = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("switch-5-keypad.yml"),
    zwave_endpoints = eaton_scene_switch_endpoint,
    zwave_manufacturer_id = 0x001A, -- aka mfr
    zwave_product_type = 0x574D, -- aka product; aka prod
    zwave_product_id = 0x0000, -- aka model
})

local function test_init()
    test.mock_device.add_test_device(mock_scene_keypad)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
        "Indicator report should be handled: value=0x01 -> 00001",
        function()
            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                Indicator:ReportV1({value=1})
                        )
                    }
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("main",
                            capabilities.switch.switch.on()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch2",
                            capabilities.switch.switch.off()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch3",
                            capabilities.switch.switch.off()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch4",
                            capabilities.switch.switch.off()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch5",
                            capabilities.switch.switch.off()
                    )
            )
        end
)

test.register_coroutine_test(
        "Indicator report should be handled: value=30 -> 11110",
        function()
            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                Indicator:ReportV1({value=30})
                        )
                    }
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("main",
                            capabilities.switch.switch.off()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch2",
                            capabilities.switch.switch.on()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch3",
                            capabilities.switch.switch.on()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch4",
                            capabilities.switch.switch.on()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch5",
                            capabilities.switch.switch.on()
                    )
            )
        end
)

test.register_coroutine_test(
        "Capability cmd, switch (switch3) off, should be handled: value=31 (11111) -> 27 (10111)",
        function()
            test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
            test.socket.zwave:__set_channel_ordering("relaxed")
            test.socket.capability:__set_channel_ordering("relaxed")

            mock_scene_keypad:set_field(INDICATOR_SWITCH_STATES, 31)

            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "switch", component = "switch3", command = "off",  args = {} }
            })

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Set({
                                value=27,
                            })
                    )
            )

        end
)

test.register_coroutine_test(
        "Capability cmds, all switch off, should be handled: value=31 (11111) -> 0 (0000)",
        function()
            mock_scene_keypad:set_field(INDICATOR_SWITCH_STATES, 31)

            -- value=31 (11111) -- switch2 off --> 29 (11101)
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "switch", component = "switch2", command = "off",  args = {} }
            })

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Set({
                                value=29,
                            })
                    )
            )
            test.wait_for_events()

            -- value=29 (11101) -- main off --> 28 (11100)
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "switch", component = "main", command = "off",  args = {} }
            })
            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Set({
                                value=28,
                            })
                    )
            )

            test.wait_for_events()

            -- value=28 (11100) -- switch4 off --> 15 (10100)
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "switch", component = "switch4", command = "off",  args = {} }
            })
            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Set({
                                value=20,
                            })
                    )
            )

            test.wait_for_events()

            -- value=15 (10100) -- switch5 off --> 15 (00100)
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "switch", component = "switch5", command = "off",  args = {} }
            })
            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Set({
                                value=4,
                            })
                    )
            )

            test.wait_for_events()

            -- value=15 (00100) -- switch3 off --> 0 (00000)
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "switch", component = "switch3", command = "off",  args = {} }
            })
            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Set({
                                value=0,
                            })
                    )
            )
        end
)

test.register_coroutine_test(
        "Capability cmd should invoke Indicator:Get after 1 sec timeout",
        function()
            test.timer.__create_and_queue_test_time_advance_timer(0, "oneshot")

            mock_scene_keypad:set_field(INDICATOR_SWITCH_STATES, 0)

            -- value=31 (11111) -- switch2 off --> 29 (11101)
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "switch", component = "switch2", command = "on",  args = {} }
            })

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Set({
                                value=2,
                            })
                    )
            )

            test.mock_time.advance_time(2)

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Get({})
                    )
            )
            test.wait_for_events()

        end
)

test.register_coroutine_test(
        "Indicator report (00100) followed by Capability command (main on)",
        function()
            mock_scene_keypad:set_field(INDICATOR_SWITCH_STATES, 31)

            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                Indicator:ReportV1({value=4})
                        )
                    }
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("main",
                            capabilities.switch.switch.off()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch2",
                            capabilities.switch.switch.off()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch3",
                            capabilities.switch.switch.on()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch4",
                            capabilities.switch.switch.off()
                    )
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch5",
                            capabilities.switch.switch.off()
                    )
            )

            test.wait_for_events()
            -- value=4 (00100) -- switch3 off --> 5 (00101)
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "switch", component = "main", command = "on",  args = {} }
            })

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Set({
                                value=5,
                            })
                    )
            )
        end
)

test.register_coroutine_test(
        "SceneActivation:Set should be handled",
        function()
            mock_scene_keypad:set_field(INDICATOR_SWITCH_STATES, 0)

            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                SceneActivation:Set({ scene_id = 1 })
                        )
                    }
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("main",
                            capabilities.switch.switch.on()
                    )
            )
            test.wait_for_events()
            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                SceneActivation:Set({ scene_id = 5 })
                        )
                    }
            )
            test.socket.capability:__expect_send(
                    mock_scene_keypad:generate_test_message("switch5",
                            capabilities.switch.switch.on()
                    )
            )
            test.wait_for_events()
            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                SceneActivation:Set({ scene_id = 6 })
                        )
                    }
            )

        end
)

test.register_coroutine_test(
        "SceneActivation: Invalid scene ID should be ignored",
        function()
            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                SceneActivation:Set({ scene_id = 6 })
                        )
                    }
            )
        end
)

test.register_coroutine_test(
        "SceneActivationConfReport should be handled. If group_id ~= scene_id then scene_id <- group_id",
        function()
            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                SceneControllerConf:Report({ group_id = 1, scene_id = 2 })
                        )
                    }
            )

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            SceneControllerConf:Set({
                                dimming_duration = 0,
                                group_id=1,
                                scene_id=1
                            })
                    )
            )
            test.wait_for_events()

            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                SceneControllerConf:Report({ group_id = 3, scene_id = 1 })
                        )
                    }
            )

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            SceneControllerConf:Set({
                                dimming_duration = 0,
                                group_id=3,
                                scene_id=3
                            })
                    )
            )
            test.wait_for_events()

            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                SceneControllerConf:Report({ group_id = 1, scene_id = 1 })
                        )
                    }
            )
            -- if group_id and scene_id are same, do nothing.
        end
)

test.register_coroutine_test(
        "BasicSet should be handled. If cmd.value == 0, then get current switch status",
        function()
            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                Basic:Set({ value = 0 })
                        )
                    }
            )

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Get({
                            })
                    )
            )
        end
)

test.register_coroutine_test(
        "BasicSet should be handled. If cmd.value != 0, then do nothing",
        function()
            test.socket.zwave:__queue_receive(
                    {
                        mock_scene_keypad.id,
                        zw_test_utils.zwave_test_build_receive_command(
                                Basic:Set({ value = 1 })
                        )
                    }
            )
            -- driver should do nothing.
        end
)

test.register_coroutine_test(
        "Refresh capability cmd should be handled",
        function()
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "refresh", component = "main", command = "refresh",  args = {} }
            })

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Get({})
                    )
            )
        end
)

test.register_coroutine_test(
        "Refresh capability cmd from sub component should be handled",
        function()
            test.socket.capability:__queue_receive({
                mock_scene_keypad.id,
                { capability = "refresh", component = "switch3", command = "refresh",  args = {} }
            })

            test.socket.zwave:__expect_send(
                    zw_test_utils.zwave_test_build_send_command(
                            mock_scene_keypad,
                            Indicator:Get({})
                    )
            )
        end
)


test.run_registered_tests()
