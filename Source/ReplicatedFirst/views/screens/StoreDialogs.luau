--!strict

--[[
	StoreDialogs (no design: PLAN 19.1, "edit in place")

	Small dialogs over a dimmed screen, owned by Hud like the share dialog
	(tap outside, Done or Back shuts them; they rise in and drop out):

	  Picker   "Add to store": each of the player's own stores and its rows
	           that take the thing (hand-filled items rows for an item,
	           hand-filled outfits rows for an outfit), each with a tick when it's
	           in it. Ticking adds it to that row, unticking takes it out
	           (StoresController AddItem / RemoveItem / AddOutfit /
	           RemoveOutfit). Opened from the store button in an item card's
	           menu, or on your own shared outfit.
	  Outfits  "Add outfits" for one outfits row: your Community outfits
	           (Mine), ticked when they're in the row.
	  Create   "Create store": a name, then the new draft store's page opens.

	Why something failed shows in the dialog itself (no toasts).

	StoreDialogs.Dialog props:
		dialog: Dialog?            nil = closed
		myStores: { string }       codes of the player's own stores
		published: { string }      the player's Community outfit codes
		onCreated: (code, name) -> ()
		onClose: () -> ()
	StoreDialogs.message(error, what?) -> string   why a store action failed,
		in words (`what` "item" | "outfit" | "store" | "row" picks the line)
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
local CommunityOutfits = require(views:WaitForChild("catalogue"):WaitForChild("CommunityOutfits"))
local PlaceholderData = require(script.Parent:WaitForChild("PlaceholderData"))
local OutfitsScreen = require(script.Parent:WaitForChild("OutfitsScreen"))
local Network = require(ReplicatedStorage:WaitForChild("Network"))

local StoresConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("StoresConfig"))

local e = React.createElement

local WIDTH = 440
local RISE = 30
local ENTRY = 50 -- design px: a tickable line
local HEADER = 30 -- design px: a store's name above its rows
local LIST_MAX = 330 -- design px: taller lists scroll

export type Target = { kind: "item", id: number } | { kind: "outfit", code: string, name: string }
export type Dialog =
	{ kind: "pick", target: Target }
	| { kind: "outfits", code: string, row: string, storeName: string, rowName: string }
	| { kind: "create" }

local function message(err: string?, what: string?): string
	if err == "full" then
		return if what == "item" then `That store is full ({StoresConfig.maxItems} items)`
			elseif what == "outfit" then `That store has its {StoresConfig.maxOutfits} outfits`
			elseif what == "row" then `A store can have {StoresConfig.maxRows} rows`
			else `You can have up to {StoresConfig.maxStores} stores`
	elseif err == "dupe" then
		return if what == "row" then "The store already has that row" else "It's already in that row"
	elseif err == "notfound" then
		return if what == "outfit" then "Share the outfit first, so it's on Community" else "Couldn't find that item on Roblox"
	elseif err == "norow" then
		return "That row has gone. Reopen the store"
	elseif err == "length" then
		local limits = if what == "row" then StoresConfig.rowNameLength else StoresConfig.nameLength
		return `Names are {limits.min} to {limits.max} characters`
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
		[React.Event.InputBegan] = Press.began(function() -- tap outside to close
			Sounds.play("back")
			props.onClose()
		end),
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

-- A list of lines: store headings, notes, and tickable rows.
type Line = {
	key: string,
	kind: "header" | "note" | "toggle",
	label: string,
	sub: string?,
	on: boolean?,
	busy: boolean?,
	onToggle: (() -> ())?,
}

local function lineHeight(line: Line): number
	return if line.kind == "toggle" then ENTRY else HEADER
end

local function Lines(props: { lines: { Line }, position: UDim2, height: number })
	local skin = useSkin()
	local children: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(4)) }),
		Inset = e("UIPadding", { PaddingRight = UDim.new(0, skin.px(8)) }),
	}
	local total = 0
	for index, line in props.lines do
		total += skin.px(lineHeight(line)) + skin.px(4)
		if line.kind ~= "toggle" then
			children[line.key] = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, skin.px(HEADER)),
				BackgroundTransparency = 1,
				Text = line.label,
				TextColor3 = Tokens.color.white,
				TextTransparency = if line.kind == "note" then Tokens.alpha.textSoft else 0,
				TextSize = skin.textPx(if line.kind == "note" then 13 else 15),
				FontFace = Tokens.font(if line.kind == "note" then 800 else 900),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = index,
			})
		else
			local function toggle()
				if line.onToggle and not line.busy then
					line.onToggle()
				end
			end
			children[line.key] = e("TextButton", {
				Size = UDim2.new(1, 0, 0, skin.px(ENTRY)),
				BackgroundColor3 = Tokens.color.inputWell,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
				[React.Event.InputBegan] = Press.began(toggle),
				[React.Event.Activated] = Press.activated(toggle),
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
				Padding = e("UIPadding", { PaddingLeft = UDim.new(0, skin.px(12)), PaddingRight = UDim.new(0, skin.px(12)) }),
				Tick = if line.busy
					then e(Spinner, { size = 24, anchorPoint = Vector2.new(0, 0.5), position = UDim2.new(0, skin.px(2), 0.5, 0) })
					else e(OutfitsScreen.Checkbox, { on = line.on == true, onToggle = toggle }),
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
						Text = line.label,
						TextColor3 = Tokens.color.white,
						TextSize = skin.textPx(15),
						FontFace = Tokens.font(900),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						LayoutOrder = 1,
					}),
					Sub = if line.sub
						then e("TextLabel", {
							Size = UDim2.new(1, 0, 0, skin.textPx(12.5) + skin.px(2)),
							BackgroundTransparency = 1,
							Text = line.sub,
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
	end
	return e("ScrollingFrame", {
		Position = props.position,
		Size = UDim2.new(1, 0, 0, props.height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, total),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = skin.px(6),
		ScrollBarImageColor3 = Tokens.color.accent,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, children)
end

local function listHeight(skin: any, lines: { Line }): number
	local total = 0
	for _, line in lines do
		total += skin.px(lineHeight(line)) + skin.px(4)
	end
	return math.min(total, skin.px(LIST_MAX))
end

-- Store pages, loaded on open and reloaded after each change; and the
-- toggles under way.
local function useStorePages(codes: { string })
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
	local function setBusy(key: string, busy: boolean?)
		if alive.current then
			setPending(function(old)
				local new = table.clone(old)
				new[key] = busy
				return new
			end)
		end
	end

	local signature = table.concat(codes, ",")
	React.useEffect(function()
		alive.current = true
		for _, code in codes do
			task.spawn(function()
				local page = StoresClient.find(code)
				store(code, page or false)
			end)
		end
		return function()
			alive.current = false
		end
	end, { signature })

	-- Send an action for one line (`key`) of a store, then reload the store.
	local function run(key: string, code: string, action: string, payload: { [string]: any }, what: string)
		if running.current[key] then
			return
		end
		running.current[key] = true
		Sounds.play("press")
		setProblem(nil)
		setBusy(key, true)
		task.spawn(function()
			local ok, _, err = StoresClient.act(action, payload)
			if ok then
				Sounds.play("confirm")
				local fresh = StoresClient.find(code)
				store(code, fresh or false)
			elseif alive.current then
				Sounds.play("error")
				setProblem(message(err, what))
			end
			running.current[key] = nil
			setBusy(key, nil)
		end)
	end

	return pages, pending, problem, run, setProblem
end

local function rowTakes(row: StoresClient.Row, target: Target): boolean
	return row.source == "manual" and row.content == (if target.kind == "item" then "items" else "outfits")
end

local function rowHas(row: StoresClient.Row, target: Target): boolean
	if target.kind == "item" then
		return row.items ~= nil and table.find(row.items, target.id) ~= nil
	end
	return row.outfitCodes ~= nil and table.find(row.outfitCodes, target.code) ~= nil
end

local function rowName(row: StoresClient.Row): string
	return if row.name ~= "" then row.name else "Row"
end

local function storeLine(page: StoresClient.Page): string
	return if page.hidden then "Hidden" elseif page.published then "Published" else "Draft"
end

local function Picker(props: { target: Target, myStores: { string }, t: any, onClose: () -> () })
	local skin = useSkin()
	local target = props.target
	local item = if target.kind == "item" then PlaceholderData.item(target.id) else nil
	local pages, pending, problem, run = useStorePages(props.myStores)

	local lines: { Line } = {}
	for _, code in props.myStores do
		local page = pages[code]
		if page == nil then
			table.insert(lines, { key = "Load" .. code, kind = "note", label = "Loading…" })
			continue
		elseif page == false then
			table.insert(lines, { key = "Fail" .. code, kind = "note", label = "Couldn't load a store" })
			continue
		end
		local loaded = page :: StoresClient.Page
		table.insert(lines, { key = "Store" .. code, kind = "header", label = loaded.name .. "  ·  " .. storeLine(loaded) })
		local any = false
		for _, row in loaded.rows do
			if rowTakes(row, target) then
				any = true
				local key = code .. "|" .. row.id
				local inside = rowHas(row, target)
				table.insert(lines, {
					key = "Row" .. key,
					kind = "toggle",
					label = rowName(row),
					sub = if row.items then #row.items .. " items" elseif row.outfitCodes then #row.outfitCodes .. " outfits" else nil,
					on = inside,
					busy = pending[key] == true,
					onToggle = function()
						if target.kind == "item" then
							if not item or not item.targetId then
								return
							end
							run(key, code, if inside then Network.Actions.Stores.RemoveItem else Network.Actions.Stores.AddItem,
								{ code = code, row = row.id, targetId = item.targetId, kind = item.kind }, "item")
						else
							run(key, code, if inside then Network.Actions.Stores.RemoveOutfit else Network.Actions.Stores.AddOutfit,
								{ code = code, row = row.id, outfit = target.code }, "outfit")
						end
					end,
				})
			end
		end
		if not any then
			table.insert(lines, {
				key = "None" .. code,
				kind = "note",
				label = if target.kind == "outfit" then "No hand-filled outfits row yet: add one on the store's page" else "No hand-filled items rows yet",
			})
		end
	end

	local listTop = skin.px(62)
	local height = listHeight(skin, lines)
	return e(Shell, {
		t = props.t,
		height = skin.px(18) + listTop + height + skin.px(34) + skin.px(Tokens.size.ctaHeight) + skin.px(18),
		title = "Add to store",
		sub = if item then item.name elseif target.kind == "outfit" then target.name else nil,
		onClose = props.onClose,
	}, {
		List = e(Lines, { lines = lines, position = UDim2.fromOffset(0, listTop), height = height }),
		Error = e(ErrorLine, { text = problem, position = UDim2.fromOffset(0, listTop + height + skin.px(8)) }),
		Buttons = e(Buttons, nil, {
			Done = e(PillButton, {
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

-- Your Community outfits, for one outfits row.
local function Outfits(props: {
	dialog: { code: string, row: string, storeName: string, rowName: string },
	published: { string },
	t: any,
	onClose: () -> (),
})
	local skin = useSkin()
	local dialog = props.dialog
	local codes = React.useMemo(function()
		return { dialog.code }
	end, { dialog.code })
	local pages, pending, problem, run = useStorePages(codes)
	local _version, setVersion = React.useState(0)
	local key = table.concat(props.published, ",")
	React.useEffect(function()
		local connection = CommunityOutfits.changed:Connect(function()
			CommunityOutfits.load("mine", key)
			setVersion(function(v: number)
				return v + 1
			end)
		end)
		CommunityOutfits.load("mine", key)
		return function()
			connection:Disconnect()
		end
	end, { key })
	local list = CommunityOutfits.get("mine")
	local page = pages[dialog.code]
	local row: StoresClient.Row? = nil
	if page then
		for _, candidate in (page :: StoresClient.Page).rows do
			if candidate.id == dialog.row then
				row = candidate
			end
		end
	end

	local lines: { Line } = {}
	if not page or list.loading and #list.cards == 0 then
		table.insert(lines, { key = "Loading", kind = "note", label = "Loading…" })
	elseif not row then
		table.insert(lines, { key = "Gone", kind = "note", label = "That row has gone" })
	elseif #list.cards == 0 then
		table.insert(lines, { key = "None", kind = "note", label = "Share an outfit to Community first: its page has Share" })
	else
		local codesIn = row.outfitCodes or {}
		for _, card in list.cards do
			local lineKey = dialog.code .. "|" .. card.code
			local inside = table.find(codesIn, card.code) ~= nil
			table.insert(lines, {
				key = "Outfit" .. card.code,
				kind = "toggle",
				label = card.name,
				sub = card.code,
				on = inside,
				busy = pending[lineKey] == true,
				onToggle = function()
					run(lineKey, dialog.code, if inside then Network.Actions.Stores.RemoveOutfit else Network.Actions.Stores.AddOutfit,
						{ code = dialog.code, row = dialog.row, outfit = card.code }, "outfit")
				end,
			})
		end
	end

	local listTop = skin.px(62)
	local height = listHeight(skin, lines)
	return e(Shell, {
		t = props.t,
		height = skin.px(18) + listTop + height + skin.px(34) + skin.px(Tokens.size.ctaHeight) + skin.px(18),
		title = "Add outfits",
		sub = dialog.storeName .. " › " .. dialog.rowName,
		onClose = props.onClose,
	}, {
		List = e(Lines, { lines = lines, position = UDim2.fromOffset(0, listTop), height = height }),
		Error = e(ErrorLine, { text = problem, position = UDim2.fromOffset(0, listTop + height + skin.px(8)) }),
		Buttons = e(Buttons, nil, {
			Done = e(PillButton, {
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

-- A name box (Create store, Add row).
local function NameBox(props: {
	text: string,
	placeholder: string,
	maxLength: number,
	position: UDim2,
	onChange: (text: string) -> (),
	onSubmit: () -> (),
})
	local skin = useSkin()
	local boxRef = React.useRef(nil :: TextBox?)
	React.useEffect(function()
		-- Straight to typing.
		task.defer(function()
			if boxRef.current then
				boxRef.current:CaptureFocus()
			end
		end)
		return nil
	end, {})
	return e("Frame", {
		Position = props.position,
		Size = UDim2.new(1, 0, 0, skin.px(52)),
		BackgroundColor3 = Tokens.color.inputWell,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
		Padding = e("UIPadding", { PaddingLeft = UDim.new(0, skin.px(14)), PaddingRight = UDim.new(0, skin.px(14)) }),
		Box = e("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			Text = props.text,
			PlaceholderText = props.placeholder,
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
				if (utf8.len(text) or 0) > props.maxLength then
					text = string.sub(text, 1, (utf8.offset(text, props.maxLength + 1) or (#text + 1)) - 1)
					box.Text = text
				end
				props.onChange(text)
			end,
			[React.Event.FocusLost] = function(_box: TextBox, enterPressed: boolean)
				if enterPressed then
					props.onSubmit()
				end
			end,
		}),
	})
end

-- Send one action; `onDone` with its answer once it's back (if still open).
local function useSubmit(): (boolean, string?, (action: string, payload: any, what: string, onDone: (code: string?, row: string?) -> ()) -> ())
	local waiting, setWaiting = React.useState(false)
	local problem, setProblem = React.useState(nil :: string?)
	local alive = React.useRef(true)
	React.useEffect(function()
		alive.current = true
		return function()
			alive.current = false
		end
	end, {})
	local function submit(action: string, payload: any, what: string, onDone: (code: string?, row: string?) -> ())
		if waiting then
			return
		end
		setWaiting(true)
		setProblem(nil)
		task.spawn(function()
			local ok, code, err, row = StoresClient.act(action, payload)
			if not alive.current then
				return
			end
			setWaiting(false)
			if ok then
				Sounds.play("confirm")
				onDone(code, row)
			else
				Sounds.play("error")
				setProblem(message(err, what))
			end
		end)
	end
	return waiting, problem, submit
end

local function Create(props: { t: any, onCreated: (code: string, name: string) -> (), onClose: () -> () })
	local skin = useSkin()
	local name, setName = React.useState("")
	local waiting, problem, submit = useSubmit()

	local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
	local ready = (utf8.len(trimmed) or 0) >= StoresConfig.nameLength.min and not waiting
	local function create()
		if ready then
			submit(Network.Actions.Stores.Create, { name = trimmed }, "store", function(code: string?)
				if code then
					props.onCreated(code, trimmed)
				end
			end)
		end
	end

	local fieldTop = skin.px(62)
	local fieldHeight = skin.px(52)
	return e(Shell, {
		t = props.t,
		height = skin.px(18) + fieldTop + fieldHeight + skin.px(34) + skin.px(Tokens.size.ctaHeight) + skin.px(18),
		title = "Create store",
		sub = `Name it, then fill its rows. {StoresConfig.minItems} items and you can publish it.`,
		onClose = props.onClose,
	}, {
		Field = e(NameBox, {
			text = name,
			placeholder = "Store name",
			maxLength = StoresConfig.nameLength.max,
			position = UDim2.fromOffset(0, fieldTop),
			onChange = setName,
			onSubmit = create,
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
				onActivated = create,
			}),
		}),
	})
end

local function Dialog(props: {
	dialog: Dialog?,
	myStores: { string },
	published: { string },
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
			local element
			if dialog.kind == "pick" then
				element = e(Picker, { target = dialog.target, myStores = props.myStores, t = t, onClose = props.onClose })
			elseif dialog.kind == "outfits" then
				element = e(Outfits, { dialog = dialog, published = props.published, t = t, onClose = props.onClose })
			else
				element = e(Create, { t = t, onCreated = props.onCreated, onClose = props.onClose })
			end
			children["Dialog" .. transition.key] = element
		end
	end
	return e(React.Fragment, nil, children)
end

return {
	Dialog = Dialog,
	message = message,
}
