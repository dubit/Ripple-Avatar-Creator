--!strict

--[[
	ShareDialog (design frame 5e: Share an outfit)

	Over a dimmed screen: "Share outfit", the outfit's name, and its code,
	hidden ("OUT-••••••", blurred) until you press Reveal code. Revealing
	gives the outfit a code if it hasn't one (the server keeps it for good;
	a spinner shows while it's made). The code sits in a box you can select
	and copy yourself: Roblox experiences can't write to the clipboard (a
	divergence from the design's Copy button). It works in the Outfits
	search on any server. The QR slot is for Task 15.

	Tapping outside, Close or Back (handled by Hud, which owns the dialog)
	shuts it. It rises in and drops out.

	Props:
		outfit: { id, name, code? } | nil   nil = closed
		onReveal: (id) -> ()                ask for a code
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

local e = React.createElement

local WIDTH, HEIGHT = 460, 270
local RISE = 30

type Outfit = { id: number, name: string, code: string? }

local function Card(props: { outfit: Outfit, t: any, onReveal: (id: number) -> (), onClose: () -> () })
	local skin = useSkin()
	local revealed, setRevealed = React.useState(false)
	local code = props.outfit.code
	local waiting = revealed and code == nil
	local qr = skin.px(120)

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
				Title = e(ShadowText, { text = "Share outfit", style = { size = 20, weight = 900 } }),
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
				-- The QR code arrives with deep links (Task 15).
				Qr = e("Frame", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, skin.px(62)),
					Size = UDim2.fromOffset(qr, qr),
					BackgroundColor3 = Tokens.color.white,
					BackgroundTransparency = 0.92,
					BorderSizePixel = 0,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(12)) }),
					Text = e("TextLabel", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "QR code\ncoming soon",
						TextColor3 = Tokens.color.white,
						TextTransparency = Tokens.alpha.textDim,
						TextSize = skin.textPx(11),
						FontFace = Tokens.font(700),
					}),
				}),
				Code = e("Frame", {
					Position = UDim2.fromOffset(0, skin.px(62)),
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
							TextSize = skin.textPx(24),
							FontFace = Tokens.font(900),
						})
						else nil,
					Hidden = if not revealed
						then e("TextLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = "OUT-••••••",
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
				Hint = e("TextLabel", {
					Position = UDim2.fromOffset(0, skin.px(122)),
					Size = UDim2.new(1, -(qr + skin.px(16)), 0, skin.px(60)),
					BackgroundTransparency = 1,
					Text = if revealed and code
						then "Select the code to copy it. Anyone can type it into the Outfits search to open this outfit, on any server. It shows the outfit as it is now."
						else "Reveal a code anyone can type into the Outfits search to open this outfit.",
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
							setRevealed(true)
							if not code then
								props.onReveal(props.outfit.id)
							end
						end,
					}),
				}),
			}),
		}),
	})
end

local function ShareDialog(props: { outfit: Outfit?, onReveal: (id: number) -> (), onClose: () -> () })
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
