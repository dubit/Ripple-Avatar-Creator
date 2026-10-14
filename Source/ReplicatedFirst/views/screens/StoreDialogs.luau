--!strict

--[[
	StoreDialogs (no design: PLAN 19.1, "edit in place")

	Two small dialogs over a dimmed screen, owned by Hud like the share
	dialog (tap outside, Close or Back shuts them; they rise in and drop out):

	  Picker   "Add to store": the player's own stores, each with a tick when
	           the item (or outfit) is in it. Ticking adds it, unticking
	           takes it out (StoresController AddItem / RemoveItem /
	           AddOutfit / RemoveOutfit). Opened from the store button in an
	           item card's menu, or on your own shared outfit.
	  Create   "Create store": a name, then the new draft store's page opens.

	Why something failed shows in the dialog itself (no toasts).

	StoreDialogs.Dialog props:
		dialog: { kind: "pick", target: Target } | { kind: "create" } | nil
		myStores: { string }       codes of the player's own stores
		onCreated: (code, name) -> ()
		onClose: () -> ()
	StoreDialogs.message(error, what?) -> string   why a store action failed,
		in words (`what` "item" | "outfit" | "store" picks the "full" line)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local Sounds = require(views:WaitForChild("Sounds"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local useTransition = require(views:WaitForChild("hooks"):WaitForChild("useTransition"))
local PillButton = require(views:WaitForChild("components"):WaitForChild("PillButton"))
local GlassPanel = require(views:WaitForChild("components"):WaitForChild("GlassPanel"))
local ShadowText = require(views:WaitForChild("components"):WaitForChild("ShadowText"))
local Spinner = require(views:WaitForChild("components"):WaitForChild("Spinner"))
local StoresClient = require(views:WaitForChild("catalogue"):WaitForChild("StoresClient"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))
local OutfitsScreen = require(script.Parent:WaitForChild("OutfitsScreen"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local StoresConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoresConfig"))

local e = React.createElement

local WIDTH = 440
local RISE = 30
local ROW = 54

export type Target = { kind: "item", id: number } | { kind: "outfit", code: string, name: string }
export type Dialog = { kind: "pick", target: Target } | { kind: "create" }

local function message(err: string?, what: string?): string
	if err == "full" then
		return if what == "item" then `That store is full ({StoresConfig.maxItems} items)`
			elseif what == "outfit" then `That store has its {StoresConfig.maxOutfits} outfits`
			else `You can have up to {StoresConfig.maxStores} stores`
	elseif err == "dupe" then
		return "It's already in that store"
	elseif err == "notfound" then
		return if what == "outfit" then "Share the outfit first, so it's on Community" else "Couldn't find that item on Roblox"
	elseif err == "length" then
		return `Names are {StoresConfig.nameLength.min} to {StoresConfig.nameLength.max} characters`
	elseif err == "filtered" then
		return "That name isn't allowed"
	elseif err == "taken" then
		return "Another store has that name"
	elseif err == "items" then
		return `Add at least {StoresConfig.minItems} items to publish`
	elseif err == "hidden" then
		return "Hidden after reports, so it can't be published"
	end
	return "Something went wrong. Try again in a moment"
end

-- The dimmed screen and the panel, rising in with `t`.
local function Shell(props: { t: any, height: number, title: string, sub: string?, onClose: () -> (), children: any })
	local skin = useSkin()
	return e("TextButton", {
		Name = "StoreDialog",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Tokens.color.black,
		BackgroundTransparency = props.t:map(function(t: number)
			return 1 - 0.5 * math.clamp(t, 0, 1)
		end),
		AutoButtonColor = false,
		Text = "",
		ZIndex = 40,
		[React.Event.InputBegan] = Press.began(props.onClose), -- tap outside to close
	}, {
		Dialog = e("CanvasGroup", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = props.t:map(function(t: number)
				return UDim2.new(0.5, 0, 0.5, (1 - t) * skin.px(RISE))
			end),
			Size = UDim2.fromOffset(skin.px(WIDTH), props.height),
			GroupTransparency = props.t:map(function(t: number)
				return 1 - math.clamp(t, 0, 1)
			end),
			BackgroundTransparency = 1,
			ZIndex = 41,
		}, {
			-- Swallow taps on the card so they don't close it.
			Block = e("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 0,
			}),
			Panel = e(GlassPanel, {
				variant = "bar",
				cornerRadius = Tokens.radius.sidePanel,
				shadow = true,
			}, {
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, skin.px(18)),
					PaddingBottom = UDim.new(0, skin.px(18)),
					PaddingLeft = UDim.new(0, skin.px(20)),
					PaddingRight = UDim.new(0, skin.px(20)),
				}),
				Title = e(ShadowText, { text = props.title, style = { size = 20, weight = 900 } }),
				Sub = if props.sub
					then e("Frame", {
						Position = UDim2.fromOffset(0, skin.px(30)),
						Size = UDim2.new(1, 0, 0, skin.px(18)),
						BackgroundTransparency = 1,
					}, {
						Text = e(ShadowText, {
							text = props.sub,
							style = Tokens.type.meta,
							transparency = Tokens.alpha.textSoft,
							shadow = false,
							maxWidth = skin.px(WIDTH - 40),
						}),
					})
					else nil,
				Body = e(React.Fragment, nil, props.children),
			}),
		}),
	})
end

local function ErrorLine(props: { text: string?, position: UDim2 })
	local skin = useSkin()
	if not props.text then
		return nil
	end
	return e("TextLabel", {
		Position = props.position,
		Size = UDim2.new(1, 0, 0, skin.px(20)),
		BackgroundTransparency = 1,
		Text = props.text,
		TextColor3 = Tokens.color.accentText,
		TextSize = skin.textPx(13.5),
		FontFace = Tokens.font(800),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

local function Buttons(props: { children: any })
	local skin = useSkin()
	return e("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, skin.px(Tokens.size.ctaHeight)),
		BackgroundTransparency = 1,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(8)),
		}),
		Buttons = e(React.Fragment, nil, props.children),
	})
end

local function contains(page: StoresClient.Page, target: Target): boolean
	if target.kind == "item" then
		return table.find(page.items, target.id) ~= nil
	end
	for _, outfit in page.outfits do
		if outfit.code == target.code then
			return true
		end
	end
	return false
end

local function storeLine(page: StoresClient.Page): string
	local count = #page.items
	return (if page.hidden then "Hidden" elseif page.published then "Published" else "Draft")
		.. " · " .. count .. " item" .. (if count == 1 then "" else "s")
		.. (if #page.outfits > 0 then " · " .. #page.outfits .. " outfit" .. (if #page.outfits == 1 then "" else "s") else "")
end

local function Picker(props: { target: Target, myStores: { string }, t: any, onClose: () -> () })
	local skin = useSkin()
	local target = props.target
	local item = if target.kind == "item" then PlaceholderData.item(target.id) else nil
	local pages, setPages = React.useState({} :: { [string]: StoresClient.Page | false })
	local pending, setPending = React.useState({} :: { [string]: boolean })
	local problem, setProblem = React.useState(nil :: string?)
	local alive = React.useRef(true)
	local running = React.useRef({} :: { [string]: boolean }) -- at once, unlike state

	local function store(code: string, page: StoresClient.Page | false)
		if alive.current then
			setPages(function(old)
				local new = table.clone(old)
				new[code] = page
				return new
			end)
		end
	end
	local function setBusy(code: string, busy: boolean?)
		if alive.current then
			setPending(function(old)
				local new = table.clone(old)
				new[code] = busy
				return new
			end)
		end
	end

	local signature = table.concat(props.myStores, ",")
	React.useEffect(function()
		alive.current = true
		for _, code in props.myStores do
			task.spawn(function()
				local page = StoresClient.find(code)
				store(code, page or false)
			end)
		end
		return function()
			alive.current = false
		end
	end, { signature })

	local function toggle(code: string, page: StoresClient.Page)
		if running.current[code] then
			return
		end
		running.current[code] = true
		Sounds.play("press")
		setProblem(nil)
		setBusy(code, true)
		local inside = contains(page, target)
		task.spawn(function()
			local ok, err
			if target.kind == "item" then
				if not item or not item.targetId then
					ok, err = false, "notfound"
				else
					local action = if inside then Network.Actions.Stores.RemoveItem else Network.Actions.Stores.AddItem
					ok, _, err = StoresClient.act(action, { code = code, targetId = item.targetId, kind = item.kind })
				end
			else
				local action = if inside then Network.Actions.Stores.RemoveOutfit else Network.Actions.Stores.AddOutfit
				ok, _, err = StoresClient.act(action, { code = code, outfit = target.code })
			end
			if ok then
				Sounds.play("confirm")
				local fresh = StoresClient.find(code)
				store(code, fresh or false)
			elseif alive.current then
				Sounds.play("error")
				setProblem(message(err, target.kind))
			end
			running.current[code] = nil
			setBusy(code, nil)
		end)
	end

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(4)) }),
	}
	for index, code in props.myStores do
		local page = pages[code]
		local busy = pending[code] == true or page == nil
		rows["Store" .. code] = e("TextButton", {
			Size = UDim2.new(1, 0, 0, skin.px(ROW)),
			BackgroundColor3 = Tokens.color.inputWell,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			[React.Event.InputBegan] = Press.began(function()
				if page then
					toggle(code, page)
				end
			end),
			[React.Event.Activated] = Press.activated(function()
				if page then
					toggle(code, page)
				end
			end),
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
			Padding = e("UIPadding", { PaddingLeft = UDim.new(0, skin.px(12)), PaddingRight = UDim.new(0, skin.px(12)) }),
			Tick = if busy
				then e(Spinner, { size = 24, anchorPoint = Vector2.new(0, 0.5), position = UDim2.new(0, skin.px(2), 0.5, 0) })
				elseif page then e(OutfitsScreen.Checkbox, {
					on = contains(page, target),
					onToggle = function()
						toggle(code, page)
					end,
				})
				else nil,
			Text = e("Frame", {
				Position = UDim2.fromOffset(skin.px(42), 0),
				Size = UDim2.new(1, -skin.px(42), 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, skin.px(2)),
				}),
				Name = e("TextLabel", {
					Size = UDim2.new(1, 0, 0, skin.textPx(15) + skin.px(2)),
					BackgroundTransparency = 1,
					Text = if page then page.name elseif page == false then "Couldn't load this store" else "",
					TextColor3 = Tokens.color.white,
					TextSize = skin.textPx(15),
					FontFace = Tokens.font(900),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = 1,
				}),
				Sub = if page
					then e("TextLabel", {
						Size = UDim2.new(1, 0, 0, skin.textPx(12.5) + skin.px(2)),
						BackgroundTransparency = 1,
						Text = storeLine(page),
						TextColor3 = Tokens.color.white,
						TextTransparency = Tokens.alpha.textSoft,
						TextSize = skin.textPx(12.5),
						FontFace = Tokens.font(800),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						LayoutOrder = 2,
					})
					else nil,
			}),
		})
	end

	local listTop = skin.px(62)
	local listHeight = #props.myStores * skin.px(ROW) + math.max(0, #props.myStores - 1) * skin.px(4)
	local height = skin.px(18) + listTop + listHeight + skin.px(34) + skin.px(Tokens.size.ctaHeight) + skin.px(18)
	return e(Shell, {
		t = props.t,
		height = height,
		title = "Add to store",
		sub = if item then item.name elseif target.kind == "outfit" then target.name else nil,
		onClose = props.onClose,
	}, {
		List = e("Frame", {
			Position = UDim2.fromOffset(0, listTop),
			Size = UDim2.new(1, 0, 0, listHeight),
			BackgroundTransparency = 1,
		}, rows),
		Error = e(ErrorLine, { text = problem, position = UDim2.fromOffset(0, listTop + listHeight + skin.px(8)) }),
		Buttons = e(Buttons, nil, {
			Close = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				width = 130,
				label = "Done",
				sound = "back",
				layoutOrder = 1,
				onActivated = props.onClose,
			}),
		}),
	})
end

local function Create(props: { t: any, onCreated: (code: string, name: string) -> (), onClose: () -> () })
	local skin = useSkin()
	local name, setName = React.useState("")
	local waiting, setWaiting = React.useState(false)
	local problem, setProblem = React.useState(nil :: string?)
	local boxRef = React.useRef(nil :: TextBox?)
	local alive = React.useRef(true)
	React.useEffect(function()
		alive.current = true
		-- Straight to typing.
		task.defer(function()
			if boxRef.current then
				boxRef.current:CaptureFocus()
			end
		end)
		return function()
			alive.current = false
		end
	end, {})

	local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
	local length = utf8.len(trimmed) or 0
	local ready = length >= StoresConfig.nameLength.min and not waiting
	local function submit()
		if not ready then
			return
		end
		setWaiting(true)
		setProblem(nil)
		task.spawn(function()
			local ok, code, err = StoresClient.act(Network.Actions.Stores.Create, { name = trimmed })
			if not alive.current then
				return
			end
			setWaiting(false)
			if ok and code then
				Sounds.play("confirm")
				props.onCreated(code, trimmed)
			else
				Sounds.play("error")
				setProblem(message(err, "store"))
			end
		end)
	end

	local fieldTop = skin.px(62)
	local fieldHeight = skin.px(52)
	local height = skin.px(18) + fieldTop + fieldHeight + skin.px(34) + skin.px(Tokens.size.ctaHeight) + skin.px(18)
	return e(Shell, {
		t = props.t,
		height = height,
		title = "Create store",
		sub = `Name it, then add items from any item card. {StoresConfig.minItems} items and you can publish it.`,
		onClose = props.onClose,
	}, {
		Field = e("Frame", {
			Position = UDim2.fromOffset(0, fieldTop),
			Size = UDim2.new(1, 0, 0, fieldHeight),
			BackgroundColor3 = Tokens.color.inputWell,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
			Padding = e("UIPadding", { PaddingLeft = UDim.new(0, skin.px(14)), PaddingRight = UDim.new(0, skin.px(14)) }),
			Box = e("TextBox", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				Text = name,
				PlaceholderText = "Store name",
				PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
				TextColor3 = Tokens.color.white,
				TextSize = skin.textPx(20),
				FontFace = Tokens.font(900),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ref = boxRef,
				[React.Change.Text] = function(box: TextBox)
					-- Names are capped (the server checks them too).
					local text = box.Text
					local cap = StoresConfig.nameLength.max
					if (utf8.len(text) or 0) > cap then
						text = string.sub(text, 1, (utf8.offset(text, cap + 1) or (#text + 1)) - 1)
						box.Text = text
					end
					setName(text)
				end,
				[React.Event.FocusLost] = function(_box: TextBox, enterPressed: boolean)
					if enterPressed then
						submit()
					end
				end,
			}),
		}),
		Error = e(ErrorLine, { text = problem, position = UDim2.fromOffset(0, fieldTop + fieldHeight + skin.px(8)) }),
		Buttons = e(Buttons, nil, {
			Cancel = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				width = 130,
				label = "Cancel",
				sound = "back",
				layoutOrder = 1,
				onActivated = props.onClose,
			}),
			Create = e(PillButton, {
				variant = "pill",
				size = Tokens.size.ctaHeight,
				width = 170,
				icon = "add_business",
				iconSize = 19,
				label = "Create",
				active = true,
				disabled = not ready and not waiting,
				loading = waiting,
				sound = false, -- the outcome plays its own sound
				layoutOrder = 2,
				onActivated = submit,
			}),
		}),
	})
end

local function Dialog(props: {
	dialog: Dialog?,
	myStores: { string },
	onCreated: (code: string, name: string) -> (),
	onClose: () -> (),
})
	local last = React.useRef(nil :: Dialog?)
	if props.dialog then
		last.current = props.dialog
	end
	local transitions = useTransition(props.dialog ~= nil, {
		from = { t = 0 },
		enter = { t = 1 },
		leave = { t = 0 },
		config = Tokens.spring.panelIn,
		leaveConfig = Tokens.spring.panelOut,
	})
	local children: { [string]: any } = {}
	for _, transition in transitions do
		local dialog = props.dialog or last.current
		if dialog then
			local t = transition.springProps.t
			children["Dialog" .. transition.key] = if dialog.kind == "pick"
				then e(Picker, { target = dialog.target, myStores = props.myStores, t = t, onClose = props.onClose })
				else e(Create, { t = t, onCreated = props.onCreated, onClose = props.onClose })
		end
	end
	return e(React.Fragment, nil, children)
end

return {
	Dialog = Dialog,
	message = message,
}
