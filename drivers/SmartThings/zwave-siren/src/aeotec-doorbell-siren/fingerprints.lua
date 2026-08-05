-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local AEOTEC_DOORBELL_SIREN_FINGERPRINTS = {
  { manufacturerId = 0x0371, productType = 0x0003, productId = 0x00A2}, -- Aeotec Doorbell 6 (EU)
  { manufacturerId = 0x0371, productType = 0x0103, productId = 0x00A2}, -- Aeotec Doorbell 6 (US)
  { manufacturerId = 0x0371, productType = 0x0203, productId = 0x00A2}, -- Aeotec Doorbell 6 (AU)
  { manufacturerId = 0x0371, productType = 0x0003, productId = 0x00A4}, -- Aeotec Siren 6 (EU)
  { manufacturerId = 0x0371, productType = 0x0103, productId = 0x00A4}, -- Aeotec Siren 6 (US)
  { manufacturerId = 0x0371, productType = 0x0203, productId = 0x00A4}, -- Aeotec Siren 6 (AU)
}

return AEOTEC_DOORBELL_SIREN_FINGERPRINTS
