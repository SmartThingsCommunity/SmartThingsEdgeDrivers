# SmartThingsEdgeDrivers

## Documentation

Check out the [SmartThings developer docs](https://developer-preview.smartthings.com/) for a bunch of guides and
reference documentation about SmartThings Edge Drivers.

## Setting up your development environment

### LUA_PATH

When running lua code it is necessary for you have a `LUA_PATH` environment variable that informs your system of where
to find code that can be used via a Lua `require` call.  For any driver it is going to be necessary that you use the
SmartThings Lua libraries to provide the functionality needed to interact with the system and devices.  You should have
a LUA_PATH that looks something like:

```
LUA_PATH=/path/to/lua_libs-api_vX/?.lua;/path/to/lua_libs-api_vX/?/init.lua;./?.lua;./?/init.lua;;
```

This assumes that the `lua_libs-api_vX` folder is the folder included in the API releases. NOTE: this is the internal
folder of this name, not a top level folder you potentially created when unzipping (i.e. it should not include the docs
folder).  This will make all the SmartThings Lua library functionality available under the same paths it will be
available when executing in the SmartThings sandbox, as well as allow any working directory folders and files to be
available (as they will be for files provided in the `src/` directory of your driver).

If you've installed `luasocket` using `luarocks` you will also need to make sure you include the luarocks include
folders in this path. You can do this semi-automatically with `eval $(luarocks path --append)` after configuring the
`LUA_PATH` for the lua_libs folder.

### IDE and Auto-completion

The lua libraries are tagged with EmmyLua comments to describe the types and functions that are
available within the libraries.  These can be very helpful with IDE support to allow for powerful auto-completion and
suggestions.  Setting this up will be IDE specific, but following are a few options:

#### IntelliJ

1) Install the EmmyLua IntelliJ plugin (Not the Lua plugin)
2) Download the API release version [from github](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/releases)
   that you will be developing against
3) Extract the contents into the git repo directory for this project (the 2 extracted folders should be .gitignored by
   default)
4) Navigate to the settings and add the `lua_libs-api_vX` extracted directory as a "Lua Additional Sources Root" under
   the EmmyLua settings

At this point IntelliJ should run an indexing task and the auto-completion and type hints should be available while
developing. However in order to run an individual test file (the only way to "run" your driver outside the context of
the sandbox on a SmartThings hub), you need to set up the run configuration.

1) Open the run configurations in your IDE
2) Create a new Lua Application (or edit an existing one)
3) Set the working directory to `path/to/your-driver/src`
4) Set the entry file to `path/to/your-driver/src/test/test_file.lua`
5) Set an environment variable for the `LUA_PATH` described in this document

From here you should be able to "run" the configuration and see the test output in your IDE.

#### VSCode

1. Install the [Lua Language Server](https://marketplace.visualstudio.com/items?itemName=sumneko.lua) VSCode plugin
1. Download the API release version [from github](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/releases)
   that you will be developing against
1. Extract the contents into the git repo directory for this project (the 2 extracted folders should be .gitignored by
   default)

Alternatively, you can extract the API release to a location of your choice and add the folder path as a Workspace
Library source in the Lua Language Server [settings](https://github.com/sumneko/lua-language-server#setting). **NOTE**:
this is the internal folder, not a top level folder you potentially created when unzipping (i.e. it should not include 
the docs folder).

## Code of Conduct

The code of conduct for SmartThingsEdgeDrivers can be found in
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## How to Contribute

We welcome contributions to SmartThingsEdgeDrivers. Read our contribution
guidelines in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

SmartThingsEdgeDrivers is released under the [Apache 2.0 License](LICENSE).
