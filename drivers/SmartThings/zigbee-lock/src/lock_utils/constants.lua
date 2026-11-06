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
  CODE_INDEX = "syncCodeIndex", -- persisted until codesSynced is set
  CODE_INDEX_VERSION = "syncCodeIndexVersion", -- persisted; the CODES_SYNC_VERSION under which CODE_INDEX was started
  CONSECUTIVE_UNOCCUPIED_CODES = "consecutiveUnoccupiedCodes",
  CODES_SYNCED = "codesSynced", -- persisted; holds the CODES_SYNC_VERSION of the last completed code sync
  CODES_SYNC_VERSION = 1, -- bump to force every device to re-sync its codes
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
lock_constants.MAX_DELAY = 10

return lock_constants
