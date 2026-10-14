--!strict
--[[
    StoresConfigTypes
    Type definitions for player stores: limits, the store page's sections
    and its rule-based collections. Shared: the server validates and builds
    store pages from it, the client shows the limits.
]]

-- A collection on a store page: the store's items that match every rule
-- given. Categories are CatalogueConfig category names ("Accessories").
export type Collection = {
    name: string,
    minPrice: number?, -- Robux, inclusive
    maxPrice: number?, -- Robux, inclusive (49 for "Under 50")
    category: string?, -- a CatalogueConfig category's asset / bundle types
    assetTypes: { string }?, -- AvatarAssetType names
    bundleTypes: { string }?, -- BundleType names
}

export type StoresConfig = {
    maxStores: number, -- stores one player can own
    minItems: number, -- items a store needs before it can be published
    maxItems: number, -- catalogue items in one store
    maxOutfits: number, -- outfits in one store
    nameLength: { min: number, max: number }, -- characters, after trimming
    featured: number, -- items a store from before rows gets in Featured
    maxRows: number, -- rows on a store page (Featured and the automatic ones count)
    rowNameLength: { min: number, max: number }, -- an owner's row name, characters
    sectionSize: number, -- items in a Bestsellers / New arrivals carousel
    collections: { Collection }, -- tried in order
    maxCollections: number, -- collection tiles on a store page
    collectionMinItems: number, -- a collection needs this many items to show
}

return nil
