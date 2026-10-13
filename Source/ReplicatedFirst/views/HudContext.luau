--!strict

--[[
	HudContext

	HUD-wide actions any view can reach without prop-drilling, provided by Hud:

	  buy(itemIds, key?)       buy one or more items through Roblox's own
	                           purchase prompt (owned items are skipped).
	                           `key` names the button that asked ("basket";
	                           default "item:<id>" for one item, else "items")
	  buying(key) -> boolean   that button's purchase is under way: show a
	                           spinner on it until Roblox's prompt has ended
	  share(outfitId)          open the share dialog for a saved outfit
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

export type HudActions = {
	buy: (itemIds: { number }, key: string?) -> (),
	buying: (key: string) -> boolean,
	share: (outfitId: number) -> (),
}

local HudContext = React.createContext({
	buy = function(_itemIds: { number }, _key: string?) end,
	buying = function(_key: string): boolean
		return false
	end,
	share = function(_outfitId: number) end,
} :: HudActions)

return HudContext
