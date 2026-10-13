--!strict

--[[
	ShareDialog (design frame 5e: Share an outfit)

	Over a dimmed screen: "Share outfit", the outfit's name, and its code
	(6 characters). An outfit with a code shows it (and its QR) at once;
	one without has it hidden ("••••••") until you press Reveal code,
	which gives it one (a spinner shows while it's made). The code lasts
	until the outfit is edited (then it's hidden again: reveal for a new
	one). The code sits in a box you can select
	and copy yourself: Roblox experiences can't write to the clipboard (a
	divergence from the design's Copy button). It works in the Outfits
	search on any server. Left of it, a QR of the share link (LaunchData):
	scanned with a phone, it joins the experience on this outfit's page
	(DeepLinkService). Until revealed the QR's place is an empty well.

	A code is also the outfit's Community entry: revealing lists the copy
	there for everyone to find (OutfitsController Share; Hud lists an older
	code that isn't yet when the dialog opens), and a line under the code
	says so. Once shared it stays (deleting the outfit drops your name
	from it).

	A store (kind "store") always has its code, so it shows at once: "Share
	store", and the code works in the Stores search.

	Tapping outside, Close or Back (handled by Hud, which owns the dialog)
	shuts it. It rises in and drops out.

	Props:
		outfit: { id, name, code?, kind? } | nil   nil = closed; kind "store"
		                                    for a store
		onReveal: (id) -> ()                ask for a code (and list it)
		onClose: () -> ()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent.Parent
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local useSkin = require(views:WaitForChild("hooks"):WaitForChild("useSkin"))
local useTransition = require(views:WaitForChild("hooks"):WaitForChild("useTransition"))
local PillButton = require(views:WaitForChild("components"):WaitForChild("PillButton"))
local GlassPanel = require(views:WaitForChild("components"):WaitForChild("GlassPanel"))
local ShadowText = require(views:WaitForChild("components"):WaitForChild("ShadowText"))
local Spinner = require(views:WaitForChild("components"):WaitForChild("Spinner"))
local QrTile = require(views:WaitForChild("components"):WaitForChild("QrTile"))
local Icon = require(views:WaitForChild("components"):WaitForChild("Icon"))
local SharedCodes = require(views:WaitForChild("catalogue"):WaitForChild("SharedCodes"))
local LaunchData = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("LaunchData"))

local e = React.createElement

local WIDTH, HEIGHT = 480, 300
local RISE = 30

type Callbacks = {
	onReveal: (id: number) -> (),
	onClose: () -> (),
}

type Outfit = { id: number, name: string, code: string?, kind: string? }

local function Card(props: Callbacks & { outfit: Outfit, t: any })
	local skin = useSkin()
	local pressed, setPressed = React.useState(false)
	-- (An old-format "OUT-…" code is replaced when you reveal.)
	local code = if SharedCodes.isCode(props.outfit.code) then props.outfit.code else nil
	local revealed = pressed or code ~= nil
	local waiting = revealed and code == nil
	local store = props.outfit.kind == "store"
	local qr = math.floor(skin.px(150))

	return e("TextButton", {
		Name = "ShareDialog",
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
			Size = UDim2.fromOffset(skin.px(WIDTH), skin.px(HEIGHT)),
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
				Title = e(ShadowText, { text = if store then "Share store" else "Share outfit", style = { size = 20, weight = 900 } }),
				Name = e("Frame", {
					Position = UDim2.fromOffset(0, skin.px(30)),
					Size = UDim2.new(1, 0, 0, skin.px(18)),
					BackgroundTransparency = 1,
				}, {
					Text = e(ShadowText, {
						text = props.outfit.name,
						style = Tokens.type.meta,
						transparency = Tokens.alpha.textSoft,
						shadow = false,
						maxWidth = skin.px(WIDTH - 40),
					}),
				}),
				-- The QR only once there's a code to show; until then an empty
				-- well (a dimmed QR looked ready to scan).
				Qr = if revealed and code
					then e(QrTile, {
						text = LaunchData.shareLink(code),
						size = qr,
						position = UDim2.fromOffset(0, skin.px(62)),
					})
					else e("Frame", {
						Position = UDim2.fromOffset(0, skin.px(62)),
						Size = UDim2.fromOffset(qr, qr),
						BackgroundColor3 = Tokens.color.inputWell,
						BorderSizePixel = 0,
					}, {
						Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
						Lock = if waiting
							then nil
							else e(Icon, {
								name = "lock",
								size = 30,
								transparency = 0.6,
								anchorPoint = Vector2.new(0.5, 0.5),
								position = UDim2.fromScale(0.5, 0.5),
							}),
					}),
				Code = e("Frame", {
					Position = UDim2.fromOffset(qr + skin.px(16), skin.px(62)),
					Size = UDim2.new(1, -(qr + skin.px(16)), 0, skin.px(52)),
					BackgroundColor3 = Tokens.color.inputWell,
					BorderSizePixel = 0,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(14)) }),
					Box = if revealed and code
						then e("TextBox", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							ClearTextOnFocus = false,
							TextEditable = false,
							Text = code,
							TextColor3 = Tokens.color.white,
							TextSize = skin.textPx(28),
							FontFace = Tokens.font(900),
						})
						else nil,
					Hidden = if not revealed
						then e("TextLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = "••••••",
							TextColor3 = Tokens.color.white,
							TextTransparency = 0.5,
							TextSize = skin.textPx(24),
							FontFace = Tokens.font(900),
						})
						else nil,
					Spinner = if waiting
						then e(Spinner, { size = 26, anchorPoint = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5) })
						else nil,
				}),
				Published = if revealed and code and not store
					then e("Frame", {
						Position = UDim2.fromOffset(qr + skin.px(16), skin.px(124)),
						Size = UDim2.new(1, -(qr + skin.px(16)), 0, skin.px(20)),
						BackgroundTransparency = 1,
					}, {
						Layout = e("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, skin.px(6)),
						}),
						Icon = e(Icon, { name = "check_circle", size = 18, color = Tokens.color.accentText, layoutOrder = 1 }),
						Text = e("TextLabel", {
							Size = UDim2.new(1, -skin.px(24), 1, 0),
							BackgroundTransparency = 1,
							Text = "Published to Community",
							TextColor3 = Tokens.color.accentText,
							TextSize = skin.textPx(13.5),
							FontFace = Tokens.font(800),
							TextXAlignment = Enum.TextXAlignment.Left,
							LayoutOrder = 2,
						}),
					})
					else nil,
				Hint = e("TextLabel", {
					Position = UDim2.fromOffset(qr + skin.px(16), skin.px(if revealed and code and not store then 150 else 122)),
					Size = UDim2.new(1, -(qr + skin.px(16)), 0, skin.px(90)),
					BackgroundTransparency = 1,
					Text = if store
						then "Scan the QR with a phone to open this store in Ripple, or type the code into the Stores search on any server. Select the code to copy it. The code stays with the store, even when it changes."
						elseif revealed and code
						then "Scan the QR with a phone to open this outfit in Ripple, or type the code into the Outfits search on any server. Select the code to copy it. Everyone can find it on Community, as a copy of the outfit as it is now: if you edit the outfit, share it again for a new code."
						else "Reveal a code and QR anyone can use to open this outfit. It goes on Community too, for everyone to find.",
					TextColor3 = Tokens.color.white,
					TextTransparency = Tokens.alpha.textSoft,
					TextSize = skin.textPx(12.5),
					FontFace = Tokens.font(700),
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
				Buttons = e("Frame", {
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
					Close = e(PillButton, {
						variant = "pill",
						size = Tokens.size.ctaHeight,
						width = 130,
						label = "Close",
						sound = "back",
						layoutOrder = 1,
						onActivated = props.onClose,
					}),
					Reveal = if revealed then nil else e(PillButton, {
						variant = "pill",
						size = Tokens.size.ctaHeight,
						width = 190,
						icon = "visibility",
						iconSize = 18,
						label = "Reveal code",
						active = true,
						sound = "confirm",
						layoutOrder = 2,
						onActivated = function()
							setPressed(true)
							props.onReveal(props.outfit.id) -- a code, listed (or just listed)
						end,
					}),
				}),
			}),
		}),
	})
end

local function ShareDialog(props: Callbacks & { outfit: Outfit? })
	local last = React.useRef(nil :: Outfit?)
	if props.outfit then
		last.current = props.outfit
	end
	local open = props.outfit ~= nil
	local transitions = useTransition(open, {
		from = { t = 0 },
		enter = { t = 1 },
		leave = { t = 0 },
		config = Tokens.spring.panelIn,
		leaveConfig = Tokens.spring.panelOut,
	})
	local children: { [string]: any } = {}
	for _, transition in transitions do
		local outfit = props.outfit or last.current
		if outfit then
			children["Share" .. transition.key] = e(Card, {
				outfit = outfit,
				t = transition.springProps.t,
				onReveal = props.onReveal,
				onClose = props.onClose,
			})
		end
	end
	return e(React.Fragment, nil, children)
end

return ShareDialog
