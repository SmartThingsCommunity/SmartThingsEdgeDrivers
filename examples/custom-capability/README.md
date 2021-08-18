Custom Capability Example
=========================

This shows an example using a custom capability from within a driver.  To get this
working you can follow the information found in the community post and linked docs
[here](https://community.smartthings.com/t/custom-capability-and-cli-developer-preview/197296).
Once you have created a custom capability (in this example we simply created `fancySwitch`
which is essentially the `switch` capability), you can then view the definition of your capability
back as JSON using the CLI command.  Note that for presentation purposes you are no longer using the `--dth`
flag, and instead you should use the profile ID instead of the dth ID.

```shell script
smartthings capabilities [ID] [VERSION] -o=cap.json
```

Once you have the definition in your package you can refer to the capability from the capabilities library.

```lua
local capabilities = require "st.capabilities"
local fancySwitch = capabilities["your_namespace.fancySwitch"]
```

It's important to note here that the syntax `capabilities.your_namespace.fancySwitch` is NOT supported.  The 
combined `your_namespace.fancySwitch` is treated as a singular ID and thus the capabilities table needs
to be indexed by the complete ID.

If you want to register handlers for your capability commands you will have to place an entry in the
capabilities table under the qualified name, so that when the command is received, the driver library
code will be able to properly find and match the capability information.

```lua

...

local driver_template = {
  capability_handlers = {
    [fancySwitch.ID] = {
      [fancySwitch.commands.fancyOn.NAME] = switch_defaults.on,
      [fancySwitch.commands.fancyOff.NAME] = switch_defaults.off,
      [fancySwitch.commands.fancySet.NAME] = fancy_set_handler,
    }
  }
}
```

At this point you should be able to use the capability like any other standard capability.

Testing
-------

Because the definition of your capability will be synced from the cloud when your driver is running on a hub, you
will need to add a local definition that the libraries will be able to access in order for the integration tests to
work as expected. The simplest way to do this is to navigate into your `lua_libs` directory and find
`lua_libs/st/capabilities/generated` then within that directory create a new folder with the name of your
namespace.  Then within that directory create a lua file with a filename of `yourCapabilityId.lua` where the capability
ID does NOT include your namespace.  Then you can add to that file a single return statement and return a string with the
JSON definition of your capability.

 ```lua
 return [[
{
    "id": "your_namespace.fancySwitch",
    "version": 1,
    ...
}
]]
```

Once that is there, your tests should be able to refer to the capability as it would when running on the hub.

This process will be improved in future updates to avoid the need to add to the library files.