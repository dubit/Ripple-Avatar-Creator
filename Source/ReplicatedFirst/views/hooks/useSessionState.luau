--!strict

--[[
	useSessionState

	useState that outlives its component for the rest of the session: the
	value is kept in memory under `key`, so a screen that's closed and opened
	again (the Catalogue when the panel closes) picks up where it was. Not
	saved anywhere; a rejoin starts fresh. The values live in SessionStore,
	so code outside a screen can preset one.

	Usage, like useState (the setter takes a value or an updater function):
		local category, setCategory = useSessionState("catalogue.category", "Body")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local store = require(script.Parent:WaitForChild("SessionStore"))

local function useSessionState<T>(key: string, initial: T | () -> T): (T, (T | (T) -> T) -> ())
	local value, setValue = React.useState(function(): T
		if store[key] ~= nil then
			return store[key]
		end
		local first = if type(initial) == "function" then (initial :: () -> T)() else initial :: T
		store[key] = first
		return first
	end)
	local set = React.useCallback(function(next: T | (T) -> T)
		setValue(function(current: T): T
			local updated = if type(next) == "function" then (next :: (T) -> T)(current) else next :: T
			store[key] = updated
			return updated
		end)
	end, { key })
	return value, set
end

return useSessionState
