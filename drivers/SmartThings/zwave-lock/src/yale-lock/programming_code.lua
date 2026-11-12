-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Yale locks keep their programming code in a user code slot that is not one of the lock's user slots. It is exposed
-- like any other credential, owned by a user with the same index and the programming code userType.
-- Everything that is specific to where Yale puts that slot lives here, so generic lock code only has to know
-- about the programmingUser userType.

local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })

local yale_programming_code = {
  MANUFACTURER_ID = 0x0129,
  SLOT = 251,
}

-- Returns the credentialIndex of the programming code slot, or nil if the device is not a Yale lock.
function yale_programming_code.credential_index(device)
  if device.zwave_manufacturer_id == yale_programming_code.MANUFACTURER_ID then
    return yale_programming_code.SLOT
  end
end

-- Read the programming code slot back from the lock, so the programming code is recorded even if it was set outside
-- SmartThings. The report is handled like any other user code report.
function yale_programming_code.read_programming_code(device)
  device:send(UserCode:Get({ user_identifier = yale_programming_code.SLOT }))
end

return yale_programming_code
