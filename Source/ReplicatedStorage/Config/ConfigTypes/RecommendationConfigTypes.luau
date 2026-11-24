--!strict
--[[
    RecommendationConfigTypes
    Type definitions for the recommendation ring and the interim recommender
    (a heuristic over the catalogue search, until the external service has
    endpoints). Read by the client, which builds the rings.
]]

-- A part of an outfit: what covers it, and where to search for it.
export type RecommendationArea = {
    name: string,
    weight: number?, -- how strongly "complete" and "wildcard" favour this area (default 1)
    category: string, -- CatalogueConfig category name
    chips: { string }, -- chips in that category to search (one is picked per search)
    covers: { string }, -- type names that count as covering this area when worn
}

-- The ring in the world (studs, unless noted).
export type RecommendationRingConfig = {
    count: number, -- pads per ring
    radius: number, -- centre to each pad's centre
    padSize: number, -- pad diameter
    cardSize: number, -- card width (height is 1.2x)
    cardHeight: number, -- card centre above the pad
    cardMaxDistance: number, -- cards hide beyond this from the camera
    walkAway: number, -- this far beyond the radius closes the ring
    maxStep: number, -- a pad's ground may be this far above / below the centre's
    groundSearch: number, -- how far down to look for ground under a pad
    modelSize: number, -- an item's 3D model is scaled to this longest side
    modelHeight: number, -- the model's centre above the pad
    spinSpeed: number, -- radians per second
    bobHeight: number, -- studs up and down
    bobSpeed: number, -- radians per second of the bob's sine
    dwell: number, -- seconds standing on a pad to choose it
}

export type RecommendationConfig = {
    -- Why each new item in a ring is there, in order; a ring takes the first
    -- `count` (6 with a back pad, 7 for the first ring).
    -- "creator" | "complete" | "style" | "wildcard"
    recipe: { string },
    areas: { RecommendationArea },
    styleWords: { string }, -- name words that describe a style, tried before colours
    colourWords: { string }, -- name words that are colours
    ignoreCreators: { string }, -- creators too broad to mean anything ("Roblox")
    skipTypes: { string }, -- type names (Item.typeName) never sent to the engine or shown in a ring
    rippleGroupId: number, -- Ripple (Tomorrow's Players): the group whose items are promoted
    rippleWithin: number, -- promote a Ripple item over a non-Ripple one whose score it's at least this fraction of (0..1)
    pickFrom: number, -- choose at random among a search's top this-many results
    maxSearches: number, -- per ring, fall-backs included
    creatorSort: string, -- Enum.CatalogSortType name
    styleSort: string,
    wildcardSort: string,
    wildcardWindow: string, -- Enum.CatalogSortAggregation name
    ring: RecommendationRingConfig,
}

return {}
