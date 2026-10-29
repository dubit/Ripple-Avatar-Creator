--!strict

--[[
	MusicPanel (World options › Music)

	The music player's controls, laid out in the side panel's scrolling body:

	  · now playing: the track's cover, name and mood, with spectrum bars
	    (AudioAnalyzer) that move while it plays
	  · progress: a bar you can tap or drag along to seek, with elapsed / length
	  · transport: Previous, Play / Pause (orange), Next; volume with a mute
	    shortcut (back to the last level when tapped again)
	  · the playlist: a 4x4 grid of covers. Lit (orange ring, tick) ones are in
	    the playlist; the one playing shows an equaliser. Tapping a dim one adds
	    it and plays it; tapping a lit one takes it out (the last one stays).
	    The track under the pointer is named under the grid.

	The clock, progress and spectrum update from the audio every frame with
	bindings (no re-render), and only while this is mounted.

	Props:
		music: useMusic result
		layoutOrder: number?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local views = script.Parent
local components = views:WaitForChild("components")
local hooks = views:WaitForChild("hooks")
local Tokens = require(views:WaitForChild("Tokens"))
local Press = require(views:WaitForChild("Press"))
local useSkin = require(hooks:WaitForChild("useSkin"))
local useInteraction = require(hooks:WaitForChild("useInteraction"))
local useSpring = require(hooks:WaitForChild("useSpring"))
local PillButton = require(components:WaitForChild("PillButton"))
local Icon = require(components:WaitForChild("Icon"))
local ShadowText = require(components:WaitForChild("ShadowText"))
local Slider = require(components:WaitForChild("Slider"))

local e = React.createElement

local COVER = 68 -- design px: a grid cell (four across the ~295 px body)
local COVER_GAP = 6
local NOW_COVER = 76
local BARS = 20
local BAR_GAP = 2
local SPECTRUM_HEIGHT = 26
-- Spectrum level (dB, at full volume) mapped to an empty / full bar. Music
-- falls off toward the treble, so each bar up gets TILT dB more (measured on
-- the tracks: ~30 dB from the bass bar to the top one).
local DB_FLOOR = -62
local DB_CEILING = -12
local TILT = 1.4
local FALL = 0.82 -- each frame a bar keeps this much of its height as it falls

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Spectrum bins (linear in frequency) grouped into BARS bands spaced
-- logarithmically, so the bass doesn't take one bar and the treble fifteen.
-- Every bar gets at least its own bin (the lowest bands are narrower than
-- one). `volume` is the player's, divided out so the bars don't shrink with
-- the volume slider.
local function bands(spectrum: { number }, volume: number): { number }
	local n = #spectrum
	local out = table.create(BARS, 0)
	if n < BARS + 2 or volume <= 0 then
		return out
	end
	local low, high = 2, n * 0.7 -- bin 1 is DC; the top bins are mostly empty
	local from = low
	for bar = 1, BARS do
		local to = math.max(from, math.floor(low * (high / low) ^ (bar / BARS)))
		local peak = 0
		for i = from, math.min(to, n) do
			peak = math.max(peak, spectrum[i])
		end
		local db = 20 * math.log10(peak / volume + 1e-9) + (bar - 1) * TILT
		out[bar] = math.clamp((db - DB_FLOOR) / (DB_CEILING - DB_FLOOR), 0, 1)
		from = to + 1
	end
	return out
end

local function label(text: string, style: Tokens.TypeStyle, order: number, transparency: number?)
	return e(ShadowText, { text = text, style = style, transparency = transparency, shadow = false, layoutOrder = order })
end

-- One cover in the playlist grid.
local function CoverTile(props: {
	track: any,
	selected: boolean,
	current: boolean,
	playing: boolean,
	onToggle: () -> (),
	onHover: (key: string?) -> (),
	layoutOrder: number,
})
	local skin = useSkin()
	local interaction = useInteraction()
	local press = useSpring({ v = if interaction.pressed then 1 else 0 }, Tokens.spring.press)
	local lit = useSpring({ v = if props.selected then 1 else 0 }, Tokens.spring.state)
	return e("ImageButton", {
		Size = UDim2.fromOffset(skin.px(COVER), skin.px(COVER)),
		BackgroundColor3 = Tokens.color.black,
		Image = "rbxassetid://" .. props.track.cover,
		ImageTransparency = lit.v:map(function(v: number)
			return 0.55 * (1 - v)
		end),
		AutoButtonColor = false,
		LayoutOrder = props.layoutOrder,
		[React.Event.InputBegan] = Press.began(props.onToggle),
		[React.Event.Activated] = Press.activated(props.onToggle),
		[React.Event.MouseEnter] = function()
			interaction.onEnter()
			props.onHover(props.track.key)
		end,
		[React.Event.MouseLeave] = function()
			interaction.onLeave()
			props.onHover(nil)
		end,
		[React.Event.MouseButton1Down] = interaction.onDown,
		[React.Event.MouseButton1Up] = interaction.onUp,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(10)) }),
		Scale = e("UIScale", {
			Scale = press.v:map(function(v: number)
				return 1 - 0.05 * v
			end),
		}),
		Ring = e("UIStroke", {
			Color = if props.selected or interaction.hovered then Tokens.color.accentText else Tokens.color.black,
			Thickness = skin.stroke(if props.selected then 2.5 else 1),
			Transparency = if props.selected or interaction.hovered then 0 else 0.4,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		-- In the playlist: a tick; the one playing: an equaliser.
		Mark = if props.selected
			then e("Frame", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -skin.px(4), 1, -skin.px(4)),
				Size = UDim2.fromOffset(skin.px(22), skin.px(22)),
				BackgroundColor3 = if props.current then Tokens.color.accent else Tokens.color.black,
				BackgroundTransparency = if props.current then 0 else 0.25,
				ZIndex = 2,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				Icon = e(Icon, {
					name = if props.current and props.playing then "graphic_eq" else "check",
					size = 15,
					anchorPoint = Vector2.new(0.5, 0.5),
					position = UDim2.fromScale(0.5, 0.5),
					zIndex = 3,
				}),
			})
			else nil,
	})
end

local function MusicPanel(props: { music: any, layoutOrder: number? })
	local skin = useSkin()
	local music = props.music
	local current = music.current
	local hovered, setHovered = React.useState(nil :: string?)
	local lastVolume = React.useRef(if music.volume > 0 then music.volume else 40)
	if music.volume > 0 then
		lastVolume.current = music.volume
	end

	-- Clock, progress and spectrum from the audio, every frame.
	local progress, setProgress = React.useBinding(0)
	local elapsed, setElapsed = React.useBinding("0:00")
	local length, setLength = React.useBinding("0:00")
	local levels, setLevels = React.useBinding(table.create(BARS, 0) :: { number })
	local trackRef = React.useRef(nil :: GuiObject?)
	local seeking = React.useRef(false)
	local latest = React.useRef(music)
	latest.current = music
	React.useEffect(function()
		local held = table.create(BARS, 0)
		local connection = RunService.RenderStepped:Connect(function()
			local audio = latest.current.audio()
			if not audio then
				return
			end
			local player = audio.player
			local total = player.TimeLength
			if not seeking.current then
				setProgress(if total > 0 then math.clamp(player.TimePosition / total, 0, 1) else 0)
				setElapsed(clock(player.TimePosition))
			end
			setLength(clock(total))
			local target = if player.IsPlaying then bands(audio.analyzer:GetSpectrum(), player.Volume) else table.create(BARS, 0)
			for i = 1, BARS do
				held[i] = math.max(target[i], held[i] * FALL)
			end
			setLevels(table.clone(held))
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	-- Seek: press on the bar and drag; it seeks on release.
	local function fractionAt(x: number): number
		local track = trackRef.current
		if not track or track.AbsoluteSize.X <= 0 then
			return 0
		end
		return math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
	end
	local function beginSeek(_rbx: GuiObject, input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		seeking.current = true
		setProgress(fractionAt(input.Position.X))
		local moved = UserInputService.InputChanged:Connect(function(change: InputObject)
			if change.UserInputType == Enum.UserInputType.MouseMovement or change.UserInputType == Enum.UserInputType.Touch then
				setProgress(fractionAt(change.Position.X))
			end
		end)
		local ended
		ended = UserInputService.InputEnded:Connect(function(done: InputObject)
			if done.UserInputType == Enum.UserInputType.MouseButton1 or done.UserInputType == Enum.UserInputType.Touch then
				moved:Disconnect()
				ended:Disconnect()
				seeking.current = false
				music.seek(fractionAt(done.Position.X))
			end
		end)
	end

	local bars: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(BAR_GAP)),
		}),
	}
	for i = 1, BARS do
		bars["Bar" .. i] = e("Frame", {
			Size = levels:map(function(all: { number })
				return UDim2.new(1 / BARS, -skin.px(BAR_GAP), 0, math.max(skin.px(2), all[i] * skin.px(SPECTRUM_HEIGHT)))
			end),
			BackgroundColor3 = Tokens.color.accent,
			BackgroundTransparency = levels:map(function(all: { number })
				return 0.45 - 0.45 * all[i]
			end),
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(1.5)) }),
		})
	end

	local grid: { [string]: any } = {
		Layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(skin.px(COVER), skin.px(COVER)),
			CellPadding = UDim2.fromOffset(skin.px(COVER_GAP), skin.px(COVER_GAP)),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	local hoveredTrack = nil
	for index, track in music.tracks do
		if track.key == hovered then
			hoveredTrack = track
		end
		grid[track.key] = e(CoverTile, {
			track = track,
			selected = table.find(music.playlist, track.key) ~= nil,
			current = track.key == current.key,
			playing = music.playing,
			layoutOrder = index,
			onToggle = function()
				music.toggle(track.key)
			end,
			onHover = setHovered,
		})
	end
	local rows = math.ceil(#music.tracks / 4)
	local gridHeight = rows * skin.px(COVER) + (rows - 1) * skin.px(COVER_GAP)
	local caption = if hoveredTrack
		then `{hoveredTrack.name} · {hoveredTrack.mood}`
		else `{#music.playlist} of {#music.tracks} in the playlist · tap to add or take out`

	local function round(icon: string, size: number, iconSize: number, order: number, onActivated: () -> (), active: boolean?)
		return e(PillButton, {
			variant = "round",
			size = size,
			icon = icon,
			iconSize = iconSize,
			active = active,
			layoutOrder = order,
			onActivated = onActivated,
		})
	end

	return e("Frame", {
		-- Its rows (now playing 76, progress 34, transport 52, volume 30, label 20,
		-- grid, caption 18) and the six 12 px gaps between them.
		Size = UDim2.new(1, 0, 0, skin.px(NOW_COVER + 34 + 52 + 30 + 20 + 18 + 6 * 12) + gridHeight),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
	}, {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, skin.px(12)),
		}),
		NowPlaying = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(NOW_COVER)),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Cover = e("ImageLabel", {
				Size = UDim2.fromOffset(skin.px(NOW_COVER), skin.px(NOW_COVER)),
				BackgroundColor3 = Tokens.color.black,
				Image = "rbxassetid://" .. current.cover,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, skin.px(12)) }),
				Stroke = e("UIStroke", {
					Color = Tokens.color.white,
					Transparency = 0.85,
					Thickness = skin.stroke(1),
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			}),
			Info = e("Frame", {
				Position = UDim2.fromOffset(skin.px(NOW_COVER + 12), 0),
				Size = UDim2.new(1, -skin.px(NOW_COVER + 12), 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, skin.px(2)) }),
				Name = e("TextLabel", {
					Size = UDim2.new(1, 0, 0, skin.textPx(Tokens.type.bodyStrong.size) + skin.px(4)),
					BackgroundTransparency = 1,
					Text = current.name,
					TextColor3 = Tokens.color.white,
					TextSize = skin.textPx(Tokens.type.bodyStrong.size),
					FontFace = Tokens.font(Tokens.type.bodyStrong.weight),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = 1,
				}),
				Mood = e("TextLabel", {
					Size = UDim2.new(1, 0, 0, skin.textPx(Tokens.type.meta.size) + skin.px(4)),
					BackgroundTransparency = 1,
					Text = if music.playing then current.mood else "Stopped",
					TextColor3 = if music.playing then Tokens.color.white else Tokens.color.accentText,
					TextTransparency = if music.playing then Tokens.alpha.textDim else 0,
					TextSize = skin.textPx(Tokens.type.meta.size),
					FontFace = Tokens.font(Tokens.type.meta.weight),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					LayoutOrder = 2,
				}),
				Spectrum = e("Frame", {
					Size = UDim2.new(1, 0, 0, skin.px(SPECTRUM_HEIGHT)),
					BackgroundTransparency = 1,
					LayoutOrder = 3,
				}, bars),
			}),
		}),
		Progress = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(34)),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, {
			-- The whole strip is the hit area; the bar is drawn in its middle.
			Hit = e("TextButton", {
				ref = trackRef,
				Size = UDim2.new(1, 0, 0, skin.px(18)),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
				[React.Event.InputBegan] = beginSeek,
			}, {
				Track = e("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.new(1, 0, 0, skin.px(6)),
					BackgroundColor3 = Tokens.color.inputWell,
					BorderSizePixel = 0,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
					Fill = e("Frame", {
						Size = progress:map(function(p: number)
							return UDim2.fromScale(p, 1)
						end),
						BackgroundColor3 = Tokens.color.accent,
						BorderSizePixel = 0,
					}, {
						Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
					}),
					Knob = e("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = progress:map(function(p: number)
							return UDim2.fromScale(p, 0.5)
						end),
						Size = UDim2.fromOffset(skin.px(12), skin.px(12)),
						BackgroundColor3 = Tokens.color.white,
						BorderSizePixel = 0,
					}, {
						Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
					}),
				}),
			}),
			Elapsed = e("TextLabel", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(0.5, 0, 0, skin.px(14)),
				BackgroundTransparency = 1,
				Text = elapsed,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(700),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Length = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.new(0.5, 0, 0, skin.px(14)),
				BackgroundTransparency = 1,
				Text = length,
				TextColor3 = Tokens.color.white,
				TextTransparency = Tokens.alpha.textDim,
				TextSize = skin.textPx(12),
				FontFace = Tokens.font(700),
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),
		Transport = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(52)),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, skin.px(14)),
			}),
			Previous = round("skip_previous", 40, 24, 1, music.previous),
			PlayPause = round(if music.playing then "pause" else "play_arrow", 52, 30, 2, music.playPause, true),
			Next = round("skip_next", 40, 24, 3, music.next),
		}),
		Volume = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(30)),
			BackgroundTransparency = 1,
			LayoutOrder = 4,
		}, {
			Mute = e(PillButton, {
				variant = "round",
				size = 30,
				icon = if music.volume > 0 then "volume_up" else "volume_off",
				iconSize = 18,
				anchorPoint = Vector2.new(0, 0.5),
				position = UDim2.fromScale(0, 0.5),
				sound = "tab",
				onActivated = function()
					music.commitVolume(if music.volume > 0 then 0 else lastVolume.current)
				end,
			}),
			Slider = e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, skin.px(40), 0.5, 0),
				Size = UDim2.new(1, -skin.px(40 + 44), 1, 0),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center }),
				Slider = e(Slider, {
					value = music.volume,
					min = 0,
					max = 100,
					step = 5,
					onChange = music.changeVolume,
					onCommit = music.commitVolume,
				}),
			}),
			Value = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.fromOffset(skin.px(40), skin.px(20)),
				BackgroundTransparency = 1,
				Text = math.floor(music.volume + 0.5) .. "%",
				TextColor3 = Tokens.color.accentText,
				TextSize = skin.textPx(Tokens.type.sectionLabel.size),
				FontFace = Tokens.font(800),
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),
		PlaylistLabel = e("Frame", {
			Size = UDim2.new(1, 0, 0, skin.px(20)),
			BackgroundTransparency = 1,
			LayoutOrder = 5,
		}, { Text = label("Playlist", Tokens.type.sectionLabel, 1) }),
		Grid = e("Frame", {
			Size = UDim2.new(1, 0, 0, gridHeight),
			BackgroundTransparency = 1,
			LayoutOrder = 6,
		}, grid),
		Caption = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, skin.px(18)),
			BackgroundTransparency = 1,
			Text = caption,
			TextColor3 = if hoveredTrack then Tokens.color.accentText else Tokens.color.white,
			TextTransparency = if hoveredTrack then 0 else Tokens.alpha.textSoft,
			TextSize = skin.textPx(Tokens.type.hint.size),
			FontFace = Tokens.font(Tokens.type.hint.weight),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 7,
		}),
	})
end

return MusicPanel
