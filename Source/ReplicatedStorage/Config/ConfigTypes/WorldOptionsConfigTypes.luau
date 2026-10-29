--!strict
--[[
    WorldOptionsConfigTypes
    Type definitions for the World options panel, its saved preferences and
    double-jump flight. Shared: the server validates against it, the client
    builds the panel and renders from it.
]]

export type WorldOptionsDefaults = {
    time: number,
    sky: string,
    floor: string, -- hex, one of floorColors
    floorLightness: number, -- percent multiplier on the floor colour
    floorOpacity: number, -- percent; 0 is an invisible (still solid) floor
    pattern: string,
    patternColor: string, -- hex, one of patternColors
    patternLightness: number, -- percent multiplier on the pattern colour
    patternStrength: number, -- percent opacity of the pattern
    brightness: number,
    shadows: boolean,
    playlist: { string }, -- music track keys, in library order
    musicOn: boolean, -- playing (false: stopped)
}

export type MusicTrack = {
    key: string, -- saved in playlists; never reuse one for a different track
    name: string,
    mood: string, -- a few words under the name
    audio: number, -- audio asset id
    cover: number, -- image asset id (256px square)
}

export type MusicConfig = {
    volume: number, -- AudioPlayer.Volume (fixed; no control)
    tracks: { MusicTrack }, -- the 4x4 grid, in order; the first is the default
}

export type FlightConfig = {
    enabled: boolean,
    speed: number, -- studs/s while moving
    climbSpeed: number, -- studs/s while holding jump
    doubleJumpWindow: number, -- seconds between jump presses to toggle flight
}

export type SprintConfig = {
    enabled: boolean,
    walkSpeed: number, -- studs/s normally
    runSpeed: number, -- studs/s while Shift is held
    flightMultiplier: number, -- flight speed × this while Shift is held
}

export type WorldOptionsConfig = {
    timeMin: number,
    timeMax: number,
    timeStep: number,
    brightnessMin: number, -- percent
    brightnessMax: number,
    brightnessStep: number,
    skies: { string }, -- preset names, in panel order
    patterns: { string },
    floorColors: { string }, -- hex, in panel order; saved as the hex itself
    lightnessMin: number, -- percent, shared by floor and pattern lightness
    lightnessMax: number,
    lightnessStep: number,
    patternColors: { string }, -- hex, in panel order; saved as the hex itself
    patternStrengthMin: number, -- percent
    patternStrengthMax: number,
    patternStrengthStep: number,
    floorOpacityMin: number, -- percent
    floorOpacityMax: number,
    floorOpacityStep: number,
    defaults: WorldOptionsDefaults,
    music: MusicConfig,
    flight: FlightConfig,
    sprint: SprintConfig,
}

return nil
