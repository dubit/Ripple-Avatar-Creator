--!strict
--[[
    AvatarConfigTypes
    Type definitions for try-on: which catalogue item types can be worn, how
    they replace or stack with each other, and request limits. Read by the
    server (AvatarController / AvatarModel / AvatarService).

    Type names are the catalogue's Enum.AvatarAssetType / Enum.BundleType
    item names ("HairAccessory", "Shoes"), as CatalogueClient reports them.
]]

export type AvatarConfig = {
    -- One at a time: wearing an item replaces whatever is in its slot.
    slots: { [string]: string }, -- typeName -> slot name
    -- Wearing into one slot also empties these others (a full body comes
    -- with its own head, so it replaces a worn head too).
    alsoReplaces: { [string]: { string } }, -- slot name -> other slot names
    -- Several at once, up to the group's limit (the oldest goes first).
    groups: { [string]: string }, -- typeName -> group name
    groupLimits: { [string]: number }, -- group name -> how many
    tryOnCooldown: number, -- seconds between a player's try-on requests
    undoDepth: number, -- how many changes Undo can step back through
    maxWearMany: number, -- most items in one Wear-all request
    basketLimit: number, -- most items the basket holds (the oldest drop off)
    basketBudget: { requests: number, seconds: number }, -- basket changes allowed per window
    outfits: {
        maxOutfits: number, -- saved outfits per player
        maxItems: number, -- items kept per outfit
        nameLength: number, -- characters in an outfit name
        cooldown: number, -- seconds between a player's outfit requests
    },
}

return nil
