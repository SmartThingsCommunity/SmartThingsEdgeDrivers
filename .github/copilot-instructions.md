 You are working in the SmartThings Edge Drivers repository. Drivers are written in **Lua 5.3** and
 run on SmartThings hubs. They translate Zigbee, Z-Wave, Matter, and LAN protocol messages into
 SmartThings capability commands and events.

 For full context, read `AGENTS.md` at the repository root. It covers driver structure, lifecycle,
 profiles, and available skills for deeper domain knowledge.

 ## Standard Commands

 ```bash
 # Run tests
 python3 tools/run_driver_tests.py -vv -f <driver-name>

 # Lint
 luacheck --config .github/workflows/.luacheckrc <path>

 # Deploy
 smartthings edge:drivers:package <driver-dir> --hub=<hub-uuid> --channel=<channel-id>
```

## Rules

Always:

 - Run tests before considering a change complete
 - Run luacheck on modified Lua files
 - Use existing standard capabilities before creating custom ones
 - Follow existing driver structure patterns

Ask before:

 - Modifying device profile YAML files (changes affect production devices)
 - Adding new custom capabilities
 - Changing config.yml permissions

Never:

 - Commit hardcoded API keys or tokens
 - Skip tests for driver changes
 - Use Lua features beyond 5.3

## Skills

Load these files for deeper knowledge when working in each area:

| Task | Skill file |
|------|-----------|
| Driver lifecycle, dispatch, default handlers       | .agents/skills/understanding-lua-libraries/SKILL.md  |
| Profiles, capabilities, preferences, fingerprints  | .agents/skills/understanding-profiles/SKILL.md       |
| Writing and running tests                          | .agents/skills/testing-edge-drivers/SKILL.md         |
| Luacheck / code style                              | .agents/skills/linting-and-style/SKILL.md            |
| Environment setup, deploying, sharing via channels | .agents/skills/dev-workflow/SKILL.md                 |
