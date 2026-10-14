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
	  addToStore(target)       open the store picker for an item
	                           ({ kind = "item", id }) or one of your shared
	                           outfits ({ kind = "outfit", code, name })
	  createStore()            open the Create store dialog (the new store's
	                           page opens once it's made)
	  addStoreRow(code)        open the Add row dialog for your store
	  pickForRow(target)       fill one of your store's rows: an items row
	                           opens the Catalogue in pick mode, an outfits
	                           row the Add outfits dialog. target: { code,
	                           row, kind, storeName, rowName, ids? (the
	                           row's items) }
	  picking                  the pick mode under way, or nil: { code, row,
	                           storeName, rowName, count, problem? }
	  isPicked(id) / pickBusy(id) -> boolean   in the row / being changed
	  pickToggle(id)           add the item to the row, or take it out
	  endPicking()             back to the store page
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

export type HudActions = {
	buy: (itemIds: { number }, key: string?, store: string?) -> (),
	buying: (key: string) -> boolean,
	share: (id: any, kind: string?, name: string?) -> (),
	addToStore: (target: any) -> (),
	createStore: () -> (),
	addStoreRow: (code: string) -> (),
	pickForRow: (target: any) -> (),
	picking: any?,
	isPicked: (id: number) -> boolean,
	pickBusy: (id: number) -> boolean,
	pickToggle: (id: number) -> (),
	endPicking: () -> (),
}

local HudContext = React.createContext({
	buy = function(_itemIds: { number }, _key: string?, _store: string?) end,
	buying = function(_key: string): boolean
		return false
	end,
	share = function(_id: any, _kind: string?, _name: string?) end,
	addToStore = function(_target: any) end,
	createStore = function() end,
	addStoreRow = function(_code: string) end,
	pickForRow = function(_target: any) end,
	picking = nil,
	isPicked = function(_id: number): boolean
		return false
	end,
	pickBusy = function(_id: number): boolean
		return false
	end,
	pickToggle = function(_id: number) end,
	endPicking = function() end,
} :: HudActions)

return HudContext
