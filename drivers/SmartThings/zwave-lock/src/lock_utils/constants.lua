-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lock_constants = {}

lock_constants.DRIVER_STATE = {
  BUSY = "busy",
  COMMAND_IN_PROGRESS = "commandInProgress",
  CREDENTIAL_ARGS_IN_USE = "currentCredential",
  SLGA_MIGRATED = "slgaMigrated",
}

lock_constants.SYNC = {
  CODES_FROM_LOCK = "syncCodesFromLock",
  CODE_INDEX = "syncCodeIndex",
  CONSECUTIVE_UNOCCUPIED_CODES = "consecutiveUnoccupiedCodes",
}

lock_constants.ADMIN = {
  -- Yale locks keep their master code in this user code slot.
  YALE_SLOT = 251,
  YALE_MANUFACTURER_ID = 0x0129,
  -- Stopgap userType for the master code until the lockUsers capability has one for it.
  USER_TYPE = "controlOnlyMember",
  NAME = "Master Code",
}

lock_constants.COMMAND_RESULT = {
  SUCCESS = "success",
  FAILURE = "failure",
  DUPLICATE = "duplicate",
  OCCUPIED = "occupied",
  INVALID_COMMAND = "invalidCommand",
  RESOURCE_EXHAUSTED = "resourceExhausted",
  BUSY = "busy"
}

lock_constants.LOCK_CREDENTIALS = {
  ADD = "addCredential",
  UPDATE = "updateCredential",
  DELETE = "deleteCredential",
  DELETE_ALL = "deleteAllCredentials"
}

lock_constants.LOCK_USERS = {
  ADD = "addUser",
  UPDATE = "updateUser",
  DELETE = "deleteUser",
  DELETE_ALL = "deleteAllUsers"
}

lock_constants.CRED_TYPE_PIN = "pin"
lock_constants.DELAY_LOCK_EVENT = "_delay_lock_event"
lock_constants.DELAY_LOCK_EVENT_TIMER = "_delay_lock_event_timer"
lock_constants.MAX_DELAY = 10

return lock_constants
