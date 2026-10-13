--!strict
--[[
    CatalogueConfigTypes
    Type definitions for the catalogue: the marketplace-style category tabs,
    their chips (each a set of catalogue item types to search), and search
    tuning. Read by the client, which searches the catalogue directly.

    Type names are Enum.AvatarAssetType / Enum.BundleType item names
    ("HairAccessory", "DynamicHead"), kept as strings so the config stays data.
]]

export type CatalogueChip = {
    name: string,
    assetTypes: { string }?, -- Enum.AvatarAssetType names
    bundleTypes: { string }?, -- Enum.BundleType names
    special: string?, -- a chip that isn't a search: "skinTone" (the skin tone picker), "layering" (layer order)
}

export type CatalogueCategory = {
    name: string, -- top-level tab
    chips: { CatalogueChip }, -- in display order; "All" (every chip's types) is implicit
    special: string?, -- a tab that isn't a search: "scale" (the body scale sliders)
}

export type PricePreset = {
    label: string,
    min: number?, -- Robux; nil = no lower bound
    max: number?, -- Robux; nil = no upper bound (0 = free only)
}

export type SortOption = {
    label: string,
    sortType: string, -- Enum.CatalogSortType name
    windowed: boolean, -- offers a time window (Most Favourited, Bestselling)
}

export type SortWindow = {
    label: string,
    aggregation: string, -- Enum.CatalogSortAggregation name
}

export type SalesTypeOption = {
    label: string,
    filter: string, -- Enum.SalesTypeFilter name
}

export type CatalogueConfig = {
    categories: { CatalogueCategory },
    pageSize: number, -- items per catalogue page (10–120)
    sort: string, -- default Enum.CatalogSortType name
    sortAggregation: string, -- default Enum.CatalogSortAggregation name (for sorts over a time window)
    sorts: { SortOption }, -- Sort popover, in order
    sortWindows: { SortWindow }, -- time windows for windowed sorts, in order
    priceMax: number, -- top of the price slider; at the top it means "any"
    priceStep: number,
    pricePresets: { PricePreset },
    salesTypes: { SalesTypeOption }, -- Filters popover; the first is the default
    colours: { string }, -- Colour popover, in order; names match the thumbnail buckets
    colourTarget: number, -- with a colour picked, keep loading pages until this many match…
    colourMaxPages: number, -- …or this many pages have been looked through
    includeOffSale: boolean,
    cacheSeconds: number, -- how long a query's results are reused
    searchDebounce: number, -- seconds of no typing before a keyword search runs
    backoffSeconds: number, -- pause after the catalogue throttles us (HTTP 429)
    thumbnailSize: number, -- rbxthumb size: 48, 60, 150 or 420
}

return nil
