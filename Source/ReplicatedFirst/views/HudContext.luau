--!strict

--[[
	HudContext

	HUD-wide actions any view can reach without prop-drilling, provided by Hud:

	  buy(itemIds, key?, store?)   buy one or more items through Roblox's
	                           own purchase prompt (owned items are skipped).
	                           `key` names the button that asked ("basket";
	                           default "item:<id>" for one item, else "items");
	                           `store` is the code of the store it's bought
	                           from (its Bestsellers count it)
	  buying(key) -> boolean   that button's purchase is under way: show a
	                           spinner on it until Roblox's prompt has ended
	  share(id, kind?, name?)  open the share dialog for a saved outfit, or
	                           (kind "creation") one saved on Roblox, with its
	                           name, or (kind "store", id its code) a store
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

export type HudActions = {
	buy: (itemIds: { number }, key: string?, store: string?) -> (),
	buying: (key: string) -> boolean,
	share: (id: any, kind: string?, name: string?) -> (),
}

local HudContext = React.createContext({
	buy = function(_itemIds: { number }, _key: string?, _store: string?) end,
	buying = function(_key: string): boolean
		return false
	end,
	share = function(_id: any, _kind: string?, _name: string?) end,
} :: HudActions)

return HudContext
