--!strict
--[[
    StoresConfigTypes
    Type definitions for player stores: limits on stores and their rows.
    Shared: the server validates against it, the client shows the limits.
]]

export type StoresConfig = {
    maxStores: number, -- stores one player can own
    minItems: number, -- items a store needs before it can be published
    maxItems: number, -- catalogue items in one store
    maxOutfits: number, -- outfits in one store
    nameLength: { min: number, max: number }, -- characters, after trimming
    maxRows: number, -- rows on a store page (Featured and the automatic ones count)
    rowNameLength: { min: number, max: number }, -- an owner's row name, characters
    rowLimit: { default: number, max: number }, -- items / outfits a row shows
}

return nil
