--!strict

--[[
	useNavigation

	Full-panel navigation state for the HUD: which root screen is open (one of
	the three tabs, or the Basket / Wearing lists) and a stack of deeper pages
	for the breadcrumbs (e.g. Outfits › Neon Rider › Varsity Jacket).

	Mirrors the design prototype (logic.js `ui.full` + `stack`):
	  toggleTab(tab)   open a tab with an empty stack; tapping the tab that's
	                   already open closes the panel
	  openRoot(root)   open Basket / Wearing (no toggle)
	  push(entry)      go one level deeper
	  replaceTop(entry) swap the deepest page (e.g. "More like this")
	  popTo(depth)     jump back to a crumb (0 = the root screen)
	  back()           pop one level
	  restore(root, stack)   reopen a root with a stack kept from before
	                   (back to a store page after picking in the Catalogue)
	  close()          close the panel, back to the world

	Entries carry their own crumb label so the breadcrumb row never needs to
	look anything up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

export type Root = "Catalogue" | "Stores" | "Outfits" | "Basket" | "Wearing"

export type Entry = {
	kind: string, -- "item" | "store" | "outfit" | …
	id: any,
	label: string,
}

export type Navigation = {
	root: Root?,
	stack: { Entry },
	top: Entry?,
	isOpen: boolean,
	toggleTab: (tab: Root) -> (),
	openRoot: (root: Root) -> (),
	push: (entry: Entry) -> (),
	replaceTop: (entry: Entry) -> (),
	popTo: (depth: number) -> (),
	back: () -> (),
	restore: (root: Root, stack: { Entry }) -> (),
	close: () -> (),
}

type State = { root: Root?, stack: { Entry } }

local CLOSED: State = { root = nil, stack = {} }

local function useNavigation(): Navigation
	local state, setState = React.useState(CLOSED)

	local toggleTab = React.useCallback(function(tab: Root)
		setState(function(current: State): State
			if current.root == tab then
				return CLOSED
			end
			return { root = tab, stack = {} }
		end)
	end, {})

	local openRoot = React.useCallback(function(root: Root)
		setState({ root = root, stack = {} })
	end, {})

	local push = React.useCallback(function(entry: Entry)
		setState(function(current: State): State
			local stack = table.clone(current.stack)
			table.insert(stack, entry)
			return { root = current.root, stack = stack }
		end)
	end, {})

	local replaceTop = React.useCallback(function(entry: Entry)
		setState(function(current: State): State
			local stack = table.clone(current.stack)
			stack[math.max(1, #stack)] = entry
			return { root = current.root, stack = stack }
		end)
	end, {})

	local popTo = React.useCallback(function(depth: number)
		setState(function(current: State): State
			local stack = table.move(current.stack, 1, math.clamp(depth, 0, #current.stack), 1, {})
			return { root = current.root, stack = stack }
		end)
	end, {})

	local back = React.useCallback(function()
		setState(function(current: State): State
			local stack = table.clone(current.stack)
			table.remove(stack)
			return { root = current.root, stack = stack }
		end)
	end, {})

	local restore = React.useCallback(function(root: Root, stack: { Entry })
		setState({ root = root, stack = table.clone(stack) })
	end, {})

	local close = React.useCallback(function()
		setState(CLOSED)
	end, {})

	return {
		root = state.root,
		stack = state.stack,
		top = state.stack[#state.stack],
		isOpen = state.root ~= nil,
		toggleTab = toggleTab,
		openRoot = openRoot,
		push = push,
		replaceTop = replaceTop,
		popTo = popTo,
		back = back,
		restore = restore,
		close = close,
	}
end

return useNavigation
