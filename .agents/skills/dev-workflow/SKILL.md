---
name: dev-workflow
description: Setting up the development environment, deploying Edge Drivers to hubs, and sharing drivers with other users via channels and invites
---

# SmartThings Edge Driver Development Workflow

This skill covers environment setup, driver deployment to hubs, and sharing
drivers with other users through channels and invite links.

---

## Environment Setup

### 1. Install Lua 5.3

Edge Drivers are Lua-based. Install the Lua 5.3 runtime for local development
and linting:

```bash
# Ubuntu / Debian
sudo apt install lua5.3

# macOS
brew install lua@5.3

# Windows
# Download the Lua 5.3 binary from https://luabinaries.sourceforge.net/download.html
# Or install via scoop:
scoop install lua
# Or via chocolatey:
choco install lua53
```

### 2. lua_libs Directory

The `lua_libs/` directory contains the SmartThings Lua libraries that are
available on the hub at runtime. These correspond to the assets attached to the
latest release on GitHub:

<https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/releases/latest>

Download the lua_libs archive from the release assets and
extract it into the repository root if it is missing or needs updating.

### 3. Configure LUA_PATH

Set `LUA_PATH` so that `require` resolves both your driver modules and the
SmartThings library modules in `lua_libs/`:

```bash
export LUA_PATH="./?.lua;./?/init.lua;$(pwd)/lua_libs/?.lua;$(pwd)/lua_libs/?/init.lua;;"
```

Run it from the repository root so `$(pwd)` resolves correctly.


### 4. Install the SmartThings CLI

The CLI is required for packaging, deploying, and managing drivers and
channels on the platform.

```bash
# Via npm (requires Node.js >= 24.8.0)
npm install -g @smartthings/cli

# macOS via Homebrew
brew install smartthingscommunity/smartthings/smartthings

# Linux / Windows
# Download the binary or installer from:
# https://github.com/SmartThingsCommunity/smartthings-cli/releases
```

Verify the installation:

```bash
smartthings --version
```

The CLI uses browser-based OAuth login by default. Run `smartthings devices` to trigger
the login flow.

### 5. Python Requirements (Testing)

Some test and tooling scripts require Python dependencies:

```bash
pip install -r tools/requirements.txt
```

### 6. Install Luacheck (Linting)

Luacheck provides static analysis for Lua source files. It requires LuaRocks
(the Lua package manager).

**Install LuaRocks first:**

```bash
# Ubuntu / Debian
sudo apt install luarocks

# macOS
brew install luarocks

# Windows
# Download the installer from https://luarocks.org/releases/
# Or via chocolatey:
choco install luarocks
```

**Then install Luacheck:**

```bash
# Via LuaRocks (all platforms)
luarocks install luacheck

# macOS alternative (installs both luarocks and luacheck)
brew install luacheck
```

Run it against a driver directory:

```bash
luacheck --config .github/workflows/.luacheckrc drivers/SmartThings/zigbee-switch/
```

---

## Deploying Drivers

### Overview

Deploying a driver to a physical hub requires three things:

1. A **channel** you own.
2. The hub **enrolled** in that channel.
3. The driver **packaged and uploaded** through the CLI.

### Step 1: Create a Channel

```bash
smartthings edge:channels:create
```

You will be prompted for a name and description. Note the returned channel ID.

### Step 2: Enroll Your Hub

```bash
smartthings edge:channels:enroll <hub-id>
```

Select the channel when prompted, or pass `--channel <channel-id>`.

Find your hub ID with:

```bash
smartthings devices --type HUB
```

### Step 3: Package and Install the Driver

The `edge:drivers:package` command can build, upload, assign to a channel, and
install in one step:

```bash
smartthings edge:drivers:package <path-to-driver-dir> \
  --hub=<hub-uuid> \
  --channel=<channel-id>
```

For example:

```bash
smartthings edge:drivers:package drivers/SmartThings/zwave-switch \
  --hub=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
  --channel=11111111-2222-3333-4444-555555555555
```

### Other Useful Deployment Commands

```bash
# List drivers installed on a hub
smartthings edge:drivers:installed --hub=<hub-uuid>

# Stream logs from a driver on the hub
smartthings edge:drivers:logcat <driver-id> --hub=<hub-uuid>

# Uninstall a driver from a hub
smartthings edge:drivers:uninstall <driver-id> --hub=<hub-uuid>

# Remove unused drivers from a hub
smartthings edge:drivers:prune --hub=<hub-uuid>

# Switch a device to a different driver
smartthings edge:drivers:switch <device-id>
```

---

## Sharing Drivers

### Creating an Invite Link

Invite links let other users install your driver from your channel without
giving them ownership of the driver or channel.

```bash
smartthings edge:channels:invites:create
```

You will be prompted to select a channel and a driver. The command returns an
invite URL of the form:

```
https://bestow-regional.api.smartthings.com/invite/<invite-id>
```

Share this URL with users. They open it in a browser or the SmartThings mobile
app to accept the invitation.

### Enrollment Flow for Recipients

1. The recipient opens the invite link.
2. They log in to their Samsung / SmartThings account.
3. They select a hub to enroll in the channel.
4. The driver can be selected to install to that hub.

### Managing Invites

```bash
# List existing invites
smartthings edge:channels:invites

# Delete an invite
smartthings edge:channels:invites:delete <invite-id>
```

### Managing Channel Assignments

```bash
# Assign a specific driver version to a channel
smartthings edge:channels:assign <driver-id> <version>

# List drivers assigned to a channel
smartthings edge:channels:drivers <channel-id>

# Remove a driver from a channel
smartthings edge:channels:unassign <driver-id>
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Create channel | `smartthings edge:channels:create` |
| Enroll hub | `smartthings edge:channels:enroll <hub-id>` |
| Package & deploy | `smartthings edge:drivers:package <dir> --hub=<id> --channel=<id>` |
| Stream logs | `smartthings edge:drivers:logcat <driver-id> --hub=<id>` |
| Create invite | `smartthings edge:channels:invites:create` |
| List installed drivers | `smartthings edge:drivers:installed --hub=<id>` |
