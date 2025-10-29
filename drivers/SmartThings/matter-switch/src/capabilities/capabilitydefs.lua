local knob = [[
{
    "id": "adminmirror01019.knob",
    "version": 1,
    "status": "proposed",
    "name": "Knob",
    "ephemeral": false,
    "attributes": {
        "knob": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "integer",
                        "minimum": -100,
                        "maximum": 100
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "enumCommands": []
        }
    },
    "commands": {}
}
]]

statelessSwitchLevelStep = [[
{
    "id": "adminmirror01019.statelessSwitchLevelStep",
    "version": 1,
    "status": "proposed",
    "name": "Stateless Switch Level Step",
    "ephemeral": false,
    "attributes": {},
    "commands": {
        "stepLevel": {
            "name": "stepLevel",
            "arguments": [
                {
                    "name": "stepSize",
                    "optional": false,
                    "schema": {
                        "type": "integer"
                    }
                }
            ],
            "sensitive": false
        }
    }
}
]]

return  {
    knob = knob,
    statelessSwitchLevelStep = statelessSwitchLevelStep
}
