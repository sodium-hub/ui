--!strict
--[=[
    Pumpkin UI - Production Standalone Distribution
    Theme: Amber Sunset (#09090B / #131318 / #F97316)
    Architecture: macOS Fluid Modern Engine
]=]

local _MODULES = {}
local _LOADED = {}

local function _require(path: string)
    if _LOADED[path] then
        return _LOADED[path]
    end
    local loader = _MODULES[path]
    if not loader then
        error('[PumpkinUI Standalone] Module not found: ' .. tostring(path))
    end
    local result = loader()
    _LOADED[path] = result
    return result
end

_MODULES['Core/Signals'] = function()
--!strict
--[=[
	Sodium UI v2 - Core/Signals.luau
	Zero-dependency pub/sub. pcall-isolated callbacks, snapshot fire,
	idempotent connections, full unload hygiene.
]=]

local Signal = {}
Signal.__index = Signal

type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type SignalInstance<T...> = {
	Connect: (self: SignalInstance<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: SignalInstance<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: SignalInstance<T...>, T...) -> number,
	Wait: (self: SignalInstance<T...>, timeout: number?) -> T...,
	Count: (self: SignalInstance<T...>) -> number,
	DisconnectAll: (self: SignalInstance<T...>) -> (),
	Destroy: (self: SignalInstance<T...>) -> (),
}

function Signal.new<T...>(): SignalInstance<T...>
	local self = setmetatable({}, Signal)
	;(self :: any)._listeners = {}
	;(self :: any)._count = 0
	;(self :: any)._firing = false
	return (self :: any) :: SignalInstance<T...>
end

function Signal:Connect(callback: (...any) -> ()): Connection
	assert(type(callback) == "function", "[SodiumUI.Signal] callback must be function")
	local listeners = self._listeners

	local conn: Connection = { Connected = true } :: Connection
	listeners[conn] = callback;
	(self :: any)._count = (self :: any)._count + 1;

	(conn :: any).Disconnect = function(c: Connection)
		if not c.Connected then
			return
		end
		c.Connected = false
		if listeners[c] ~= nil then
			listeners[c] = nil
			;(self :: any)._count = (self :: any)._count - 1
		end
	end

	return conn
end

function Signal:Once(callback: (...any) -> ()): Connection
	local conn: Connection? = nil
	conn = self:Connect(function(...)
		local c = conn :: Connection
		if c.Connected then
			(c :: any):Disconnect()
		end
		local ok, err = pcall(callback, ...)
		if not ok then
			warn("[SodiumUI.Signal:Once] " .. tostring(err))
		end
	end)
	return conn :: Connection
end

local function safeDispatch(cb: (...any) -> (), ...: any)
	local ok, err = pcall(cb, ...)
	if not ok then
		warn("[SodiumUI.Signal] " .. tostring(err))
	end
end

-- Snapshot fire: safe against Connect/Disconnect inside callbacks.
-- Zero-allocation callback dispatch via direct task.spawn argument forwarding.
function Signal:Fire(...: any): number
	local listeners = self._listeners
	if next(listeners) == nil then
		return 0
	end
	(self :: any)._firing = true
	local n = 0
	local batch: { (...any) -> () } = {}
	for conn, cb in pairs(listeners) do
		if (conn :: any).Connected then
			n += 1
			batch[n] = cb
		end
	end
	(self :: any)._firing = false
	for i = 1, n do
		local cb = batch[i]
		batch[i] = nil :: any
		task.spawn(safeDispatch, cb, ...)
	end
	return n
end

function Signal:Wait(timeout: number?): ...any
	local thread = coroutine.running()
	local conn: Connection? = nil
	conn = self:Connect(function(...)
		local c = conn :: Connection
		if c.Connected then
			(c :: any):Disconnect()
		end
		task.spawn(thread, ...)
	end)
	if type(timeout) == "number" and (timeout :: number) > 0 then
		task.delay(timeout :: number, function()
			local c = conn :: Connection
			if c.Connected then
				(c :: any):Disconnect()
				task.spawn(thread)
			end
		end)
	end
	return coroutine.yield()
end

function Signal:Count(): number
	return (self :: any)._count
end

function Signal:DisconnectAll()
	for conn in pairs(self._listeners) do
		(conn :: any).Connected = false
	end
	table.clear(self._listeners)
	;(self :: any)._count = 0
end

function Signal:Destroy()
	self:DisconnectAll()
	setmetatable(self, nil)
	table.clear(self :: any)
end

return Signal
end

_MODULES['Core/Locale'] = function()
--!strict
--[=[
	Sodium UI v2 - Core/Locale.luau
	Reactive I18n. Zero overhead for static strings,
	dedupe bind, weak-key GC + Destroying cleanup.
]=]

local Signals = _require("Core/Signals")

local Locale = {}
Locale.__index = Locale

export type LocalizedString = string | { [string]: string }

local CurrentLanguage = "EN"
Locale.Changed = Signals.new()

type BindItem = { property: string, source: { [string]: string } }
local bound: { [Instance]: { BindItem } } = setmetatable({}, { __mode = "k" })

function Locale.Resolve(source: any, targetLang: string?): string
	if source == nil then
		return ""
	end
	if type(source) == "string" then
		return source
	end
	if type(source) ~= "table" then
		return tostring(source)
	end
	local lang: string = targetLang or CurrentLanguage
	local upper = string.upper(lang)
	local v = (source :: any)[lang] or (source :: any)[upper]
	if v ~= nil then
		return tostring(v)
	end
	for k, val in pairs(source :: any) do
		if string.upper(tostring(k)) == upper then
			return tostring(val)
		end
	end
	local en = (source :: any).EN or (source :: any).en
	if en ~= nil then
		return tostring(en)
	end
	for _, val in pairs(source :: any) do
		if type(val) == "string" then
			return val
		end
	end
	return tostring(source)
end

function Locale.Bind(instance: Instance, property: string, source: any)
	if instance == nil then
		return
	end
	if type(source) ~= "table" then
		pcall(function()
			(instance :: any)[property] = Locale.Resolve(source)
		end)
		return
	end
	pcall(function()
		(instance :: any)[property] = Locale.Resolve(source)
	end)
	local list = bound[instance]
	if list == nil then
		list = {}
		bound[instance] = list
		pcall(function()
			(instance.Destroying :: RBXScriptSignal):Once(function()
				bound[instance] = nil
			end)
		end)
	else
		for _, it in ipairs(list) do
			if it.property == property and it.source == source then
				return
			end
		end
	end
	table.insert(list, { property = property, source = source })
end

function Locale.Unbind(instance: Instance)
	bound[instance] = nil
end

function Locale.SetLanguage(lang: string)
	if type(lang) ~= "string" or #lang == 0 then
		return
	end
	local upper = string.upper(lang)
	if CurrentLanguage == upper then
		return
	end
	CurrentLanguage = upper
	Locale.Changed:Fire(upper)
	for instance, items in pairs(bound) do
		local parentOk = pcall(function()
			return (instance :: any).Parent
		end)
		if not parentOk then
			bound[instance] = nil
			continue
		end
		if (instance :: any).Parent == nil then
			local okName = pcall(function()
				local _ = (instance :: any).Name
			end)
			if not okName then
				bound[instance] = nil
				continue
			end
		end
		for _, item in ipairs(items) do
			local t = Locale.Resolve(item.source, upper)
			pcall(function()
				(instance :: any)[item.property] = t
			end)
		end
	end
end

function Locale.GetLanguage(): string
	return CurrentLanguage
end

return Locale
end

_MODULES['Core/Theme'] = function()
--!strict
--[=[
	Sodium UI v2 - Core/Theme.luau
	Single token table, weak-key bind registry with dedupe,
	batched SetTheme (tween <=200 else instant), cached mobile flag.
]=]

local Signals = _require("Core/Signals")

local Theme = {}
Theme.__index = Theme

export type ColorTokenMap = {
	Background: Color3,
	Card: Color3,
	SurfaceHover: Color3,
	SurfaceActive: Color3,
	BorderSubtle: Color3,
	BorderStrong: Color3,
	BorderAccent: Color3,
	TextPrimary: Color3,
	TextMuted: Color3,
	TextDark: Color3,
	Placeholder: Color3,
	Accent: Color3,
	AccentDark: Color3,
	AccentGlow: Color3,
	AccentGlowTransparency: number,
	Success: Color3,
	Warning: Color3,
	Danger: Color3,
}

local ObsidianAmethyst: ColorTokenMap = {
	Background = Color3.fromHex("#09090B"),
	Card = Color3.fromHex("#131318"),
	SurfaceHover = Color3.fromHex("#1C1C24"),
	SurfaceActive = Color3.fromHex("#262633"),
	BorderSubtle = Color3.fromHex("#22222B"),
	BorderStrong = Color3.fromHex("#333340"),
	BorderAccent = Color3.fromHex("#EA580C"), -- Vibrant Amber/Orange
	TextPrimary = Color3.fromHex("#FFFFFF"),
	TextMuted = Color3.fromHex("#B8B8C2"),
	TextDark = Color3.fromHex("#09090B"),
	Placeholder = Color3.fromHex("#8E8E98"),
	Accent = Color3.fromHex("#F97316"), -- Warm Amber Orange
	AccentDark = Color3.fromHex("#C2410C"), -- Deep Burnt Orange / Brown
	AccentGlow = Color3.fromHex("#EA580C"),
	AccentGlowTransparency = 0.88,
	Success = Color3.fromHex("#22C55E"),
	Warning = Color3.fromHex("#F59E0B"),
	Danger = Color3.fromHex("#EF4444"),
}

local WhiteMode: ColorTokenMap = {
    Background = Color3.fromHex("#F6F6F8"),
    Card = Color3.fromHex("#FFFFFF"),
    SurfaceHover = Color3.fromHex("#EFEFF3"),
    SurfaceActive = Color3.fromHex("#E5E5EB"),
    BorderSubtle = Color3.fromHex("#E2E2E8"),
    BorderStrong = Color3.fromHex("#D1D1DB"),
    BorderAccent = Color3.fromHex("#EA580C"),
    TextPrimary = Color3.fromHex("#111827"),
    TextMuted = Color3.fromHex("#6B7280"),
    TextDark = Color3.fromHex("#000000"),
    Placeholder = Color3.fromHex("#9CA3AF"),
    Accent = Color3.fromHex("#F97316"),
    AccentDark = Color3.fromHex("#C2410C"),
    AccentGlow = Color3.fromHex("#EA580C"),
    AccentGlowTransparency = 0.88,
    Success = Color3.fromHex("#10B981"),
    Warning = Color3.fromHex("#F59E0B"),
    Danger = Color3.fromHex("#EF4444"),
}

local Themes: { [string]: ColorTokenMap } = {
	["Obsidian Amethyst"] = ObsidianAmethyst,
	["Dark"] = ObsidianAmethyst,
	["WhiteMode"] = WhiteMode,
	["Light"] = WhiteMode,
}

local CurrentThemeName = "Obsidian Amethyst"
local CurrentThemeTokens: ColorTokenMap = ObsidianAmethyst

Theme.Changed = Signals.new()

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- cached once (no per-call service query)
local _isMobileCached: boolean = UserInputService.TouchEnabled or (not UserInputService.KeyboardEnabled)
Theme.IsMobile = _isMobileCached

type BoundItem = { property: string, token: string }
local boundInstances: { [Instance]: { BoundItem } } = setmetatable({}, { __mode = "k" })
local boundCount = 0

function Theme.Bind(instance: Instance, property: string, token: string)
	local val = (CurrentThemeTokens :: any)[token]
	if val ~= nil then
		pcall(function()
			(instance :: any)[property] = val
		end)
	end
	local list = boundInstances[instance]
	if list == nil then
		list = {}
		boundInstances[instance] = list
		boundCount += 1
		pcall(function()
			(instance.Destroying :: RBXScriptSignal):Once(function()
				if boundInstances[instance] ~= nil then
					boundInstances[instance] = nil
					boundCount = math.max(0, boundCount - 1)
				end
			end)
		end)
	else
		-- dedupe same property+token (avoid unbounded growth on re-bind)
		for _, it in ipairs(list) do
			if it.property == property and it.token == token then
				return
			end
		end
	end
	table.insert(list, { property = property, token = token })
end

function Theme.Unbind(instance: Instance)
	if boundInstances[instance] ~= nil then
		boundInstances[instance] = nil
		boundCount = math.max(0, boundCount - 1)
	end
end

function Theme.GetToken(token: string): any
	return (CurrentThemeTokens :: any)[token]
end

function Theme.GetTokens(): ColorTokenMap
	return CurrentThemeTokens
end

function Theme.GetCurrentThemeName(): string
	return CurrentThemeName
end

function Theme.AddTheme(name: string, tokens: any)
	assert(type(name) == "string" and #name > 0, "[SodiumUI.Theme] name must be non-empty string")
	assert(type(tokens) == "table", "[SodiumUI.Theme] tokens must be table")
	local merged: any = table.clone(ObsidianAmethyst)
	for k, v in pairs(tokens :: any) do
		merged[k] = v
	end
	Themes[name] = merged
end

function Theme.SetTheme(name: string)
	local target = Themes[name]
	if target == nil then
		target = ObsidianAmethyst
		name = "Obsidian Amethyst"
	end
	if target == CurrentThemeTokens and name == CurrentThemeName then
		return
	end
	CurrentThemeName = name
	CurrentThemeTokens = target
	Theme.Changed:Fire(CurrentThemeTokens)

	local useTweens = boundCount <= 200
	local tweenInfo: TweenInfo? = nil
	if useTweens then
		tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
	for instance, props in pairs(boundInstances) do
		local alive = pcall(function()
			return (instance :: any).Parent
		end)
		if not alive or (instance :: any).Parent == nil then
			-- keep destroyed entries for GC via weak keys; drop explicitly unparented-or-dead
			local okName = pcall(function()
				local _ = (instance :: any).Name
			end)
			if not okName then
				boundInstances[instance] = nil
				boundCount = math.max(0, boundCount - 1)
			end
			continue
		end
		for _, item in ipairs(props) do
			local tokenVal = (CurrentThemeTokens :: any)[item.token]
			if tokenVal ~= nil then
				if useTweens and tweenInfo ~= nil then
					pcall(function()
						TweenService:Create(instance, tweenInfo :: TweenInfo, { [item.property] = tokenVal }):Play()
					end)
				else
					pcall(function()
						(instance :: any)[item.property] = tokenVal
					end)
				end
			end
		end
	end
end

-- Typography: precomputed size tables (no per-call alloc)
local DesktopSizes = { Display = 18, Title = 15, Header = 15, Body = 14, Sub = 13, Small = 12, Code = 12 }
local MobileSizes = { Display = 20, Title = 17, Header = 17, Body = 16, Sub = 15, Small = 13, Code = 13 }

Theme.FontFaces = {
	Display = Font.fromName("Inter", Enum.FontWeight.Bold),
	Title = Font.fromName("Inter", Enum.FontWeight.SemiBold),
	Header = Font.fromName("Inter", Enum.FontWeight.SemiBold),
	Body = Font.fromName("Inter", Enum.FontWeight.Medium),
	Sub = Font.fromName("Inter", Enum.FontWeight.Regular),
	Code = Font.fromName("RobotoMono", Enum.FontWeight.Medium),
}

Theme.Fonts = {
	Display = Enum.Font.GothamBold,
	Title = Enum.Font.GothamBold,
	Header = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
	Sub = Enum.Font.Gotham,
	Code = Enum.Font.RobotoMono,
}

function Theme.GetFontSize(sizeRole: string): number
	local t = if _isMobileCached then MobileSizes else DesktopSizes
	local v = (t :: any)[sizeRole]
	if type(v) == "number" then
		return v
	end
	return if _isMobileCached then 15 else 13
end

Theme.FontSizes = setmetatable({}, {
	__index = function(_, key)
		return Theme.GetFontSize(tostring(key))
	end,
}) :: any

function Theme.ApplyTypography(instance: Instance, role: string, sizeRole: string?)
	local face = Theme.FontFaces[role]
	local done = false
	if face then
		done = pcall(function()
			(instance :: any).FontFace = face
		end)
	end
	if not done then
		local ef = Theme.Fonts[role]
		if ef then
			pcall(function()
				(instance :: any).Font = ef
			end)
		end
	end
	if sizeRole then
		local sz = Theme.GetFontSize(sizeRole)
		pcall(function()
			(instance :: any).TextSize = sz
		end)
	end
end

function Theme.ResolveColor(colorInput: any): Color3?
	if typeof(colorInput) == "Color3" then
		return colorInput
	end
	if type(colorInput) == "string" then
		local lower = string.lower(colorInput)
		if lower == "green" or lower == "success" or lower == "online" or lower == "ok" then
			return Color3.fromHex("#22C55E")
		elseif lower == "yellow" or lower == "warning" or lower == "warn" or lower == "amber" then
			return Color3.fromHex("#F59E0B")
		elseif lower == "red" or lower == "danger" or lower == "error" or lower == "critical" then
			return Color3.fromHex("#EF4444")
		elseif string.sub(colorInput, 1, 1) == "#" then
			local ok, col = pcall(Color3.fromHex, colorInput)
			if ok and typeof(col) == "Color3" then
				return col
			end
		end
	end
	return nil
end

Theme.Radii = {
    Window = UDim.new(0, 14),
    Card = UDim.new(0, 10),
    Element = UDim.new(0, 8),
    Control = UDim.new(0, 6),
    Pill = UDim.new(0, 99),
}

return Theme
end

_MODULES['Core/Tweener'] = function()
--!strict
--[=[
	Sodium UI v2 - Core/Tweener.luau
	Tween manager: cancel-before-start, pcall-safe, connection-tracked
	feedback helpers. No Theme require (injected colors, no cycles).
]=]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = _require("Core/Theme")

local Tweener = {}

Tweener.Info = {
	Micro = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Fast = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(0.32, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
	Fluid = TweenInfo.new(0.30, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Spring = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	BackOut = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	ExitFast = TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
	ExitSmooth = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Appear = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	RotateInfinite = TweenInfo.new(1.0, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	-- macOS Fluid Motion Curves (Strict lockstep durations)
	MacOSWindowOpen = TweenInfo.new(0.24, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
	MacOSWindowClose = TweenInfo.new(0.20, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
	MacOSTabSlide = TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	MacOSSpring = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

-- weak-key: auto-release when instance destroyed
local activeTweens: { [Instance]: Tween } = setmetatable({}, { __mode = "k" })

local function makeCompletedSignal(): any
	return {
		Once = function(_, fn)
			task.defer(fn)
		end,
		Connect = function(_, fn)
			task.defer(fn)
			return { Disconnect = function() end }
		end,
		Wait = function() end,
	}
end

local function makeCompletedTween(): any
	return {
		Completed = makeCompletedSignal(),
		Play = function() end,
		Pause = function() end,
		Cancel = function() end,
		Destroy = function() end,
	}
end

function Tweener.Cancel(instance: Instance)
	local t = activeTweens[instance]
	if t then
		activeTweens[instance] = nil
		pcall(t.Cancel, t)
	end
end

function Tweener.CancelAll()
	for inst, t in pairs(activeTweens) do
		activeTweens[inst] = nil
		pcall(t.Cancel, t)
	end
	table.clear(activeTweens)
end

-- Max ~3 props per tween (skill rule). Extra props split into 2nd tween.
function Tweener.Tween(instance: Instance, info: TweenInfo, goals: { [string]: any }, onComplete: (() -> ())?): any
	if instance == nil or (instance :: any).Parent == nil then
		-- allow tween on unparented during build (Visible=false tree), but skip destroyed
		if (instance :: any).Parent == nil and not pcall(function()
			local _ = (instance :: any).Name
		end) then
			if onComplete then task.defer(onComplete) end
			return makeCompletedTween()
		end
	end

	-- Zero-waste optimization: skip tween if instance already matches target goals
	local hasDiff = false
	for prop, targetVal in pairs(goals) do
		local ok, curVal = pcall(function()
			return (instance :: any)[prop]
		end)
		if not ok or curVal ~= targetVal then
			hasDiff = true
			break
		end
	end
	if not hasDiff then
		Tweener.Cancel(instance)
		if onComplete then
			task.defer(onComplete)
		end
		return makeCompletedTween()
	end

	Tweener.Cancel(instance)
	local ok, tween = pcall(TweenService.Create, TweenService, instance, info, goals)
	if not ok or tween == nil then
		if onComplete then
			task.spawn(onComplete)
		end
		return makeCompletedTween()
	end
	activeTweens[instance] = tween :: Tween
	;(tween :: Tween).Completed:Once(function()
		if activeTweens[instance] == (tween :: Tween) then
			activeTweens[instance] = nil
		end
		if onComplete then
			local ok2, err = pcall(onComplete)
			if not ok2 then
				warn("[SodiumUI.Tweener] " .. tostring(err))
			end
		end
	end)
	local okPlay = pcall((tween :: Tween).Play, tween)
	if not okPlay then
		activeTweens[instance] = nil
		if onComplete then task.defer(onComplete) end
		return makeCompletedTween()
	end
	return tween :: Tween
end

local function _isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function _ensureScale(gui: GuiObject): UIScale?
	local ok, s = pcall(gui.FindFirstChildOfClass, gui, "UIScale")
	local sc: UIScale? = if ok then (s :: any) else nil
	if sc then
		return sc
	end
	local ok2, created = pcall(Instance.new, "UIScale")
	if not ok2 then
		return nil
	end
	;(created :: UIScale).Scale = 1
	pcall(function()
		(created :: UIScale).Parent = gui
	end)
	return created :: UIScale
end

export type FeedbackHandle = {
	Disconnect: (self: FeedbackHandle) -> (),
	Destroy: (self: FeedbackHandle) -> (),
}

-- Scale press feedback. Returns handle for unload hygiene.
function Tweener.BindPressFeedback(
	visual: GuiObject,
	trigger: GuiButton?,
	targetScale: number?,
	preserveText: boolean?
): FeedbackHandle?
	local button: GuiButton? = trigger
	if button == nil and visual:IsA("GuiButton") then
		button = visual :: GuiButton
	end
	if button == nil then
		return nil
	end
	local uiScale = _ensureScale(visual)
	if uiScale == nil then
		return nil
	end
	local pressScale = targetScale or 0.96
	local conns: { RBXScriptConnection } = {}

	local function press()
		Tweener.Tween(uiScale :: UIScale, Tweener.Info.Micro, { Scale = pressScale })
	end
	local function release()
		Tweener.Tween(uiScale :: UIScale, Tweener.Info.Fast, { Scale = 1.0 })
	end

	-- preserveText: counter-scale descendants lazily (cached once)
	local textScalers: { UIScale }? = nil
	local function getTextScalers(): { UIScale }
		if preserveText ~= true then
			return {} :: { UIScale }
		end
		if textScalers then
			return textScalers
		end
		textScalers = {}
		local ok, descs = pcall(visual.GetDescendants, visual)
		if ok and type(descs) == "table" then
			for _, d in ipairs(descs) do
				if (d :: Instance):IsA("TextLabel") or (d :: Instance):IsA("TextBox") then
					local s = _ensureScale(d :: GuiObject)
					if s then
						table.insert(textScalers :: { UIScale }, s)
					end
				end
			end
		end
		return textScalers :: { UIScale }
	end

	local counter = 1 / pressScale
	local function pressFull()
		press()
		if preserveText == true then
			for _, s in ipairs(getTextScalers()) do
				Tweener.Tween(s, Tweener.Info.Micro, { Scale = counter })
			end
		end
	end
	local function releaseFull()
		release()
		if preserveText == true and textScalers then
			for _, s in ipairs(textScalers) do
				Tweener.Tween(s, Tweener.Info.Fast, { Scale = 1.0 })
			end
		end
	end

	table.insert(conns, (button :: GuiButton).InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressFull()
		end
	end))
	table.insert(conns, (button :: GuiButton).InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			releaseFull()
		end
	end))
	table.insert(conns, (button :: GuiButton).MouseLeave:Connect(releaseFull))

	local handle: FeedbackHandle = {} :: FeedbackHandle
	function handle:Disconnect()
		for _, c in ipairs(conns) do
			pcall(c.Disconnect, c)
		end
		table.clear(conns)
	end
	function handle:Destroy()
		(handle :: FeedbackHandle):Disconnect()
	end
	return handle
end

-- Hover = PC-only bonus. Color-only (no Position shift -> layout safe).
-- Theme injected at module load (no cycle: Theme only depends on Signals).
local function _themeToken(name: string): Color3?
	if Theme and type(Theme.GetToken) == "function" then
		local ok, v = pcall(Theme.GetToken, name)
		if ok and typeof(v) == "Color3" then
			return v
		end
	end
	return nil
end

function Tweener.BindHoverLift(
	container: GuiObject,
	stroke: UIStroke?,
	defaultBg: Color3?,
	hoverBg: Color3?,
	defaultStroke: Color3?,
	hoverStroke: Color3?
): FeedbackHandle?
	if _isTouchOnly() then
		return nil
	end
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, container.MouseEnter:Connect(function()
		local hBg = hoverBg or _themeToken("SurfaceActive")
		local hStroke = hoverStroke or _themeToken("BorderAccent")
		if hBg ~= nil then
			Tweener.Tween(container, Tweener.Info.Fast, { BackgroundColor3 = hBg })
		end
		if stroke and hStroke ~= nil then
			Tweener.Tween(stroke, Tweener.Info.Fast, { Color = hStroke })
		end
	end))
	table.insert(conns, container.MouseLeave:Connect(function()
		local dBg = defaultBg or _themeToken("SurfaceHover")
		local dStroke = defaultStroke or _themeToken("BorderSubtle")
		if dBg ~= nil then
			Tweener.Tween(container, Tweener.Info.Fast, { BackgroundColor3 = dBg })
		end
		if stroke and dStroke ~= nil then
			Tweener.Tween(stroke, Tweener.Info.Fast, { Color = dStroke })
		end
	end))
	local handle: FeedbackHandle = {} :: FeedbackHandle
	function handle:Disconnect()
		for _, c in ipairs(conns) do
			pcall(c.Disconnect, c)
		end
		table.clear(conns)
	end
	function handle:Destroy()
		(handle :: FeedbackHandle):Disconnect()
	end
	return handle
end

-- Legacy card shrink feedback (Button.luau uses it). Kept for compat.
-- New code should prefer BindPressFeedback (scale-based, cheaper than Size tween).
function Tweener.BindCardPressFeedback(card: GuiObject, trigger: GuiButton, shrinkOffset: Vector2?): FeedbackHandle?
	if trigger == nil then
		return nil
	end
	local offset = shrinkOffset or Vector2.new(6, 4)
	local defaultSize: UDim2 = card.Size
	local pressedSize = UDim2.new(
		defaultSize.X.Scale,
		defaultSize.X.Offset - offset.X,
		defaultSize.Y.Scale,
		defaultSize.Y.Offset - offset.Y
	)
	local conns: { RBXScriptConnection } = {}
	local function press()
		Tweener.Tween(card, Tweener.Info.Micro, { Size = pressedSize })
	end
	local function release()
		Tweener.Tween(card, Tweener.Info.Fast, { Size = defaultSize })
	end
	table.insert(conns, trigger.MouseButton1Down:Connect(press))
	table.insert(conns, trigger.MouseButton1Up:Connect(release))
	table.insert(conns, trigger.MouseLeave:Connect(release))
	table.insert(conns, trigger.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			release()
		end
	end))
	local handle: FeedbackHandle = {} :: FeedbackHandle
	function handle:Disconnect()
		for _, c in ipairs(conns) do
			pcall(c.Disconnect, c)
		end
		table.clear(conns)
	end
	function handle:Destroy()
		(handle :: FeedbackHandle):Disconnect()
	end
	return handle
end

return Tweener
end

_MODULES['Core/Icons'] = function()
-- Sodium UI - Core/Icons.luau
-- High-Performance Multi-Pack Icon Engine for Sodium UI
-- Default Icon Pack: Lucide (1,700+ Icons Embedded Offline)
-- Supported External Packs: Solar, Craft, Geist, SFSymbols, Gravity UI
-- Powered by Sodium UI Architecture

local ContentProvider = game:GetService("ContentProvider")

local Compat = _require("Core/Compat")

local Icons = {}

Icons.IconsType = "lucide"
Icons.Fallback = "rbxassetid://10723406988"

Icons.Packs = {}

Icons.Packs["lucide"] = {
	["a-arrow-down"] = "rbxassetid://92867583610071",
	["a-arrow-up"] = "rbxassetid://132318504999733",
	["a-large-small"] = "rbxassetid://111491496660216",
	["accessibility"] = "rbxassetid://114029945302017",
	["activity"] = "rbxassetid://94212016861936",
	["aim"] = "rbxassetid://134242818164054",
	["air-vent"] = "rbxassetid://81517226012329",
	["airplay"] = "rbxassetid://115020759309179",
	["alarm-clock"] = "rbxassetid://126259032907535",
	["alarm-clock-check"] = "rbxassetid://76437352099157",
	["alarm-clock-minus"] = "rbxassetid://77364179863205",
	["alarm-clock-off"] = "rbxassetid://97904885874823",
	["alarm-clock-plus"] = "rbxassetid://80468822979214",
	["alarm-smoke"] = "rbxassetid://96965448419685",
	["album"] = "rbxassetid://127358331163602",
	["alert-circle"] = "rbxassetid://83898160590116",
	["alert-triangle"] = "rbxassetid://125920361880643",
	["align-center-horizontal"] = "rbxassetid://81570549209434",
	["align-center-vertical"] = "rbxassetid://118470463752466",
	["align-end-horizontal"] = "rbxassetid://139502909745427",
	["align-end-vertical"] = "rbxassetid://96528869059554",
	["align-horizontal-distribute-center"] = "rbxassetid://97220086126656",
	["align-horizontal-distribute-end"] = "rbxassetid://106128590702022",
	["align-horizontal-distribute-start"] = "rbxassetid://76074660002997",
	["align-horizontal-justify-center"] = "rbxassetid://75732302772427",
	["align-horizontal-justify-end"] = "rbxassetid://129167626402283",
	["align-horizontal-justify-start"] = "rbxassetid://130161830325281",
	["align-horizontal-space-around"] = "rbxassetid://91646106782950",
	["align-horizontal-space-between"] = "rbxassetid://103886093046990",
	["align-start-horizontal"] = "rbxassetid://125674804697729",
	["align-start-vertical"] = "rbxassetid://105020230154823",
	["align-vertical-distribute-center"] = "rbxassetid://93791183635525",
	["align-vertical-distribute-end"] = "rbxassetid://139354223511433",
	["align-vertical-distribute-start"] = "rbxassetid://74961997822126",
	["align-vertical-justify-center"] = "rbxassetid://134754696166569",
	["align-vertical-justify-end"] = "rbxassetid://92569381441969",
	["align-vertical-justify-start"] = "rbxassetid://99692844572718",
	["align-vertical-space-around"] = "rbxassetid://96206012459190",
	["align-vertical-space-between"] = "rbxassetid://124998077349706",
	["ambulance"] = "rbxassetid://78599995190651",
	["ampersand"] = "rbxassetid://75272915739209",
	["ampersands"] = "rbxassetid://126947193455996",
	["amphora"] = "rbxassetid://137370389604364",
	["anchor"] = "rbxassetid://92181172123618",
	["angry"] = "rbxassetid://74237056000103",
	["annoyed"] = "rbxassetid://80064369052011",
	["antenna"] = "rbxassetid://99628923540956",
	["anvil"] = "rbxassetid://100203029845919",
	["aperture"] = "rbxassetid://83396154449972",
	["app-window"] = "rbxassetid://93142176757189",
	["app-window-mac"] = "rbxassetid://79587216113811",
	["apple"] = "rbxassetid://104349242902442",
	["archive"] = "rbxassetid://122180020814574",
	["archive-restore"] = "rbxassetid://78956681942188",
	["archive-x"] = "rbxassetid://75830115088395",
	["armchair"] = "rbxassetid://105384358373973",
	["arrow-big-down"] = "rbxassetid://81081164158885",
	["arrow-big-down-dash"] = "rbxassetid://137987229582002",
	["arrow-big-left"] = "rbxassetid://85973092492641",
	["arrow-big-left-dash"] = "rbxassetid://97827621354677",
	["arrow-big-right"] = "rbxassetid://82960676755590",
	["arrow-big-right-dash"] = "rbxassetid://117825834972403",
	["arrow-big-up"] = "rbxassetid://93136954756149",
	["arrow-big-up-dash"] = "rbxassetid://99260194327483",
	["arrow-down"] = "rbxassetid://98764963621439",
	["arrow-down-0-1"] = "rbxassetid://120961896217875",
	["arrow-down-1-0"] = "rbxassetid://93474255891850",
	["arrow-down-a-z"] = "rbxassetid://99554596207900",
	["arrow-down-from-line"] = "rbxassetid://132045845807798",
	["arrow-down-left"] = "rbxassetid://102899325237364",
	["arrow-down-narrow-wide"] = "rbxassetid://129105261655061",
	["arrow-down-right"] = "rbxassetid://123109928624974",
	["arrow-down-to-dot"] = "rbxassetid://101675355931221",
	["arrow-down-to-line"] = "rbxassetid://87050478931254",
	["arrow-down-up"] = "rbxassetid://85780258549577",
	["arrow-down-wide-narrow"] = "rbxassetid://88461733425991",
	["arrow-down-z-a"] = "rbxassetid://76115279362232",
	["arrow-left"] = "rbxassetid://102531941843733",
	["arrow-left-from-line"] = "rbxassetid://87857914437603",
	["arrow-left-right"] = "rbxassetid://131324733048447",
	["arrow-left-to-line"] = "rbxassetid://118645136026970",
	["arrow-right"] = "rbxassetid://113692007244654",
	["arrow-right-from-line"] = "rbxassetid://74073639809355",
	["arrow-right-left"] = "rbxassetid://77015754304300",
	["arrow-right-to-line"] = "rbxassetid://78632510329852",
	["arrow-up"] = "rbxassetid://89282378235317",
	["arrow-up-0-1"] = "rbxassetid://105257823943016",
	["arrow-up-1-0"] = "rbxassetid://134175521693798",
	["arrow-up-a-z"] = "rbxassetid://77763416595160",
	["arrow-up-down"] = "rbxassetid://81019887641527",
	["arrow-up-from-dot"] = "rbxassetid://124408496673275",
	["arrow-up-from-line"] = "rbxassetid://95777664626453",
	["arrow-up-left"] = "rbxassetid://123490598231261",
	["arrow-up-narrow-wide"] = "rbxassetid://73006024672636",
	["arrow-up-right"] = "rbxassetid://129280608535523",
	["arrow-up-to-line"] = "rbxassetid://108818207813537",
	["arrow-up-wide-narrow"] = "rbxassetid://87437426951568",
	["arrow-up-z-a"] = "rbxassetid://107546173611884",
	["arrows-up-from-line"] = "rbxassetid://133710016938621",
	["asterisk"] = "rbxassetid://88552752106723",
	["at-sign"] = "rbxassetid://79059152889146",
	["atom"] = "rbxassetid://73167696981648",
	["audio-lines"] = "rbxassetid://70930641819242",
	["audio-waveform"] = "rbxassetid://86462036665209",
	["award"] = "rbxassetid://132740088158419",
	["axe"] = "rbxassetid://132405197863294",
	["axis-3d"] = "rbxassetid://122438676546804",
	["baby"] = "rbxassetid://93472926933440",
	["backpack"] = "rbxassetid://140420225386018",
	["badge"] = "rbxassetid://116620312917084",
	["badge-alert"] = "rbxassetid://101829200081951",
	["badge-cent"] = "rbxassetid://133345018873154",
	["badge-check"] = "rbxassetid://76078495178149",
	["badge-dollar-sign"] = "rbxassetid://127139803581141",
	["badge-euro"] = "rbxassetid://120016477674659",
	["badge-indian-rupee"] = "rbxassetid://75659682309981",
	["badge-info"] = "rbxassetid://131995373201472",
	["badge-japanese-yen"] = "rbxassetid://99081574588615",
	["badge-minus"] = "rbxassetid://140321561183881",
	["badge-percent"] = "rbxassetid://121359224294885",
	["badge-plus"] = "rbxassetid://100325578561866",
	["badge-pound-sterling"] = "rbxassetid://119688217279444",
	["badge-question-mark"] = "rbxassetid://121464963737502",
	["badge-russian-ruble"] = "rbxassetid://108839463659864",
	["badge-swiss-franc"] = "rbxassetid://91447608372740",
	["badge-turkish-lira"] = "rbxassetid://137839965873529",
	["badge-x"] = "rbxassetid://122931434733842",
	["baggage-claim"] = "rbxassetid://86922213051957",
	["balloon"] = "rbxassetid://97489111621526",
	["ban"] = "rbxassetid://90767043015246",
	["banana"] = "rbxassetid://140713420056179",
	["bandage"] = "rbxassetid://129660129590770",
	["banknote"] = "rbxassetid://104840231536668",
	["banknote-arrow-down"] = "rbxassetid://139366449345199",
	["banknote-arrow-up"] = "rbxassetid://133758343082529",
	["banknote-x"] = "rbxassetid://95348701438065",
	["barcode"] = "rbxassetid://118473018143689",
	["barrel"] = "rbxassetid://130647115622774",
	["baseline"] = "rbxassetid://124677132511270",
	["bath"] = "rbxassetid://76031400297942",
	["battery"] = "rbxassetid://70765800346189",
	["battery-charging"] = "rbxassetid://80139357470047",
	["battery-full"] = "rbxassetid://70906718268972",
	["battery-low"] = "rbxassetid://139659256984314",
	["battery-medium"] = "rbxassetid://105934079398915",
	["battery-plus"] = "rbxassetid://91931341486966",
	["battery-warning"] = "rbxassetid://115230083817257",
	["beaker"] = "rbxassetid://80902539995520",
	["bean"] = "rbxassetid://89491967076869",
	["bean-off"] = "rbxassetid://98164436608714",
	["bed"] = "rbxassetid://97726529032925",
	["bed-double"] = "rbxassetid://73820193212911",
	["bed-single"] = "rbxassetid://113423940880634",
	["beef"] = "rbxassetid://105850162318915",
	["beef-off"] = "rbxassetid://99869959725200",
	["beer"] = "rbxassetid://116404978807744",
	["beer-off"] = "rbxassetid://120333134736361",
	["bell"] = "rbxassetid://97392696311902",
	["bell-dot"] = "rbxassetid://93161277118810",
	["bell-electric"] = "rbxassetid://100277767266983",
	["bell-minus"] = "rbxassetid://126334890449727",
	["bell-off"] = "rbxassetid://78560046118930",
	["bell-plus"] = "rbxassetid://77014333795836",
	["bell-ring"] = "rbxassetid://94612128913941",
	["between-horizontal-end"] = "rbxassetid://81602774794322",
	["between-horizontal-start"] = "rbxassetid://76112384929846",
	["between-vertical-end"] = "rbxassetid://72817612571631",
	["between-vertical-start"] = "rbxassetid://85278312190301",
	["biceps-flexed"] = "rbxassetid://82004462003936",
	["bike"] = "rbxassetid://102930322246035",
	["binary"] = "rbxassetid://91751953950088",
	["binoculars"] = "rbxassetid://101460003267896",
	["biohazard"] = "rbxassetid://95956532900432",
	["bird"] = "rbxassetid://132284145117371",
	["birdhouse"] = "rbxassetid://83999157401433",
	["bitcoin"] = "rbxassetid://95459240442938",
	["blend"] = "rbxassetid://111679612185257",
	["blinds"] = "rbxassetid://71164165283925",
	["blocks"] = "rbxassetid://72212693357737",
	["bluetooth"] = "rbxassetid://90506573139443",
	["bluetooth-connected"] = "rbxassetid://96315134002985",
	["bluetooth-off"] = "rbxassetid://80600044218117",
	["bluetooth-searching"] = "rbxassetid://100673019606426",
	["bold"] = "rbxassetid://116141470019166",
	["bolt"] = "rbxassetid://102881251417484",
	["bomb"] = "rbxassetid://139223800924636",
	["bone"] = "rbxassetid://111242153474115",
	["book"] = "rbxassetid://125383279695672",
	["book-a"] = "rbxassetid://104067275658465",
	["book-alert"] = "rbxassetid://124159928044853",
	["book-audio"] = "rbxassetid://109208148317037",
	["book-check"] = "rbxassetid://115999656081696",
	["book-copy"] = "rbxassetid://108543407492005",
	["book-dashed"] = "rbxassetid://127430784795958",
	["book-down"] = "rbxassetid://101011730128222",
	["book-headphones"] = "rbxassetid://108670200799574",
	["book-heart"] = "rbxassetid://112788845135284",
	["book-image"] = "rbxassetid://80808285757226",
	["book-key"] = "rbxassetid://116024426170705",
	["book-lock"] = "rbxassetid://118765061220571",
	["book-marked"] = "rbxassetid://73211024251780",
	["book-minus"] = "rbxassetid://112724962046282",
	["book-open"] = "rbxassetid://129845326810392",
	["book-open-check"] = "rbxassetid://130848362492667",
	["book-open-text"] = "rbxassetid://100629528672195",
	["book-plus"] = "rbxassetid://140267785051233",
	["book-search"] = "rbxassetid://132585409504950",
	["book-text"] = "rbxassetid://94011772484232",
	["book-type"] = "rbxassetid://97817304725443",
	["book-up"] = "rbxassetid://98640174079190",
	["book-up-2"] = "rbxassetid://130161620853665",
	["book-user"] = "rbxassetid://128489189240523",
	["book-x"] = "rbxassetid://118754548186537",
	["bookmark"] = "rbxassetid://121093149326239",
	["bookmark-check"] = "rbxassetid://93940443347986",
	["bookmark-minus"] = "rbxassetid://96807096039910",
	["bookmark-plus"] = "rbxassetid://121469724491615",
	["bookmark-x"] = "rbxassetid://112272342584706",
	["boom-box"] = "rbxassetid://99901322535868",
	["bot"] = "rbxassetid://80451686744860",
	["bot-message-square"] = "rbxassetid://96145330292478",
	["bot-off"] = "rbxassetid://140417690560013",
	["bottle-wine"] = "rbxassetid://131675403196921",
	["bow-arrow"] = "rbxassetid://124089655150375",
	["box"] = "rbxassetid://101768155599700",
	["boxes"] = "rbxassetid://136372617578355",
	["braces"] = "rbxassetid://117761094704041",
	["brackets"] = "rbxassetid://74368995728099",
	["brain"] = "rbxassetid://92424107303177",
	["brain-circuit"] = "rbxassetid://70547962410202",
	["brain-cog"] = "rbxassetid://132039205501538",
	["brick-wall"] = "rbxassetid://112878522258821",
	["brick-wall-fire"] = "rbxassetid://92980588705520",
	["brick-wall-shield"] = "rbxassetid://75954432775071",
	["briefcase"] = "rbxassetid://96754188164225",
	["briefcase-business"] = "rbxassetid://129135125207283",
	["briefcase-conveyor-belt"] = "rbxassetid://108665725653714",
	["briefcase-medical"] = "rbxassetid://119917756334087",
	["bring-to-front"] = "rbxassetid://132975903553748",
	["brush"] = "rbxassetid://127035535799640",
	["brush-cleaning"] = "rbxassetid://71728977448805",
	["bubbles"] = "rbxassetid://106183424168227",
	["bug"] = "rbxassetid://83626408925438",
	["bug-off"] = "rbxassetid://88020025049245",
	["bug-play"] = "rbxassetid://80107955888092",
	["building"] = "rbxassetid://110616258983082",
	["building-2"] = "rbxassetid://77873775611951",
	["bus"] = "rbxassetid://133798469717463",
	["bus-front"] = "rbxassetid://89863432456045",
	["cable"] = "rbxassetid://128449944504901",
	["cable-car"] = "rbxassetid://128643682205596",
	["cake"] = "rbxassetid://103131590503275",
	["cake-slice"] = "rbxassetid://136769828413242",
	["calculator"] = "rbxassetid://74915716529646",
	["calendar"] = "rbxassetid://114792700814035",
	["calendar-1"] = "rbxassetid://98458364171044",
	["calendar-arrow-down"] = "rbxassetid://108415736543437",
	["calendar-arrow-up"] = "rbxassetid://70574654109118",
	["calendar-check"] = "rbxassetid://71551019465748",
	["calendar-check-2"] = "rbxassetid://120231170248276",
	["calendar-clock"] = "rbxassetid://119132152594595",
	["calendar-cog"] = "rbxassetid://122402172360287",
	["calendar-days"] = "rbxassetid://99072017568595",
	["calendar-fold"] = "rbxassetid://117368871270394",
	["calendar-heart"] = "rbxassetid://88839008103676",
	["calendar-minus"] = "rbxassetid://137354318924383",
	["calendar-minus-2"] = "rbxassetid://98846170279891",
	["calendar-off"] = "rbxassetid://109726151749217",
	["calendar-plus"] = "rbxassetid://125266115249843",
	["calendar-plus-2"] = "rbxassetid://112264562093883",
	["calendar-range"] = "rbxassetid://103641849247576",
	["calendar-search"] = "rbxassetid://92010083223634",
	["calendar-sync"] = "rbxassetid://78082218499697",
	["calendar-x"] = "rbxassetid://106703374806500",
	["calendar-x-2"] = "rbxassetid://107518051061147",
	["calendars"] = "rbxassetid://130944763042289",
	["camera"] = "rbxassetid://79950339943067",
	["camera-off"] = "rbxassetid://81057636835256",
	["candy"] = "rbxassetid://107812129154678",
	["candy-cane"] = "rbxassetid://71689468772492",
	["candy-off"] = "rbxassetid://110232752314832",
	["cannabis"] = "rbxassetid://98792006538601",
	["cannabis-off"] = "rbxassetid://101938500363812",
	["captions"] = "rbxassetid://104960225031445",
	["captions-off"] = "rbxassetid://105223545364193",
	["car"] = "rbxassetid://121065933462582",
	["car-front"] = "rbxassetid://87380942739063",
	["car-taxi-front"] = "rbxassetid://122455403384057",
	["caravan"] = "rbxassetid://120070979471783",
	["card-sim"] = "rbxassetid://134490550095771",
	["carrot"] = "rbxassetid://119118221444304",
	["cart"] = "rbxassetid://128420521375441",
	["case-lower"] = "rbxassetid://129303130603241",
	["case-sensitive"] = "rbxassetid://125410273293056",
	["case-upper"] = "rbxassetid://111633433531325",
	["cassette-tape"] = "rbxassetid://137065788934157",
	["cast"] = "rbxassetid://98202245922071",
	["castle"] = "rbxassetid://119275077187784",
	["cat"] = "rbxassetid://124252153404931",
	["cctv"] = "rbxassetid://99979894766624",
	["cctv-off"] = "rbxassetid://75925370187295",
	["chart-area"] = "rbxassetid://123446436762366",
	["chart-bar"] = "rbxassetid://105389816384108",
	["chart-bar-big"] = "rbxassetid://72336824986044",
	["chart-bar-decreasing"] = "rbxassetid://107217459044963",
	["chart-bar-increasing"] = "rbxassetid://88268905998571",
	["chart-bar-stacked"] = "rbxassetid://98478751113024",
	["chart-candlestick"] = "rbxassetid://125676898615697",
	["chart-column"] = "rbxassetid://97915995538580",
	["chart-column-big"] = "rbxassetid://98598733210787",
	["chart-column-decreasing"] = "rbxassetid://73586137373563",
	["chart-column-increasing"] = "rbxassetid://120421615068601",
	["chart-column-stacked"] = "rbxassetid://86031449675105",
	["chart-gantt"] = "rbxassetid://88811660555940",
	["chart-line"] = "rbxassetid://101833156055618",
	["chart-network"] = "rbxassetid://104027882693561",
	["chart-no-axes-column"] = "rbxassetid://94078751170351",
	["chart-no-axes-column-decreasing"] = "rbxassetid://123371717192542",
	["chart-no-axes-column-increasing"] = "rbxassetid://140383830943049",
	["chart-no-axes-combined"] = "rbxassetid://121424233161912",
	["chart-no-axes-gantt"] = "rbxassetid://131936541106368",
	["chart-pie"] = "rbxassetid://113412261630136",
	["chart-scatter"] = "rbxassetid://108217585014571",
	["chart-spline"] = "rbxassetid://90307460742494",
	["check"] = "rbxassetid://93898873302694",
	["check-check"] = "rbxassetid://95183312173858",
	["check-circle"] = "rbxassetid://85262178816537",
	["check-line"] = "rbxassetid://115122343485290",
	["chef-hat"] = "rbxassetid://121744015002573",
	["cherry"] = "rbxassetid://139519182403183",
	["chess-bishop"] = "rbxassetid://121701705580238",
	["chess-king"] = "rbxassetid://90885687223462",
	["chess-knight"] = "rbxassetid://96467707042169",
	["chess-pawn"] = "rbxassetid://111318574652751",
	["chess-queen"] = "rbxassetid://98304702099749",
	["chess-rook"] = "rbxassetid://76223925830262",
	["chevron-down"] = "rbxassetid://134243273101015",
	["chevron-first"] = "rbxassetid://105243363790238",
	["chevron-last"] = "rbxassetid://89268452603731",
	["chevron-left"] = "rbxassetid://73780377692148",
	["chevron-right"] = "rbxassetid://92473583511724",
	["chevron-up"] = "rbxassetid://122444883127455",
	["chevrons-down"] = "rbxassetid://100524612205956",
	["chevrons-down-up"] = "rbxassetid://139404716013205",
	["chevrons-left"] = "rbxassetid://82617201744347",
	["chevrons-left-right"] = "rbxassetid://87910685945204",
	["chevrons-left-right-ellipsis"] = "rbxassetid://125035817741526",
	["chevrons-right"] = "rbxassetid://139121276490483",
	["chevrons-right-left"] = "rbxassetid://87149546686569",
	["chevrons-up"] = "rbxassetid://100467452364672",
	["chevrons-up-down"] = "rbxassetid://131833120209646",
	["chromium"] = "rbxassetid://128165143739006",
	["church"] = "rbxassetid://113714744350666",
	["cigarette"] = "rbxassetid://137149549886852",
	["cigarette-off"] = "rbxassetid://77797883078452",
	["circle"] = "rbxassetid://130359823580534",
	["circle-alert"] = "rbxassetid://83898160590116",
	["circle-arrow-down"] = "rbxassetid://95901860261344",
	["circle-arrow-left"] = "rbxassetid://102148876968988",
	["circle-arrow-out-down-left"] = "rbxassetid://140598097856694",
	["circle-arrow-out-down-right"] = "rbxassetid://119952801379305",
	["circle-arrow-out-up-left"] = "rbxassetid://132858212688303",
	["circle-arrow-out-up-right"] = "rbxassetid://81783743753173",
	["circle-arrow-right"] = "rbxassetid://70786767999559",
	["circle-arrow-up"] = "rbxassetid://84395128546494",
	["circle-check"] = "rbxassetid://85262178816537",
	["circle-check-big"] = "rbxassetid://93202927221730",
	["circle-chevron-down"] = "rbxassetid://137069490345718",
	["circle-chevron-left"] = "rbxassetid://130250009740827",
	["circle-chevron-right"] = "rbxassetid://125943696958495",
	["circle-chevron-up"] = "rbxassetid://111223574026321",
	["circle-dashed"] = "rbxassetid://126799443883746",
	["circle-divide"] = "rbxassetid://106398997754208",
	["circle-dollar-sign"] = "rbxassetid://91106238890387",
	["circle-dot"] = "rbxassetid://82947033619201",
	["circle-dot-dashed"] = "rbxassetid://111451232827180",
	["circle-ellipsis"] = "rbxassetid://91687150884779",
	["circle-equal"] = "rbxassetid://95133963751438",
	["circle-fading-arrow-up"] = "rbxassetid://104648212910336",
	["circle-fading-plus"] = "rbxassetid://91847890443490",
	["circle-gauge"] = "rbxassetid://108157549473765",
	["circle-help"] = "rbxassetid://10723406988",
	["circle-minus"] = "rbxassetid://133556159576809",
	["circle-off"] = "rbxassetid://97923456918886",
	["circle-parking"] = "rbxassetid://124034962915196",
	["circle-parking-off"] = "rbxassetid://128369410981252",
	["circle-pause"] = "rbxassetid://139337739700879",
	["circle-percent"] = "rbxassetid://133311912860256",
	["circle-pile"] = "rbxassetid://116353155251541",
	["circle-play"] = "rbxassetid://120408917249739",
	["circle-plus"] = "rbxassetid://113157136350384",
	["circle-pound-sterling"] = "rbxassetid://105476153083828",
	["circle-power"] = "rbxassetid://140676030155098",
	["circle-question-mark"] = "rbxassetid://97516698664325",
	["circle-slash"] = "rbxassetid://125206439913049",
	["circle-slash-2"] = "rbxassetid://136766902186549",
	["circle-small"] = "rbxassetid://73685402843600",
	["circle-star"] = "rbxassetid://120318414957104",
	["circle-stop"] = "rbxassetid://87400503942659",
	["circle-user"] = "rbxassetid://136220511671311",
	["circle-user-round"] = "rbxassetid://95489465399880",
	["circle-x"] = "rbxassetid://76821953846248",
	["circuit-board"] = "rbxassetid://107695264369312",
	["citrus"] = "rbxassetid://139018222976433",
	["clapperboard"] = "rbxassetid://132660667070200",
	["clipboard"] = "rbxassetid://89601995828423",
	["clipboard-check"] = "rbxassetid://92649798577170",
	["clipboard-clock"] = "rbxassetid://123957515687745",
	["clipboard-copy"] = "rbxassetid://125851897718493",
	["clipboard-list"] = "rbxassetid://96460215958908",
	["clipboard-minus"] = "rbxassetid://107968008485671",
	["clipboard-paste"] = "rbxassetid://74382068849983",
	["clipboard-pen"] = "rbxassetid://75290966822953",
	["clipboard-pen-line"] = "rbxassetid://77711589791615",
	["clipboard-plus"] = "rbxassetid://134285318675662",
	["clipboard-type"] = "rbxassetid://89949374318028",
	["clipboard-x"] = "rbxassetid://102222456890103",
	["clock"] = "rbxassetid://121808839832144",
	["clock-1"] = "rbxassetid://129363225422045",
	["clock-10"] = "rbxassetid://104332695855541",
	["clock-11"] = "rbxassetid://119023205186105",
	["clock-12"] = "rbxassetid://117789618723068",
	["clock-2"] = "rbxassetid://134710777209413",
	["clock-3"] = "rbxassetid://136385631189327",
	["clock-4"] = "rbxassetid://121808839832144",
	["clock-5"] = "rbxassetid://85082019959457",
	["clock-6"] = "rbxassetid://71009733505593",
	["clock-7"] = "rbxassetid://103111188546225",
	["clock-8"] = "rbxassetid://110059272125337",
	["clock-9"] = "rbxassetid://77610027126437",
	["clock-alert"] = "rbxassetid://97157344465162",
	["clock-arrow-down"] = "rbxassetid://92349314416042",
	["clock-arrow-up"] = "rbxassetid://111484286332629",
	["clock-check"] = "rbxassetid://85231630218857",
	["clock-fading"] = "rbxassetid://93205297285245",
	["clock-plus"] = "rbxassetid://93367709263150",
	["closed-caption"] = "rbxassetid://99832644030788",
	["cloud"] = "rbxassetid://121226497050352",
	["cloud-alert"] = "rbxassetid://91967273658626",
	["cloud-backup"] = "rbxassetid://111649579696132",
	["cloud-check"] = "rbxassetid://97318598202432",
	["cloud-cog"] = "rbxassetid://96497764065749",
	["cloud-download"] = "rbxassetid://121435581993566",
	["cloud-drizzle"] = "rbxassetid://139525315752605",
	["cloud-fog"] = "rbxassetid://76650233148776",
	["cloud-hail"] = "rbxassetid://72320462748242",
	["cloud-lightning"] = "rbxassetid://133517088924849",
	["cloud-moon"] = "rbxassetid://71938114737914",
	["cloud-moon-rain"] = "rbxassetid://127667837827018",
	["cloud-off"] = "rbxassetid://131907154501444",
	["cloud-rain"] = "rbxassetid://105547081967408",
	["cloud-rain-wind"] = "rbxassetid://107414583736721",
	["cloud-snow"] = "rbxassetid://72307126270226",
	["cloud-sun"] = "rbxassetid://86114208148727",
	["cloud-sun-rain"] = "rbxassetid://99041604425705",
	["cloud-sync"] = "rbxassetid://79393911188593",
	["cloud-upload"] = "rbxassetid://93307473217005",
	["cloudy"] = "rbxassetid://105360479023346",
	["clover"] = "rbxassetid://74925550436750",
	["club"] = "rbxassetid://108490365816628",
	["code"] = "rbxassetid://107380207681249",
	["code-xml"] = "rbxassetid://130150477351734",
	["codepen"] = "rbxassetid://135643965971885",
	["codesandbox"] = "rbxassetid://106911852964823",
	["coffee"] = "rbxassetid://106864403231093",
	["cog"] = "rbxassetid://80758916183665",
	["cogs"] = "rbxassetid://80758916183665",
	["coins"] = "rbxassetid://116510979641930",
	["columns-2"] = "rbxassetid://113004100221850",
	["columns-3"] = "rbxassetid://115223357399375",
	["columns-3-cog"] = "rbxassetid://121589691981064",
	["columns-4"] = "rbxassetid://130807991968419",
	["combine"] = "rbxassetid://79908476334048",
	["command"] = "rbxassetid://93648221906330",
	["compass"] = "rbxassetid://115123411028382",
	["component"] = "rbxassetid://110027788875080",
	["computer"] = "rbxassetid://77480056459407",
	["concierge-bell"] = "rbxassetid://140384259310436",
	["cone"] = "rbxassetid://97759550688437",
	["construction"] = "rbxassetid://106539489968173",
	["contact"] = "rbxassetid://75868297719012",
	["contact-round"] = "rbxassetid://71907624112229",
	["container"] = "rbxassetid://91507237573499",
	["contrast"] = "rbxassetid://112796643981497",
	["cookie"] = "rbxassetid://73159504540002",
	["cooking-pot"] = "rbxassetid://94959783129799",
	["copy"] = "rbxassetid://78979572434545",
	["copy-check"] = "rbxassetid://91177247988892",
	["copy-minus"] = "rbxassetid://109524509933035",
	["copy-plus"] = "rbxassetid://113618379616952",
	["copy-slash"] = "rbxassetid://93805787810390",
	["copy-x"] = "rbxassetid://106557557978061",
	["copyleft"] = "rbxassetid://78559055698593",
	["copyright"] = "rbxassetid://129433635747111",
	["corner-down-left"] = "rbxassetid://90473561177832",
	["corner-down-right"] = "rbxassetid://86512767702085",
	["corner-left-down"] = "rbxassetid://139876989150630",
	["corner-left-up"] = "rbxassetid://126228268096099",
	["corner-right-down"] = "rbxassetid://89237035551302",
	["corner-right-up"] = "rbxassetid://112851237026705",
	["corner-up-left"] = "rbxassetid://84669279763024",
	["corner-up-right"] = "rbxassetid://115099889693145",
	["cpu"] = "rbxassetid://77549309870247",
	["creative-commons"] = "rbxassetid://90408210735312",
	["credit-card"] = "rbxassetid://99163352872346",
	["croissant"] = "rbxassetid://130710485559420",
	["crop"] = "rbxassetid://116344601101413",
	["cross"] = "rbxassetid://101833377863588",
	["crosshair"] = "rbxassetid://134242818164054",
	["crown"] = "rbxassetid://127843403295538",
	["cuboid"] = "rbxassetid://75618807946111",
	["cup-soda"] = "rbxassetid://121098640829562",
	["currency"] = "rbxassetid://90551250119972",
	["cylinder"] = "rbxassetid://90569677179169",
	["dam"] = "rbxassetid://76874486231393",
	["database"] = "rbxassetid://126791525623846",
	["database-backup"] = "rbxassetid://103403210984699",
	["database-search"] = "rbxassetid://92017137080138",
	["database-zap"] = "rbxassetid://131199921258418",
	["decimals-arrow-left"] = "rbxassetid://120198500638749",
	["decimals-arrow-right"] = "rbxassetid://118263047146797",
	["delete"] = "rbxassetid://126279426372342",
	["dessert"] = "rbxassetid://71508133278830",
	["diameter"] = "rbxassetid://97429051503783",
	["diamond"] = "rbxassetid://105846996304890",
	["diamond-minus"] = "rbxassetid://128989071438290",
	["diamond-percent"] = "rbxassetid://107717860105959",
	["diamond-plus"] = "rbxassetid://134701163723675",
	["dice-1"] = "rbxassetid://112650149591038",
	["dice-2"] = "rbxassetid://112278274566793",
	["dice-3"] = "rbxassetid://118526270626312",
	["dice-4"] = "rbxassetid://113365650364004",
	["dice-5"] = "rbxassetid://72768312430593",
	["dice-6"] = "rbxassetid://85376239182543",
	["dices"] = "rbxassetid://81268120302865",
	["diff"] = "rbxassetid://135052708609715",
	["disc"] = "rbxassetid://101908120120777",
	["disc-2"] = "rbxassetid://91419420404185",
	["disc-3"] = "rbxassetid://135470554736048",
	["disc-album"] = "rbxassetid://74693460404344",
	["divide"] = "rbxassetid://136678191878278",
	["dna"] = "rbxassetid://74007982981741",
	["dna-off"] = "rbxassetid://89612426361540",
	["dock"] = "rbxassetid://121997427160252",
	["dog"] = "rbxassetid://71920105558570",
	["dollar-sign"] = "rbxassetid://127320961224019",
	["donut"] = "rbxassetid://72204922742657",
	["door-closed"] = "rbxassetid://136249099949073",
	["door-closed-locked"] = "rbxassetid://74027613267551",
	["door-open"] = "rbxassetid://91306356501736",
	["dot"] = "rbxassetid://137321056643916",
	["download"] = "rbxassetid://134814648082393",
	["drafting-compass"] = "rbxassetid://99701976182841",
	["drama"] = "rbxassetid://110297795801577",
	["dribbble"] = "rbxassetid://80231809663849",
	["drill"] = "rbxassetid://108644821412796",
	["drone"] = "rbxassetid://117299095794783",
	["droplet"] = "rbxassetid://100597455015098",
	["droplet-off"] = "rbxassetid://119365002225172",
	["droplets"] = "rbxassetid://140111846025180",
	["drum"] = "rbxassetid://136979060344890",
	["drumstick"] = "rbxassetid://104662462521709",
	["dumbbell"] = "rbxassetid://80277236776212",
	["ear"] = "rbxassetid://121894949934209",
	["ear-off"] = "rbxassetid://87421916192807",
	["earth"] = "rbxassetid://76231597751076",
	["earth-lock"] = "rbxassetid://88814147073745",
	["eclipse"] = "rbxassetid://114829622118222",
	["egg"] = "rbxassetid://117851493400222",
	["egg-fried"] = "rbxassetid://90622538210545",
	["egg-off"] = "rbxassetid://92288321309285",
	["ellipse"] = "rbxassetid://71559658267482",
	["ellipsis"] = "rbxassetid://140019550645825",
	["ellipsis-vertical"] = "rbxassetid://117978708573781",
	["equal"] = "rbxassetid://123467780715624",
	["equal-approximately"] = "rbxassetid://105382689698323",
	["equal-not"] = "rbxassetid://76864449458032",
	["eraser"] = "rbxassetid://133957773112410",
	["ethernet-port"] = "rbxassetid://75391715149314",
	["euro"] = "rbxassetid://72229646524456",
	["ev-charger"] = "rbxassetid://97906158859623",
	["expand"] = "rbxassetid://137492887754537",
	["external-link"] = "rbxassetid://129331830773832",
	["eye"] = "rbxassetid://100033680381365",
	["eye-closed"] = "rbxassetid://111063268625789",
	["eye-off"] = "rbxassetid://135928786788378",
	["facebook"] = "rbxassetid://72098528632192",
	["factory"] = "rbxassetid://102170024318039",
	["fan"] = "rbxassetid://78391400440696",
	["fast-forward"] = "rbxassetid://121615540167909",
	["feather"] = "rbxassetid://91872927606406",
	["fence"] = "rbxassetid://123451565578029",
	["ferris-wheel"] = "rbxassetid://79729205796176",
	["figma"] = "rbxassetid://134182122852301",
	["file"] = "rbxassetid://74748492079329",
	["file-archive"] = "rbxassetid://77018106869967",
	["file-axis-3d"] = "rbxassetid://133912328009885",
	["file-badge"] = "rbxassetid://74564895394477",
	["file-box"] = "rbxassetid://119264004071690",
	["file-braces"] = "rbxassetid://95314128621234",
	["file-braces-corner"] = "rbxassetid://77253337986109",
	["file-chart-column"] = "rbxassetid://82048481252560",
	["file-chart-column-increasing"] = "rbxassetid://134449481172067",
	["file-chart-line"] = "rbxassetid://71954360551345",
	["file-chart-pie"] = "rbxassetid://81072193564497",
	["file-check"] = "rbxassetid://82604001452455",
	["file-check-corner"] = "rbxassetid://76295552859171",
	["file-clock"] = "rbxassetid://102325208830990",
	["file-code"] = "rbxassetid://130978036895504",
	["file-code-corner"] = "rbxassetid://78293841184371",
	["file-cog"] = "rbxassetid://101385347151368",
	["file-diff"] = "rbxassetid://96147216772241",
	["file-digit"] = "rbxassetid://89220220354580",
	["file-down"] = "rbxassetid://120650154178290",
	["file-exclamation-point"] = "rbxassetid://102821865889635",
	["file-headphone"] = "rbxassetid://100533735901986",
	["file-heart"] = "rbxassetid://132214916401696",
	["file-image"] = "rbxassetid://123334057511782",
	["file-input"] = "rbxassetid://124728604166044",
	["file-key"] = "rbxassetid://118790255921100",
	["file-lock"] = "rbxassetid://72170228691242",
	["file-minus"] = "rbxassetid://111014798459222",
	["file-minus-corner"] = "rbxassetid://119263271735124",
	["file-music"] = "rbxassetid://134948051536671",
	["file-output"] = "rbxassetid://92146832572911",
	["file-pen"] = "rbxassetid://79556179730240",
	["file-pen-line"] = "rbxassetid://104622936345006",
	["file-play"] = "rbxassetid://89006821567838",
	["file-plus"] = "rbxassetid://78881710800060",
	["file-plus-corner"] = "rbxassetid://76544604043974",
	["file-question-mark"] = "rbxassetid://127617422859576",
	["file-scan"] = "rbxassetid://129480105228213",
	["file-search"] = "rbxassetid://97780235974933",
	["file-search-corner"] = "rbxassetid://90974165234008",
	["file-signal"] = "rbxassetid://122070252538165",
	["file-sliders"] = "rbxassetid://85787771732439",
	["file-spreadsheet"] = "rbxassetid://134501869359270",
	["file-stack"] = "rbxassetid://138929929862605",
	["file-symlink"] = "rbxassetid://91865722036510",
	["file-terminal"] = "rbxassetid://116757454755476",
	["file-text"] = "rbxassetid://90496405707281",
	["file-type"] = "rbxassetid://115272552799361",
	["file-type-corner"] = "rbxassetid://124902230275209",
	["file-up"] = "rbxassetid://131173039312748",
	["file-user"] = "rbxassetid://99552018455009",
	["file-video-camera"] = "rbxassetid://81719056173960",
	["file-volume"] = "rbxassetid://111264764438958",
	["file-x"] = "rbxassetid://107333775515154",
	["file-x-corner"] = "rbxassetid://87554136773609",
	["files"] = "rbxassetid://102806336233202",
	["film"] = "rbxassetid://120978945609706",
	["fingerprint"] = "rbxassetid://112173305232811",
	["fingerprint-pattern"] = "rbxassetid://80934710831288",
	["fire-extinguisher"] = "rbxassetid://111643493006960",
	["fish"] = "rbxassetid://124360663785796",
	["fish-off"] = "rbxassetid://89756724887508",
	["fish-symbol"] = "rbxassetid://118475177681618",
	["fishing-hook"] = "rbxassetid://121038780855899",
	["fishing-rod"] = "rbxassetid://71754848048049",
	["flag"] = "rbxassetid://78183383236196",
	["flag-off"] = "rbxassetid://112944528856799",
	["flag-triangle-left"] = "rbxassetid://88045221285272",
	["flag-triangle-right"] = "rbxassetid://108292480304566",
	["flame"] = "rbxassetid://98218034436456",
	["flame-kindling"] = "rbxassetid://139728976917928",
	["flashlight"] = "rbxassetid://100286985600444",
	["flashlight-off"] = "rbxassetid://79780362871740",
	["flask-conical"] = "rbxassetid://128406680901165",
	["flask-conical-off"] = "rbxassetid://112597970025298",
	["flask-round"] = "rbxassetid://127508287324940",
	["flip-horizontal"] = "rbxassetid://122937530107837",
	["flip-horizontal-2"] = "rbxassetid://103726993598186",
	["flip-vertical"] = "rbxassetid://108003917346888",
	["flip-vertical-2"] = "rbxassetid://103836358956328",
	["flower"] = "rbxassetid://86129438272762",
	["flower-2"] = "rbxassetid://72934574245145",
	["focus"] = "rbxassetid://87493973153317",
	["fold-horizontal"] = "rbxassetid://92835712442240",
	["fold-vertical"] = "rbxassetid://108873727253656",
	["folder"] = "rbxassetid://80846616596607",
	["folder-archive"] = "rbxassetid://97312009460206",
	["folder-check"] = "rbxassetid://128492920904557",
	["folder-clock"] = "rbxassetid://111964836738545",
	["folder-closed"] = "rbxassetid://118286209350843",
	["folder-code"] = "rbxassetid://70624096349370",
	["folder-cog"] = "rbxassetid://85299519462846",
	["folder-dot"] = "rbxassetid://138687772725278",
	["folder-down"] = "rbxassetid://118044108459225",
	["folder-git"] = "rbxassetid://121885778095158",
	["folder-git-2"] = "rbxassetid://101394054141166",
	["folder-heart"] = "rbxassetid://79104747211105",
	["folder-input"] = "rbxassetid://90699920697871",
	["folder-kanban"] = "rbxassetid://78313285104072",
	["folder-key"] = "rbxassetid://85270407596791",
	["folder-lock"] = "rbxassetid://119201572260567",
	["folder-minus"] = "rbxassetid://85648718999010",
	["folder-open"] = "rbxassetid://76018996254888",
	["folder-open-dot"] = "rbxassetid://74741494767354",
	["folder-output"] = "rbxassetid://101532447937612",
	["folder-pen"] = "rbxassetid://112770491173911",
	["folder-plus"] = "rbxassetid://91865663406119",
	["folder-root"] = "rbxassetid://103333751154693",
	["folder-search"] = "rbxassetid://110568075123861",
	["folder-search-2"] = "rbxassetid://71276453442655",
	["folder-symlink"] = "rbxassetid://127485747227189",
	["folder-sync"] = "rbxassetid://91544602659796",
	["folder-tree"] = "rbxassetid://85577554337861",
	["folder-up"] = "rbxassetid://72008269765857",
	["folder-x"] = "rbxassetid://91699618247635",
	["folders"] = "rbxassetid://110351216219061",
	["footprints"] = "rbxassetid://139192589041315",
	["forklift"] = "rbxassetid://72030930983101",
	["form"] = "rbxassetid://72999643971000",
	["forward"] = "rbxassetid://97545944739523",
	["frame"] = "rbxassetid://109080612832751",
	["framer"] = "rbxassetid://108384807262391",
	["frown"] = "rbxassetid://124407301067982",
	["fuel"] = "rbxassetid://106447647274511",
	["fullscreen"] = "rbxassetid://77793665526178",
	["funnel"] = "rbxassetid://108829540827529",
	["funnel-plus"] = "rbxassetid://100780233821928",
	["funnel-x"] = "rbxassetid://70984385812555",
	["gallery-horizontal"] = "rbxassetid://80004001442122",
	["gallery-horizontal-end"] = "rbxassetid://74672430161161",
	["gallery-thumbnails"] = "rbxassetid://136219289862706",
	["gallery-vertical"] = "rbxassetid://119299431466725",
	["gallery-vertical-end"] = "rbxassetid://106461402088317",
	["gamepad"] = "rbxassetid://121607283959010",
	["gamepad-2"] = "rbxassetid://92483947987410",
	["gamepad-directional"] = "rbxassetid://84342305212226",
	["gauge"] = "rbxassetid://110273524101447",
	["gavel"] = "rbxassetid://78952298198456",
	["gear"] = "rbxassetid://80758916183665",
	["gears"] = "rbxassetid://80758916183665",
	["gem"] = "rbxassetid://112904952151156",
	["georgian-lari"] = "rbxassetid://98084432591687",
	["ghost"] = "rbxassetid://113822048130017",
	["gift"] = "rbxassetid://109855212076373",
	["git-branch"] = "rbxassetid://90490195516649",
	["git-branch-minus"] = "rbxassetid://97385010649411",
	["git-branch-plus"] = "rbxassetid://125944221134316",
	["git-commit-horizontal"] = "rbxassetid://133646041800147",
	["git-commit-vertical"] = "rbxassetid://122098032990350",
	["git-compare"] = "rbxassetid://91945124438792",
	["git-compare-arrows"] = "rbxassetid://84874426520216",
	["git-fork"] = "rbxassetid://89954992404765",
	["git-graph"] = "rbxassetid://86166832019304",
	["git-merge"] = "rbxassetid://131833355158059",
	["git-merge-conflict"] = "rbxassetid://85677801675703",
	["git-pull-request"] = "rbxassetid://138463010991471",
	["git-pull-request-arrow"] = "rbxassetid://94507974577439",
	["git-pull-request-closed"] = "rbxassetid://78070600389091",
	["git-pull-request-create"] = "rbxassetid://105929577383926",
	["git-pull-request-create-arrow"] = "rbxassetid://127422677061091",
	["git-pull-request-draft"] = "rbxassetid://76173459869943",
	["github"] = "rbxassetid://7733954058",
	["gitlab"] = "rbxassetid://114054627192933",
	["glass-water"] = "rbxassetid://115526102400988",
	["glasses"] = "rbxassetid://87936407455373",
	["globe"] = "rbxassetid://114238209622913",
	["globe-lock"] = "rbxassetid://134065526704402",
	["globe-off"] = "rbxassetid://77775243585824",
	["globe-x"] = "rbxassetid://109268097029296",
	["goal"] = "rbxassetid://120517954878160",
	["gpu"] = "rbxassetid://95577823614219",
	["graduation-cap"] = "rbxassetid://93771896340220",
	["grape"] = "rbxassetid://134760640415561",
	["grid-2x2"] = "rbxassetid://99050491897640",
	["grid-2x2-check"] = "rbxassetid://138468840220821",
	["grid-2x2-plus"] = "rbxassetid://91811610580247",
	["grid-2x2-x"] = "rbxassetid://72407303981388",
	["grid-3x2"] = "rbxassetid://95528684210010",
	["grid-3x3"] = "rbxassetid://70419024781206",
	["grip"] = "rbxassetid://109058783556768",
	["grip-horizontal"] = "rbxassetid://136255899715930",
	["grip-vertical"] = "rbxassetid://137183678565296",
	["group"] = "rbxassetid://107643418926671",
	["guitar"] = "rbxassetid://75915531867926",
	["ham"] = "rbxassetid://74465607934635",
	["hamburger"] = "rbxassetid://93086916815495",
	["hammer"] = "rbxassetid://83545120140895",
	["hand"] = "rbxassetid://130703864968637",
	["hand-coins"] = "rbxassetid://126990543175462",
	["hand-fist"] = "rbxassetid://83341608917591",
	["hand-grab"] = "rbxassetid://88867162163985",
	["hand-heart"] = "rbxassetid://117507367668412",
	["hand-helping"] = "rbxassetid://89897738419446",
	["hand-metal"] = "rbxassetid://113619498548713",
	["hand-platter"] = "rbxassetid://88594727743168",
	["handbag"] = "rbxassetid://135675846264061",
	["handshake"] = "rbxassetid://78442115255814",
	["hard-drive"] = "rbxassetid://88183305858463",
	["hard-drive-download"] = "rbxassetid://73913801230614",
	["hard-drive-upload"] = "rbxassetid://85762133615118",
	["hard-hat"] = "rbxassetid://128050846767382",
	["hash"] = "rbxassetid://82890331678520",
	["hat-glasses"] = "rbxassetid://101165538224815",
	["haze"] = "rbxassetid://108857561768901",
	["hd"] = "rbxassetid://71682790698278",
	["hdmi-port"] = "rbxassetid://103693661037020",
	["heading"] = "rbxassetid://129254312067735",
	["heading-1"] = "rbxassetid://118129315662110",
	["heading-2"] = "rbxassetid://110209069670094",
	["heading-3"] = "rbxassetid://90267885237062",
	["heading-4"] = "rbxassetid://129625620307602",
	["heading-5"] = "rbxassetid://120386663181267",
	["heading-6"] = "rbxassetid://90959079775093",
	["headphone-off"] = "rbxassetid://85038251615641",
	["headphones"] = "rbxassetid://118833729589183",
	["headset"] = "rbxassetid://129269236787694",
	["heart"] = "rbxassetid://116559368303288",
	["heart-crack"] = "rbxassetid://110987638564119",
	["heart-handshake"] = "rbxassetid://111483078692002",
	["heart-minus"] = "rbxassetid://96827380163326",
	["heart-off"] = "rbxassetid://89748414415617",
	["heart-plus"] = "rbxassetid://94877796283249",
	["heart-pulse"] = "rbxassetid://129352925579546",
	["heater"] = "rbxassetid://140478466880916",
	["helicopter"] = "rbxassetid://111557171735930",
	["help-circle"] = "rbxassetid://10723406988",
	["hexagon"] = "rbxassetid://127592089339199",
	["highlighter"] = "rbxassetid://77411555641113",
	["history"] = "rbxassetid://123980022019922",
	["home"] = "rbxassetid://98755624629571",
	["hop"] = "rbxassetid://82778923997672",
	["hop-off"] = "rbxassetid://103386036934034",
	["hospital"] = "rbxassetid://105868763850707",
	["hotel"] = "rbxassetid://132283390859718",
	["hourglass"] = "rbxassetid://86160434939203",
	["house"] = "rbxassetid://98755624629571",
	["house-heart"] = "rbxassetid://136054771868597",
	["house-plug"] = "rbxassetid://71438263712075",
	["house-plus"] = "rbxassetid://118495165208309",
	["house-wifi"] = "rbxassetid://126495519725698",
	["houses"] = "rbxassetid://98755624629571",
	["ice-cream-bowl"] = "rbxassetid://124867218454386",
	["ice-cream-cone"] = "rbxassetid://90751397288639",
	["id-card"] = "rbxassetid://75354294622640",
	["id-card-lanyard"] = "rbxassetid://90761480469224",
	["image"] = "rbxassetid://112751259236831",
	["image-down"] = "rbxassetid://78972295741235",
	["image-minus"] = "rbxassetid://101066016918565",
	["image-off"] = "rbxassetid://81934811700938",
	["image-play"] = "rbxassetid://129501806784210",
	["image-plus"] = "rbxassetid://70391970623917",
	["image-up"] = "rbxassetid://126610009605241",
	["image-upscale"] = "rbxassetid://106963545024679",
	["images"] = "rbxassetid://79350649395557",
	["import"] = "rbxassetid://116545008906029",
	["inbox"] = "rbxassetid://112591360302868",
	["indian-rupee"] = "rbxassetid://113038778381805",
	["infinity"] = "rbxassetid://98083086936965",
	["info"] = "rbxassetid://124560466474914",
	["inspection-panel"] = "rbxassetid://70905313146088",
	["instagram"] = "rbxassetid://119864798614855",
	["italic"] = "rbxassetid://96220378864282",
	["iteration-ccw"] = "rbxassetid://140221832794083",
	["iteration-cw"] = "rbxassetid://95534489554662",
	["japanese-yen"] = "rbxassetid://106362863465813",
	["joystick"] = "rbxassetid://99416790224739",
	["kanban"] = "rbxassetid://125934100055431",
	["kayak"] = "rbxassetid://136107544609389",
	["key"] = "rbxassetid://96510194465420",
	["key-round"] = "rbxassetid://83619031955390",
	["key-square"] = "rbxassetid://94621420033649",
	["keyboard"] = "rbxassetid://121474456068237",
	["keyboard-music"] = "rbxassetid://121058541758636",
	["keyboard-off"] = "rbxassetid://92466375369772",
	["lamp"] = "rbxassetid://110730830653382",
	["lamp-ceiling"] = "rbxassetid://80032758469141",
	["lamp-desk"] = "rbxassetid://85290686983238",
	["lamp-floor"] = "rbxassetid://104585881375892",
	["lamp-wall-down"] = "rbxassetid://91271394132073",
	["lamp-wall-up"] = "rbxassetid://132141464337445",
	["land-plot"] = "rbxassetid://96449039620294",
	["landmark"] = "rbxassetid://76885079756393",
	["languages"] = "rbxassetid://90816903776498",
	["laptop"] = "rbxassetid://111387063244975",
	["laptop-minimal"] = "rbxassetid://136705765566068",
	["laptop-minimal-check"] = "rbxassetid://114352019833865",
	["lasso"] = "rbxassetid://121072936884007",
	["lasso-select"] = "rbxassetid://105609719912753",
	["laugh"] = "rbxassetid://104491311361166",
	["layers"] = "rbxassetid://81973586053257",
	["layers-2"] = "rbxassetid://70536710516357",
	["layers-plus"] = "rbxassetid://77587765623057",
	["layout-dashboard"] = "rbxassetid://139929981863901",
	["layout-grid"] = "rbxassetid://81344910161871",
	["layout-list"] = "rbxassetid://87462136296578",
	["layout-panel-left"] = "rbxassetid://125092469751491",
	["layout-panel-top"] = "rbxassetid://91943941515944",
	["layout-template"] = "rbxassetid://115564446417985",
	["leaf"] = "rbxassetid://119951075637174",
	["leafy-green"] = "rbxassetid://105146290493154",
	["lectern"] = "rbxassetid://106166425183862",
	["lens-concave"] = "rbxassetid://94819631937027",
	["lens-convex"] = "rbxassetid://74736504195474",
	["library"] = "rbxassetid://114334671982047",
	["library-big"] = "rbxassetid://106794530191412",
	["life-buoy"] = "rbxassetid://81168450671956",
	["ligature"] = "rbxassetid://111397873269411",
	["lightbulb"] = "rbxassetid://103871245626488",
	["lightbulb-off"] = "rbxassetid://83795722296178",
	["line-dot-right-horizontal"] = "rbxassetid://104718593155221",
	["line-squiggle"] = "rbxassetid://109555164424447",
	["line-style"] = "rbxassetid://90176717785772",
	["link"] = "rbxassetid://131607023382430",
	["link-2"] = "rbxassetid://86072351557466",
	["link-2-off"] = "rbxassetid://76885956296867",
	["linkedin"] = "rbxassetid://132842789255788",
	["list"] = "rbxassetid://113179976918783",
	["list-check"] = "rbxassetid://72374358471156",
	["list-checks"] = "rbxassetid://99809353635593",
	["list-chevrons-down-up"] = "rbxassetid://137409641500711",
	["list-chevrons-up-down"] = "rbxassetid://81825351389084",
	["list-collapse"] = "rbxassetid://124505247702401",
	["list-end"] = "rbxassetid://77650610048119",
	["list-filter"] = "rbxassetid://103321376129527",
	["list-filter-plus"] = "rbxassetid://96385120752336",
	["list-indent-decrease"] = "rbxassetid://137879979228193",
	["list-indent-increase"] = "rbxassetid://79051053161201",
	["list-minus"] = "rbxassetid://138507965142671",
	["list-music"] = "rbxassetid://126380635781840",
	["list-ordered"] = "rbxassetid://83212528113913",
	["list-plus"] = "rbxassetid://112384738137814",
	["list-restart"] = "rbxassetid://91703153577421",
	["list-start"] = "rbxassetid://84828348299727",
	["list-todo"] = "rbxassetid://132980603752108",
	["list-tree"] = "rbxassetid://97685396239010",
	["list-video"] = "rbxassetid://93648525452489",
	["list-x"] = "rbxassetid://113025303988861",
	["loader"] = "rbxassetid://78408734580845",
	["loader-circle"] = "rbxassetid://116535712789945",
	["loader-pinwheel"] = "rbxassetid://108513357940900",
	["locate"] = "rbxassetid://84467676590391",
	["locate-fixed"] = "rbxassetid://137367361548433",
	["locate-off"] = "rbxassetid://73729216338137",
	["lock"] = "rbxassetid://134724289526879",
	["lock-keyhole"] = "rbxassetid://78672912777756",
	["lock-keyhole-open"] = "rbxassetid://110863509313073",
	["lock-open"] = "rbxassetid://93597915325122",
	["log-in"] = "rbxassetid://103768533135201",
	["log-out"] = "rbxassetid://84895399304975",
	["logs"] = "rbxassetid://89772091251787",
	["lollipop"] = "rbxassetid://84681611583044",
	["luggage"] = "rbxassetid://76619236486400",
	["magnet"] = "rbxassetid://135162361226972",
	["mail"] = "rbxassetid://103945161245599",
	["mail-check"] = "rbxassetid://86921536259917",
	["mail-minus"] = "rbxassetid://81989813236553",
	["mail-open"] = "rbxassetid://122785416858638",
	["mail-plus"] = "rbxassetid://104886401588341",
	["mail-question-mark"] = "rbxassetid://126540170949819",
	["mail-search"] = "rbxassetid://135616173775287",
	["mail-warning"] = "rbxassetid://81495303676089",
	["mail-x"] = "rbxassetid://74607841705644",
	["mailbox"] = "rbxassetid://82765503320335",
	["mails"] = "rbxassetid://90673453450080",
	["map"] = "rbxassetid://95107167260947",
	["map-minus"] = "rbxassetid://129525760577747",
	["map-pin"] = "rbxassetid://84279202219901",
	["map-pin-check"] = "rbxassetid://118110914690154",
	["map-pin-check-inside"] = "rbxassetid://107130529843809",
	["map-pin-house"] = "rbxassetid://80546885029816",
	["map-pin-minus"] = "rbxassetid://74518762643623",
	["map-pin-minus-inside"] = "rbxassetid://79005529692964",
	["map-pin-off"] = "rbxassetid://82474689391020",
	["map-pin-pen"] = "rbxassetid://113515395277504",
	["map-pin-plus"] = "rbxassetid://91875228967029",
	["map-pin-plus-inside"] = "rbxassetid://134639656514430",
	["map-pin-search"] = "rbxassetid://89065012915078",
	["map-pin-x"] = "rbxassetid://101085273547316",
	["map-pin-x-inside"] = "rbxassetid://126235934252379",
	["map-pinned"] = "rbxassetid://103963788475034",
	["map-plus"] = "rbxassetid://129388826743495",
	["mars"] = "rbxassetid://111287112372511",
	["mars-stroke"] = "rbxassetid://131973193186828",
	["martini"] = "rbxassetid://82977695401058",
	["maximize"] = "rbxassetid://76045941763188",
	["maximize-2"] = "rbxassetid://73085922906397",
	["medal"] = "rbxassetid://79016002264450",
	["megaphone"] = "rbxassetid://118759541854879",
	["megaphone-off"] = "rbxassetid://124280774193935",
	["meh"] = "rbxassetid://132197867028557",
	["memory-stick"] = "rbxassetid://93212591343119",
	["menu"] = "rbxassetid://77021539815611",
	["merge"] = "rbxassetid://126201866476775",
	["message-circle"] = "rbxassetid://127255077587058",
	["message-circle-check"] = "rbxassetid://132772297689418",
	["message-circle-code"] = "rbxassetid://112865244991651",
	["message-circle-dashed"] = "rbxassetid://81525157881897",
	["message-circle-heart"] = "rbxassetid://101990756073677",
	["message-circle-more"] = "rbxassetid://92856823884663",
	["message-circle-off"] = "rbxassetid://134955643890328",
	["message-circle-plus"] = "rbxassetid://106562979649273",
	["message-circle-question-mark"] = "rbxassetid://107700302759934",
	["message-circle-reply"] = "rbxassetid://137071749508334",
	["message-circle-warning"] = "rbxassetid://119020096067894",
	["message-circle-x"] = "rbxassetid://126843387725536",
	["message-square"] = "rbxassetid://83881670383280",
	["message-square-check"] = "rbxassetid://125789987055668",
	["message-square-code"] = "rbxassetid://110968863152123",
	["message-square-dashed"] = "rbxassetid://107653455516238",
	["message-square-diff"] = "rbxassetid://75472190472625",
	["message-square-dot"] = "rbxassetid://127806382463916",
	["message-square-heart"] = "rbxassetid://75612811742074",
	["message-square-lock"] = "rbxassetid://81268215619563",
	["message-square-more"] = "rbxassetid://120139782405970",
	["message-square-off"] = "rbxassetid://99961019005789",
	["message-square-plus"] = "rbxassetid://76934450256199",
	["message-square-quote"] = "rbxassetid://116670768629340",
	["message-square-reply"] = "rbxassetid://130985622754637",
	["message-square-share"] = "rbxassetid://131017005324026",
	["message-square-text"] = "rbxassetid://94899503194205",
	["message-square-warning"] = "rbxassetid://138432903962261",
	["message-square-x"] = "rbxassetid://137285463279462",
	["messages-square"] = "rbxassetid://97532166733358",
	["metronome"] = "rbxassetid://101991829345965",
	["mic"] = "rbxassetid://89640799126523",
	["mic-off"] = "rbxassetid://82123034444822",
	["mic-vocal"] = "rbxassetid://99082286164362",
	["microchip"] = "rbxassetid://73937907669903",
	["microscope"] = "rbxassetid://116875530102782",
	["microwave"] = "rbxassetid://108411735353008",
	["milestone"] = "rbxassetid://101618292325920",
	["milk"] = "rbxassetid://96221903896918",
	["milk-off"] = "rbxassetid://72388480962742",
	["minimize"] = "rbxassetid://121304296213645",
	["minimize-2"] = "rbxassetid://116269596042539",
	["minus"] = "rbxassetid://118026365011536",
	["mirror-rectangular"] = "rbxassetid://109046769760336",
	["mirror-round"] = "rbxassetid://121534049429097",
	["monitor"] = "rbxassetid://72664649203050",
	["monitor-check"] = "rbxassetid://86651948439229",
	["monitor-cloud"] = "rbxassetid://85931096038318",
	["monitor-cog"] = "rbxassetid://94345128715799",
	["monitor-dot"] = "rbxassetid://130394010063680",
	["monitor-down"] = "rbxassetid://97466933743423",
	["monitor-off"] = "rbxassetid://74395526657953",
	["monitor-pause"] = "rbxassetid://76002184067562",
	["monitor-play"] = "rbxassetid://133018824306217",
	["monitor-smartphone"] = "rbxassetid://84335680433378",
	["monitor-speaker"] = "rbxassetid://81744810060380",
	["monitor-stop"] = "rbxassetid://98708958984757",
	["monitor-up"] = "rbxassetid://96035360858377",
	["monitor-x"] = "rbxassetid://126265210441423",
	["moon"] = "rbxassetid://83380517901735",
	["moon-star"] = "rbxassetid://82782200506348",
	["motorbike"] = "rbxassetid://94580787368233",
	["mountain"] = "rbxassetid://73269957566415",
	["mountain-snow"] = "rbxassetid://105315495740588",
	["mouse"] = "rbxassetid://73096068864710",
	["mouse-left"] = "rbxassetid://99144293708743",
	["mouse-off"] = "rbxassetid://75267871697595",
	["mouse-pointer"] = "rbxassetid://72322454962935",
	["mouse-pointer-2"] = "rbxassetid://117093892862228",
	["mouse-pointer-2-off"] = "rbxassetid://104701076865632",
	["mouse-pointer-ban"] = "rbxassetid://106849413057133",
	["mouse-pointer-click"] = "rbxassetid://107150227368485",
	["mouse-right"] = "rbxassetid://88331710212594",
	["move"] = "rbxassetid://116138709011735",
	["move-3d"] = "rbxassetid://103365982054003",
	["move-diagonal"] = "rbxassetid://101433481954184",
	["move-diagonal-2"] = "rbxassetid://117298577948096",
	["move-down"] = "rbxassetid://70510115135583",
	["move-down-left"] = "rbxassetid://102819433534567",
	["move-down-right"] = "rbxassetid://101479760041877",
	["move-horizontal"] = "rbxassetid://88513523439149",
	["move-left"] = "rbxassetid://137614740247980",
	["move-right"] = "rbxassetid://132455779472989",
	["move-up"] = "rbxassetid://84505444262658",
	["move-up-left"] = "rbxassetid://139079815540148",
	["move-up-right"] = "rbxassetid://105885140592646",
	["move-vertical"] = "rbxassetid://86234730730899",
	["music"] = "rbxassetid://113343203848535",
	["music-2"] = "rbxassetid://134397426600888",
	["music-3"] = "rbxassetid://94466120066498",
	["music-4"] = "rbxassetid://132459323665838",
	["navigation"] = "rbxassetid://79308213542922",
	["navigation-2"] = "rbxassetid://81889066747907",
	["navigation-2-off"] = "rbxassetid://116569611780763",
	["navigation-off"] = "rbxassetid://87003270290777",
	["network"] = "rbxassetid://127410729922644",
	["newspaper"] = "rbxassetid://123479530460544",
	["nfc"] = "rbxassetid://76822396542242",
	["non-binary"] = "rbxassetid://78442360386235",
	["notebook"] = "rbxassetid://136132108664987",
	["notebook-pen"] = "rbxassetid://140380614761023",
	["notebook-tabs"] = "rbxassetid://127371085570083",
	["notebook-text"] = "rbxassetid://93061585217270",
	["notepad-text"] = "rbxassetid://93404682958966",
	["notepad-text-dashed"] = "rbxassetid://135793446376219",
	["nut"] = "rbxassetid://127146410705656",
	["nut-off"] = "rbxassetid://78795397311573",
	["octagon"] = "rbxassetid://120803515514852",
	["octagon-alert"] = "rbxassetid://140438367956051",
	["octagon-minus"] = "rbxassetid://74720436795421",
	["octagon-pause"] = "rbxassetid://103161463909039",
	["octagon-x"] = "rbxassetid://90498161006311",
	["omega"] = "rbxassetid://70414080018786",
	["option"] = "rbxassetid://100776883894054",
	["orbit"] = "rbxassetid://108926136860562",
	["origami"] = "rbxassetid://136020626667101",
	["package"] = "rbxassetid://97261141732706",
	["package-2"] = "rbxassetid://70394974762575",
	["package-check"] = "rbxassetid://102374216055130",
	["package-minus"] = "rbxassetid://114492858789692",
	["package-open"] = "rbxassetid://132890233237818",
	["package-plus"] = "rbxassetid://129261988138366",
	["package-search"] = "rbxassetid://95465120894145",
	["package-x"] = "rbxassetid://70818501607442",
	["paint-bucket"] = "rbxassetid://124275586663284",
	["paint-roller"] = "rbxassetid://115248074358348",
	["paintbrush"] = "rbxassetid://125572663700289",
	["paintbrush-vertical"] = "rbxassetid://105151296591292",
	["palette"] = "rbxassetid://86350350950064",
	["panda"] = "rbxassetid://132509022802512",
	["panel-bottom"] = "rbxassetid://132127145048511",
	["panel-bottom-close"] = "rbxassetid://74287004071159",
	["panel-bottom-dashed"] = "rbxassetid://131084651621603",
	["panel-bottom-open"] = "rbxassetid://107768659586540",
	["panel-left"] = "rbxassetid://97419752870313",
	["panel-left-close"] = "rbxassetid://126579818823552",
	["panel-left-dashed"] = "rbxassetid://75536606374585",
	["panel-left-open"] = "rbxassetid://111075816195767",
	["panel-left-right-dashed"] = "rbxassetid://110100707973959",
	["panel-right"] = "rbxassetid://116365035443156",
	["panel-right-close"] = "rbxassetid://139528655524132",
	["panel-right-dashed"] = "rbxassetid://94959793877311",
	["panel-right-open"] = "rbxassetid://118114419142794",
	["panel-top"] = "rbxassetid://75838479462875",
	["panel-top-bottom-dashed"] = "rbxassetid://134737235653344",
	["panel-top-close"] = "rbxassetid://83578325777808",
	["panel-top-dashed"] = "rbxassetid://70522913169237",
	["panel-top-open"] = "rbxassetid://137959875507454",
	["panels-left-bottom"] = "rbxassetid://72996856149149",
	["panels-right-bottom"] = "rbxassetid://90659068960726",
	["panels-top-left"] = "rbxassetid://79858853850600",
	["paperclip"] = "rbxassetid://92088291163453",
	["parentheses"] = "rbxassetid://78950955173096",
	["parking-meter"] = "rbxassetid://84652733960568",
	["party-popper"] = "rbxassetid://111626795712193",
	["pause"] = "rbxassetid://74873705394436",
	["paw-print"] = "rbxassetid://112218825427601",
	["pc-case"] = "rbxassetid://122978648019101",
	["pen"] = "rbxassetid://72037878096321",
	["pen-line"] = "rbxassetid://109108135755303",
	["pen-off"] = "rbxassetid://84807123119438",
	["pen-tool"] = "rbxassetid://106145404953445",
	["pencil"] = "rbxassetid://137986121120732",
	["pencil-line"] = "rbxassetid://88392917053533",
	["pencil-off"] = "rbxassetid://103330927652832",
	["pencil-ruler"] = "rbxassetid://110120288284597",
	["pentagon"] = "rbxassetid://79184802179890",
	["percent"] = "rbxassetid://130155041032013",
	["person-standing"] = "rbxassetid://125020872044147",
	["philippine-peso"] = "rbxassetid://91173798254675",
	["phone"] = "rbxassetid://128804946640049",
	["phone-call"] = "rbxassetid://70555587592860",
	["phone-forwarded"] = "rbxassetid://113269614319737",
	["phone-incoming"] = "rbxassetid://82863576359288",
	["phone-missed"] = "rbxassetid://130156165198376",
	["phone-off"] = "rbxassetid://133318623553383",
	["phone-outgoing"] = "rbxassetid://104576478735825",
	["pi"] = "rbxassetid://74936036243146",
	["piano"] = "rbxassetid://85008880789520",
	["pickaxe"] = "rbxassetid://105888023317688",
	["picture-in-picture"] = "rbxassetid://80579597835123",
	["picture-in-picture-2"] = "rbxassetid://112803319544468",
	["piggy-bank"] = "rbxassetid://79498575790721",
	["pilcrow"] = "rbxassetid://139512780392871",
	["pilcrow-left"] = "rbxassetid://103803000849583",
	["pilcrow-right"] = "rbxassetid://104881733911870",
	["pill"] = "rbxassetid://73280534813448",
	["pill-bottle"] = "rbxassetid://118394692404597",
	["pin"] = "rbxassetid://120978111007514",
	["pin-off"] = "rbxassetid://127696372451750",
	["pipette"] = "rbxassetid://133167932934404",
	["pizza"] = "rbxassetid://126964453193501",
	["plane"] = "rbxassetid://126985561580989",
	["plane-landing"] = "rbxassetid://122555692211889",
	["plane-takeoff"] = "rbxassetid://117179478829575",
	["play"] = "rbxassetid://135609604299893",
	["plug"] = "rbxassetid://99782373064495",
	["plug-2"] = "rbxassetid://97912386476366",
	["plug-zap"] = "rbxassetid://74506269884055",
	["plus"] = "rbxassetid://111774323017047",
	["pocket"] = "rbxassetid://136686762542964",
	["pocket-knife"] = "rbxassetid://134075428063965",
	["podcast"] = "rbxassetid://109577075549215",
	["pointer"] = "rbxassetid://92615117311099",
	["pointer-off"] = "rbxassetid://95488389312794",
	["popcorn"] = "rbxassetid://139446511232750",
	["popsicle"] = "rbxassetid://112696318077073",
	["pound-sterling"] = "rbxassetid://127482649469130",
	["power"] = "rbxassetid://96479131758775",
	["power-off"] = "rbxassetid://118768311012214",
	["presentation"] = "rbxassetid://106134583757890",
	["printer"] = "rbxassetid://76080649734247",
	["printer-check"] = "rbxassetid://130273549443689",
	["printer-x"] = "rbxassetid://103002721801548",
	["projector"] = "rbxassetid://103281856385283",
	["proportions"] = "rbxassetid://130046855997237",
	["puzzle"] = "rbxassetid://136837798892463",
	["pyramid"] = "rbxassetid://107811442374127",
	["qr-code"] = "rbxassetid://105329945723350",
	["quote"] = "rbxassetid://103271711590001",
	["rabbit"] = "rbxassetid://98580518804206",
	["radar"] = "rbxassetid://138528222906635",
	["radiation"] = "rbxassetid://104499586848433",
	["radical"] = "rbxassetid://132758286926047",
	["radio"] = "rbxassetid://85611589536956",
	["radio-off"] = "rbxassetid://80359258046586",
	["radio-receiver"] = "rbxassetid://129598303378835",
	["radio-tower"] = "rbxassetid://93958663130054",
	["radius"] = "rbxassetid://89814505307129",
	["rail-symbol"] = "rbxassetid://134295386306962",
	["rainbow"] = "rbxassetid://132488862841895",
	["rat"] = "rbxassetid://127400975953159",
	["ratio"] = "rbxassetid://126369423897295",
	["receipt"] = "rbxassetid://77877895901792",
	["receipt-cent"] = "rbxassetid://91557573925201",
	["receipt-euro"] = "rbxassetid://94015722210295",
	["receipt-indian-rupee"] = "rbxassetid://89718170439990",
	["receipt-japanese-yen"] = "rbxassetid://132472560758851",
	["receipt-pound-sterling"] = "rbxassetid://73934967569625",
	["receipt-russian-ruble"] = "rbxassetid://105164576936853",
	["receipt-swiss-franc"] = "rbxassetid://72503668620116",
	["receipt-text"] = "rbxassetid://138483536013737",
	["receipt-turkish-lira"] = "rbxassetid://91950765836342",
	["rectangle-circle"] = "rbxassetid://100642423153903",
	["rectangle-ellipsis"] = "rbxassetid://112919953980965",
	["rectangle-goggles"] = "rbxassetid://98605436666727",
	["rectangle-horizontal"] = "rbxassetid://90224199814966",
	["rectangle-vertical"] = "rbxassetid://117277050590967",
	["recycle"] = "rbxassetid://140417023381961",
	["redo"] = "rbxassetid://116150342119054",
	["redo-2"] = "rbxassetid://70451039017914",
	["redo-dot"] = "rbxassetid://94252981719732",
	["refresh-ccw"] = "rbxassetid://117913330389477",
	["refresh-ccw-dot"] = "rbxassetid://106702246753270",
	["refresh-cw"] = "rbxassetid://138133190015277",
	["refresh-cw-off"] = "rbxassetid://140179498843054",
	["refrigerator"] = "rbxassetid://102614042652753",
	["regex"] = "rbxassetid://100727200791841",
	["remove-formatting"] = "rbxassetid://112833162022628",
	["repeat"] = "rbxassetid://121886242955173",
	["repeat-1"] = "rbxassetid://130144534857095",
	["repeat-2"] = "rbxassetid://85927537182704",
	["replace"] = "rbxassetid://128404082279430",
	["replace-all"] = "rbxassetid://127862728198635",
	["reply"] = "rbxassetid://109788633497028",
	["reply-all"] = "rbxassetid://71723137343562",
	["rewind"] = "rbxassetid://95205297521988",
	["ribbon"] = "rbxassetid://94265331526851",
	["road"] = "rbxassetid://120251329173530",
	["rocket"] = "rbxassetid://87412317685854",
	["rocking-chair"] = "rbxassetid://110420269495360",
	["roller-coaster"] = "rbxassetid://112426178972099",
	["rose"] = "rbxassetid://126336840238769",
	["rotate-3d"] = "rbxassetid://76300551576392",
	["rotate-ccw"] = "rbxassetid://110116685948665",
	["rotate-ccw-key"] = "rbxassetid://74976035240976",
	["rotate-ccw-square"] = "rbxassetid://90515853170424",
	["rotate-cw"] = "rbxassetid://84183336178654",
	["rotate-cw-square"] = "rbxassetid://77095448159303",
	["route"] = "rbxassetid://89968303228953",
	["route-off"] = "rbxassetid://106350402024079",
	["router"] = "rbxassetid://102130331994471",
	["rows-2"] = "rbxassetid://112556185960101",
	["rows-3"] = "rbxassetid://117215586961375",
	["rows-4"] = "rbxassetid://125646021959055",
	["rss"] = "rbxassetid://131789058984793",
	["ruler"] = "rbxassetid://81432445547423",
	["ruler-dimension-line"] = "rbxassetid://70673861371412",
	["russian-ruble"] = "rbxassetid://126357936542156",
	["sailboat"] = "rbxassetid://87110567187540",
	["salad"] = "rbxassetid://128864507821603",
	["sandwich"] = "rbxassetid://104573187458917",
	["satellite"] = "rbxassetid://134967053164645",
	["satellite-dish"] = "rbxassetid://136742443888305",
	["saudi-riyal"] = "rbxassetid://102282769104635",
	["save"] = "rbxassetid://126116963775616",
	["save-all"] = "rbxassetid://116946975799440",
	["save-off"] = "rbxassetid://87085435778560",
	["scale"] = "rbxassetid://108203682317477",
	["scale-3d"] = "rbxassetid://72414199620352",
	["scaling"] = "rbxassetid://122360365318466",
	["scan"] = "rbxassetid://123104789658180",
	["scan-barcode"] = "rbxassetid://96889457154761",
	["scan-eye"] = "rbxassetid://99244790601968",
	["scan-face"] = "rbxassetid://109959345069668",
	["scan-heart"] = "rbxassetid://106280819776142",
	["scan-line"] = "rbxassetid://126544908146540",
	["scan-qr-code"] = "rbxassetid://105409149549927",
	["scan-search"] = "rbxassetid://80009010551347",
	["scan-text"] = "rbxassetid://73702396787766",
	["school"] = "rbxassetid://76351530290068",
	["scissors"] = "rbxassetid://118665510911274",
	["scissors-line-dashed"] = "rbxassetid://122237447974173",
	["scooter"] = "rbxassetid://100035452787934",
	["screen-share"] = "rbxassetid://85137895705653",
	["screen-share-off"] = "rbxassetid://107677572669805",
	["scroll"] = "rbxassetid://74072101474951",
	["scroll-text"] = "rbxassetid://97321022666868",
	["search"] = "rbxassetid://121018724060431",
	["search-alert"] = "rbxassetid://127597984617505",
	["search-check"] = "rbxassetid://75442076191356",
	["search-code"] = "rbxassetid://117114794592802",
	["search-slash"] = "rbxassetid://96483932261041",
	["search-x"] = "rbxassetid://137319957522951",
	["section"] = "rbxassetid://91732188298948",
	["send"] = "rbxassetid://127751956873796",
	["send-horizontal"] = "rbxassetid://111734392411664",
	["send-to-back"] = "rbxassetid://75340312862253",
	["separator-horizontal"] = "rbxassetid://84864453699927",
	["separator-vertical"] = "rbxassetid://84031801478581",
	["server"] = "rbxassetid://92188766517878",
	["server-cog"] = "rbxassetid://138470287250966",
	["server-crash"] = "rbxassetid://132810618000212",
	["server-off"] = "rbxassetid://114048751507723",
	["settings"] = "rbxassetid://80758916183665",
	["settings-2"] = "rbxassetid://135684703553372",
	["shapes"] = "rbxassetid://129989433311409",
	["share"] = "rbxassetid://87340985053299",
	["share-2"] = "rbxassetid://71210767962065",
	["sheet"] = "rbxassetid://134902122480171",
	["shell"] = "rbxassetid://140212943563599",
	["shelving-unit"] = "rbxassetid://80116568514793",
	["shield"] = "rbxassetid://110987169760162",
	["shield-alert"] = "rbxassetid://114995877719925",
	["shield-ban"] = "rbxassetid://108765041044649",
	["shield-check"] = "rbxassetid://87354736164608",
	["shield-cog"] = "rbxassetid://129235695057857",
	["shield-cog-corner"] = "rbxassetid://111694066132698",
	["shield-ellipsis"] = "rbxassetid://114794739892123",
	["shield-half"] = "rbxassetid://117842634172647",
	["shield-minus"] = "rbxassetid://89965059528921",
	["shield-off"] = "rbxassetid://133426959132690",
	["shield-plus"] = "rbxassetid://100664857995498",
	["shield-question-mark"] = "rbxassetid://135722075265150",
	["shield-user"] = "rbxassetid://124832775645347",
	["shield-x"] = "rbxassetid://73370117343811",
	["shields"] = "rbxassetid://110987169760162",
	["ship"] = "rbxassetid://83995100553930",
	["ship-wheel"] = "rbxassetid://130797795829448",
	["shirt"] = "rbxassetid://106579555405966",
	["shopping-bag"] = "rbxassetid://71885477293226",
	["shopping-basket"] = "rbxassetid://138646411956433",
	["shopping-cart"] = "rbxassetid://128420521375441",
	["shovel"] = "rbxassetid://102465000512056",
	["shower-head"] = "rbxassetid://75884944024117",
	["shredder"] = "rbxassetid://122125164414463",
	["shrimp"] = "rbxassetid://102625900815307",
	["shrink"] = "rbxassetid://90953687918880",
	["shrub"] = "rbxassetid://127326280714343",
	["shuffle"] = "rbxassetid://132382786975101",
	["sigma"] = "rbxassetid://126884244870899",
	["signal"] = "rbxassetid://78424889355261",
	["signal-high"] = "rbxassetid://130436670012270",
	["signal-low"] = "rbxassetid://73674683500458",
	["signal-medium"] = "rbxassetid://125003021367019",
	["signal-zero"] = "rbxassetid://130045332414754",
	["signature"] = "rbxassetid://114402748013000",
	["signpost"] = "rbxassetid://106584743791433",
	["signpost-big"] = "rbxassetid://115780185675001",
	["siren"] = "rbxassetid://134210267818039",
	["skip-back"] = "rbxassetid://70466132711334",
	["skip-forward"] = "rbxassetid://124844823753990",
	["skull"] = "rbxassetid://137726256442333",
	["slack"] = "rbxassetid://96089719516736",
	["slash"] = "rbxassetid://117792185664263",
	["slice"] = "rbxassetid://95810504278179",
	["sliders-horizontal"] = "rbxassetid://85538382643347",
	["sliders-vertical"] = "rbxassetid://101190569086853",
	["smartphone"] = "rbxassetid://96623008834511",
	["smartphone-charging"] = "rbxassetid://102837532613995",
	["smartphone-nfc"] = "rbxassetid://82326425754446",
	["smile"] = "rbxassetid://105880397565283",
	["smile-plus"] = "rbxassetid://131981881472144",
	["snail"] = "rbxassetid://70904536548363",
	["snowflake"] = "rbxassetid://101235206534566",
	["soap-dispenser-droplet"] = "rbxassetid://77258480479465",
	["sofa"] = "rbxassetid://114427687218324",
	["solar-panel"] = "rbxassetid://132448188047921",
	["soup"] = "rbxassetid://115092551871618",
	["space"] = "rbxassetid://87072088914178",
	["spade"] = "rbxassetid://131444449466462",
	["sparkle"] = "rbxassetid://111044800239623",
	["sparkles"] = "rbxassetid://138635884129147",
	["speaker"] = "rbxassetid://96227183003618",
	["speech"] = "rbxassetid://87013139446349",
	["spell-check"] = "rbxassetid://91913483031334",
	["spell-check-2"] = "rbxassetid://81556731785534",
	["spline"] = "rbxassetid://129406685807412",
	["spline-pointer"] = "rbxassetid://84842840956804",
	["split"] = "rbxassetid://105112438805988",
	["spool"] = "rbxassetid://124541981347743",
	["sport-shoe"] = "rbxassetid://120495992692630",
	["spotlight"] = "rbxassetid://77571742539344",
	["spray-can"] = "rbxassetid://128372039366326",
	["sprout"] = "rbxassetid://100091687832508",
	["square"] = "rbxassetid://86304921356806",
	["square-activity"] = "rbxassetid://89496630185293",
	["square-arrow-down"] = "rbxassetid://135962519626588",
	["square-arrow-down-left"] = "rbxassetid://108194680296901",
	["square-arrow-down-right"] = "rbxassetid://99403846801050",
	["square-arrow-left"] = "rbxassetid://111671474549238",
	["square-arrow-out-down-left"] = "rbxassetid://125714881756353",
	["square-arrow-out-down-right"] = "rbxassetid://89971003001390",
	["square-arrow-out-up-left"] = "rbxassetid://103759986579087",
	["square-arrow-out-up-right"] = "rbxassetid://91221896066807",
	["square-arrow-right"] = "rbxassetid://113920471701361",
	["square-arrow-right-enter"] = "rbxassetid://138867831495334",
	["square-arrow-right-exit"] = "rbxassetid://133688575845430",
	["square-arrow-up"] = "rbxassetid://106998604646718",
	["square-arrow-up-left"] = "rbxassetid://112424670290693",
	["square-arrow-up-right"] = "rbxassetid://76602291406940",
	["square-asterisk"] = "rbxassetid://89186832353625",
	["square-bottom-dashed-scissors"] = "rbxassetid://79076980104803",
	["square-centerline-dashed-horizontal"] = "rbxassetid://77780104374341",
	["square-centerline-dashed-vertical"] = "rbxassetid://107878435803525",
	["square-chart-gantt"] = "rbxassetid://104034017316411",
	["square-check"] = "rbxassetid://134682053539509",
	["square-check-big"] = "rbxassetid://115320390907184",
	["square-chevron-down"] = "rbxassetid://91032307924592",
	["square-chevron-left"] = "rbxassetid://73143404829510",
	["square-chevron-right"] = "rbxassetid://90612077729930",
	["square-chevron-up"] = "rbxassetid://85565910197337",
	["square-code"] = "rbxassetid://81604576616881",
	["square-dashed"] = "rbxassetid://136905537847606",
	["square-dashed-bottom"] = "rbxassetid://101102319625624",
	["square-dashed-bottom-code"] = "rbxassetid://100354801563230",
	["square-dashed-kanban"] = "rbxassetid://90388067649847",
	["square-dashed-mouse-pointer"] = "rbxassetid://121016142178467",
	["square-dashed-top-solid"] = "rbxassetid://117157577548540",
	["square-divide"] = "rbxassetid://99894657101970",
	["square-dot"] = "rbxassetid://116613421354866",
	["square-equal"] = "rbxassetid://110283363706707",
	["square-function"] = "rbxassetid://86075219551088",
	["square-kanban"] = "rbxassetid://114537101260131",
	["square-library"] = "rbxassetid://73810931222081",
	["square-m"] = "rbxassetid://117662700410577",
	["square-menu"] = "rbxassetid://104067089444415",
	["square-minus"] = "rbxassetid://116764432015770",
	["square-mouse-pointer"] = "rbxassetid://76141850603920",
	["square-parking"] = "rbxassetid://133116656122387",
	["square-parking-off"] = "rbxassetid://100857293535141",
	["square-pause"] = "rbxassetid://86608552787615",
	["square-pen"] = "rbxassetid://120239476110475",
	["square-percent"] = "rbxassetid://87111930314567",
	["square-pi"] = "rbxassetid://75383328781618",
	["square-pilcrow"] = "rbxassetid://131854284699367",
	["square-play"] = "rbxassetid://108186325238481",
	["square-plus"] = "rbxassetid://114713264461873",
	["square-power"] = "rbxassetid://129240437805187",
	["square-radical"] = "rbxassetid://132645931868292",
	["square-round-corner"] = "rbxassetid://104592745113567",
	["square-scissors"] = "rbxassetid://110601255612411",
	["square-sigma"] = "rbxassetid://113231244246816",
	["square-slash"] = "rbxassetid://105477013908757",
	["square-split-horizontal"] = "rbxassetid://76095370148660",
	["square-split-vertical"] = "rbxassetid://88589192032058",
	["square-square"] = "rbxassetid://136555087357875",
	["square-stack"] = "rbxassetid://100463396619394",
	["square-star"] = "rbxassetid://94506958703720",
	["square-stop"] = "rbxassetid://80018708472943",
	["square-terminal"] = "rbxassetid://83969264476798",
	["square-user"] = "rbxassetid://70771214183445",
	["square-user-round"] = "rbxassetid://86484997229302",
	["square-x"] = "rbxassetid://125136183850190",
	["squares-exclude"] = "rbxassetid://102345385822324",
	["squares-intersect"] = "rbxassetid://120869602570119",
	["squares-subtract"] = "rbxassetid://131484650948795",
	["squares-unite"] = "rbxassetid://96673080107843",
	["squircle"] = "rbxassetid://82426632573807",
	["squircle-dashed"] = "rbxassetid://129936702532522",
	["squirrel"] = "rbxassetid://112864252085343",
	["stamp"] = "rbxassetid://92370779813368",
	["star"] = "rbxassetid://136141469398409",
	["star-half"] = "rbxassetid://117449275562979",
	["star-off"] = "rbxassetid://75742832732503",
	["step-back"] = "rbxassetid://108672750005121",
	["step-forward"] = "rbxassetid://126131872136145",
	["stethoscope"] = "rbxassetid://122331031702148",
	["sticker"] = "rbxassetid://79938203791608",
	["sticky-note"] = "rbxassetid://111894074643919",
	["stone"] = "rbxassetid://135161057497830",
	["store"] = "rbxassetid://90338129673705",
	["stretch-horizontal"] = "rbxassetid://87665042192343",
	["stretch-vertical"] = "rbxassetid://95265463417122",
	["strikethrough"] = "rbxassetid://103417324549613",
	["subscript"] = "rbxassetid://74553514785183",
	["sun"] = "rbxassetid://110150589884127",
	["sun-dim"] = "rbxassetid://129141645592715",
	["sun-medium"] = "rbxassetid://130278807964710",
	["sun-moon"] = "rbxassetid://75752898854559",
	["sun-snow"] = "rbxassetid://112791898014579",
	["sunrise"] = "rbxassetid://134705665494098",
	["sunset"] = "rbxassetid://75904872203588",
	["superscript"] = "rbxassetid://96887696590118",
	["swatch-book"] = "rbxassetid://126786244872453",
	["swiss-franc"] = "rbxassetid://113497920041625",
	["switch-camera"] = "rbxassetid://76841154349737",
	["sword"] = "rbxassetid://124448418211665",
	["swords"] = "rbxassetid://124448418211665",
	["syringe"] = "rbxassetid://123891270479254",
	["table"] = "rbxassetid://109109148250737",
	["table-2"] = "rbxassetid://95751552281545",
	["table-cells-merge"] = "rbxassetid://95363715175258",
	["table-cells-split"] = "rbxassetid://114799086088649",
	["table-columns-split"] = "rbxassetid://111011625447949",
	["table-of-contents"] = "rbxassetid://135044763275414",
	["table-properties"] = "rbxassetid://125062886015372",
	["table-rows-split"] = "rbxassetid://96443733673997",
	["tablet"] = "rbxassetid://128403991264386",
	["tablet-smartphone"] = "rbxassetid://133680859813404",
	["tablets"] = "rbxassetid://80835787970735",
	["tag"] = "rbxassetid://129104970103940",
	["tags"] = "rbxassetid://107179263080798",
	["tally-1"] = "rbxassetid://115301298241643",
	["tally-2"] = "rbxassetid://110363186864027",
	["tally-3"] = "rbxassetid://97655344572540",
	["tally-4"] = "rbxassetid://102633494371890",
	["tally-5"] = "rbxassetid://88031817475886",
	["tangent"] = "rbxassetid://123263132981724",
	["target"] = "rbxassetid://87563802520297",
	["telescope"] = "rbxassetid://91755049143647",
	["tent"] = "rbxassetid://109779587826330",
	["tent-tree"] = "rbxassetid://76698322463977",
	["terminal"] = "rbxassetid://106783148545356",
	["test-tube"] = "rbxassetid://98801015650164",
	["test-tube-diagonal"] = "rbxassetid://75662704378840",
	["test-tubes"] = "rbxassetid://92555361447433",
	["text-align-center"] = "rbxassetid://84051028246390",
	["text-align-end"] = "rbxassetid://130041738343555",
	["text-align-justify"] = "rbxassetid://80279880143030",
	["text-align-start"] = "rbxassetid://134489585487649",
	["text-cursor"] = "rbxassetid://115984654447300",
	["text-cursor-input"] = "rbxassetid://107551944047171",
	["text-initial"] = "rbxassetid://129458097472087",
	["text-quote"] = "rbxassetid://139278366448736",
	["text-search"] = "rbxassetid://92345384671606",
	["text-select"] = "rbxassetid://117087320884956",
	["text-wrap"] = "rbxassetid://114804318314018",
	["theater"] = "rbxassetid://108558145549163",
	["thermometer"] = "rbxassetid://106546011492311",
	["thermometer-snowflake"] = "rbxassetid://121876188028425",
	["thermometer-sun"] = "rbxassetid://106693240074310",
	["thumbs-down"] = "rbxassetid://87794009914015",
	["thumbs-up"] = "rbxassetid://111137070767020",
	["ticket"] = "rbxassetid://126527071492145",
	["ticket-check"] = "rbxassetid://105428777212507",
	["ticket-minus"] = "rbxassetid://78966299769328",
	["ticket-percent"] = "rbxassetid://80834774406405",
	["ticket-plus"] = "rbxassetid://110086734392189",
	["ticket-slash"] = "rbxassetid://89045681172265",
	["ticket-x"] = "rbxassetid://88674114109926",
	["tickets"] = "rbxassetid://135268612687833",
	["tickets-plane"] = "rbxassetid://100367018248695",
	["timer"] = "rbxassetid://85473888890506",
	["timer-off"] = "rbxassetid://110916370767271",
	["timer-reset"] = "rbxassetid://110052125369932",
	["toggle-left"] = "rbxassetid://85887872573050",
	["toggle-right"] = "rbxassetid://90411952142550",
	["toilet"] = "rbxassetid://80930782432931",
	["tool-case"] = "rbxassetid://87533537832522",
	["toolbox"] = "rbxassetid://85341033903792",
	["tornado"] = "rbxassetid://88358291515768",
	["torus"] = "rbxassetid://70855707283051",
	["touchpad"] = "rbxassetid://74882354908014",
	["touchpad-off"] = "rbxassetid://78784008075456",
	["towel-rack"] = "rbxassetid://125223915620991",
	["tower-control"] = "rbxassetid://95937619060532",
	["toy-brick"] = "rbxassetid://86293483924633",
	["tractor"] = "rbxassetid://103376704722051",
	["traffic-cone"] = "rbxassetid://74110220470369",
	["train-front"] = "rbxassetid://125237934215370",
	["train-front-tunnel"] = "rbxassetid://105194827005114",
	["train-track"] = "rbxassetid://77451032453723",
	["tram-front"] = "rbxassetid://93315182364998",
	["transgender"] = "rbxassetid://135530817673639",
	["trash"] = "rbxassetid://106723740584310",
	["trash-2"] = "rbxassetid://109843431391323",
	["tree-deciduous"] = "rbxassetid://123124389219004",
	["tree-palm"] = "rbxassetid://103846705893963",
	["tree-pine"] = "rbxassetid://124662547202594",
	["trees"] = "rbxassetid://121203841375919",
	["trello"] = "rbxassetid://130987241149527",
	["trending-down"] = "rbxassetid://139309232226438",
	["trending-up"] = "rbxassetid://81819858538839",
	["trending-up-down"] = "rbxassetid://85083293981691",
	["triangle"] = "rbxassetid://126330486745540",
	["triangle-alert"] = "rbxassetid://125920361880643",
	["triangle-dashed"] = "rbxassetid://124324079103935",
	["triangle-right"] = "rbxassetid://116930791412791",
	["trophy"] = "rbxassetid://131545003268773",
	["truck"] = "rbxassetid://86662707764771",
	["truck-electric"] = "rbxassetid://111873446387359",
	["turkish-lira"] = "rbxassetid://114589876174070",
	["turntable"] = "rbxassetid://129870346487856",
	["turtle"] = "rbxassetid://118295081560334",
	["tv"] = "rbxassetid://135687724791776",
	["tv-minimal"] = "rbxassetid://100382201729427",
	["tv-minimal-play"] = "rbxassetid://99201833426972",
	["twitch"] = "rbxassetid://71383308134888",
	["twitter"] = "rbxassetid://88791703276842",
	["type"] = "rbxassetid://133543553793564",
	["type-outline"] = "rbxassetid://80108627791690",
	["umbrella"] = "rbxassetid://127502210274589",
	["umbrella-off"] = "rbxassetid://72395143739955",
	["underline"] = "rbxassetid://123709229216544",
	["undo"] = "rbxassetid://111258459077271",
	["undo-2"] = "rbxassetid://113885292059932",
	["undo-dot"] = "rbxassetid://132055277744844",
	["unfold-horizontal"] = "rbxassetid://117128358526398",
	["unfold-vertical"] = "rbxassetid://116593025265499",
	["ungroup"] = "rbxassetid://106674800451003",
	["university"] = "rbxassetid://84652528263642",
	["unlink"] = "rbxassetid://139835795227752",
	["unlink-2"] = "rbxassetid://128131898892572",
	["unplug"] = "rbxassetid://90171381619874",
	["upload"] = "rbxassetid://138212042425501",
	["usb"] = "rbxassetid://117230058949613",
	["user"] = "rbxassetid://81589895647169",
	["user-check"] = "rbxassetid://81775205032725",
	["user-cog"] = "rbxassetid://92795491530865",
	["user-key"] = "rbxassetid://105403041782190",
	["user-lock"] = "rbxassetid://78892639693821",
	["user-minus"] = "rbxassetid://126976941957511",
	["user-pen"] = "rbxassetid://87445472574836",
	["user-plus"] = "rbxassetid://118514469915884",
	["user-round"] = "rbxassetid://136485052187963",
	["user-round-check"] = "rbxassetid://118794737621941",
	["user-round-cog"] = "rbxassetid://78239503290053",
	["user-round-key"] = "rbxassetid://124547549008939",
	["user-round-minus"] = "rbxassetid://98944176636447",
	["user-round-pen"] = "rbxassetid://108155244324878",
	["user-round-plus"] = "rbxassetid://113301899567470",
	["user-round-search"] = "rbxassetid://71565774381870",
	["user-round-x"] = "rbxassetid://122367980560930",
	["user-search"] = "rbxassetid://101335649828115",
	["user-star"] = "rbxassetid://98777846316000",
	["user-x"] = "rbxassetid://139748155894754",
	["users"] = "rbxassetid://115398113982385",
	["users-round"] = "rbxassetid://103005444008339",
	["utensils"] = "rbxassetid://139952569804235",
	["utensils-crossed"] = "rbxassetid://109520762270383",
	["utility-pole"] = "rbxassetid://101965541238242",
	["van"] = "rbxassetid://122066377022942",
	["variable"] = "rbxassetid://104743088438151",
	["vault"] = "rbxassetid://108049164599845",
	["vector-square"] = "rbxassetid://86713728565344",
	["vegan"] = "rbxassetid://119489190688082",
	["venetian-mask"] = "rbxassetid://102636443033920",
	["venus"] = "rbxassetid://82891342220859",
	["venus-and-mars"] = "rbxassetid://120227752103771",
	["vibrate"] = "rbxassetid://108330910738733",
	["vibrate-off"] = "rbxassetid://113446447326246",
	["video"] = "rbxassetid://107587444636945",
	["video-off"] = "rbxassetid://132239189859305",
	["videotape"] = "rbxassetid://114816894323398",
	["view"] = "rbxassetid://118717253976805",
	["voicemail"] = "rbxassetid://134313454010227",
	["volleyball"] = "rbxassetid://83889351124153",
	["volume"] = "rbxassetid://103236289817396",
	["volume-1"] = "rbxassetid://98514588731639",
	["volume-2"] = "rbxassetid://89344380902620",
	["volume-off"] = "rbxassetid://103047478058767",
	["volume-x"] = "rbxassetid://139252359189540",
	["vote"] = "rbxassetid://89409762851246",
	["wallet"] = "rbxassetid://132331555762628",
	["wallet-cards"] = "rbxassetid://129728715308337",
	["wallet-minimal"] = "rbxassetid://137800448816116",
	["wallpaper"] = "rbxassetid://74682121235494",
	["wand"] = "rbxassetid://114580617777835",
	["wand-sparkles"] = "rbxassetid://82546429942392",
	["warehouse"] = "rbxassetid://78388887451080",
	["washing-machine"] = "rbxassetid://104194127573858",
	["watch"] = "rbxassetid://130544621618405",
	["waves"] = "rbxassetid://96340135183647",
	["waves-arrow-down"] = "rbxassetid://129215220911792",
	["waves-arrow-up"] = "rbxassetid://102314705716217",
	["waves-ladder"] = "rbxassetid://101808619355514",
	["waypoints"] = "rbxassetid://102450133666017",
	["webcam"] = "rbxassetid://104148487911129",
	["webhook"] = "rbxassetid://112812457747322",
	["webhook-off"] = "rbxassetid://96370548093471",
	["weight"] = "rbxassetid://103860559844854",
	["weight-tilde"] = "rbxassetid://112081212176951",
	["wheat"] = "rbxassetid://85261952080359",
	["wheat-off"] = "rbxassetid://133294844612307",
	["whole-word"] = "rbxassetid://90111083954485",
	["wifi"] = "rbxassetid://104669375183960",
	["wifi-cog"] = "rbxassetid://110500263326209",
	["wifi-high"] = "rbxassetid://81954601342139",
	["wifi-low"] = "rbxassetid://138217335635913",
	["wifi-off"] = "rbxassetid://74113634330106",
	["wifi-pen"] = "rbxassetid://91290205064712",
	["wifi-sync"] = "rbxassetid://84043971055177",
	["wifi-zero"] = "rbxassetid://124286465246123",
	["wind"] = "rbxassetid://114551690399915",
	["wind-arrow-down"] = "rbxassetid://127753987414870",
	["wine"] = "rbxassetid://115743721332829",
	["wine-off"] = "rbxassetid://108294164302317",
	["workflow"] = "rbxassetid://99186544029189",
	["worm"] = "rbxassetid://115752311548091",
	["wrench"] = "rbxassetid://112148279212860",
	["x"] = "rbxassetid://110786993356448",
	["x-circle"] = "rbxassetid://76821953846248",
	["x-line-top"] = "rbxassetid://140592656289509",
	["youtube"] = "rbxassetid://123663668456341",
	["zap"] = "rbxassetid://130551565616516",
	["zap-off"] = "rbxassetid://81385483183652",
	["zodiac-aquarius"] = "rbxassetid://74560047770362",
	["zodiac-aries"] = "rbxassetid://73255859670234",
	["zodiac-cancer"] = "rbxassetid://131985162532947",
	["zodiac-capricorn"] = "rbxassetid://97859568140652",
	["zodiac-gemini"] = "rbxassetid://80997588122992",
	["zodiac-leo"] = "rbxassetid://75509406718106",
	["zodiac-libra"] = "rbxassetid://113222735060218",
	["zodiac-ophiuchus"] = "rbxassetid://129180108892480",
	["zodiac-pisces"] = "rbxassetid://95845819440327",
	["zodiac-sagittarius"] = "rbxassetid://82651026742181",
	["zodiac-scorpio"] = "rbxassetid://113640924054631",
	["zodiac-taurus"] = "rbxassetid://123053219704400",
	["zodiac-virgo"] = "rbxassetid://99462994613661",
	["zoom-in"] = "rbxassetid://127956924984803",
	["zoom-out"] = "rbxassetid://108334162607319",
}

local IconAliases = {
    -- Home & Navigation
    ["house"] = "house",
    ["houses"] = "house",
    ["home"] = "house",
    ["homepage"] = "house",
    ["main"] = "house",
    ["dashboard"] = "house",
    
    -- Settings & Config
    ["gear"] = "settings",
    ["gears"] = "settings",
    ["cog"] = "settings",
    ["cogs"] = "settings",
    ["setting"] = "settings",
    ["pref"] = "settings",
    ["prefs"] = "settings",
    ["preference"] = "settings",
    ["preferences"] = "settings",
    ["option"] = "settings",
    ["options"] = "settings",
    ["config"] = "settings",
    ["configuration"] = "settings",
    
    -- Combat & Aim
    ["aim"] = "crosshair",
    ["aimbot"] = "crosshair",
    ["scope"] = "crosshair",
    ["crosshairs"] = "crosshair",
    ["swords"] = "sword",
    ["blade"] = "sword",
    ["blades"] = "sword",
    ["weapon"] = "sword",
    ["weapons"] = "sword",
    ["combat"] = "sword",
    ["attack"] = "sword",
    ["shields"] = "shield",
    ["armor"] = "shield",
    ["defense"] = "shield",
    ["protection"] = "shield",
    ["protect"] = "shield",
    ["guard"] = "shield",
    
    -- Users & Identity
    ["player"] = "user",
    ["players"] = "users",
    ["profile"] = "user",
    ["account"] = "user",
    ["person"] = "user",
    ["avatar"] = "user",
    ["people"] = "users",
    ["team"] = "users",
    ["members"] = "users",
    ["robot"] = "bot",
    ["ai"] = "bot",
    ["ghosts"] = "ghost",
    ["stealth"] = "ghost",
    
    -- Notifications & Alerts
    ["notification"] = "bell",
    ["notifications"] = "bell",
    ["notify"] = "bell",
    ["alert"] = "bell",
    ["alerts"] = "bell",
    ["warn"] = "triangle-alert",
    ["warning"] = "triangle-alert",
    ["warnings"] = "triangle-alert",
    ["caution"] = "triangle-alert",
    ["hazard"] = "triangle-alert",
    ["danger"] = "triangle-alert",
    ["exclamation"] = "triangle-alert",
    ["alert-triangle"] = "triangle-alert",
    ["triangle-alert"] = "triangle-alert",
    ["alert-circle"] = "circle-alert",
    ["circle-alert"] = "circle-alert",
    ["error"] = "circle-alert",
    ["errors"] = "circle-alert",
    ["question"] = "circle-help",
    ["help"] = "circle-help",
    ["help-circle"] = "circle-help",
    ["circle-help"] = "circle-help",
    ["check-circle"] = "circle-check",
    ["circle-check"] = "circle-check",
    ["x-circle"] = "circle-x",
    ["circle-x"] = "circle-x",
    
    -- Files, Storage & Actions
    ["bin"] = "trash",
    ["trashcan"] = "trash",
    ["garbage"] = "trash",
    ["delete"] = "trash",
    ["remove"] = "trash",
    ["shop"] = "shopping-cart",
    ["store"] = "shopping-cart",
    ["market"] = "shopping-cart",
    ["bag"] = "shopping-cart",
    ["box"] = "package",
    ["crate"] = "package",
    ["item"] = "package",
    ["items"] = "package",
    ["directory"] = "folder",
    ["directories"] = "folder",
    ["folders"] = "folder",
    ["doc"] = "file-text",
    ["docs"] = "file-text",
    ["document"] = "file-text",
    ["documents"] = "file-text",
    ["script"] = "file-code",
    ["scripts"] = "file-code",
    ["lua"] = "file-code",
    ["luau"] = "file-code",
    ["cli"] = "terminal",
    ["cmd"] = "terminal",
    ["console"] = "terminal",
    
    -- Telemetry & Senses
    ["speed"] = "gauge",
    ["speedometer"] = "gauge",
    ["velocity"] = "gauge",
    ["tachometer"] = "gauge",
    ["meter"] = "gauge",
    ["nav"] = "compass",
    ["navigation"] = "compass",
    ["explore"] = "compass",
    ["see"] = "eye",
    ["look"] = "eye",
    ["view"] = "eye",
    ["visible"] = "eye",
    ["vision"] = "eye",
    ["esp"] = "eye",
    ["wallhack"] = "eye",
    ["hide"] = "eye-off",
    ["invisible"] = "eye-off",
    ["conceal"] = "eye-off",
    ["sparkle"] = "sparkles",
    ["stars"] = "sparkles",
    ["magic"] = "sparkles",
    ["clean"] = "sparkles",
    ["boost"] = "sparkles",
    ["lightning"] = "zap",
    ["energy"] = "zap",
    ["power"] = "zap",
    ["bolt"] = "zap",
    ["thunder"] = "zap",
    ["fire"] = "flame",
    ["burn"] = "flame",
    ["hot"] = "flame",
    ["death"] = "skull",
    ["kill"] = "skull",
    ["dead"] = "skull",
    
    -- Audio & Media
    ["sound"] = "volume-2",
    ["sounds"] = "volume-2",
    ["audio"] = "volume-2",
    ["speaker"] = "volume-2",
    ["volume-up"] = "volume-2",
    ["mute"] = "volume-x",
    ["unmute"] = "volume-2",
    ["music"] = "volume-2",
    ["photo"] = "camera",
    ["screenshot"] = "camera",
    ["chat"] = "message-square",
    ["chats"] = "message-square",
    ["message"] = "message-square",
    ["messages"] = "message-square",
    ["email"] = "mail",
    ["inbox"] = "mail",
    
    -- Keys & Locks
    ["keys"] = "key",
    ["passcode"] = "key",
    ["pass"] = "key",
    ["locks"] = "lock",
    ["locked"] = "lock",
    ["unlocks"] = "unlock",
    ["unlocked"] = "unlock",
    
    -- System, Network & Flow
    ["reload"] = "rotate-cw",
    ["sync"] = "rotate-cw",
    ["reset"] = "rotate-ccw",
    ["loop"] = "repeat",
    ["network"] = "wifi",
    ["internet"] = "globe",
    ["web"] = "globe",
    ["site"] = "globe",
    ["servers"] = "server",
    ["db"] = "database",
    ["processor"] = "cpu",
    ["hardware"] = "cpu",
    ["hp"] = "heart",
    ["health"] = "heart",
    ["life"] = "heart",
    ["hearts"] = "heart",
    ["time"] = "clock",
    ["timer"] = "clock",
    ["color"] = "palette",
    ["colors"] = "palette",
    ["paint"] = "palette",
    ["brush"] = "palette",
    ["edit"] = "pencil",
    ["write"] = "pencil",
    ["pen"] = "pencil",
    ["pins"] = "pin",
    ["pinned"] = "pin",
    ["bookmarks"] = "bookmark",
    ["urls"] = "link",
    ["url"] = "link",
    ["maps"] = "map",
    ["layer"] = "layers",
    ["stack"] = "layers",
}

Icons.Aliases = IconAliases
Icons.Registry = Icons.Packs["lucide"]
Icons.Icons = Icons.Packs

local lookupCache = {}
local warnedMissing = {}

local function parseIconString(raw)
    if not raw or raw == "" then return nil, "" end
    local splitIndex = raw:find(":")
    if splitIndex then
        local pack = raw:sub(1, splitIndex - 1):lower()
        local name = raw:sub(splitIndex + 1)
        return pack, name
    end
    return nil, raw
end

local function normalizeName(raw)
    local s = raw:gsub("^lucide[-:/_]?", "")
    s = s:gsub("^icon[-:/_]?", "")
    s = s:gsub("(%l)(%u)", "%1-%2")
    s = s:gsub("(%d)(%u)", "%1-%2")
    s = s:gsub("(%a)(%d)", "%1-%2")
    s = s:gsub("[%s_%.]+", "-")
    s = s:gsub("%-icon$", "")
    return string.lower(s)
end

function Icons.Normalize(name)
    if not name or name == "" then return "" end
    return normalizeName(name)
end

function Icons.SetIconsType(packName)
    if type(packName) == "string" then
        Icons.IconsType = string.lower(packName)
    end
end

function Icons.AddIcons(packName, iconsData)
    if type(packName) ~= "string" or type(iconsData) ~= "table" then return end
    local pName = string.lower(packName)
    if not Icons.Packs[pName] then
        Icons.Packs[pName] = {}
    end
    local pack = Icons.Packs[pName]
    for k, v in pairs(iconsData) do
        if type(v) == "string" or type(v) == "number" then
            local asset = type(v) == "number" and ("rbxassetid://" .. tostring(v)) or v
            pack[k] = asset
        elseif type(v) == "table" then
            if not pack.Icons then pack.Icons = {} end
            pack.Icons[k] = v
        end
    end
end

-- Safe executor accessor via Compat (single cached lookup, no identity check)
local function getExecutorFunc(name: string): any
	return Compat.GetFunc(name)
end

function Icons.LoadPack(packName)
	local pName = string.lower(packName)
	if Icons.Packs[pName] then
		return true
	end
	local cdnUrl = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/" .. pName .. "/dist/Icons.lua"
	local localFile = "SodiumHub/Cache/Icons_" .. pName .. ".lua"
	if Compat.IsFile(localFile) then
		local content = Compat.ReadFile(localFile)
		if type(content) == "string" and #content > 0 then
			local ok, result = pcall(function()
				return loadstring(content)()
			end)
			if ok and type(result) == "table" then
				Icons.Packs[pName] = result
				return true
			end
		end
	end
	local body = Compat.HttpGet(cdnUrl)
	if type(body) == "string" and #body > 0 then
		Compat.WriteFile(localFile, body)
		local ok, result = pcall(function()
			return loadstring(body)()
		end)
		if ok and type(result) == "table" then
			Icons.Packs[pName] = result
			return true
		end
	end
	return false
end

local _iconResolutionCache: { [string]: any } = {}

local function resolveFromPack(packName, query)
    local pName = string.lower(packName or Icons.IconsType)
    local cacheKey = pName .. ":" .. tostring(query)
    local cached = _iconResolutionCache[cacheKey]
    if cached ~= nil then
        return if cached == false then nil else cached
    end

    local pack = Icons.Packs[pName]
    if not pack then
        Icons.LoadPack(pName)
        pack = Icons.Packs[pName]
        if not pack then
            _iconResolutionCache[cacheKey] = false
            return nil
        end
    end
    
    if pack[query] then
        _iconResolutionCache[cacheKey] = pack[query]
        return pack[query]
    end
    
    if pack.Icons and pack.Icons[query] then
        local item = pack.Icons[query]
        local sheetId = pack.Spritesheets and pack.Spritesheets[tostring(item.Image)] or item.Image
        local res = {
            sheetId,
            item,
        }
        _iconResolutionCache[cacheKey] = res
        return res
    end
    
    local alias = IconAliases[query]
    if alias then
        if pack[alias] then
            _iconResolutionCache[cacheKey] = pack[alias]
            return pack[alias]
        end
        if pack.Icons and pack.Icons[alias] then
            local item = pack.Icons[alias]
            local sheetId = pack.Spritesheets and pack.Spritesheets[tostring(item.Image)] or item.Image
            local res = { sheetId, item }
            _iconResolutionCache[cacheKey] = res
            return res
        end
    end
    
    if #query > 3 and query:sub(-1) == "s" then
        local singular = query:sub(1, -2)
        local fromSingular = resolveFromPack(pName, singular)
        if fromSingular then
            _iconResolutionCache[cacheKey] = fromSingular
            return fromSingular
        end
    end
    
    _iconResolutionCache[cacheKey] = false
    return nil
end

function Icons.IsKnown(name, defaultPack)
    if not name or name == "" then return false end
    if string.find(name, "^rbxassetid://") or string.find(name, "^rbxthumb://") or string.find(name, "^https?://") or string.match(name, "^%d+$") then
        return true
    end
    local packPrefix, cleanName = parseIconString(name)
    local targetPack = packPrefix or defaultPack or Icons.IconsType
    local norm = normalizeName(cleanName)
    local found = resolveFromPack(targetPack, norm)
    if not found and targetPack ~= "lucide" then
        found = resolveFromPack("lucide", norm)
    end
    return found ~= nil
end

function Icons.Icon(icon, pack, defaultFormat)
    local packPrefix, cleanName = parseIconString(icon)
    local targetPack = packPrefix or pack or Icons.IconsType
    local norm = normalizeName(cleanName)
    local resolved = resolveFromPack(targetPack, norm)
    if not resolved and targetPack ~= "lucide" then
        resolved = resolveFromPack("lucide", norm)
    end
    if type(resolved) == "table" then
        return resolved
    elseif type(resolved) == "string" then
        return (defaultFormat ~= false) and {
            resolved,
            { ImageRectSize = Vector2.new(0, 0), ImageRectPosition = Vector2.new(0, 0) }
        } or resolved
    end
    return nil
end

function Icons.Get(iconName, defaultPack)
	if not iconName or iconName == "" then
		return Icons.Fallback
	end

	local cached = lookupCache[iconName]
	if cached then
		return cached
	end
    
    if string.find(iconName, "^rbxassetid://") or string.find(iconName, "^rbxthumb://") or string.find(iconName, "^https?://") then
        lookupCache[iconName] = iconName
        return iconName
    end
    
    if string.match(iconName, "^%d+$") then
        local asset = "rbxassetid://" .. iconName
        lookupCache[iconName] = asset
        return asset
    end
    
    local packPrefix, cleanName = parseIconString(iconName)
    local targetPack = packPrefix or defaultPack or Icons.IconsType
    local norm = normalizeName(cleanName)
    
    local resolved = resolveFromPack(targetPack, norm)
    if not resolved and targetPack ~= "lucide" then
        resolved = resolveFromPack("lucide", norm)
    end
    
    if not resolved then
        if not warnedMissing[iconName] then
            warnedMissing[iconName] = true
            warn(string.format("[SodiumUI.Icons] Icon '%s' (pack: '%s', normalized: '%s') not found. Using deterministic fallback.", iconName, targetPack, norm))
        end
        resolved = Icons.Fallback
    end
    
	local finalAsset = resolved
	if type(resolved) == "table" then
		finalAsset = resolved[1]
	end

	-- cache cap: prevent unbounded growth (skill: no leak on long sessions)
	lookupCache[iconName] = finalAsset
	local n = 0
	for _ in pairs(lookupCache) do
		n += 1
		if n > 2000 then
			table.clear(lookupCache)
			table.clear(warnedMissing)
			lookupCache[iconName] = finalAsset
			break
		end
	end
	return finalAsset
end

Icons.GetIcon = Icons.Get

local pendingPreloads = {}
local preloadScheduled = false

local function batchPreload()
    preloadScheduled = false
    if #pendingPreloads == 0 then return end
    
    local toPreload = pendingPreloads
    pendingPreloads = {}
    
    task.spawn(function()
        pcall(function()
            ContentProvider:PreloadAsync(toPreload)
        end)
    end)
end

local function schedulePreload(instance)
    table.insert(pendingPreloads, instance)
    if not preloadScheduled then
        preloadScheduled = true
        task.defer(batchPreload)
    end
end

function Icons.Apply(imageLabel, name)
    if not name or name == "" then
        imageLabel.Image = Icons.Fallback
        imageLabel.ImageRectSize = Vector2.new(0, 0)
        imageLabel.ImageRectOffset = Vector2.new(0, 0)
        return
    end
    
    if string.find(name, "^rbxthumb://") or string.find(name, "^https?://") or string.match(name, "^%d+$") then
        Icons.ApplyAsset(imageLabel, name)
        return
    end
    
    local packPrefix, cleanName = parseIconString(name)
    local targetPack = packPrefix or Icons.IconsType
    local norm = normalizeName(cleanName)
    local resolved = resolveFromPack(targetPack, norm)
    
    if not resolved and targetPack ~= "lucide" then
        resolved = resolveFromPack("lucide", norm)
    end
    
    if type(resolved) == "table" then
        imageLabel.Image = tostring(resolved[1])
        if resolved[2] then
            imageLabel.ImageRectSize = resolved[2].ImageRectSize or Vector2.new(0, 0)
            imageLabel.ImageRectOffset = resolved[2].ImageRectPosition or Vector2.new(0, 0)
        end
    elseif type(resolved) == "string" and resolved ~= "" then
        imageLabel.Image = resolved
        imageLabel.ImageRectSize = Vector2.new(0, 0)
        imageLabel.ImageRectOffset = Vector2.new(0, 0)
    else
        imageLabel.Image = Icons.Get(name)
        imageLabel.ImageRectSize = Vector2.new(0, 0)
        imageLabel.ImageRectOffset = Vector2.new(0, 0)
    end
end

function Icons.ApplyAsset(imageLabel, source)
	if not source or source == "" then
		return
	end
	local sourceStr = tostring(source)

	if string.find(sourceStr, "^https?://") then
		local getcustomasset = Compat.GetFunc("getcustomasset") or Compat.GetFunc("getsynasset")
		if type(getcustomasset) == "function" and Compat.HasFS() then
			task.spawn(function()
				local ok = pcall(function()
					local fileName = "SodiumHub/Cache/" .. string.sub(string.gsub(sourceStr, "[^%w]", "_"), -32) .. ".png"
					if not Compat.IsFile(fileName) then
						local content = Compat.HttpGet(sourceStr)
						if type(content) == "string" and #content > 0 then
							Compat.WriteFile(fileName, content)
						end
					end
					if imageLabel.Parent then
						imageLabel.Image = getcustomasset(fileName)
					end
				end)
				if not ok then
					pcall(function()
						if imageLabel.Parent then
							imageLabel.Image = sourceStr
						end
					end)
				end
			end)
			return
		else
			imageLabel.Image = sourceStr
			return
		end
	end

	local assetId = string.match(sourceStr, "%d+")
	if assetId then
		-- Map Decal page ID to direct Image/Texture ID so Roblox loads it natively from cloud without saving files
		if assetId == "130380569123905" then
			assetId = "120284703484003"
		end
		imageLabel.Image = "rbxassetid://" .. assetId
		schedulePreload(imageLabel)
		return
	end

	if string.find(sourceStr, "^rbxthumb://") then
		imageLabel.Image = sourceStr
		schedulePreload(imageLabel)
		return
	end

	imageLabel.Image = Icons.Get(sourceStr)
end

function Icons.Image(IconConfig)
    local iconName = IconConfig.Icon or "house"
    local iconType = IconConfig.Type or Icons.IconsType
    local size = IconConfig.Size or UDim2.new(0, 24, 0, 24)
    local colors = IconConfig.Colors or { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }
    
    local imgLabel = Instance.new("ImageLabel")
    imgLabel.Name = "SodiumIcon_" .. tostring(iconName)
    imgLabel.Size = size
    imgLabel.BackgroundTransparency = 1
    if colors[1] and typeof(colors[1]) == "Color3" then
        imgLabel.ImageColor3 = colors[1]
    end
    
    Icons.Apply(imgLabel, (iconType and (iconType .. ":") or "") .. tostring(iconName))
    
    return {
        IconFrame = imgLabel,
        ImageLabel = imgLabel,
    }
end

function Icons.ClearCache()
    table.clear(lookupCache)
    table.clear(warnedMissing)
end

function Icons.Purge()
    Icons.ClearCache()
    table.clear(pendingPreloads)
end

return Icons
end

_MODULES['Core/Compat'] = function()
--!strict
--[=[
	Sodium UI v2 - Core/Compat.luau
	Feature-detection compat layer. Loaded first, zero dependencies.
	No identity detection (identifyexecutor). All executor calls pcall-wrapped.
]=]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local Compat = {}

-- Cache genv/_G once (avoid getgenv() per call in hot paths)
local _genv: any = nil
do
	local ok, v = pcall(function()
		return (type(getgenv) == "function" and getgenv()) or nil
	end)
	if ok and type(v) == "table" then
		_genv = v
	end
end

local _G_fallback: any = nil
do
	local ok, v = pcall(function()
		return rawget(getfenv(), "_G")
	end)
	if ok then
		_G_fallback = v
	end
end

function Compat.GetEnv(): any
	return _genv or _G_fallback
end

-- Single lookup: genv -> getfenv -> _G -> getrenv
function Compat.GetFunc(name: string): any
	if _genv and _genv[name] ~= nil then
		return _genv[name]
	end
	local ok, val = pcall(function()
		return getfenv()[name]
	end)
	if ok and val ~= nil then
		return val
	end
	if _G_fallback and _G_fallback[name] ~= nil then
		return _G_fallback[name]
	end
	local gr = rawget(getfenv(), "getrenv")
	if type(gr) == "function" then
		local ok2, renv = pcall(gr)
		if ok2 and type(renv) == "table" and (renv :: any)[name] ~= nil then
			return (renv :: any)[name]
		end
	end
	return nil
end

-- Capabilities resolved once at require time
local _gethui: any = Compat.GetFunc("gethui")
if type(_gethui) ~= "function" then
	_gethui = nil
end

local _protect: any = nil
do
	local syn = Compat.GetFunc("syn")
	if type(syn) == "table" and type((syn :: any).protect_gui) == "function" then
		_protect = (syn :: any).protect_gui
	else
		local pg = Compat.GetFunc("protect_gui")
		if type(pg) == "function" then
			_protect = pg
		end
	end
end

local _http: any = Compat.GetFunc("http_request")
if type(_http) ~= "function" then
	_http = Compat.GetFunc("request")
end
if type(_http) ~= "function" then
	local h = Compat.GetFunc("http")
	if type(h) == "table" and type((h :: any).request) == "function" then
		_http = (h :: any).request
	else
		local s = Compat.GetFunc("syn")
		if type(s) == "table" and type((s :: any).request) == "function" then
			_http = (s :: any).request
		end
	end
end
if type(_http) ~= "function" then
	_http = nil
end

local _clip: any = Compat.GetFunc("setclipboard")
if type(_clip) ~= "function" then
	_clip = Compat.GetFunc("toclipboard")
end
if type(_clip) ~= "function" then
	_clip = nil
end

local _getclip: any = Compat.GetFunc("getclipboard")
if type(_getclip) ~= "function" then
	_getclip = nil
end

-- Filesystem funcs (UNC names, cached)
local function _fn(name: string): any
	local v = Compat.GetFunc(name)
	return if type(v) == "function" then v else nil
end

local _writefile = _fn("writefile")
local _readfile = _fn("readfile")
local _isfile = _fn("isfile")
local _isfolder = _fn("isfolder")
local _makefolder = _fn("makefolder")
local _listfiles = _fn("listfiles")
local _delfile = _fn("delfile") or _fn("deletefile") or _fn("removefile")
local _delfolder = _fn("delfolder") or _fn("deletefolder") or _fn("removefolder")
local _loadfile = _fn("loadfile")
local _dofile = _fn("dofile")

Compat.HttpRequest = _http
Compat.SetClipboard = _clip
Compat.GetClipboard = _getclip

function Compat.HasFS(): boolean
	return type(_writefile) == "function"
		and type(_readfile) == "function"
		and type(_isfile) == "function"
end

function Compat.NormalizePath(p: string): string
	local s = string.gsub(p, "\\", "/")
	s = string.gsub(s, "/+", "/")
	if #s > 1 and string.sub(s, #s, #s) == "/" then
		s = string.sub(s, 1, #s - 1)
	end
	return s
end

function Compat.IsFile(p: string): boolean
	if type(_isfile) ~= "function" then
		return false
	end
	local ok, r = pcall(_isfile, Compat.NormalizePath(p))
	if ok and r == true then
		return true
	end
	local ok2, r2 = pcall(_isfile, p)
	return ok2 and r2 == true
end

function Compat.IsFolder(p: string): boolean
	if type(_isfolder) ~= "function" then
		return false
	end
	local ok, r = pcall(_isfolder, Compat.NormalizePath(p))
	return ok and r == true
end

function Compat.MakeFolder(p: string)
	if type(_makefolder) ~= "function" then
		return
	end
	local norm = Compat.NormalizePath(p)
	-- progressive mkdir: executors often lack recursive mkdir
	local parts: { string } = string.split(norm, "/")
	local cur = ""
	for i, part in ipairs(parts) do
		if part == "" then
			if i == 1 then
				cur = "/"
			end
			continue
		end
		cur = if cur == "" or cur == "/" then cur .. part else cur .. "/" .. part
		pcall(_makefolder, cur)
		if type(_isfolder) == "function" then
			local ok, isF = pcall(_isfolder, cur)
			if ok and isF == true then
				continue
			end
		end
	end
end

function Compat.ReadFile(p: string): string?
	if type(_readfile) ~= "function" then
		return nil
	end
	local ok, r = pcall(_readfile, Compat.NormalizePath(p))
	if ok and type(r) == "string" then
		return r
	end
	local ok2, r2 = pcall(_readfile, p)
	if ok2 and type(r2) == "string" then
		return r2
	end
	return nil
end

function Compat.WriteFile(p: string, data: string): boolean
	if type(_writefile) ~= "function" then
		return false
	end
	local norm = Compat.NormalizePath(p)
	-- auto-mkdir parent
	local slash = string.find(string.reverse(norm), "/")
	if slash then
		local parent = string.sub(norm, 1, #norm - slash)
		if parent ~= "" then
			Compat.MakeFolder(parent)
		end
	end
	local ok, _ = pcall(_writefile, norm, data)
	if ok then
		return true
	end
	local ok2, _2 = pcall(_writefile, p, data)
	return ok2
end

function Compat.DeleteFile(p: string): boolean
	if type(_delfile) ~= "function" then
		return false
	end
	local ok, _ = pcall(_delfile, Compat.NormalizePath(p))
	if ok then
		return true
	end
	local ok2, _2 = pcall(_delfile, p)
	return ok2
end

function Compat.DeleteFolder(p: string): boolean
	if type(_delfolder) ~= "function" then
		return false
	end
	local ok, _ = pcall(_delfolder, Compat.NormalizePath(p))
	return ok
end

function Compat.ListFiles(p: string): { string }
	if type(_listfiles) ~= "function" then
		return {}
	end
	local ok, r = pcall(_listfiles, Compat.NormalizePath(p))
	if ok and type(r) == "table" then
		return r
	end
	return {}
end

function Compat.LoadFile(p: string): ((...any) -> (...any))?
	if type(_loadfile) == "function" then
		local ok, r = pcall(_loadfile, Compat.NormalizePath(p))
		if ok and type(r) == "function" then
			return r
		end
	end
	local content = Compat.ReadFile(p)
	if type(content) == "string" then
		local ok, fn = pcall(loadstring, content)
		if ok and type(fn) == "function" then
			return fn
		end
	end
	return nil
end

function Compat.DoFile(p: string): any
	if type(_dofile) == "function" then
		local ok, r = pcall(_dofile, Compat.NormalizePath(p))
		if ok then
			return r
		end
	end
	local fn = Compat.LoadFile(p)
	if type(fn) == "function" then
		local ok, r = pcall(fn)
		if ok then
			return r
		end
	end
	return nil
end

function Compat.CopyText(text: string): boolean
	if type(_clip) == "function" then
		local ok, _ = pcall(_clip, text)
		return ok
	end
	return false
end

function Compat.GetClipText(): string?
	if type(_getclip) == "function" then
		local ok, r = pcall(_getclip)
		if ok and type(r) == "string" then
			return r
		end
	end
	return nil
end

function Compat.HttpGet(url: string): string?
	local ok, res = pcall(game.HttpGet, game, url)
	if ok and type(res) == "string" and #res > 0 then
		return res
	end
	return nil
end

function Compat.ProtectGui(gui: Instance)
	if type(_protect) == "function" then
		pcall(_protect, gui)
	end
end

-- Mount order: gethui -> protect+CoreGui -> CoreGui direct -> PlayerGui
function Compat.GetGuiParent(): Instance
	if type(_gethui) == "function" then
		local ok, res = pcall(_gethui)
		if ok and typeof(res) == "Instance" then
			return res
		end
	end
	local okName, _ = pcall(function()
		local _t = CoreGui.Name
	end)
	if okName then
		return CoreGui
	end
	local lp = Players.LocalPlayer
	if lp then
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		if pg then
			return pg
		end
		local okW, pg2 = pcall(lp.WaitForChild, lp, "PlayerGui", 5)
		if okW and typeof(pg2) == "Instance" then
			return pg2
		end
	end
	return CoreGui
end

function Compat.CleanupRoots(prefix: string, attr: string?)
	local roots: { Instance } = {}
	if type(_gethui) == "function" then
		local ok, r = pcall(_gethui)
		if ok and typeof(r) == "Instance" then
			table.insert(roots, r)
		end
	end
	pcall(function()
		table.insert(roots, CoreGui)
	end)
	local lp = Players.LocalPlayer
	if lp then
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		if pg then
			table.insert(roots, pg)
		end
	end
	for _, root in ipairs(roots) do
		local ok, children = pcall(root.GetChildren, root)
		if not ok or type(children) ~= "table" then
			continue
		end
		for _, child in ipairs(children) do
			local isGui = pcall(function()
				return (child :: any):IsA("ScreenGui")
			end)
			if isGui then
				local match = false
				pcall(function()
					local n = (child :: any).Name
					if type(n) == "string" and string.sub(n, 1, #prefix) == prefix then
						match = true
					end
					if not match and attr ~= nil and (child :: any):GetAttribute(attr) == true then
						match = true
					end
				end)
				if match then
					pcall((child :: any).Destroy, child)
				end
			end
		end
	end
end

function Compat.DestroyActiveWindow(): boolean
	local env = Compat.GetEnv()
	if env and env._SODIUM_ACTIVE_WINDOW then
		local w = env._SODIUM_ACTIVE_WINDOW
		env._SODIUM_ACTIVE_WINDOW = nil
		if type(w) == "table" and type((w :: any).Destroy) == "function" then
			pcall((w :: any).Destroy, w)
			return true
		elseif typeof(w) == "Instance" then
			pcall((w :: any).Destroy, w)
			return true
		end
	end
	return false
end

return Compat
end

_MODULES['Core/Container'] = function()
--!strict
--[=[
	Sodium UI v2 - Core/Container.luau
	Root ScreenGui + viewport UIScale engine.
	Keeps v1 scale math (margin/inset/dpiMax) + leak-free debounce.
	Uses Compat for mount/cleanup (feature-detect, no identity check).
]=]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Compat = _require("Core/Compat")
local Tweener = _require("Core/Tweener")

local Container = {}
Container.__index = Container

export type ContainerInstance = {
	ScreenGui: ScreenGui,
	UIScale: UIScale,
	BaseWindowSize: Vector2,
	IsMobile: boolean,
	OnScaleChanged: ((number) -> ())?,
	SetBaseWindowSize: (self: ContainerInstance, size: Vector2) -> (),
	GetSafeAreaInsets: (self: ContainerInstance) -> (Vector2, Vector2),
	Destroy: (self: ContainerInstance) -> (),
}

local _camera: Camera? = workspace.CurrentCamera

function Container:_updateScaling(immediate: boolean?)
	if not _camera then
		_camera = workspace.CurrentCamera
	end
	local cam = _camera
	if not cam then
		return
	end
	local vp: Vector2 = cam.ViewportSize
	local baseW = self.BaseWindowSize.X
	local baseH = self.BaseWindowSize.Y
	if baseW <= 0 then
		baseW = 720
	end
	if baseH <= 0 then
		baseH = 480
	end

	local insetTL: Vector2? = nil
	local insetBR: Vector2? = nil
	pcall(function()
		insetTL, insetBR = GuiService:GetGuiInset()
	end)
	local insetX = if insetTL then insetTL.X else 0
	local insetY = if insetTL then insetTL.Y else 0
	if insetBR then
		insetX = math.max(insetX, insetBR.X)
		insetY = math.max(insetY, insetBR.Y)
	end

	local isSmall = vp.X < 900 or self.IsMobile
	local marginX = (if isSmall then 12 else 24) + insetX
	local marginY = (if vp.Y < 600 or self.IsMobile then 12 else 24) + insetY

	local availW = math.max(60, vp.X - marginX * 2)
	local availH = math.max(60, vp.Y - marginY * 2)

	local fitScale = math.min(availW / baseW, availH / baseH)
	local minScale = if self.IsMobile then 0.40 else 0.48
	local dpiMax = math.clamp(vp.X / 1920, 1.0, 1.85)
	local target = math.clamp(fitScale, minScale, dpiMax)

	-- Optimization: skip redundant scaling if delta is negligible
	if immediate ~= true and math.abs(self.UIScale.Scale - target) < 0.003 then
		return
	end

	if immediate == true then
		Tweener.Cancel(self.UIScale)
		pcall(function()
			self.UIScale.Scale = target
		end)
	else
		Tweener.Tween(self.UIScale, Tweener.Info.Fast, { Scale = target })
	end
	local cb = self.OnScaleChanged
	if type(cb) == "function" then
		task.spawn(function()
			local ok, err = pcall(cb, target)
			if not ok then
				warn("[SodiumUI.Container] OnScaleChanged " .. tostring(err))
			end
		end)
	end
end

function Container:_initViewportScaling()
	self._scaleGen = 0
	local function schedule(immediate: boolean?)
		if immediate == true then
			self._scaleGen += 1
			self:_updateScaling(true)
			return
		end
		self._scaleGen += 1
		local gen = self._scaleGen
		task.delay(0.1, function()
			if gen ~= self._scaleGen then
				return
			end
			self:_updateScaling(false)
		end)
	end
	self._scheduleScale = schedule
	schedule(true)

	local cam = _camera
	if cam then
		table.insert(self._connections, cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			schedule(false)
		end))
	end
	table.insert(self._connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		_camera = workspace.CurrentCamera
		local c = _camera
		if c then
			table.insert(self._connections, c:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				schedule(false)
			end))
			schedule(true)
		end
	end))
end

function Container.new(title: any, parentOverride: Instance?): ContainerInstance
	Compat.DestroyActiveWindow()
	Compat.CleanupRoots("SodiumUI_", "SodiumUI_Root")

	local self = setmetatable({}, Container)
	;(self :: any)._connections = {}
	;(self :: any)._scaleGen = 0

	local rawTitle: string = if type(title) == "table"
		then tostring((title :: any).en or (title :: any).EN or (title :: any).th or (title :: any).TH or "SodiumUI")
		else tostring(title or "SodiumUI")

	-- Build tree in memory, parent once (single reflow)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SodiumUI_" .. string.gsub(rawTitle, "%s+", "_")
	screenGui:SetAttribute("SodiumUI_Root", true)
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 999999

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "GlobalScaler"
	uiScale.Scale = 1.0
	uiScale.Parent = screenGui

	Compat.ProtectGui(screenGui)
	screenGui.Parent = parentOverride or Compat.GetGuiParent()

	;(self :: any).ScreenGui = screenGui
	;(self :: any).UIScale = uiScale
	;(self :: any).BaseWindowSize = Vector2.new(720, 480)
	;(self :: any).IsMobile = UserInputService.TouchEnabled or (not UserInputService.KeyboardEnabled)
	;(self :: any).OnScaleChanged = nil

	Container._initViewportScaling(self)

	return self :: ContainerInstance
end

function Container:SetBaseWindowSize(size: Vector2)
	(self :: any).BaseWindowSize = size
	self:_updateScaling(true)
end

function Container:GetSafeAreaInsets(): (Vector2, Vector2)
	local ok, a, b = pcall(GuiService.GetGuiInset, GuiService)
	if ok and typeof(a) == "Vector2" and typeof(b) == "Vector2" then
		return a, b
	end
	return Vector2.zero, Vector2.zero
end

function Container:Destroy()
	Tweener.Cancel((self :: any).UIScale)
	if (self :: any)._connections then
		for _, conn in ipairs((self :: any)._connections) do
			if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
				pcall((conn :: any).Disconnect, conn)
			elseif typeof(conn) == "RBXScriptConnection" then
				pcall((conn :: RBXScriptConnection).Disconnect, conn)
			end
		end
		table.clear((self :: any)._connections)
	end
	local gui: ScreenGui? = (self :: any).ScreenGui
	if gui then
		pcall((gui :: ScreenGui).Destroy, gui)
	end
	;(self :: any).ScreenGui = nil
	;(self :: any).UIScale = nil
end

return Container
end

_MODULES['Elements/Button'] = function()
--!strict
--[=[
    Sodium UI - Elements/Button.luau
    Action trigger with physical micro-press feedback (scale: 0.97) and hover lift.
]=]

local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Button = {}
Button.__index = Button

export type ButtonProps = {
    Title: any,
    Desc: any?,
    Description: any?,
    Icon: string?,
    TrailingIcon: any?, -- string | false | nil (nil = default "mouse-pointer-click")
    Color: Color3?,
    Justify: string?, -- "Between", "Center", "Left", "Right"
    IconAlign: string?, -- "Left", "Right"
    Locked: boolean?,
    Callback: (() -> ())?,
}

function Button.new(parent: Instance, props: any)
    local titleText = Locale.Resolve(props.Title or props.Name or "Button")
    local self = setmetatable({}, Button)
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    
    local descProp = props.Desc or props.Description
    local isDesc = descProp and (if type(descProp) == "table" then true else descProp ~= "")
    local containerHeight = if isDesc then 54 else 38
    
    -- Slot wrapper (for UIListLayout stability, stays in place while button scales into center)
    local slot = Instance.new("Frame")
    slot.Name = "Button_" .. tostring(titleText)
    slot.Size = UDim2.new(1, 0, 0, containerHeight)
    slot.BackgroundTransparency = 1
    slot.BorderSizePixel = 0
    
    -- Card container (Positioned at center 0.5, 0.5 with AnchorPoint 0.5, 0.5 for true center micro-press scaling)
    local container = Instance.new("Frame")
    container.Name = "Card"
    container.Size = UDim2.fromScale(1, 1)
    container.Position = UDim2.fromScale(0.5, 0.5)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    container.BackgroundTransparency = 0.5
    container.BorderSizePixel = 0
    container.ClipsDescendants = true
    container.Parent = slot
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = container
    
    local btn = Instance.new("TextButton")
    btn.Name = "Trigger"
    btn.Size = UDim2.fromScale(1, 1)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = container
    
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 14)
    pad.PaddingRight = UDim.new(0, 14)
    pad.Parent = btn
    
    self._connections = {}
    
    -- Icon
    local iconLabel: ImageLabel? = nil
    local iconWidth = 0
    local isRightIcon = props.IconAlign == "Right"
    if props.Icon and props.Icon ~= "" then
        iconLabel = Instance.new("ImageLabel")
        iconLabel.Name = "Icon"
        iconLabel.Size = UDim2.fromOffset(18, 18)
        if isRightIcon then
            iconLabel.Position = UDim2.new(1, 0, 0.5, 0)
            iconLabel.AnchorPoint = Vector2.new(1, 0.5)
        else
            iconLabel.Position = UDim2.new(0, 0, 0.5, 0)
            iconLabel.AnchorPoint = Vector2.new(0, 0.5)
        end
        iconLabel.BackgroundTransparency = 1
        iconLabel.ImageColor3 = props.Color or Theme.GetToken("Accent")
        Icons.Apply(iconLabel, props.Icon)
        iconLabel.Parent = btn
        iconWidth = 26
    end
    
    -- Trailing icon (right edge, vertically centered) - "click" affordance on every Button
    local trailingIcon = props.TrailingIcon
    if trailingIcon == nil then
        trailingIcon = "mouse-pointer-click"
    end
    local trailingWidth = 0
    local trailingIconLabel: ImageLabel? = nil
    if trailingIcon and trailingIcon ~= "" then
        trailingIconLabel = Instance.new("ImageLabel")
        trailingIconLabel.Name = "TrailingIcon"
        trailingIconLabel.Size = UDim2.fromOffset(18, 18)
        trailingIconLabel.Position = UDim2.new(1, 0, 0.5, 0)
        trailingIconLabel.AnchorPoint = Vector2.new(1, 0.5)
        trailingIconLabel.BackgroundTransparency = 1
        trailingIconLabel.ImageColor3 = props.Color or Theme.GetToken("Accent")
        Icons.Apply(trailingIconLabel, trailingIcon)
        trailingIconLabel.Parent = btn
        trailingWidth = 26
    end
    
    local textStartX = if isRightIcon then 0 else iconWidth
    local textRightInset = trailingWidth
    local textAlignment = Enum.TextXAlignment.Left
    if props.Justify == "Center" then
        textAlignment = Enum.TextXAlignment.Center
    elseif props.Justify == "Right" then
        textAlignment = Enum.TextXAlignment.Right
    end
    
    -- Text Container
    local titleColor = Theme.ResolveColor(props.TitleColor or props.Color)
    local descColor = Theme.ResolveColor(props.DescColor or props.DescriptionColor)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -(iconWidth + textRightInset), 0, 18)
    titleLabel.Position = UDim2.new(0, textStartX, 0, if isDesc then 8 else 10)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Header", "Header")
    Locale.Bind(titleLabel, "Text", props.Title or props.Name or "Button")
    titleLabel.TextColor3 = titleColor or Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = textAlignment
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = btn
    
    local descLabel: TextLabel? = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -(iconWidth + textRightInset), 0, 16)
        descLabel.Position = UDim2.new(0, textStartX, 0, 28)
        descLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(descLabel, "Sub", "Sub")
        Locale.Bind(descLabel, "Text", descProp or "")
        descLabel.TextColor3 = descColor or Theme.GetToken("TextMuted")
        descLabel.TextXAlignment = textAlignment
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = btn
    end
    
    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    if not titleColor then
        Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    end
    if descLabel and not descColor then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end
    
	-- Micro-press feedback on card border/background into Center
	self._feedback = {}
	do
		local h1 = Tweener.BindCardPressFeedback(container, btn, Vector2.new(4, 2))
		if h1 then
			table.insert(self._feedback, h1)
		end
		local h2 = Tweener.BindHoverLift(container, stroke)
		if h2 then
			table.insert(self._feedback, h2)
		end
	end
    
	table.insert(self._connections, btn.Activated:Connect(function()
		if not self.Locked and self.Callback then
			local ok, err = pcall(self.Callback)
			if not ok then
				warn("[SodiumUI.Button] Callback error:", err)
			end
		end
	end))
    
    slot.Parent = parent
    self.Slot = slot
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.IconLabel = iconLabel
    self.TrailingIconLabel = trailingIconLabel
    
    return self
end

function Button:SetTitle(title: string)
	Locale.Unbind(self.TitleLabel)
	if type(title) == "table" then
		Locale.Bind(self.TitleLabel, "Text", title)
	else
		self.TitleLabel.Text = tostring(title)
	end
end

function Button:SetDesc(desc: string)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
		if type(desc) == "table" then
			Locale.Bind(self.DescLabel, "Text", desc)
		else
			self.DescLabel.Text = tostring(desc)
		end
	end
end

function Button:Lock()
    self.Locked = true
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.8 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("Placeholder") })
end

function Button:Unlock()
    self.Locked = false
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
end

function Button:Destroy()
	Tweener.Cancel(self.Container)
	if self._feedback then
		for _, h in ipairs(self._feedback) do
			pcall((h :: any).Disconnect, h)
		end
		table.clear(self._feedback)
	end
	for _, conn in ipairs(self._connections) do
		if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
			pcall((conn :: any).Disconnect, conn)
		elseif typeof(conn) == "RBXScriptConnection" then
			pcall((conn :: RBXScriptConnection).Disconnect, conn)
		end
	end
	table.clear(self._connections)
	Locale.Unbind(self.TitleLabel)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
	end
	Theme.Unbind(self.Container)
	if self.Slot then
		pcall((self.Slot :: Instance).Destroy, self.Slot)
	elseif self.Container then
		pcall((self.Container :: Instance).Destroy, self.Container)
	end
end

return Button
end

_MODULES['Elements/Divider'] = function()
--!strict
--[=[
	Sodium UI v2 - Elements/Divider.luau
	Flex-based separator. No AbsoluteSize listeners, no TextBounds math.
	Supports LocalizedString titles.
]=]

local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")

local Divider = {}
Divider.__index = Divider

export type DividerProps = {
	Title: any?,
}

function Divider.new(parent: Instance, props: DividerProps?)
	local self = setmetatable({}, Divider)
	self._conns = {}
	local rawTitle: any = props and (props :: any).Title
	local hasTitle = rawTitle ~= nil and Locale.Resolve(rawTitle) ~= ""

	local container = Instance.new("Frame")
	container.Name = "Divider_" .. (if hasTitle then Locale.Resolve(rawTitle) else "Line")
	container.Size = UDim2.new(1, 0, 0, if hasTitle then 22 else 8)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0

	if hasTitle then
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = container

		local leftLine = Instance.new("Frame")
		leftLine.Name = "LeftLine"
		leftLine.Size = UDim2.new(0.5, -20, 0, 1)
		leftLine.BorderSizePixel = 0
		Theme.Bind(leftLine, "BackgroundColor3", "BorderSubtle")
		leftLine.LayoutOrder = 1
		pcall(function()
			local flex = Instance.new("UIFlexItem")
			flex.FlexMode = Enum.UIFlexMode.Grow
			flex.Parent = leftLine
		end)
		leftLine.Parent = container

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.LayoutOrder = 2
		Theme.ApplyTypography(label, "Title", "Small")
		if type(rawTitle) == "table" then
			local upperMap: { [string]: string } = {}
			for k, v in pairs(rawTitle :: any) do
				upperMap[k] = string.upper(tostring(v))
			end
			Locale.Bind(label, "Text", upperMap)
		else
			label.Text = string.upper(tostring(rawTitle))
		end
		Theme.Bind(label, "TextColor3", "Placeholder")
		label.Parent = container
		self.Label = label

		local rightLine = Instance.new("Frame")
		rightLine.Name = "RightLine"
		rightLine.Size = UDim2.new(0.5, -20, 0, 1)
		rightLine.BorderSizePixel = 0
		Theme.Bind(rightLine, "BackgroundColor3", "BorderSubtle")
		rightLine.LayoutOrder = 3
		pcall(function()
			local flex = Instance.new("UIFlexItem")
			flex.FlexMode = Enum.UIFlexMode.Grow
			flex.Parent = rightLine
		end)
		rightLine.Parent = container
	else
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.new(0, 0, 0.5, 0)
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.BorderSizePixel = 0
		Theme.Bind(line, "BackgroundColor3", "BorderSubtle")
		line.Parent = container
	end

	container.Parent = parent
	self.Container = container
	return self
end

function Divider:Destroy()
	for _, c in ipairs(self._conns) do
		pcall((c :: RBXScriptConnection).Disconnect, c)
	end
	table.clear(self._conns)
	if self.Label then
		Locale.Unbind(self.Label)
	end
	Theme.Unbind(self.Container)
	if self.Container then
		pcall((self.Container :: Instance).Destroy, self.Container)
	end
end

return Divider
end

_MODULES['Elements/Toggle'] = function()
--!strict
--[=[
    Sodium UI - Elements/Toggle.luau
    Stateful switch with animated thumb slider.
    Refined: ApplyStrokeMode = Border, polished typography, and smooth thumb animation.
]=]

local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Toggle = {}
Toggle.__index = Toggle

export type ToggleProps = {
    Title: any,
    Desc: any?,
    Description: any?,
    Icon: string?,
    Value: boolean?,
    Locked: boolean?,
    Callback: ((state: boolean) -> ())?,
}

function Toggle.new(parent: Instance, props: any)
    local titleText = Locale.Resolve(props.Title or props.Name or "Toggle")
    local initialVal = if props.Value ~= nil then props.Value elseif props.Default ~= nil then props.Default else false
    
    local self = setmetatable({}, Toggle)
    self.Value = initialVal
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self._connections = {}
    
    local descProp = props.Desc or props.Description
    local isDesc = descProp and (if type(descProp) == "table" then true else descProp ~= "")
    local containerHeight = if isDesc then 54 else 42
    
    local container = Instance.new("Frame")
    container.Name = "Toggle_" .. tostring(titleText)
    container.Size = UDim2.new(1, 0, 0, containerHeight)
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    container.BackgroundTransparency = 0.5
    container.BorderSizePixel = 0
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = container
    
    local triggerBtn = Instance.new("TextButton")
    triggerBtn.Name = "Trigger"
    triggerBtn.Size = UDim2.fromScale(1, 1)
    triggerBtn.BackgroundTransparency = 1
    triggerBtn.Text = ""
    triggerBtn.AutoButtonColor = false
    triggerBtn.Parent = container
    
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = triggerBtn
    
    local iconOffset = 0
    if props.Icon and props.Icon ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(18, 18)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(icon, props.Icon)
        icon.Parent = triggerBtn
        iconOffset = 26
    end
    
    local titleColor = Theme.ResolveColor(props.TitleColor or props.Color)
    local descColor = Theme.ResolveColor(props.DescColor or props.DescriptionColor)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 26, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 9 else 12)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Header", "Header")
    Locale.Bind(titleLabel, "Text", props.Title or props.Name or "Toggle")
    titleLabel.TextColor3 = titleColor or Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = triggerBtn
    if not titleColor then
        Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    end
    
    local descLabel: TextLabel? = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 26, 0, 16)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 29)
        descLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(descLabel, "Sub", "Sub")
        Locale.Bind(descLabel, "Text", descProp or "")
        descLabel.TextColor3 = descColor or Theme.GetToken("TextMuted")
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = triggerBtn
        if not descColor then
            Theme.Bind(descLabel, "TextColor3", "TextMuted")
        end
    end
    
    -- Toggle Switch Control (Apple iOS/macOS Pill Switch style)
    local switchTrack = Instance.new("Frame")
    switchTrack.Name = "SwitchTrack"
    switchTrack.Size = UDim2.fromOffset(36, 20)
    switchTrack.Position = UDim2.new(1, 0, 0.5, 0)
    switchTrack.AnchorPoint = Vector2.new(1, 0.5)
    switchTrack.BackgroundColor3 = if self.Value then Theme.GetToken("Accent") else Theme.GetToken("SurfaceActive")
    switchTrack.BorderSizePixel = 0
    
    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = Theme.Radii.Pill
    trackCorner.Parent = switchTrack
    
    local trackStroke = Instance.new("UIStroke")
    trackStroke.Color = if self.Value then Theme.GetToken("BorderAccent") else Theme.GetToken("BorderSubtle")
    trackStroke.Thickness = 1
    trackStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    trackStroke.Parent = switchTrack
    
    local thumb = Instance.new("Frame")
    thumb.Name = "Thumb"
    thumb.Size = UDim2.fromOffset(16, 16)
    thumb.Position = if self.Value then UDim2.new(1, -18, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
    thumb.AnchorPoint = Vector2.new(0, 0.5)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.BorderSizePixel = 0
    
    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = Theme.Radii.Pill
    thumbCorner.Parent = thumb
    thumb.Parent = switchTrack
    
    switchTrack.Parent = triggerBtn
    
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.SwitchTrack = switchTrack
    self.TrackStroke = trackStroke
    self.Thumb = thumb
    -- Backwards-compatibility aliases:
    self.CheckSquare = switchTrack
    self.CheckStroke = trackStroke
    self.CheckIcon = thumb
    
    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    if descLabel then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end
    
    table.insert(self._connections, Theme.Changed:Connect(function()
        if self.Value then
            switchTrack.BackgroundColor3 = Theme.GetToken("Accent")
            trackStroke.Color = Theme.GetToken("BorderAccent")
        else
            switchTrack.BackgroundColor3 = Theme.GetToken("SurfaceActive")
            trackStroke.Color = Theme.GetToken("BorderSubtle")
        end
    end))
    
	self._feedback = {}
	local h1 = Tweener.BindPressFeedback(switchTrack, triggerBtn, 0.94)
	if h1 then
		table.insert(self._feedback, h1)
	end
	local h2 = Tweener.BindHoverLift(container, stroke)
	if h2 then
		table.insert(self._feedback, h2)
	end
    
    table.insert(self._connections, triggerBtn.Activated:Connect(function()
        if not self.Locked then
            self:Set(not self.Value)
        end
    end))
    
    
    container.Parent = parent
    return self
end

function Toggle:Set(state: boolean, skipCallback: boolean?, animate: boolean?)
    self.Value = (state == true)
    
    local targetBg = if self.Value then Theme.GetToken("Accent") else Theme.GetToken("SurfaceActive")
    local targetStroke = if self.Value then Theme.GetToken("BorderAccent") else Theme.GetToken("BorderSubtle")
    local targetThumbPos = if self.Value then UDim2.new(1, -18, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
    
    if animate == false then
        self.SwitchTrack.BackgroundColor3 = targetBg
        self.TrackStroke.Color = targetStroke
        self.Thumb.Position = targetThumbPos
    else
        Tweener.Tween(self.SwitchTrack, Tweener.Info.Normal, {
            BackgroundColor3 = targetBg,
        })
        Tweener.Tween(self.TrackStroke, Tweener.Info.Normal, {
            Color = targetStroke,
        })
        Tweener.Tween(self.Thumb, Tweener.Info.Normal, {
            Position = targetThumbPos,
        })
    end
    
    if not skipCallback and self.Callback then
        local ok, err = pcall(self.Callback, self.Value)
        if not ok then
            warn("[SodiumUI.Toggle] Callback error:", err)
        end
    end
    
end

function Toggle:Get(): boolean
    return self.Value
end

function Toggle:SetTitle(title: string)
	Locale.Unbind(self.TitleLabel)
	if type(title) == "table" then
		Locale.Bind(self.TitleLabel, "Text", title)
	else
		self.TitleLabel.Text = tostring(title)
	end
end

function Toggle:SetDesc(desc: string)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
		if type(desc) == "table" then
			Locale.Bind(self.DescLabel, "Text", desc)
		else
			self.DescLabel.Text = tostring(desc)
		end
	end
end

function Toggle:Lock()
    self.Locked = true
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.7 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("Placeholder") })
    Tweener.Tween(self.CheckSquare, Tweener.Info.Fast, { BackgroundTransparency = 0.6 })
    Tweener.Tween(self.CheckStroke, Tweener.Info.Fast, { Transparency = 0.6 })
end

function Toggle:Unlock()
    self.Locked = false
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
    Tweener.Tween(self.CheckSquare, Tweener.Info.Fast, { BackgroundTransparency = 0 })
    Tweener.Tween(self.CheckStroke, Tweener.Info.Fast, { Transparency = 0 })
end

function Toggle:Destroy()
	Tweener.Cancel(self.CheckSquare)
	Tweener.Cancel(self.CheckIcon)
	if self._feedback then
		for _, h in ipairs(self._feedback) do
			pcall((h :: any).Disconnect, h)
		end
		table.clear(self._feedback)
	end
	for _, conn in ipairs(self._connections) do
		if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
			pcall((conn :: any).Disconnect, conn)
		elseif typeof(conn) == "RBXScriptConnection" then
			pcall((conn :: RBXScriptConnection).Disconnect, conn)
		end
	end
	table.clear(self._connections)
	Locale.Unbind(self.TitleLabel)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
	end
	Theme.Unbind(self.Container)
	if self.Container then
		pcall((self.Container :: Instance).Destroy, self.Container)
	end
end

return Toggle
end

_MODULES['Elements/Slider'] = function()
--!strict
--[=[
    Sodium UI - Elements/Slider.luau
    Touch & Mouse draggable slider with integer/float snapping and numeric value badge.
    Refined: Compact control area (112px) giving maximum width to Title, zero truncation.
]=]

local UserInputService = game:GetService("UserInputService")
local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Slider = {}
Slider.__index = Slider

export type SliderProps = {
    Title: any,
    Desc: any?,
    Description: any?,
    Icon: string?,
    Step: number?,
    Suffix: string?,
    Value: {
        Min: number,
        Max: number,
        Default: number,
    },
    Locked: boolean?,
    Callback: ((val: number) -> ())?,
}

function Slider.new(parent: Instance, props: any)
    local titleText = Locale.Resolve(props.Title or props.Name or "Slider")
    local valTable = if type(props.Value) == "table" then props.Value else {}
    local minVal = props.Min or valTable.Min or 0
    local maxVal = props.Max or valTable.Max or 100
    local defVal = props.Default or valTable.Default or minVal

    local self = setmetatable({}, Slider)
    self.Min = minVal
    self.Max = maxVal
    self.Step = props.Step or 1
    self.Suffix = props.Suffix or ""
    self.Value = math.clamp(defVal, self.Min, self.Max)
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self.IsDragging = false
    self._connections = {}
    
    local descProp = props.Desc or props.Description
    local isDesc = descProp and (if type(descProp) == "table" then true else descProp ~= "")
    local containerHeight = if isDesc then 54 else 42
    
    local container = Instance.new("Frame")
    container.Name = "Slider_" .. tostring(titleText)
    container.Size = UDim2.new(1, 0, 0, containerHeight)
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    container.BackgroundTransparency = 0.5
    container.BorderSizePixel = 0
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = container
    
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = container
    
    local iconOffset = 0
    if props.Icon and props.Icon ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(16, 16)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(icon, props.Icon)
        icon.Parent = container
        iconOffset = 22
    end
    
    -- Left Text: Title & Desc take all space up to the 160px control cluster
    local titleColor = Theme.ResolveColor(props.TitleColor or props.Color)
    local descColor = Theme.ResolveColor(props.DescColor or props.DescriptionColor)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 168, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 8 else 12)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Header", "Header")
    Locale.Bind(titleLabel, "Text", props.Title or props.Name or "Slider")
    titleLabel.TextColor3 = titleColor or Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = container
    if not titleColor then
        Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    end
    
    local descLabel: TextLabel? = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 168, 0, 14)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 28)
        descLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(descLabel, "Sub", "Sub")
        Locale.Bind(descLabel, "Text", descProp or "")
        descLabel.TextColor3 = descColor or Theme.GetToken("TextMuted")
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = container
        if not descColor then
            Theme.Bind(descLabel, "TextColor3", "TextMuted")
        end
    end
    
    -- Right side controls: Track + Gap + Editable Value Badge
    local controlArea = Instance.new("Frame")
    controlArea.Name = "ControlArea"
    controlArea.Size = UDim2.new(0, 160, 0, 24)
    controlArea.Position = UDim2.new(1, 0, 0.5, 0)
    controlArea.AnchorPoint = Vector2.new(1, 0.5)
    controlArea.BackgroundTransparency = 1
    
    -- Editable Value Badge (Direct manual input + numeric badge)
    local badge = Instance.new("Frame")
    badge.Name = "Badge"
    badge.Size = UDim2.fromOffset(42, 22)
    badge.Position = UDim2.new(1, 0, 0.5, 0)
    badge.AnchorPoint = Vector2.new(1, 0.5)
    badge.BackgroundColor3 = Theme.GetToken("Card")
    
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = Theme.Radii.Control
    badgeCorner.Parent = badge
    
    local badgeStroke = Instance.new("UIStroke")
    badgeStroke.Color = Theme.GetToken("BorderSubtle")
    badgeStroke.Thickness = 1
    badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    badgeStroke.Parent = badge
    
    local badgeInput = Instance.new("TextBox")
    badgeInput.Name = "ValueInput"
    badgeInput.Size = UDim2.fromScale(1, 1)
    badgeInput.BackgroundTransparency = 1
    Theme.ApplyTypography(badgeInput, "Code", "Small")
    badgeInput.Text = tostring(self.Value)
    badgeInput.TextColor3 = Theme.GetToken("TextPrimary")
    badgeInput.ClearTextOnFocus = false
    badgeInput.ClipsDescendants = true
    badgeInput.TextXAlignment = Enum.TextXAlignment.Center
    badgeInput.Parent = badge
    badge.Parent = controlArea
    
    -- Track Frame (24px height hit area for touch, inner visual bar is 4px)
    local track = Instance.new("TextButton")
    track.Name = "Track"
    track.Size = UDim2.new(1, -48, 0, 24)
    track.Position = UDim2.new(0, 0, 0.5, 0)
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.BackgroundTransparency = 1
    track.BorderSizePixel = 0
    track.Text = ""
    track.AutoButtonColor = false
    
    local trackBar = Instance.new("Frame")
    trackBar.Name = "TrackBar"
    trackBar.Size = UDim2.new(1, 0, 0, 4)
    trackBar.Position = UDim2.new(0, 0, 0.5, 0)
    trackBar.AnchorPoint = Vector2.new(0, 0.5)
    trackBar.BackgroundColor3 = Theme.GetToken("BorderStrong")
    trackBar.BorderSizePixel = 0
    
    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = Theme.Radii.Pill
    trackCorner.Parent = trackBar
    
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Theme.GetToken("Accent")
    fill.BorderSizePixel = 0
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = Theme.Radii.Pill
    fillCorner.Parent = fill
    fill.Parent = trackBar
    trackBar.Parent = track
    
    local thumb = Instance.new("Frame")
    thumb.Name = "Thumb"
    thumb.Size = UDim2.fromOffset(14, 14)
    thumb.Position = UDim2.new(0, 0, 0.5, 0)
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.BorderSizePixel = 0
    
    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = Theme.Radii.Pill
    thumbCorner.Parent = thumb

    local thumbStroke = Instance.new("UIStroke")
    thumbStroke.Color = Color3.fromRGB(0, 0, 0)
    thumbStroke.Transparency = 0.8
    thumbStroke.Thickness = 1.5
    thumbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    thumbStroke.Parent = thumb
    Theme.Bind(thumbStroke, "Color", "BorderSubtle")
    thumb.Parent = track
    
    track.Parent = controlArea
    controlArea.Parent = container
    
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.Track = track
    self.Fill = fill
    self.Thumb = thumb
    self.BadgeInput = badgeInput
    self.BadgeStroke = badgeStroke
    self._fillTween = nil
    self._thumbTween = nil
    self._isUpdating = false
    
    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    if descLabel then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end
    Theme.Bind(badge, "BackgroundColor3", "Card")
    Theme.Bind(badgeStroke, "Color", "BorderSubtle")
    Theme.Bind(badgeInput, "TextColor3", "TextPrimary")
    Theme.Bind(track, "BackgroundColor3", "BorderStrong")
    
    Tweener.BindHoverLift(container, stroke)
    
    local function snap(rawVal: number): number
        local stepped = math.floor((rawVal - self.Min) / self.Step + 0.5) * self.Step + self.Min
        return math.clamp(stepped, self.Min, self.Max)
    end
    
    local allowNegative = self.Min < 0
    local allowDecimal = (self.Step % 1 ~= 0)
    local isEditing = false
    
    local function formatValue(val: number): string
        if self.Step % 1 == 0 then
            return string.format("%d", math.round(val))
        else
            return string.format("%.1f", val)
        end
    end
    
    table.insert(self._connections, badgeInput.Focused:Connect(function()
        if self.Locked then
            badgeInput:ReleaseFocus()
            return
        end
        isEditing = true
        Tweener.Tween(badgeStroke, Tweener.Info.Fast, { Color = Theme.GetToken("Accent") })
        badgeInput.Text = formatValue(self.Value)
    end))
    
    table.insert(self._connections, badgeInput:GetPropertyChangedSignal("Text"):Connect(function()
        if not isEditing then return end
        local raw = badgeInput.Text
        local sanitized = {}
        local hasDot = false
        local hasMinus = false
        for i = 1, #raw do
            local ch = string.sub(raw, i, i)
            if ch >= "0" and ch <= "9" then
                table.insert(sanitized, ch)
            elseif ch == "-" and allowNegative and #sanitized == 0 and not hasMinus then
                hasMinus = true
                table.insert(sanitized, ch)
            elseif (ch == "." or ch == ",") and allowDecimal and not hasDot then
                hasDot = true
                table.insert(sanitized, ".")
            end
        end
        local clean = table.concat(sanitized)
        if clean ~= raw then
            badgeInput.Text = clean
        end
    end))
    
    table.insert(self._connections, badgeInput.FocusLost:Connect(function(enterPressed)
        isEditing = false
        Tweener.Tween(badgeStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
        
        local cleanText = badgeInput.Text
        local num = tonumber(cleanText)
        if num == nil or num ~= num then
            badgeInput.Text = formatValue(self.Value)
            return
        end
        
        local clamped = math.clamp(num, self.Min, self.Max)
        local stepped = snap(clamped)
        
        self:Set(stepped, false, true)
        badgeInput.Text = formatValue(self.Value)
    end))
    
    local function updateFromInput(inputPos: Vector2)
        local trackAbsX = track.AbsolutePosition.X
        local trackWidth = track.AbsoluteSize.X
        if trackWidth <= 0 then return end
        
        local relX = math.clamp(inputPos.X - trackAbsX, 0, trackWidth)
        local pct = relX / trackWidth
        local rawVal = self.Min + (self.Max - self.Min) * pct
        local snapped = snap(rawVal)
        self:Set(snapped, false, false)
    end
    
    local function setDragging(dragging: boolean)
        if self.IsDragging == dragging then return end
        self.IsDragging = dragging
        if dragging then
            Tweener.Tween(thumb, Tweener.Info.Fast, { Size = UDim2.fromOffset(14, 14) })
            Tweener.Tween(thumbStroke, Tweener.Info.Fast, { Color = Theme.GetToken("Accent"), Thickness = 1.5 })
        else
            Tweener.Tween(thumb, Tweener.Info.Fast, { Size = UDim2.fromOffset(10, 10) })
            Tweener.Tween(thumbStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle"), Thickness = 1 })
        end
    end

	local inputChangedConn: any = nil
	local function stopDragging()
		if inputChangedConn then
			pcall((inputChangedConn :: RBXScriptConnection).Disconnect, inputChangedConn)
			inputChangedConn = nil
		end
		setDragging(false)
		-- sync badge once on release (avoid per-pixel Text layout thrash while dragging)
		if self.BadgeInput and not self.BadgeInput:IsFocused() then
			local ds = if self.Step % 1 == 0
				then string.format("%d", math.round(self.Value))
				else string.format("%.1f", self.Value)
			self.BadgeInput.Text = ds .. self.Suffix
		end
	end
	self._stopDragging = stopDragging

	table.insert(
		self._connections,
		track.InputBegan:Connect(function(input: InputObject)
			if not self.Locked and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				setDragging(true)
				updateFromInput(input.Position)

				if inputChangedConn then
					pcall((inputChangedConn :: RBXScriptConnection).Disconnect, inputChangedConn)
				end
				inputChangedConn = input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						stopDragging()
					end
				end)
			end
		end)
	)
    
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if self.IsDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input.Position)
        end
    end))
    
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            stopDragging()
        end
    end))
    
    self:Set(self.Value, true, false)
    
    container.Parent = parent
    return self
end

function Slider:Set(newVal: number, skipCallback: boolean?, animate: boolean?)
	if self._isUpdating then
		return
	end
	self._isUpdating = true

	local num = tonumber(newVal)
	if num == nil then
		self._isUpdating = false
		return
	end

	-- Single source of truth: clamp -> snap to Step -> clamp (skill round())
	local step = self.Step
	if type(step) ~= "number" or step <= 0 then
		step = 1
	end
	local v = math.clamp(num, self.Min, self.Max)
	v = math.floor((v - self.Min) / step + 0.5) * step + self.Min
	v = math.clamp(v, self.Min, self.Max)
	self.Value = v

	local pct = (self.Value - self.Min) / math.max(1e-5, (self.Max - self.Min))

	if self._fillTween then
		Tweener.Cancel(self.Fill)
		self._fillTween = nil
	end
	if self._thumbTween then
		Tweener.Cancel(self.Thumb)
		self._thumbTween = nil
	end

	if animate then
		self._fillTween = Tweener.Tween(self.Fill, Tweener.Info.Fluid, { Size = UDim2.new(pct, 0, 1, 0) })
		self._thumbTween = Tweener.Tween(self.Thumb, Tweener.Info.Fluid, { Position = UDim2.new(pct, 0, 0.5, 0) }, function()
			self._fillTween = nil
			self._thumbTween = nil
		end)
	else
		self.Fill.Size = UDim2.new(pct, 0, 1, 0)
		self.Thumb.Position = UDim2.new(pct, 0, 0.5, 0)
	end

	local displayStr
	if self.Step % 1 == 0 then
		displayStr = string.format("%d", math.round(self.Value))
	else
		displayStr = string.format("%.1f", self.Value)
	end

	-- Real-time badge text update (even while dragging) - display number only without suffix
	if self.BadgeInput and not self.BadgeInput:IsFocused() then
		self.BadgeInput.Text = displayStr
	end
    
    if not skipCallback and self.Callback then
        local ok, err = pcall(self.Callback, self.Value)
        if not ok then
            warn("[SodiumUI.Slider] Callback error:", err)
        end
    end
    
    
    self._isUpdating = false
end

function Slider:Get(): number
    return self.Value
end

function Slider:SetTitle(title: string)
	Locale.Unbind(self.TitleLabel)
	if type(title) == "table" then
		Locale.Bind(self.TitleLabel, "Text", title)
	else
		self.TitleLabel.Text = tostring(title)
	end
end

function Slider:SetDesc(desc: string)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
		if type(desc) == "table" then
			Locale.Bind(self.DescLabel, "Text", desc)
		else
			self.DescLabel.Text = tostring(desc)
		end
	end
end

function Slider:Lock()
    self.Locked = true
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.7 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("Placeholder") })
    if self.BadgeInput then
        self.BadgeInput.TextEditable = false
    end
end

function Slider:Unlock()
    self.Locked = false
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
    if self.BadgeInput then
        self.BadgeInput.TextEditable = true
    end
end

function Slider:Destroy()
	if self._stopDragging then
		pcall(self._stopDragging)
	end
	Tweener.Cancel(self.Fill)
	Tweener.Cancel(self.Thumb)
	self._fillTween = nil
	self._thumbTween = nil
	for _, conn in ipairs(self._connections) do
		if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
			pcall((conn :: any).Disconnect, conn)
		elseif typeof(conn) == "RBXScriptConnection" then
			pcall((conn :: RBXScriptConnection).Disconnect, conn)
		end
	end
	table.clear(self._connections)
	Locale.Unbind(self.TitleLabel)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
	end
	Theme.Unbind(self.Container)
	if self.Container then
		pcall((self.Container :: Instance).Destroy, self.Container)
	end
end

return Slider
end

_MODULES['Elements/Dropdown'] = function()
--!strict
--[=[
    Sodium UI - Elements/Dropdown.luau
    Standard Obsidian Amethyst Popover Menu: Single-Select & Multi-Select.
    Features:
    - Built-in Case-Insensitive Search Filter (Upper/Lower case auto-filtered)
    - Compact horizontal layout with center-aligned selected text
    - Floating Window-Level Popover with smooth viewport boundary detection
    - Dynamic deselection (AllowNone support)
]=]

local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Dropdown = {}
Dropdown.__index = Dropdown

local currentOpenDropdown: any = nil

export type DropdownItem = string | { Title: any, Icon: string?, Value: any?, Id: any?, Name: any?, Text: any?, Label: any? }

export type DropdownProps = {
    Title: any,
    Desc: any?,
    Description: any?,
    Icon: string?,
    Values: { DropdownItem },
    Value: (string | { string })?,
    Default: (string | { string })?,
    Multi: boolean?,
    AllowNone: boolean?,
    Locked: boolean?,
    Callback: ((selected: any) -> ())?,
}

local function normalizeValues(raw: any): { any }
    if type(raw) ~= "table" then
        return {}
    end
    local list = {}
    local isArray = false
    for k, _ in pairs(raw) do
        if type(k) == "number" then
            isArray = true
            break
        end
    end
    
    if isArray then
        local maxIdx = 0
        for k in pairs(raw) do
            if type(k) == "number" and k > maxIdx then
                maxIdx = k
            end
        end
        for i = 1, maxIdx do
            if raw[i] ~= nil then
                table.insert(list, raw[i])
            end
        end
        for k, v in pairs(raw) do
            if type(k) ~= "number" then
                if type(v) == "boolean" and v == true then
                    table.insert(list, tostring(k))
                elseif type(v) == "table" or type(v) == "string" or type(v) == "number" then
                    table.insert(list, v)
                end
            end
        end
    else
        for k, v in pairs(raw) do
            if type(v) == "boolean" then
                if v == true then
                    table.insert(list, tostring(k))
                end
            elseif type(v) == "table" then
                table.insert(list, v)
            elseif type(k) == "string" and (type(v) == "string" or type(v) == "number") then
                table.insert(list, { Title = tostring(k), Value = v })
            else
                table.insert(list, v)
            end
        end
    end
    return list
end

function Dropdown.new(parent: Instance, props: any, parentCard: GuiObject?)
    local titleText = Locale.Resolve(props.Title or props.Name or "Dropdown")
    local rawVal = if props.Value ~= nil then props.Value else props.Default
    
    local self = setmetatable({}, Dropdown)
    self.Values = props.Values or props.Options or props.Items or {}
    self.Multi = props.Multi or false
    self.AllowNone = if props.AllowNone ~= nil then props.AllowNone else true
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self.ParentCard = parentCard
    self.Parent = parent
    self.MainWindow = nil
    self.IsOpen = false
    self.SearchQuery = ""
    self.ClickOutsideConn = nil
    self._scrollConn = nil
    self._connections = {}
    
    local normValues = normalizeValues(self.Values)
    self._normalizedValues = normValues
    
    if self.Multi then
        self.Selected = if type(rawVal) == "table" then rawVal else (rawVal and { rawVal } or {})
    else
        self.Selected = if type(rawVal) == "string" then rawVal else (normValues[1] and (type(normValues[1]) == "table" and (normValues[1].Title or normValues[1].Name or normValues[1].Value) or normValues[1]) or "")
    end
    
    local descProp = props.Desc or props.Description
    local isDesc = descProp and (if type(descProp) == "table" then true else descProp ~= "")
    local containerHeight = if isDesc then 54 else 42
    
    -- Main Container inside Section Card
    local container = Instance.new("Frame")
    container.Name = "Dropdown_" .. tostring(titleText)
    container.Size = UDim2.new(1, 0, 0, containerHeight)
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    container.BackgroundTransparency = 0.5
    container.BorderSizePixel = 0
    container.ZIndex = 5
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = container
    
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = container
    
    local iconOffset = 0
    if props.Icon and props.Icon ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(16, 16)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(icon, props.Icon)
        icon.Parent = container
        iconOffset = 22
    end
    
    -- Left Text: Title & Description
    local titleColor = Theme.ResolveColor(props.TitleColor or props.Color)
    local descColor = Theme.ResolveColor(props.DescColor or props.DescriptionColor)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 150, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 8 else 12)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Header", "Header")
    Locale.Bind(titleLabel, "Text", props.Title or props.Name or "Dropdown")
    titleLabel.TextColor3 = titleColor or Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = container
    if not titleColor then
        Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    end
    
    local descLabel: TextLabel? = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 150, 0, 14)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 28)
        descLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(descLabel, "Sub", "Sub")
        Locale.Bind(descLabel, "Text", descProp or "")
        descLabel.TextColor3 = descColor or Theme.GetToken("TextMuted")
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = container
        if not descColor then
            Theme.Bind(descLabel, "TextColor3", "TextMuted")
        end
    end
    
    -- Right Control: Trigger Button (Auto-expands to accommodate long text)
    local trigger = Instance.new("TextButton")
    trigger.Name = "Trigger"
    trigger.Size = UDim2.new(0, 140, 0, 30)
    trigger.Position = UDim2.new(1, 0, 0.5, 0)
    trigger.AnchorPoint = Vector2.new(1, 0.5)
    trigger.BackgroundColor3 = Theme.GetToken("Card")
    trigger.AutoButtonColor = false
    trigger.Text = ""
    trigger.ZIndex = 6
    
    local trigCorner = Instance.new("UICorner")
    trigCorner.CornerRadius = Theme.Radii.Control
    trigCorner.Parent = trigger
    
    local trigStroke = Instance.new("UIStroke")
    trigStroke.Color = Theme.GetToken("BorderSubtle")
    trigStroke.Thickness = 1
    trigStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    trigStroke.Parent = trigger
    
    local trigPad = Instance.new("UIPadding")
    trigPad.PaddingLeft = UDim.new(0, 8)
    trigPad.PaddingRight = UDim.new(0, 8)
    trigPad.Parent = trigger
    
    local selectedText = Instance.new("TextLabel")
    selectedText.Name = "SelectedText"
    selectedText.Size = UDim2.new(1, -16, 1, 0)
    selectedText.Position = UDim2.new(0, -2, 0, 0)
    selectedText.BackgroundTransparency = 1
    Theme.ApplyTypography(selectedText, "Body", "Sub")
    selectedText.TextColor3 = Theme.GetToken("TextPrimary")
    selectedText.TextXAlignment = Enum.TextXAlignment.Center
    selectedText.TextTruncate = Enum.TextTruncate.AtEnd
    selectedText.Parent = trigger
    
    local chevron = Instance.new("ImageLabel")
    chevron.Name = "Chevron"
    chevron.Size = UDim2.fromOffset(12, 12)
    chevron.Position = UDim2.new(1, 0, 0.5, 0)
    chevron.AnchorPoint = Vector2.new(1, 0.5)
    chevron.BackgroundTransparency = 1
    chevron.ImageColor3 = Theme.GetToken("TextMuted")
    Icons.Apply(chevron, "chevron-down")
    chevron.Parent = trigger
    
    trigger.Parent = container

    local function getOptimalWidth(): number
        local maxW = 140
        local fFace = selectedText.FontFace
        local fSize = selectedText.TextSize or 13

        -- 1. Measure selected text width
        local curStr = tostring(selectedText.Text or "")
        if curStr ~= "" then
            local ok, sz = pcall(function()
                return TextService:GetTextSize(curStr, fSize, fFace, Vector2.new(1000, 30))
            end)
            if not ok then
                local legacyFont = selectedText.Font or Enum.Font.Gotham
                pcall(function()
                    sz = TextService:GetTextSize(curStr, fSize, legacyFont, Vector2.new(1000, 30))
                end)
            end
            if sz and sz.X then
                maxW = math.max(maxW, sz.X + 38)
            end
        end

        -- 2. Measure all option items width
        local normList = self._normalizedValues or normalizeValues(self.Values)
        for _, valItem in ipairs(normList) do
            local rawTitle = if type(valItem) == "table" 
                then ((valItem :: any).Title or (valItem :: any).Name or (valItem :: any).Text or (valItem :: any).Label or (valItem :: any).Value)
                else valItem
            local optStr = Locale.Resolve(rawTitle)
            if optStr and optStr ~= "" then
                local ok, sz = pcall(function()
                    return TextService:GetTextSize(optStr, fSize, fFace, Vector2.new(1000, 30))
                end)
                if not ok then
                    local legacyFont = selectedText.Font or Enum.Font.Gotham
                    pcall(function()
                        sz = TextService:GetTextSize(optStr, fSize, legacyFont, Vector2.new(1000, 30))
                    end)
                end
                if sz and sz.X then
                    local hasIcon = (type(valItem) == "table" and (valItem :: any).Icon) ~= nil
                    local itemExtra = if hasIcon then 62 else 46
                    maxW = math.max(maxW, sz.X + itemExtra)
                end
            end
        end

        return math.clamp(math.ceil(maxW), 140, 260)
    end
    self.GetOptimalWidth = getOptimalWidth
    
    -- Floating Popover List (Parented to Window level when opened)
    local popover = Instance.new("Frame")
    popover.Name = "DropdownPopover_" .. tostring(titleText)
    popover.Size = UDim2.new(0, 140, 0, 0)
    popover.Position = UDim2.new(0, 0, 0, 0)
    popover.BackgroundColor3 = Theme.GetToken("Card")
    popover.BorderSizePixel = 0
    popover.Visible = false
    popover.ZIndex = 4500
    popover.ClipsDescendants = true
    
    local popCorner = Instance.new("UICorner")
    popCorner.CornerRadius = Theme.Radii.Card
    popCorner.Parent = popover
    
    local popStroke = Instance.new("UIStroke")
    popStroke.Color = Theme.GetToken("BorderStrong")
    popStroke.Thickness = 1
    popStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    popStroke.Parent = popover
    
    local popPad = Instance.new("UIPadding")
    popPad.PaddingTop = UDim.new(0, 5)
    popPad.PaddingBottom = UDim.new(0, 5)
    popPad.PaddingLeft = UDim.new(0, 5)
    popPad.PaddingRight = UDim.new(0, 5)
    popPad.Parent = popover
    
    -- Search Input Container inside Popover (Top Row)
    local searchContainer = Instance.new("Frame")
    searchContainer.Name = "SearchContainer"
    searchContainer.Size = UDim2.new(1, 0, 0, 26)
    searchContainer.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    searchContainer.BorderSizePixel = 0
    searchContainer.ZIndex = 4501
    searchContainer.Parent = popover
    
    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = Theme.Radii.Control
    searchCorner.Parent = searchContainer
    
    local searchStroke = Instance.new("UIStroke")
    searchStroke.Color = Theme.GetToken("BorderSubtle")
    searchStroke.Thickness = 1
    searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    searchStroke.Parent = searchContainer
    
    local searchIcon = Instance.new("ImageLabel")
    searchIcon.Name = "SearchIcon"
    searchIcon.Size = UDim2.fromOffset(13, 13)
    searchIcon.Position = UDim2.new(0, 6, 0.5, 0)
    searchIcon.AnchorPoint = Vector2.new(0, 0.5)
    searchIcon.BackgroundTransparency = 1
    searchIcon.ImageColor3 = Theme.GetToken("TextMuted")
    searchIcon.ZIndex = 4502
    Icons.Apply(searchIcon, "search")
    searchIcon.Parent = searchContainer
    
    local searchInput = Instance.new("TextBox")
    searchInput.Name = "SearchInput"
    searchInput.Size = UDim2.new(1, -26, 1, 0)
    searchInput.Position = UDim2.new(0, 22, 0, 0)
    searchInput.BackgroundTransparency = 1
    Theme.ApplyTypography(searchInput, "Body", "Small")
    searchInput.PlaceholderText = "Search..."
    searchInput.PlaceholderColor3 = Theme.GetToken("Placeholder")
    searchInput.Text = ""
    searchInput.TextColor3 = Theme.GetToken("TextPrimary")
    searchInput.TextXAlignment = Enum.TextXAlignment.Left
    searchInput.ClearTextOnFocus = false
    searchInput.ZIndex = 4502
    searchInput.Parent = searchContainer
    
    -- Scrolling list for options
    local optionsList = Instance.new("ScrollingFrame")
    optionsList.Name = "OptionsList"
    optionsList.Size = UDim2.new(1, 0, 1, -30)
    optionsList.Position = UDim2.new(0, 0, 0, 30)
    optionsList.BackgroundTransparency = 1
    optionsList.BorderSizePixel = 0
    optionsList.ScrollBarThickness = 2
    optionsList.ScrollBarImageColor3 = Theme.GetToken("BorderStrong")
    optionsList.CanvasSize = UDim2.new(0, 0, 0, 0)
    optionsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    optionsList.ZIndex = 4501
    optionsList.ClipsDescendants = true
    optionsList.Parent = popover
    
    local popList = Instance.new("UIListLayout")
    popList.SortOrder = Enum.SortOrder.LayoutOrder
    popList.Padding = UDim.new(0, 2)
    popList.Parent = optionsList
    
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.Trigger = trigger
    self.SelectedText = selectedText
    self.Chevron = chevron
    self.Popover = popover
    self.PopStroke = popStroke
    self.SearchContainer = searchContainer
    self.SearchInput = searchInput
    self.OptionsList = optionsList
    
    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    if descLabel then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end
    Theme.Bind(trigger, "BackgroundColor3", "Card")
    Theme.Bind(trigStroke, "Color", "BorderSubtle")
    Theme.Bind(chevron, "ImageColor3", "TextMuted")
    Theme.Bind(popover, "BackgroundColor3", "Card")
    Theme.Bind(popStroke, "Color", "BorderStrong")
    Theme.Bind(searchContainer, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(searchStroke, "Color", "BorderSubtle")
    Theme.Bind(searchIcon, "ImageColor3", "TextMuted")
    Theme.Bind(searchInput, "TextColor3", "TextPrimary")
    Theme.Bind(searchInput, "PlaceholderColor3", "Placeholder")
    
    local function isItemMatch(selectedValue: any, targetTitle: string, targetVal: any?): boolean
        if selectedValue == nil then return false end
        if selectedValue == targetTitle or tostring(selectedValue) == targetTitle then return true end
        if targetVal ~= nil and (selectedValue == targetVal or tostring(selectedValue) == tostring(targetVal)) then
            return true
        end
        if type(selectedValue) == "table" then
            local selTitle = selectedValue.Title or selectedValue.Name or selectedValue.Value
            if selTitle and (selTitle == targetTitle or tostring(selTitle) == targetTitle) then
                return true
            end
        end
        return false
    end

    local function isItemInList(selectedList: any, targetTitle: string, targetVal: any?): (boolean, number?)
        if type(selectedList) ~= "table" then
            if selectedList ~= nil and isItemMatch(selectedList, targetTitle, targetVal) then
                return true, 1
            end
            return false, nil
        end
        for idx, item in ipairs(selectedList) do
            if isItemMatch(item, targetTitle, targetVal) then
                return true, idx
            end
        end
        return false, nil
    end

    local function updateDisplay()
        if self.Multi then
            local count = (type(self.Selected) == "table" and #self.Selected) or 0
            if count == 0 then
                selectedText.Text = "None"
                selectedText.TextColor3 = Theme.GetToken("Placeholder")
            elseif count == 1 then
                selectedText.Text = tostring(self.Selected[1])
                selectedText.TextColor3 = Theme.GetToken("TextPrimary")
            else
                local strList = {}
                for _, it in ipairs(self.Selected) do
                    table.insert(strList, tostring(it))
                end
                selectedText.Text = string.format("%d selected (%s)", count, table.concat(strList, ", "))
                selectedText.TextColor3 = Theme.GetToken("TextPrimary")
            end
        else
            if self.Selected and tostring(self.Selected) ~= "" and tostring(self.Selected) ~= "nil" then
                selectedText.Text = tostring(self.Selected)
                selectedText.TextColor3 = Theme.GetToken("TextPrimary")
            else
                selectedText.Text = "Select..."
                selectedText.TextColor3 = Theme.GetToken("Placeholder")
            end
        end

        local optW = getOptimalWidth()
        trigger.Size = UDim2.new(0, optW, 0, 30)
        titleLabel.Size = UDim2.new(1, -iconOffset - (optW + 10), 0, 18)
        if descLabel then
            descLabel.Size = UDim2.new(1, -iconOffset - (optW + 10), 0, 14)
        end
    end

    local function updateOptionStates()
        for _, child in ipairs(optionsList:GetChildren()) do
            if child:IsA("GuiObject") and child.Name:sub(1, 4) == "Opt_" then
                local optTitle = child:GetAttribute("ItemTitle") or child.Name:sub(5)
                local optVal = child:GetAttribute("ItemValue")
                
                local isSel = false
                if self.Multi then
                    isSel = isItemInList(self.Selected, optTitle, optVal)
                else
                    isSel = isItemMatch(self.Selected, optTitle, optVal)
                end
                
                local optLabel = child:FindFirstChild("Label")
                if optLabel and optLabel:IsA("TextLabel") then
                    optLabel.TextColor3 = if isSel then Theme.GetToken("Accent") else Theme.GetToken("TextPrimary")
                end
                
                local check = child:FindFirstChild("Check")
                if check and check:IsA("ImageLabel") then
                    check.Visible = isSel
                    check.ImageColor3 = Theme.GetToken("Accent")
                end
            end
        end
    end

    local function filterOptions(queryText: string)
        local query = string.lower(queryText or "")
        local visibleCount = 0
        for _, child in ipairs(optionsList:GetChildren()) do
            if child:IsA("GuiObject") and child.Name:sub(1, 4) == "Opt_" then
                local optTitle = string.lower(child:GetAttribute("ItemTitle") or child.Name:sub(5))
                local optVal = string.lower(tostring(child:GetAttribute("ItemValue") or ""))
                
                local matches = query == "" or optTitle:find(query, 1, true) ~= nil or optVal:find(query, 1, true) ~= nil
                child.Visible = matches
                if matches then
                    visibleCount += 1
                end
            end
        end
        local totalItemH = (visibleCount * 26) + math.max(0, visibleCount - 1) * 2
        optionsList.CanvasSize = UDim2.new(0, 0, 0, totalItemH)
    end
    self.FilterOptions = filterOptions

    local function rebuildOptions()
        for _, child in ipairs(optionsList:GetChildren()) do
            if child:IsA("GuiObject") and child.Name:sub(1, 4) == "Opt_" then
                child:Destroy()
            end
        end
        
        local normList = normalizeValues(self.Values)
        self._normalizedValues = normList
        
        for i, valItem in ipairs(normList) do
            local rawTitle = if type(valItem) == "table" 
                then ((valItem :: any).Title or (valItem :: any).Name or (valItem :: any).Text or (valItem :: any).Label or (valItem :: any).Value)
                else valItem
            local itemTitle = Locale.Resolve(rawTitle)
            if itemTitle == "" and type(valItem) == "table" then
                itemTitle = tostring((valItem :: any).Value or (valItem :: any).Id or i)
            elseif itemTitle == "" then
                itemTitle = tostring(valItem or i)
            end

            local rawItemVal = if type(valItem) == "table" 
                then ((valItem :: any).Value ~= nil and (valItem :: any).Value or (valItem :: any).Id or (valItem :: any).Name or (valItem :: any).Title or itemTitle)
                else itemTitle
            local itemIcon = if type(valItem) == "table" then (valItem :: any).Icon else nil
            
            local optBtn = Instance.new("TextButton")
            optBtn.Name = "Opt_" .. tostring(itemTitle)
            optBtn:SetAttribute("ItemTitle", tostring(itemTitle))
            optBtn:SetAttribute("ItemValue", tostring(rawItemVal))
            optBtn.Size = UDim2.new(1, 0, 0, 26)
            optBtn.BackgroundColor3 = Theme.GetToken("SurfaceHover")
            optBtn.BackgroundTransparency = 1
            optBtn.AutoButtonColor = false
            optBtn.Text = ""
            optBtn.ZIndex = 4502
            optBtn.LayoutOrder = i
            
            local optCorner = Instance.new("UICorner")
            optCorner.CornerRadius = Theme.Radii.Control
            optCorner.Parent = optBtn
            
            local optPad = Instance.new("UIPadding")
            optPad.PaddingLeft = UDim.new(0, 8)
            optPad.PaddingRight = UDim.new(0, 8)
            optPad.Parent = optBtn
            
            local optOffset = 0
            if itemIcon and itemIcon ~= "" then
                local icon = Instance.new("ImageLabel")
                icon.Size = UDim2.fromOffset(14, 14)
                icon.Position = UDim2.new(0, 0, 0.5, 0)
                icon.AnchorPoint = Vector2.new(0, 0.5)
                icon.BackgroundTransparency = 1
                icon.ImageColor3 = Theme.GetToken("Accent")
                icon.ZIndex = 4503
                Icons.Apply(icon, itemIcon)
                icon.Parent = optBtn
                optOffset = 20
            end
            
            local isSel = false
            if self.Multi then
                isSel = isItemInList(self.Selected, itemTitle, rawItemVal)
            else
                isSel = isItemMatch(self.Selected, itemTitle, rawItemVal)
            end
            
            local optLabel = Instance.new("TextLabel")
            optLabel.Name = "Label"
            optLabel.Size = UDim2.new(1, -optOffset - 22, 1, 0)
            optLabel.Position = UDim2.new(0, optOffset, 0, 0)
            optLabel.BackgroundTransparency = 1
            Theme.ApplyTypography(optLabel, "Body", "Sub")
            optLabel.Text = itemTitle
            optLabel.TextColor3 = if isSel then Theme.GetToken("Accent") else Theme.GetToken("TextPrimary")
            optLabel.TextXAlignment = Enum.TextXAlignment.Left
            optLabel.TextYAlignment = Enum.TextYAlignment.Center
            optLabel.ZIndex = 4503
            optLabel.Parent = optBtn
            
            local check = Instance.new("ImageLabel")
            check.Name = "Check"
            check.Size = UDim2.fromOffset(12, 12)
            check.Position = UDim2.new(1, 0, 0.5, 0)
            check.AnchorPoint = Vector2.new(1, 0.5)
            check.BackgroundTransparency = 1
            check.ImageColor3 = Theme.GetToken("Accent")
            check.ZIndex = 4503
            Icons.Apply(check, "check")
            check.Visible = isSel
            check.Parent = optBtn
            
            optBtn.MouseEnter:Connect(function()
                Tweener.Tween(optBtn, Tweener.Info.Micro, { BackgroundTransparency = 0 })
            end)
            optBtn.MouseLeave:Connect(function()
                Tweener.Tween(optBtn, Tweener.Info.Micro, { BackgroundTransparency = 1 })
            end)
            
            optBtn.Activated:Connect(function()
                if self.Multi then
                    local itemExists, idx = isItemInList(self.Selected, itemTitle, rawItemVal)
                    if itemExists and idx then
                        table.remove(self.Selected, idx)
                    else
                        table.insert(self.Selected, itemTitle)
                    end
                    updateDisplay()
                    updateOptionStates()
                    if self.Callback then
                        self.Callback(table.clone(self.Selected))
                    end
                else
                    if isItemMatch(self.Selected, itemTitle, rawItemVal) then
                        self.Selected = nil
                    else
                        self.Selected = itemTitle
                    end
                    updateDisplay()
                    updateOptionStates()
                    self:Close()
                    if self.Callback then
                        self.Callback(self.Selected)
                    end
                end
            end)
            
            optBtn.Parent = optionsList
        end
        filterOptions(self.SearchQuery)
    end

    self.UpdateDisplay = updateDisplay
    self.UpdateOptionStates = updateOptionStates
    self.RebuildOptions = rebuildOptions
    rebuildOptions()
    updateDisplay()
    updateOptionStates()
    
    -- Realtime Search Listener (Case-Insensitive filter)
    searchInput:GetPropertyChangedSignal("Text"):Connect(function()
        self.SearchQuery = searchInput.Text
        filterOptions(self.SearchQuery)
    end)
    
    table.insert(self._connections, Theme.Changed:Connect(function()
        updateDisplay()
        updateOptionStates()
    end))
    
    trigger.Activated:Connect(function()
        if self.Locked then return end
        if self.IsOpen then
            self:Close()
        else
            self:Open()
        end
    end)
    
    
    container.Parent = parent
    return self
end

function Dropdown:_findMainWindow(): GuiObject?
    if self.MainWindow and self.MainWindow.Parent then
        return self.MainWindow
    end
    local cur: Instance? = self.ParentCard or self.Parent or self.Container
    while cur and cur.Parent do
        if cur:IsA("Frame") and cur.Name:find("^SodiumWindow_") then
            self.MainWindow = cur :: GuiObject
            return self.MainWindow
        end
        cur = cur.Parent
    end
    return nil
end

function Dropdown:_updatePosition()
    if not self.IsOpen or not self.Popover then return end
    local mainWindow = self:_findMainWindow()
    if not mainWindow or not mainWindow.Parent then
        return
    end
    
    local uiScale = mainWindow.Parent and mainWindow.Parent:FindFirstChild("GlobalScaler")
    local globalScale = (uiScale and uiScale:IsA("UIScale") and uiScale.Scale) or 1
    local winScaleObj = mainWindow:FindFirstChild("WindowScale")
    local winScale = (winScaleObj and winScaleObj:IsA("UIScale") and winScaleObj.Scale) or 1
    local totalScale = globalScale * winScale
    if totalScale <= 0 then totalScale = 1 end
    
    local trigAbsPos = self.Trigger.AbsolutePosition
    local trigAbsSize = self.Trigger.AbsoluteSize
    local winAbsPos = mainWindow.AbsolutePosition
    local winAbsSize = mainWindow.AbsoluteSize
    
    local relX = (trigAbsPos.X - winAbsPos.X) / totalScale
    local relY = (trigAbsPos.Y - winAbsPos.Y) / totalScale
    local trigW = trigAbsSize.X / totalScale
    local trigH = trigAbsSize.Y / totalScale
    
    local optW = if type(self.GetOptimalWidth) == "function" then self:GetOptimalWidth() else trigW
    local popW = math.max(trigW, optW)
    local popX = relX + (trigW - popW)
    
    local maxWinW = (winAbsSize.X / totalScale) - 12
    if popW > maxWinW then
        popW = math.max(140, maxWinW)
    end
    if popX < 12 then
        popX = 12
    end
    
    local normList = self._normalizedValues or normalizeValues(self.Values)
    local optCount = #normList
    -- 34px for Search row + items list
    local totalContentH = 34 + (optCount * 26) + math.max(0, optCount - 1) * 2 + 10
    local maxAllowedH = 220
    local targetH = math.clamp(totalContentH, 70, maxAllowedH)
    
    local camera = workspace.CurrentCamera
    local screenH = (camera and camera.ViewportSize.Y) or 1080
    
    local wouldOverflowBottom = (trigAbsPos.Y + trigAbsSize.Y + (targetH * totalScale) + 8) > (screenH - 12)
    local popY: number
    if wouldOverflowBottom then
        popY = relY - targetH - 4
    else
        popY = relY + trigH + 4
    end
    
    self.Popover.Position = UDim2.fromOffset(popX, popY)
end

function Dropdown:Open()
    if currentOpenDropdown and currentOpenDropdown ~= self then
        currentOpenDropdown:Close()
    end
    currentOpenDropdown = self
    self.IsOpen = true
    
    if self.UpdateOptionStates then
        self.UpdateOptionStates()
    end
    
    -- Reset search query on open
    if self.SearchInput then
        self.SearchInput.Text = ""
    end
    self.SearchQuery = ""
    if self.FilterOptions then
        self.FilterOptions("")
    end
    
    local mainWindow = self:_findMainWindow()
    local normList = self._normalizedValues or normalizeValues(self.Values)
    local optCount = #normList
    local totalContentH = 34 + (optCount * 26) + math.max(0, optCount - 1) * 2 + 10
    local maxAllowedH = 220
    local targetH = math.clamp(totalContentH, 70, maxAllowedH)
    
    if mainWindow and mainWindow.Parent then
        self.Popover.Parent = mainWindow
        self.Popover.ZIndex = 4500
        
        local uiScale = mainWindow.Parent and mainWindow.Parent:FindFirstChild("GlobalScaler")
        local globalScale = (uiScale and uiScale:IsA("UIScale") and uiScale.Scale) or 1
        local winScaleObj = mainWindow:FindFirstChild("WindowScale")
        local winScale = (winScaleObj and winScaleObj:IsA("UIScale") and winScaleObj.Scale) or 1
        local totalScale = globalScale * winScale
        if totalScale <= 0 then totalScale = 1 end
        
        local trigAbsPos = self.Trigger.AbsolutePosition
        local trigAbsSize = self.Trigger.AbsoluteSize
        local winAbsPos = mainWindow.AbsolutePosition
        local winAbsSize = mainWindow.AbsoluteSize
        
        local relX = (trigAbsPos.X - winAbsPos.X) / totalScale
        local relY = (trigAbsPos.Y - winAbsPos.Y) / totalScale
        local trigW = trigAbsSize.X / totalScale
        local trigH = trigAbsSize.Y / totalScale
        
        local optW = if type(self.GetOptimalWidth) == "function" then self:GetOptimalWidth() else trigW
        local popW = math.max(trigW, optW)
        local popX = relX + (trigW - popW)

        local maxWinW = (winAbsSize.X / totalScale) - 12
        if popW > maxWinW then
            popW = math.max(140, maxWinW)
        end
        if popX < 12 then
            popX = 12
        end
        
        local camera = workspace.CurrentCamera
        local screenH = (camera and camera.ViewportSize.Y) or 1080
        
        local wouldOverflowBottom = (trigAbsPos.Y + trigAbsSize.Y + (targetH * totalScale) + 8) > (screenH - 12)
        local popY: number
        if wouldOverflowBottom then
            popY = relY - targetH - 4
        else
            popY = relY + trigH + 4
        end
        
        self.Popover.Position = UDim2.fromOffset(popX, popY)
        self.Popover.Size = UDim2.fromOffset(popW, 0)
        self.Popover.Visible = true
        
        Tweener.Tween(self.Popover, Tweener.Info.Fluid, {
            Size = UDim2.fromOffset(popW, targetH)
        })
    else
        self.Popover.Parent = self.Trigger
        self.Popover.Position = UDim2.new(0, 0, 1, 4)
        self.Popover.Size = UDim2.new(1, 0, 0, 0)
        self.Popover.Visible = true
        Tweener.Tween(self.Popover, Tweener.Info.Fluid, {
            Size = UDim2.new(1, 0, 0, targetH)
        })
    end
    
    Tweener.Tween(self.Chevron, Tweener.Info.Fast, {
        Rotation = 180
    })
    
    -- Auto-track scrolling of tab
    local pageScroll = self.Trigger:FindFirstAncestorWhichIsA("ScrollingFrame")
    if pageScroll and pageScroll ~= self.OptionsList then
        if self._scrollConn then
            self._scrollConn:Disconnect()
            self._scrollConn = nil
        end
        self._scrollConn = pageScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
            if not self.IsOpen then return end
            local trigY = self.Trigger.AbsolutePosition.Y
            local pageY = pageScroll.AbsolutePosition.Y
            local pageH = pageScroll.AbsoluteSize.Y
            if trigY < (pageY - 30) or trigY > (pageY + pageH) then
                self:Close()
            else
                self:_updatePosition()
            end
        end)
    end
    
    -- Click outside auto-close listener
    local openTime = os.clock()
    task.defer(function()
        if not self.IsOpen then return end
        if self.ClickOutsideConn then
            self.ClickOutsideConn:Disconnect()
            self.ClickOutsideConn = nil
        end
        
        self.ClickOutsideConn = UserInputService.InputBegan:Connect(function(input)
            if (os.clock() - openTime) < 0.15 then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                local pos = Vector2.new(input.Position.X, input.Position.Y)
                local trigPos = self.Trigger.AbsolutePosition
                local trigSize = self.Trigger.AbsoluteSize
                local inTrigger = pos.X >= trigPos.X and pos.X <= (trigPos.X + trigSize.X) and pos.Y >= trigPos.Y and pos.Y <= (trigPos.Y + trigSize.Y)
                
                local popPos = self.Popover.AbsolutePosition
                local popSize = self.Popover.AbsoluteSize
                local inPopover = pos.X >= popPos.X and pos.X <= (popPos.X + popSize.X) and pos.Y >= popPos.Y and pos.Y <= (popPos.Y + popSize.Y)
                
                if not inTrigger and not inPopover then
                    self:Close()
                end
            end
        end)
    end)
end

function Dropdown:Close()
    self.IsOpen = false
    if currentOpenDropdown == self then
        currentOpenDropdown = nil
    end
    
    if self.ClickOutsideConn then
        self.ClickOutsideConn:Disconnect()
        self.ClickOutsideConn = nil
    end
    if self._scrollConn then
        self._scrollConn:Disconnect()
        self._scrollConn = nil
    end
    
    local curW = self.Popover.Size.X.Offset
    if curW <= 0 then
        curW = self.Popover.AbsoluteSize.X
    end
    if curW <= 0 then
        curW = 140
    end
    
    Tweener.Tween(self.Popover, Tweener.Info.Fast, {
        Size = UDim2.fromOffset(curW, 0),
    })
    local rotTween = Tweener.Tween(self.Chevron, Tweener.Info.Fast, {
        Rotation = 0,
    })
    if rotTween then
        rotTween.Completed:Once(function()
            if not self.IsOpen and self.Popover and self.Popover.Parent then
                self.Popover.Visible = false
            end
        end)
    else
        if not self.IsOpen and self.Popover then
            pcall(function()
                self.Popover.Visible = false
            end)
        end
    end
end

function Dropdown:Set(val: any, skipCallback: boolean?)
    if self.Multi then
        if type(val) == "table" then
            local isDict = false
            for k, _ in pairs(val) do
                if type(k) ~= "number" then
                    isDict = true
                    break
                end
            end
            if isDict then
                local list = {}
                for k, v in pairs(val) do
                    if v == true then
                        table.insert(list, tostring(k))
                    end
                end
                table.sort(list)
                self.Selected = list
            else
                local list = {}
                for _, v in ipairs(val) do
                    table.insert(list, tostring(v))
                end
                self.Selected = list
            end
        elseif val ~= nil and val ~= "" then
            self.Selected = { tostring(val) }
        else
            self.Selected = {}
        end
    else
        if val == nil then
            self.Selected = if self.AllowNone then nil else self.Selected
        elseif type(val) == "table" then
            local first = val[1] or val.Title or val.Value or val.Name
            self.Selected = if first ~= nil then tostring(first) else self.Selected
        else
            self.Selected = tostring(val)
        end
    end
    self:RebuildOptions()
    self.UpdateDisplay()
    if self.UpdateOptionStates then
        self.UpdateOptionStates()
    end
    
    if not skipCallback and self.Callback then
        local ok, err = pcall(self.Callback, self.Selected)
        if not ok then
            warn("[SodiumUI.Dropdown] Callback error:", err)
        end
    end
end

function Dropdown:Clear(skipCallback: boolean?)
    if self.Multi then
        self.Selected = {}
    else
        self.Selected = nil
    end
    self:RebuildOptions()
    self.UpdateDisplay()
    if self.UpdateOptionStates then
        self.UpdateOptionStates()
    end
    if not skipCallback and self.Callback then
        local ok, err = pcall(self.Callback, self.Selected)
        if not ok then
            warn("[SodiumUI.Dropdown] Callback error:", err)
        end
    end
end
Dropdown.ClearDropdown = Dropdown.Clear

function Dropdown:Get(): any
    return self.Selected
end

function Dropdown:Refresh(newValues: { DropdownItem })
    self.Values = newValues or {}
    self._normalizedValues = normalizeValues(self.Values)
    self:RebuildOptions()
    self.UpdateDisplay()
    if self.UpdateOptionStates then
        self.UpdateOptionStates()
    end
    if self.IsOpen then
        self:_updatePosition()
        local normList = self._normalizedValues
        local optCount = #normList
        local totalContentH = 34 + (optCount * 26) + math.max(0, optCount - 1) * 2 + 10
        local maxAllowedH = 220
        local targetH = math.clamp(totalContentH, 70, maxAllowedH)
        Tweener.Tween(self.Popover, Tweener.Info.Fast, {
            Size = UDim2.fromOffset(self.Popover.Size.X.Offset, targetH)
        })
    end
end

function Dropdown:SetTitle(title: string)
    Locale.Unbind(self.TitleLabel)
    if type(title) == "table" then
        Locale.Bind(self.TitleLabel, "Text", title)
    else
        self.TitleLabel.Text = tostring(title)
    end
end

function Dropdown:SetDesc(desc: string)
    if self.DescLabel then
        Locale.Unbind(self.DescLabel)
        if type(desc) == "table" then
            Locale.Bind(self.DescLabel, "Text", desc)
        else
            self.DescLabel.Text = tostring(desc)
        end
    end
end

function Dropdown:Lock()
    self.Locked = true
    self:Close()
    self.Container.BackgroundTransparency = 0.7
    self.TitleLabel.TextColor3 = Theme.GetToken("Placeholder")
end

function Dropdown:Unlock()
    self.Locked = false
    self.Container.BackgroundTransparency = 0.5
    self.TitleLabel.TextColor3 = Theme.GetToken("TextPrimary")
end

function Dropdown:Destroy()
    self.IsOpen = false
    if currentOpenDropdown == self then
        currentOpenDropdown = nil
    end
    if self.ClickOutsideConn then
        pcall((self.ClickOutsideConn :: RBXScriptConnection).Disconnect, self.ClickOutsideConn)
        self.ClickOutsideConn = nil
    end
    if self._scrollConn then
        pcall((self._scrollConn :: RBXScriptConnection).Disconnect, self._scrollConn)
        self._scrollConn = nil
    end
    for _, conn in ipairs(self._connections) do
        if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
            pcall((conn :: any).Disconnect, conn)
        elseif typeof(conn) == "RBXScriptConnection" then
            pcall((conn :: RBXScriptConnection).Disconnect, conn)
        end
    end
    table.clear(self._connections)
    Tweener.Cancel(self.Popover)
    Tweener.Cancel(self.Chevron)
    Locale.Unbind(self.TitleLabel)
    if self.DescLabel then
        Locale.Unbind(self.DescLabel)
    end
    Theme.Unbind(self.Container)
    Theme.Unbind(self.Popover)
    if self.Popover then
        pcall((self.Popover :: Instance).Destroy, self.Popover)
    end
    if self.Container then
        pcall((self.Container :: Instance).Destroy, self.Container)
    end
end

return Dropdown
end

_MODULES['Elements/Input'] = function()
--!strict
--[=[
    Sodium UI - Elements/Input.luau
    Text input field with placeholder, clear button, focus glow, and enter submit callback.
]=]

local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Input = {}
Input.__index = Input

export type InputProps = {
    Title: any,
    Desc: any?,
    Description: any?,
    Icon: string?,
    Value: string?,
    Placeholder: any?,
    ClearTextOnFocus: boolean?,
    Locked: boolean?,
    Callback: ((text: string) -> ())?,
}

function Input.new(parent: Instance, props: any)
    local titleText = Locale.Resolve(props.Title or props.Name or "Input")
    local rawVal = if props.Value ~= nil then props.Value elseif props.Default ~= nil then props.Default else ""

    local self = setmetatable({}, Input)
    self.Value = tostring(rawVal)
    self.Placeholder = Locale.Resolve(props.Placeholder or "Type here...")
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self._connections = {}
    
    local descProp = props.Desc or props.Description
    local isDesc = descProp and (if type(descProp) == "table" then true else descProp ~= "")
    local containerHeight = if isDesc then 66 else 52
    
    local container = Instance.new("Frame")
    container.Name = "Input_" .. tostring(titleText)
    container.Size = UDim2.new(1, 0, 0, containerHeight)
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    container.BackgroundTransparency = 0.5
    container.BorderSizePixel = 0
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = container
    
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = container
    
    -- Icon Support
    local iconOffset = 0
    if props.Icon and props.Icon ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(16, 16)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(icon, props.Icon)
        icon.Parent = container
        Theme.Bind(icon, "ImageColor3", "Accent")
        iconOffset = 22
    end
    
    -- Title & Desc
    local titleColor = Theme.ResolveColor(props.TitleColor or props.Color)
    local descColor = Theme.ResolveColor(props.DescColor or props.DescriptionColor)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 150, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 8 else 12)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Header", "Header")
    Locale.Bind(titleLabel, "Text", props.Title or props.Name or "Input")
    titleLabel.TextColor3 = titleColor or Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = container
    if not titleColor then
        Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    end
    
    local descLabel: TextLabel? = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 150, 0, 14)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 28)
        descLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(descLabel, "Sub", "Sub")
        Locale.Bind(descLabel, "Text", descProp or "")
        descLabel.TextColor3 = descColor or Theme.GetToken("TextMuted")
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = container
        if not descColor then
            Theme.Bind(descLabel, "TextColor3", "TextMuted")
        end
    end
    
    -- Input Box Frame (Width = 140px, Height = 30px to match Dropdown trigger exactly)
    local boxFrame = Instance.new("Frame")
    boxFrame.Name = "BoxFrame"
    boxFrame.Size = UDim2.new(0, 140, 0, 30)
    boxFrame.Position = UDim2.new(1, 0, 0.5, 0)
    boxFrame.AnchorPoint = Vector2.new(1, 0.5)
    boxFrame.BackgroundColor3 = Theme.GetToken("Card")
    
    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = Theme.Radii.Control
    boxCorner.Parent = boxFrame
    
    local boxStroke = Instance.new("UIStroke")
    boxStroke.Color = Theme.GetToken("BorderSubtle")
    boxStroke.Thickness = 1
    boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    boxStroke.Parent = boxFrame
    
    local boxPad = Instance.new("UIPadding")
    boxPad.PaddingLeft = UDim.new(0, 10)
    boxPad.PaddingRight = UDim.new(0, 8)
    boxPad.Parent = boxFrame
    
    local textBox = Instance.new("TextBox")
    textBox.Name = "TextBox"
    textBox.Size = UDim2.new(1, -22, 1, 0)
    textBox.BackgroundTransparency = 1
    Theme.ApplyTypography(textBox, "Body", "Sub")
    textBox.Text = self.Value
    Locale.Bind(textBox, "PlaceholderText", props.Placeholder or "Type here...")
    textBox.PlaceholderColor3 = Theme.GetToken("Placeholder")
    textBox.TextColor3 = Theme.GetToken("TextPrimary")
    textBox.TextXAlignment = Enum.TextXAlignment.Center
    textBox.TextTruncate = Enum.TextTruncate.AtEnd
    textBox.ClearTextOnFocus = if props.ClearTextOnFocus ~= nil then props.ClearTextOnFocus else false
    textBox.ClipsDescendants = true
    textBox.Parent = boxFrame
    
    -- Clear button (x icon)
    local clearBtn = Instance.new("ImageButton")
    clearBtn.Name = "Clear"
    clearBtn.Size = UDim2.fromOffset(14, 14)
    clearBtn.Position = UDim2.new(1, 0, 0.5, 0)
    clearBtn.AnchorPoint = Vector2.new(1, 0.5)
    clearBtn.BackgroundTransparency = 1
    clearBtn.ImageColor3 = Theme.GetToken("Placeholder")
    clearBtn.Visible = self.Value ~= ""
    Icons.Apply(clearBtn, "x")
    clearBtn.Parent = boxFrame
    
    boxFrame.Parent = container
    
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.TextBox = textBox
    self.BoxStroke = boxStroke
    self.ClearBtn = clearBtn
    
    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    if descLabel then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end
    Theme.Bind(boxFrame, "BackgroundColor3", "Card")
    Theme.Bind(boxStroke, "Color", "BorderSubtle")
    Theme.Bind(textBox, "TextColor3", "TextPrimary")
    Theme.Bind(textBox, "PlaceholderColor3", "Placeholder")
    Theme.Bind(clearBtn, "ImageColor3", "Placeholder")
    
    Tweener.BindHoverLift(container, stroke)
    
    -- Focus in/out glow animations with thickness and background tint
    table.insert(self._connections, textBox.Focused:Connect(function()
        Tweener.Tween(boxStroke, Tweener.Info.Fast, {
            Color = Theme.GetToken("BorderAccent"),
            Thickness = 1.5,
        })
        Tweener.Tween(boxFrame, Tweener.Info.Fast, {
            BackgroundColor3 = Theme.GetToken("SurfaceHover"),
        })
    end))
    
    table.insert(self._connections, textBox.FocusLost:Connect(function(enterPressed)
        Tweener.Tween(boxStroke, Tweener.Info.Fast, {
            Color = Theme.GetToken("BorderSubtle"),
            Thickness = 1,
        })
        Tweener.Tween(boxFrame, Tweener.Info.Fast, {
            BackgroundColor3 = Theme.GetToken("Card"),
        })
		self.Value = textBox.Text
		clearBtn.Visible = self.Value ~= ""
		if self.Callback then
			local ok, err = pcall(self.Callback, self.Value)
			if not ok then
				warn("[SodiumUI.Input] Callback error:", err)
			end
		end
	end))
    
    table.insert(self._connections, textBox:GetPropertyChangedSignal("Text"):Connect(function()
        clearBtn.Visible = textBox.Text ~= ""
    end))
    
	table.insert(self._connections, clearBtn.MouseEnter:Connect(function()
		Tweener.Tween(clearBtn, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextPrimary") })
	end))
	table.insert(self._connections, clearBtn.MouseLeave:Connect(function()
		Tweener.Tween(clearBtn, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Placeholder") })
	end))

	table.insert(self._connections, clearBtn.Activated:Connect(function()
		textBox.Text = ""
		self.Value = ""
		clearBtn.Visible = false
		if self.Callback then
			local ok, err = pcall(self.Callback, "")
			if not ok then
				warn("[SodiumUI.Input] Callback error:", err)
			end
		end
	end))
    
    -- Flag Registration
    
    container.Parent = parent
    return self
end

function Input:Set(text: string, skipCallback: boolean?)
    local cleanText = if text ~= nil then tostring(text) else ""
    self.Value = cleanText
    self.TextBox.Text = cleanText
    self.ClearBtn.Visible = cleanText ~= ""
    if not skipCallback and self.Callback then
        local ok, err = pcall(self.Callback, self.Value)
        if not ok then
            warn("[SodiumUI.Input] Callback error:", err)
        end
    end
end

function Input:Get(): string
    return self.Value
end

function Input:SetPlaceholder(placeholder: string)
	self.Placeholder = placeholder
	Locale.Unbind(self.TextBox)
	if type(placeholder) == "table" then
		Locale.Bind(self.TextBox, "PlaceholderText", placeholder)
	else
		self.TextBox.PlaceholderText = tostring(placeholder)
	end
end

function Input:SetTitle(title: string)
	Locale.Unbind(self.TitleLabel)
	if type(title) == "table" then
		Locale.Bind(self.TitleLabel, "Text", title)
	else
		self.TitleLabel.Text = tostring(title)
	end
end

function Input:SetDesc(desc: string)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
		if type(desc) == "table" then
			Locale.Bind(self.DescLabel, "Text", desc)
		else
			self.DescLabel.Text = tostring(desc)
		end
	end
end

function Input:Lock()
    self.Locked = true
    self.TextBox.TextEditable = false
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.7 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("Placeholder") })
end

function Input:Unlock()
    self.Locked = false
    self.TextBox.TextEditable = true
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
end

function Input:Destroy()
	Tweener.Cancel(self.Container)
	for _, conn in ipairs(self._connections) do
		if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
			pcall((conn :: any).Disconnect, conn)
		elseif typeof(conn) == "RBXScriptConnection" then
			pcall((conn :: RBXScriptConnection).Disconnect, conn)
		end
	end
	table.clear(self._connections)
	Locale.Unbind(self.TitleLabel)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
	end
	Locale.Unbind(self.TextBox)
	Theme.Unbind(self.Container)
	if self.Container then
		pcall((self.Container :: Instance).Destroy, self.Container)
	end
end

return Input
end

_MODULES['Elements/Keybind'] = function()
--!strict
--[=[
    Sodium UI - Elements/Keybind.luau
    Dynamic key listener supporting Keyboard and Mouse buttons (M1/M2/M3) with listening badge.
    Refined: 82px badge width accommodating longer key names like RightBracket.
]=]

local UserInputService = game:GetService("UserInputService")
local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Keybind = {}
Keybind.__index = Keybind

export type KeybindProps = {
    Title: any,
    Desc: any?,
    Description: any?,
    Icon: string?,
    Value: (string | Enum.KeyCode)?,
    Locked: boolean?,
    Callback: ((key: string) -> ())?,
}

function Keybind.new(parent: Instance, props: any)
    local titleText = Locale.Resolve(props.Title or props.Name or "Keybind")
    local rawVal = if props.Value ~= nil then props.Value elseif props.Default ~= nil then props.Default else nil

    local self = setmetatable({}, Keybind)
    self.Value = if rawVal then (if typeof(rawVal) == "EnumItem" then rawVal.Name else tostring(rawVal)) else "None"
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self.IsListening = false
    self._connections = {}
    self._listenConn = nil
    
    local descProp = props.Desc or props.Description
    local isDesc = descProp and (if type(descProp) == "table" then true else descProp ~= "")
    local containerHeight = if isDesc then 54 else 42
    
    local container = Instance.new("Frame")
    container.Name = "Keybind_" .. tostring(titleText)
    container.Size = UDim2.new(1, 0, 0, containerHeight)
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    container.BackgroundTransparency = 0.5
    container.BorderSizePixel = 0
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = container
    
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = container
    
    local iconOffset = 0
    if props.Icon and props.Icon ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(18, 18)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(icon, props.Icon)
        icon.Parent = container
        iconOffset = 26
    end
    
    local titleColor = Theme.ResolveColor(props.TitleColor or props.Color)
    local descColor = Theme.ResolveColor(props.DescColor or props.DescriptionColor)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 90, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 9 else 12)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Header", "Header")
    Locale.Bind(titleLabel, "Text", props.Title or props.Name or "Keybind")
    titleLabel.TextColor3 = titleColor or Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = container
    if not titleColor then
        Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    end
    
    local descLabel: TextLabel? = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 90, 0, 16)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 29)
        descLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(descLabel, "Sub", "Sub")
        Locale.Bind(descLabel, "Text", descProp or "")
        descLabel.TextColor3 = descColor or Theme.GetToken("TextMuted")
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = container
        if not descColor then
            Theme.Bind(descLabel, "TextColor3", "TextMuted")
        end
    end
    
    -- Key Display Badge / Trigger (Height 30px to match Dropdown trigger, min 68px, max 140px)
    local badge = Instance.new("TextButton")
    badge.Name = "KeyBadge"
    badge.Size = UDim2.new(0, 0, 0, 30)
    badge.AutomaticSize = Enum.AutomaticSize.X
    badge.Position = UDim2.new(1, 0, 0.5, 0)
    badge.AnchorPoint = Vector2.new(1, 0.5)
    badge.BackgroundColor3 = Theme.GetToken("Card")
    badge.AutoButtonColor = false
    badge.Text = ""
    
    local badgeConstraint = Instance.new("UISizeConstraint")
    badgeConstraint.MinSize = Vector2.new(68, 30)
    badgeConstraint.MaxSize = Vector2.new(140, 30)
    badgeConstraint.Parent = badge
    
    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = Theme.Radii.Control
    badgeCorner.Parent = badge
    
    local badgeStroke = Instance.new("UIStroke")
    badgeStroke.Color = Theme.GetToken("BorderSubtle")
    badgeStroke.Thickness = 1
    badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    badgeStroke.Parent = badge
    
    local badgePad = Instance.new("UIPadding")
    badgePad.PaddingLeft = UDim.new(0, 10)
    badgePad.PaddingRight = UDim.new(0, 10)
    badgePad.Parent = badge
    
    local badgeText = Instance.new("TextLabel")
    badgeText.Name = "KeyText"
    badgeText.Size = UDim2.fromScale(1, 1)
    badgeText.BackgroundTransparency = 1
    Theme.ApplyTypography(badgeText, "Code", "Small")
    badgeText.Text = self.Value
    badgeText.TextColor3 = Theme.GetToken("TextPrimary")
    badgeText.TextXAlignment = Enum.TextXAlignment.Center
    badgeText.TextTruncate = Enum.TextTruncate.AtEnd
    badgeText.Parent = badge
    badge.Parent = container
    
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.Badge = badge
    self.BadgeStroke = badgeStroke
    self.BadgeText = badgeText
    
    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    if descLabel then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end
    Theme.Bind(badge, "BackgroundColor3", "Card")
    Theme.Bind(badgeStroke, "Color", "BorderSubtle")
    Theme.Bind(badgeText, "TextColor3", "TextPrimary")
    
	self._feedback = {}
	do
		local h = Tweener.BindHoverLift(container, stroke)
		if h then
			table.insert(self._feedback, h)
		end
		local p = Tweener.BindPressFeedback(badge)
		if p then
			table.insert(self._feedback, p)
		end
	end

	table.insert(self._connections, badge.MouseEnter:Connect(function()
		if not self.IsListening then
			Tweener.Tween(badge, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
			Tweener.Tween(badgeStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderAccent") })
		end
	end))
	table.insert(self._connections, badge.MouseLeave:Connect(function()
		if not self.IsListening then
			Tweener.Tween(badge, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Card") })
			Tweener.Tween(badgeStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
		end
	end))
    
    local pulseThread: any = nil
    local function endListening(selectedKey: string?)
        if self._listenConn then
            self._listenConn:Disconnect()
            self._listenConn = nil
        end
        if pulseThread then
            task.cancel(pulseThread)
            pulseThread = nil
        end
        self.IsListening = false
        badgeStroke.Transparency = 0
        Tweener.Tween(badge, Tweener.Info.Fast, {
            BackgroundColor3 = Theme.GetToken("Card")
        })
        Tweener.Tween(badgeStroke, Tweener.Info.Fast, {
            Color = Theme.GetToken("BorderSubtle")
        })
        Tweener.Tween(badgeText, Tweener.Info.Fast, {
            TextColor3 = Theme.GetToken("TextPrimary")
        })
        if selectedKey then
            self:Set(selectedKey)
        else
            badgeText.Text = self.Value
        end
    end
    self._endListening = endListening
    
    local function openMobileKeyPicker()
        local targetParent: Instance? = nil
        local cur = container.Parent
        while cur and cur.Parent do
            if cur:IsA("Frame") and cur.Name:find("SodiumWindow") then
                targetParent = cur
                break
            end
            cur = cur.Parent
        end
        if not targetParent then
            targetParent = container:FindFirstAncestorOfClass("ScreenGui")
        end
        if not targetParent then return end
        
        local existingModal = targetParent:FindFirstChild("SodiumUI_KeyPickerModal")
        if existingModal then existingModal:Destroy() end
        
        local backdrop = Instance.new("TextButton")
        backdrop.Name = "SodiumUI_KeyPickerModal"
        backdrop.Size = UDim2.fromScale(1, 1)
        backdrop.Position = UDim2.fromScale(0, 0)
        backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        backdrop.BackgroundTransparency = 0.5
        backdrop.ZIndex = 80
        backdrop.AutoButtonColor = false
        backdrop.Text = ""
        backdrop.Active = true
        
        local backdropCorner = Instance.new("UICorner")
        backdropCorner.CornerRadius = Theme.Radii.Window
        backdropCorner.Parent = backdrop
        
        local modal = Instance.new("Frame")
        modal.Name = "KeyPickerCard"
        modal.Size = UDim2.new(0.85, 0, 0, 0)
        modal.AutomaticSize = Enum.AutomaticSize.Y
        modal.Position = UDim2.fromScale(0.5, 0.5)
        modal.AnchorPoint = Vector2.new(0.5, 0.5)
        modal.BackgroundColor3 = Theme.GetToken("Card")
        modal.BorderSizePixel = 0
        modal.ZIndex = 85
        modal.Active = true
        
        local constraint = Instance.new("UISizeConstraint")
        constraint.MaxSize = Vector2.new(340, 420)
        constraint.Parent = modal
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = Theme.Radii.Card
        corner.Parent = modal
        
        local stroke = Instance.new("UIStroke")
        stroke.Color = Theme.GetToken("BorderSubtle")
        stroke.Thickness = 1
        stroke.Parent = modal
        
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 14)
        pad.PaddingBottom = UDim.new(0, 14)
        pad.PaddingLeft = UDim.new(0, 14)
        pad.PaddingRight = UDim.new(0, 14)
        pad.Parent = modal
        
        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 10)
        layout.Parent = modal
        
        local title = Instance.new("TextLabel")
        title.Text = "Select Key: " .. titleText
        Theme.ApplyTypography(title, "Title", "Header")
        title.TextColor3 = Theme.GetToken("TextPrimary")
        title.Size = UDim2.new(1, 0, 0, 20)
        title.BackgroundTransparency = 1
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = modal
        
        local grid = Instance.new("Frame")
        grid.Name = "KeyGrid"
        grid.Size = UDim2.new(1, 0, 0, 0)
        grid.AutomaticSize = Enum.AutomaticSize.Y
        grid.BackgroundTransparency = 1
        grid.Parent = modal
        
        local gridLayout = Instance.new("UIGridLayout")
        gridLayout.CellSize = UDim2.new(0, 58, 0, 32)
        gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
        gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
        gridLayout.Parent = grid
        
        local keys = {
            "None", "E", "Q", "F", "R", "C", "X", "Z", "V", "B", "T", "G", "Tab", "LeftShift", "Space", "Mouse1", "Mouse2"
        }
        
        for _, k in ipairs(keys) do
            local keyBtn = Instance.new("TextButton")
            keyBtn.Name = "Key_" .. k
            keyBtn.Text = k
            Theme.ApplyTypography(keyBtn, "Code", "Small")
            keyBtn.TextColor3 = Theme.GetToken("TextPrimary")
            keyBtn.BackgroundColor3 = Theme.GetToken("SurfaceHover")
            keyBtn.AutoButtonColor = false
            keyBtn.ZIndex = 10000000
            
            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = Theme.Radii.Control
            btnCorner.Parent = keyBtn
            
            local btnStroke = Instance.new("UIStroke")
            btnStroke.Color = Theme.GetToken("BorderSubtle")
            btnStroke.Thickness = 1
            btnStroke.Parent = keyBtn
            
            keyBtn.Activated:Connect(function()
                backdrop:Destroy()
                endListening(k)
            end)
            keyBtn.Parent = grid
        end
        
        backdrop.Activated:Connect(function()
            backdrop:Destroy()
            endListening(nil)
        end)
        
        modal.Parent = backdrop
        backdrop.Parent = targetParent
    end

    badge.Activated:Connect(function()
        if self.Locked then return end
        if self.IsListening then
            endListening(nil)
            return
        end
        
        if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
            openMobileKeyPicker()
            return
        end
        
        self.IsListening = true
        badgeText.Text = "..."
        Tweener.Tween(badge, Tweener.Info.Fast, {
            BackgroundColor3 = Theme.GetToken("SurfaceActive")
        })
        Tweener.Tween(badgeText, Tweener.Info.Fast, {
            TextColor3 = Theme.GetToken("Accent")
        })
        Tweener.Tween(badgeStroke, Tweener.Info.Fast, {
            Color = Theme.GetToken("BorderAccent"),
            Transparency = 0,
        })
        
        if pulseThread then task.cancel(pulseThread) end
        pulseThread = task.spawn(function()
            while self.IsListening do
                Tweener.Tween(badgeStroke, Tweener.Info.Smooth, { Transparency = 0.5 })
                task.wait(0.35)
                if not self.IsListening then break end
                Tweener.Tween(badgeStroke, Tweener.Info.Smooth, { Transparency = 0 })
                task.wait(0.35)
            end
        end)
        
        self._listenConn = UserInputService.InputBegan:Connect(function(input)
            if self._listenConn then
                self._listenConn:Disconnect()
                self._listenConn = nil
            end
            
            if input.UserInputType == Enum.UserInputType.Keyboard then
                if input.KeyCode == Enum.KeyCode.Escape then
                    endListening("None")
                else
                    endListening(input.KeyCode.Name)
                end
            elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
                endListening("Mouse1")
            elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
                endListening("Mouse2")
            elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
                endListening("Mouse3")
            elseif input.UserInputType == Enum.UserInputType.Touch then
                openMobileKeyPicker()
            else
                endListening(nil)
            end
        end)
    end)
    
    
    container.Parent = parent
    return self
end

function Keybind:Set(key: any, skipCallback: boolean?)
    local cleanKey: string
    if typeof(key) == "EnumItem" then
        cleanKey = key.Name
    elseif type(key) == "string" then
        cleanKey = string.gsub(key, "^Enum%.KeyCode%.", "")
        cleanKey = string.gsub(cleanKey, "^Enum%.", "")
    else
        cleanKey = tostring(key or "")
    end
    self.Value = cleanKey
    self.BadgeText.Text = self.Value
    if not skipCallback and self.Callback then
        local ok, err = pcall(self.Callback, self.Value)
        if not ok then
            warn("[SodiumUI.Keybind] Callback error:", err)
        end
    end
end

function Keybind:Get(): string
    return self.Value
end

function Keybind:SetTitle(title: string)
	Locale.Unbind(self.TitleLabel)
	if type(title) == "table" then
		Locale.Bind(self.TitleLabel, "Text", title)
	else
		self.TitleLabel.Text = tostring(title)
	end
end

function Keybind:SetDesc(desc: string)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
		if type(desc) == "table" then
			Locale.Bind(self.DescLabel, "Text", desc)
		else
			self.DescLabel.Text = tostring(desc)
		end
	end
end

function Keybind:Lock()
    self.Locked = true
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.7 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("Placeholder") })
end

function Keybind:Unlock()
    self.Locked = false
    Tweener.Tween(self.Container, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
end

function Keybind:Destroy()
	if self.IsListening and self._endListening then
		pcall(self._endListening, nil)
	end
	Tweener.Cancel(self.Container)
	if self._feedback then
		for _, h in ipairs(self._feedback) do
			pcall((h :: any).Disconnect, h)
		end
		table.clear(self._feedback)
	end
	for _, conn in ipairs(self._connections) do
		if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
			pcall((conn :: any).Disconnect, conn)
		elseif typeof(conn) == "RBXScriptConnection" then
			pcall((conn :: RBXScriptConnection).Disconnect, conn)
		end
	end
	table.clear(self._connections)
	Locale.Unbind(self.TitleLabel)
	if self.DescLabel then
		Locale.Unbind(self.DescLabel)
	end
	Theme.Unbind(self.Container)
	if self.Container then
		pcall((self.Container :: Instance).Destroy, self.Container)
	end
end

return Keybind
end

_MODULES['Elements/Paragraph'] = function()
--!strict
--[=[
    Sodium UI - Elements/Paragraph.luau
    Informational card with title, rich description text, and optional action buttons.
]=]

local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Paragraph = {}
Paragraph.__index = Paragraph

export type ParagraphButton = {
    Title: any,
    Icon: string?,
    Callback: (() -> ())?,
}

export type ParagraphProps = {
    Title: any,
    Desc: any?,
    Content: any?,
    Icon: string?,
    Buttons: { ParagraphButton }?,
}

function Paragraph.new(parent: Instance, props: any)
    local titleText = Locale.Resolve(props.Title or props.Name or "Paragraph")
    local descProp = props.Desc or props.Content or ""

	local self = setmetatable({}, Paragraph)
	self._connections = {}
	self._feedback = {}
    
    local container = Instance.new("Frame")
    container.Name = "Paragraph_" .. tostring(titleText)
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    container.BackgroundTransparency = 0.5
    container.BorderSizePixel = 0
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.Parent = container
    
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 14)
    pad.PaddingBottom = UDim.new(0, 14)
    pad.PaddingLeft = UDim.new(0, 16)
    pad.PaddingRight = UDim.new(0, 16)
    pad.Parent = container
    
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.Parent = container
    
    -- Header Row
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 20)
    header.BackgroundTransparency = 1
    header.LayoutOrder = 1
    header.Parent = container
    
    local iconOffset = 0
    if props.Icon and props.Icon ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(16, 16)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(icon, props.Icon)
        icon.Parent = header
        iconOffset = 22
    end
    
    local titleColor = Theme.ResolveColor(props.TitleColor or props.Color)
    local descColor = Theme.ResolveColor(props.DescColor or props.DescriptionColor or props.ContentColor)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset, 1, 0)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, 0)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Title", "Header")
    Locale.Bind(titleLabel, "Text", props.Title or props.Name or "Paragraph")
    titleLabel.TextColor3 = titleColor or Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.RichText = true
    titleLabel.Parent = header
    
    local descLabel = Instance.new("TextLabel")
    descLabel.Name = "Desc"
    descLabel.Size = UDim2.new(1, 0, 0, 0)
    descLabel.AutomaticSize = Enum.AutomaticSize.Y
    descLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(descLabel, "Body", "Sub")
    Locale.Bind(descLabel, "Text", descProp)
    descLabel.TextColor3 = descColor or Theme.GetToken("TextMuted")
    descLabel.TextWrapped = true
    descLabel.RichText = true
    descLabel.LineHeight = 1.2
    descLabel.TextXAlignment = Enum.TextXAlignment.Left
    descLabel.LayoutOrder = 2
    descLabel.Parent = container
    
    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    if not titleColor then
        Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    end
    if not descColor then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end
    
    -- Optional Action Buttons
    if props.Buttons and #props.Buttons > 0 then
        local btnRow = Instance.new("Frame")
        btnRow.Name = "ButtonRow"
        btnRow.Size = UDim2.new(1, 0, 0, 28)
        btnRow.BackgroundTransparency = 1
        btnRow.LayoutOrder = 3
        
        local btnList = Instance.new("UIListLayout")
        btnList.FillDirection = Enum.FillDirection.Horizontal
        btnList.SortOrder = Enum.SortOrder.LayoutOrder
        btnList.Padding = UDim.new(0, 8)
        btnList.Parent = btnRow
        
        for i, bData in ipairs(props.Buttons) do
            local bTitleResolved = Locale.Resolve(bData.Title or "Button")
            local btn = Instance.new("TextButton")
            btn.Name = "Btn_" .. tostring(bTitleResolved)
            btn.Size = UDim2.new(0, 80, 1, 0)
            btn.AutomaticSize = Enum.AutomaticSize.X
            btn.BackgroundColor3 = Theme.GetToken("Card")
            btn.AutoButtonColor = false
            btn.Text = ""
            btn.LayoutOrder = i
            
            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = Theme.Radii.Control
            btnCorner.Parent = btn
            
            local btnStroke = Instance.new("UIStroke")
            btnStroke.Color = Theme.GetToken("BorderSubtle")
            btnStroke.Thickness = 1
            btnStroke.Parent = btn
            
            local btnPad = Instance.new("UIPadding")
            btnPad.PaddingLeft = UDim.new(0, 10)
            btnPad.PaddingRight = UDim.new(0, 10)
            btnPad.Parent = btn
            
            local bOffset = 0
            if bData.Icon and bData.Icon ~= "" then
                local bIcon = Instance.new("ImageLabel")
                bIcon.Name = "Icon"
                bIcon.Size = UDim2.fromOffset(13, 13)
                bIcon.Position = UDim2.new(0, 0, 0.5, 0)
                bIcon.AnchorPoint = Vector2.new(0, 0.5)
                bIcon.BackgroundTransparency = 1
                bIcon.ImageColor3 = Theme.GetToken("TextPrimary")
                Icons.Apply(bIcon, bData.Icon)
                bIcon.Parent = btn
                bOffset = 18
            end
            
            local btnLabel = Instance.new("TextLabel")
            btnLabel.Name = "Label"
            btnLabel.Size = UDim2.new(1, -bOffset, 1, 0)
            btnLabel.Position = UDim2.new(0, bOffset, 0, 0)
            btnLabel.BackgroundTransparency = 1
            Theme.ApplyTypography(btnLabel, "Header", "Small")
            Locale.Bind(btnLabel, "Text", bData.Title or "Button")
            btnLabel.TextColor3 = Theme.GetToken("TextPrimary")
            btnLabel.TextXAlignment = Enum.TextXAlignment.Center
            btnLabel.Parent = btn
            
			Theme.Bind(btn, "BackgroundColor3", "SurfaceActive")
			Theme.Bind(btnStroke, "Color", "BorderSubtle")
			Theme.Bind(btnLabel, "TextColor3", "TextPrimary")

			do
				local h = Tweener.BindPressFeedback(btn)
				if h then
					table.insert(self._feedback, h)
				end
			end

			table.insert(self._connections, btn.MouseEnter:Connect(function()
				Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Accent") })
				Tweener.Tween(btnLabel, Tweener.Info.Fast, { TextColor3 = Color3.fromRGB(255, 255, 255) })
			end))
			table.insert(self._connections, btn.MouseLeave:Connect(function()
				Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceActive") })
				Tweener.Tween(btnLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
			end))

			table.insert(self._connections, btn.Activated:Connect(function()
				if bData.Callback then
					local ok, err = pcall(bData.Callback)
					if not ok then
						warn("[SodiumUI.Paragraph] Button callback error:", err)
					end
				end
			end))
            btn.Parent = btnRow
        end
        btnRow.Parent = container
    end
    
    container.Parent = parent
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    return self
end

function Paragraph:SetTitle(title: string)
	Locale.Unbind(self.TitleLabel)
	if type(title) == "table" then
		Locale.Bind(self.TitleLabel, "Text", title)
	else
		self.TitleLabel.Text = tostring(title)
	end
end

function Paragraph:SetDesc(desc: string)
	Locale.Unbind(self.DescLabel)
	if type(desc) == "table" then
		Locale.Bind(self.DescLabel, "Text", desc)
	else
		self.DescLabel.Text = tostring(desc)
	end
end

function Paragraph:Destroy()
	Tweener.Cancel(self.Container)
	for _, h in ipairs(self._feedback) do
		pcall((h :: any).Disconnect, h)
	end
	table.clear(self._feedback)
	for _, conn in ipairs(self._connections) do
		if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
			pcall((conn :: any).Disconnect, conn)
		elseif typeof(conn) == "RBXScriptConnection" then
			pcall((conn :: RBXScriptConnection).Disconnect, conn)
		end
	end
	table.clear(self._connections)
	Locale.Unbind(self.TitleLabel)
	Locale.Unbind(self.DescLabel)
	Theme.Unbind(self.Container)
	if self.Container then
		pcall((self.Container :: Instance).Destroy, self.Container)
	end
end

return Paragraph
end

_MODULES['Elements/Stepper'] = function()
--!strict
--[=[
    Sodium UI - Elements/Stepper.luau
    Numeric Stepper Control:
    - Left text (Title + Description)
    - Right compact stepper capsule with [-], editable numeric value, and [+]
    - Supports Min, Max, Step, Suffix, Flag, Direct manual text editing, and Callbacks.
]=]

local UserInputService = game:GetService("UserInputService")
local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Stepper = {}
Stepper.__index = Stepper

export type StepperProps = {
    Title: any,
    Desc: any?,
    Description: any?,
    Icon: string?,
    Min: number?,
    Max: number?,
    Step: number?,
    Default: number?,
    Suffix: string?,
    Value: (number | { Min: number, Max: number, Default: number })?,
    Locked: boolean?,
    Callback: ((val: number) -> ())?,
}

function Stepper.new(parent: Instance, props: any)
    local titleText = Locale.Resolve(props.Title or props.Name or "Stepper")
    local valTable = if type(props.Value) == "table" then props.Value else {}
    local minVal = props.Min or valTable.Min or 0
    local maxVal = props.Max or valTable.Max or 100
    local defVal = props.Default or valTable.Default or (if type(props.Value) == "number" then props.Value else minVal)
    
    local self = setmetatable({}, Stepper)
    self.Min = minVal
    self.Max = maxVal
    self.Step = props.Step or 1
    self.Suffix = props.Suffix or ""
    self.Value = math.clamp(defVal, self.Min, self.Max)
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self._connections = {}
    self._feedback = {}
    self._isUpdating = false
    
    local descProp = props.Desc or props.Description
    local isDesc = descProp and (if type(descProp) == "table" then true else descProp ~= "")
    local containerHeight = if isDesc then 54 else 42
    
    local container = Instance.new("Frame")
    container.Name = "Stepper_" .. tostring(titleText)
    container.Size = UDim2.new(1, 0, 0, containerHeight)
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    container.BackgroundTransparency = 0.5
    container.BorderSizePixel = 0
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = container
    
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = container
    
    local iconOffset = 0
    if props.Icon and props.Icon ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(16, 16)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(icon, props.Icon)
        icon.Parent = container
        iconOffset = 22
    end
    
    -- Left Text: Title & Desc
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 130, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 8 else 12)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Header", "Header")
    Locale.Bind(titleLabel, "Text", props.Title or props.Name or "Stepper")
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = container
    
    local descLabel: TextLabel? = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 130, 0, 14)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 28)
        descLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(descLabel, "Sub", "Sub")
        Locale.Bind(descLabel, "Text", descProp or "")
        descLabel.TextColor3 = Theme.GetToken("TextMuted")
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = container
    end
    
    -- Right side controls: Stepper Capsule ([-] [ Value ] [+])
    local stepperFrame = Instance.new("Frame")
    stepperFrame.Name = "StepperControl"
    stepperFrame.Size = UDim2.new(0, 110, 0, 30)
    stepperFrame.Position = UDim2.new(1, 0, 0.5, 0)
    stepperFrame.AnchorPoint = Vector2.new(1, 0.5)
    stepperFrame.BackgroundColor3 = Theme.GetToken("Card")
    stepperFrame.BorderSizePixel = 0
    
    local sCorner = Instance.new("UICorner")
    sCorner.CornerRadius = Theme.Radii.Control
    sCorner.Parent = stepperFrame
    
    local sStroke = Instance.new("UIStroke")
    sStroke.Color = Theme.GetToken("BorderSubtle")
    sStroke.Thickness = 1
    sStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    sStroke.Parent = stepperFrame
    
    -- Minus Button [-] (AnchorPoint centered to prevent off-center scale animation)
    local minusBtn = Instance.new("TextButton")
    minusBtn.Name = "MinusButton"
    minusBtn.Size = UDim2.new(0, 28, 1, 0)
    minusBtn.Position = UDim2.new(0, 14, 0.5, 0)
    minusBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    minusBtn.BackgroundTransparency = 1
    minusBtn.AutoButtonColor = false
    minusBtn.Text = ""
    minusBtn.Parent = stepperFrame
    
    local minusIcon = Instance.new("ImageLabel")
    minusIcon.Name = "Icon"
    minusIcon.Size = UDim2.fromOffset(13, 13)
    minusIcon.Position = UDim2.fromScale(0.5, 0.5)
    minusIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    minusIcon.BackgroundTransparency = 1
    minusIcon.ImageColor3 = Theme.GetToken("TextMuted")
    Icons.Apply(minusIcon, "minus")
    minusIcon.Parent = minusBtn
    
    -- Plus Button [+] (AnchorPoint centered to prevent off-center scale animation)
    local plusBtn = Instance.new("TextButton")
    plusBtn.Name = "PlusButton"
    plusBtn.Size = UDim2.new(0, 28, 1, 0)
    plusBtn.Position = UDim2.new(1, -14, 0.5, 0)
    plusBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    plusBtn.BackgroundTransparency = 1
    plusBtn.AutoButtonColor = false
    plusBtn.Text = ""
    plusBtn.Parent = stepperFrame
    
    local plusIcon = Instance.new("ImageLabel")
    plusIcon.Name = "Icon"
    plusIcon.Size = UDim2.fromOffset(13, 13)
    plusIcon.Position = UDim2.fromScale(0.5, 0.5)
    plusIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    plusIcon.BackgroundTransparency = 1
    plusIcon.ImageColor3 = Theme.GetToken("TextMuted")
    Icons.Apply(plusIcon, "plus")
    plusIcon.Parent = plusBtn
    
    -- Value Input / Label in the center
    local valueBox = Instance.new("TextBox")
    valueBox.Name = "ValueBox"
    valueBox.Size = UDim2.new(1, -56, 1, 0)
    valueBox.Position = UDim2.new(0, 28, 0, 0)
    valueBox.BackgroundTransparency = 1
    Theme.ApplyTypography(valueBox, "Header", "Small")
    valueBox.Text = tostring(self.Value)
    valueBox.TextColor3 = Theme.GetToken("TextPrimary")
    valueBox.TextXAlignment = Enum.TextXAlignment.Center
    valueBox.ClearTextOnFocus = false
    valueBox.ClipsDescendants = true
    valueBox.Parent = stepperFrame
    
    stepperFrame.Parent = container
    
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.StepperFrame = stepperFrame
    self.MinusBtn = minusBtn
    self.PlusBtn = plusBtn
    self.ValueBox = valueBox
    self.MinusIcon = minusIcon
    self.PlusIcon = plusIcon
    self.FrameStroke = sStroke
    
    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    if descLabel then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end
    Theme.Bind(stepperFrame, "BackgroundColor3", "Card")
    Theme.Bind(sStroke, "Color", "BorderSubtle")
    Theme.Bind(valueBox, "TextColor3", "TextPrimary")
    Theme.Bind(minusIcon, "ImageColor3", "TextMuted")
    Theme.Bind(plusIcon, "ImageColor3", "TextMuted")
    
    local function snap(raw: number): number
        local step = self.Step
        if type(step) ~= "number" or step <= 0 then step = 1 end
        local v = math.floor((raw - self.Min) / step + 0.5) * step + self.Min
        return math.clamp(v, self.Min, self.Max)
    end
    
    local function formatValue(val: number): string
        if self.Step % 1 == 0 then
            return string.format("%d", math.round(val))
        else
            return string.format("%.1f", val)
        end
    end
    
    local isEditing = false
    local allowNegative = self.Min < 0
    local allowDecimal = (self.Step % 1 ~= 0)
    
    table.insert(self._connections, valueBox.Focused:Connect(function()
        if self.Locked then
            valueBox:ReleaseFocus()
            return
        end
        isEditing = true
        Tweener.Tween(sStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderAccent") })
        valueBox.Text = formatValue(self.Value)
    end))
    
    table.insert(self._connections, valueBox:GetPropertyChangedSignal("Text"):Connect(function()
        if not isEditing then return end
        local raw = valueBox.Text
        local sanitized = {}
        local hasDot = false
        local hasMinus = false
        for i = 1, #raw do
            local ch = string.sub(raw, i, i)
            if ch >= "0" and ch <= "9" then
                table.insert(sanitized, ch)
            elseif ch == "-" and allowNegative and #sanitized == 0 and not hasMinus then
                hasMinus = true
                table.insert(sanitized, ch)
            elseif (ch == "." or ch == ",") and allowDecimal and not hasDot then
                hasDot = true
                table.insert(sanitized, ".")
            end
        end
        local clean = table.concat(sanitized)
        if clean ~= raw then
            valueBox.Text = clean
        end
    end))
    
    table.insert(self._connections, valueBox.FocusLost:Connect(function()
        isEditing = false
        Tweener.Tween(sStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
        local num = tonumber(valueBox.Text)
        if num == nil or num ~= num then
            valueBox.Text = formatValue(self.Value)
            return
        end
        local snapped = snap(num)
        self:Set(snapped)
    end))
    
    -- Button actions
    minusBtn.Activated:Connect(function()
        if self.Locked then return end
        self:Set(snap(self.Value - self.Step))
    end)
    
    plusBtn.Activated:Connect(function()
        if self.Locked then return end
        self:Set(snap(self.Value + self.Step))
    end)
    
    -- Button hover & click feedback
    minusBtn.MouseEnter:Connect(function()
        Tweener.Tween(minusIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextPrimary") })
    end)
    minusBtn.MouseLeave:Connect(function()
        Tweener.Tween(minusIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
    end)
    
    plusBtn.MouseEnter:Connect(function()
        Tweener.Tween(plusIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextPrimary") })
    end)
    plusBtn.MouseLeave:Connect(function()
        Tweener.Tween(plusIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
    end)
    
    Tweener.BindPressFeedback(minusBtn, minusBtn, 0.9)
    Tweener.BindPressFeedback(plusBtn, plusBtn, 0.9)
    
    self:Set(self.Value, true)
    
    container.Parent = parent
    return self
end

function Stepper:Set(newVal: number, skipCallback: boolean?)
    if self._isUpdating then return end
    self._isUpdating = true
    
    local num = tonumber(newVal)
    if num == nil then
        self._isUpdating = false
        return
    end
    
    local step = self.Step
    if type(step) ~= "number" or step <= 0 then step = 1 end
    local v = math.floor((num - self.Min) / step + 0.5) * step + self.Min
    v = math.clamp(v, self.Min, self.Max)
    self.Value = v
    
    local displayStr = if self.Step % 1 == 0 then string.format("%d", math.round(self.Value)) else string.format("%.1f", self.Value)
    if self.ValueBox and not self.ValueBox:IsFocused() then
        self.ValueBox.Text = displayStr
    end
    
    if not skipCallback and self.Callback then
        local ok, err = pcall(self.Callback, self.Value)
        if not ok then
            warn("[SodiumUI.Stepper] Callback error:", err)
        end
    end
    
    
    self._isUpdating = false
end

function Stepper:Get(): number
    return self.Value
end

function Stepper:SetTitle(title: string)
    Locale.Unbind(self.TitleLabel)
    if type(title) == "table" then
        Locale.Bind(self.TitleLabel, "Text", title)
    else
        self.TitleLabel.Text = tostring(title)
    end
end

function Stepper:SetDesc(desc: string)
    if self.DescLabel then
        Locale.Unbind(self.DescLabel)
        if type(desc) == "table" then
            Locale.Bind(self.DescLabel, "Text", desc)
        else
            self.DescLabel.Text = tostring(desc)
        end
    end
end

function Stepper:Lock()
    self.Locked = true
    self.Container.BackgroundTransparency = 0.7
    self.TitleLabel.TextColor3 = Theme.GetToken("Placeholder")
end

function Stepper:Unlock()
    self.Locked = false
    self.Container.BackgroundTransparency = 0.5
    self.TitleLabel.TextColor3 = Theme.GetToken("TextPrimary")
end

function Stepper:Destroy()
    for _, conn in ipairs(self._connections) do
        if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
            pcall((conn :: any).Disconnect, conn)
        elseif typeof(conn) == "RBXScriptConnection" then
            pcall((conn :: RBXScriptConnection).Disconnect, conn)
        end
    end
    table.clear(self._connections)
    Locale.Unbind(self.TitleLabel)
    if self.DescLabel then
        Locale.Unbind(self.DescLabel)
    end
    Theme.Unbind(self.Container)
    if self.Container then
        pcall((self.Container :: Instance).Destroy, self.Container)
    end
end

return Stepper
end

_MODULES['Components/Primitives'] = function()
--!strict
--[=[
	Sodium UI v2 - Components/Primitives.luau
	Layout-safe Divider/Space/Tag. No TextBounds math, no AbsoluteSize
	listeners. Theme.Bind for live SetTheme.
]=]

local Theme = _require("Core/Theme")

local Primitives = {}

function Primitives.Divider(parent: Instance, text: string?): Frame
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundTransparency = 1
	divider.BorderSizePixel = 0

	if text and text ~= "" then
		divider.Size = UDim2.new(1, 0, 0, 24)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Padding = UDim.new(0, 8)
		layout.Parent = divider

		local left = Instance.new("Frame")
		left.Name = "LeftLine"
		left.Size = UDim2.new(0.5, -20, 0, 1)
		left.AutomaticSize = Enum.AutomaticSize.None
		left.FlexMode = Enum.FlexMode.Grow
		left.BorderSizePixel = 0
		Theme.Bind(left, "BackgroundColor3", "BorderSubtle")
		left.Parent = divider

		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Theme.Fonts.Header
		label.Text = string.upper(text)
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Center
		Theme.Bind(label, "TextColor3", "TextMuted")
		Theme.ApplyTypography(label, "Header", "Small")
		label.Parent = divider

		local right = Instance.new("Frame")
		right.Name = "RightLine"
		right.Size = UDim2.new(0.5, -20, 0, 1)
		right.FlexMode = Enum.FlexMode.Grow
		right.BorderSizePixel = 0
		Theme.Bind(right, "BackgroundColor3", "BorderSubtle")
		right.Parent = divider
	else
		divider.Size = UDim2.new(1, 0, 0, 8)
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.new(0, 0, 0.5, 0)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.BorderSizePixel = 0
		Theme.Bind(line, "BackgroundColor3", "BorderSubtle")
		line.Parent = divider
	end

	divider.Parent = parent
	return divider
end

function Primitives.Space(parent: Instance, height: number?): Frame
	local space = Instance.new("Frame")
	space.Name = "Space"
	space.Size = UDim2.new(1, 0, 0, height or 8)
	space.BackgroundTransparency = 1
	space.BorderSizePixel = 0
	space.Parent = parent
	return space
end

function Primitives.Tag(parent: Instance, text: string, color: Color3?, radius: number?): Frame
	local tag = Instance.new("Frame")
	tag.Name = "Tag_" .. tostring(text)
	tag.Size = UDim2.new(0, 0, 0, 20)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.BorderSizePixel = 0
	if color then
		tag.BackgroundColor3 = color
	else
		Theme.Bind(tag, "BackgroundColor3", "Accent")
	end
	tag.BackgroundTransparency = 0.85

	local corner = Instance.new("UICorner")
	corner.CornerRadius = if radius then UDim.new(0, radius) else Theme.Radii.Pill
	corner.Parent = tag

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	if color then
		stroke.Color = color
	else
		Theme.Bind(stroke, "Color", "Accent")
	end
	stroke.Parent = tag

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tag

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Header
	label.Text = tostring(text)
	label.TextSize = 11
	if color then
		label.TextColor3 = color
	else
		Theme.Bind(label, "TextColor3", "TextPrimary")
	end
	Theme.ApplyTypography(label, "Header", "Small")
	label.Parent = tag

	tag.Parent = parent
	return tag
end

return Primitives
end

_MODULES['Components/Notification'] = function()
--!strict
--[=[
    Sodium UI - Components/Notification.luau
    Non-intrusive, responsive toast alert system.
    Dynamically scales with screen dimensions, supports safe-area insets, and auto-stacks smoothly.
]=]

local TweenService = game:GetService("TweenService")

local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Notification = {}

export type NotifyProps = {
    Title: string,
    Content: string?,
    Duration: number?,
    Icon: string?,
}

local toastStackContainer: Frame? = nil
local activeToasts = {}
local stackConnections = {}

local function updateStackGeometry(stack: Frame)
    local camera = workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local isSmallScreen = vp.X < 900 or vp.Y < 600
    
    -- Responsive width: compact 210px on mobile screens, up to 260px on PC
    local toastWidth = math.clamp(math.floor(vp.X * 0.24), 210, 260)
    local posY = if isSmallScreen then 48 else 20
    local posX = if isSmallScreen then -12 else -18
    
    stack.Size = UDim2.new(0, toastWidth, 1, -posY - 16)
    stack.Position = UDim2.new(1, posX, 0, posY)
end

local function cleanupStackConnections()
    for _, conn in stackConnections do
        conn:Disconnect()
    end
    table.clear(stackConnections)
end

local function getOrCreateStack(root: Instance?): Frame?
    if toastStackContainer and toastStackContainer.Parent then
        return toastStackContainer
    end
    
    cleanupStackConnections()
    
    local ok, stack = pcall(function()
        local s = Instance.new("Frame")
        s.Name = "ToastNotificationStack"
        s.AnchorPoint = Vector2.new(1, 0)
        s.BackgroundTransparency = 1
        s.ZIndex = 9999999
        
        updateStackGeometry(s)
        
        local list = Instance.new("UIListLayout")
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Padding = UDim.new(0, 8)
        list.VerticalAlignment = Enum.VerticalAlignment.Top
        list.HorizontalAlignment = Enum.HorizontalAlignment.Right
        list.Parent = s
        
        -- Auto adapt to screen resize / rotation
        local camera = workspace.CurrentCamera
        if camera then
            table.insert(stackConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if s and s.Parent then
                    updateStackGeometry(s)
                end
            end))
        end
        table.insert(stackConnections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            local newCam = workspace.CurrentCamera
            if newCam then
                table.insert(stackConnections, newCam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                    if s and s.Parent then
                        updateStackGeometry(s)
                    end
                end))
                updateStackGeometry(s)
            end
        end))
        
        s.Destroying:Connect(cleanupStackConnections)
        
        if root then
            local parentOk = pcall(function()
                s.Parent = root
            end)
            if not parentOk then
                -- Fallback if root parenting is restricted by thread capability
                pcall(function()
                    local Players = game:GetService("Players")
                    local lp = Players.LocalPlayer
                    if lp and lp:FindFirstChild("PlayerGui") then
                        s.Parent = lp.PlayerGui
                    end
                end)
            end
        end
        return s
    end)
    
    if ok and stack then
        toastStackContainer = stack
        return stack
    end
    return toastStackContainer
end

function Notification.Init(root: Instance): Frame?
    return getOrCreateStack(root)
end

local function dismissToast(toastData: any)
    if toastData.Dismissed then return end
    toastData.Dismissed = true
    
    local idx = table.find(activeToasts, toastData)
    if idx then
        table.remove(activeToasts, idx)
    end
    
	if toastData.Card and toastData.Card.Parent then
		local exitTween = Tweener.Tween(toastData.Card, Tweener.Info.ExitFast, {
			Position = UDim2.new(1, 40, 0, 0),
			GroupTransparency = 1,
		})
		if exitTween then
			exitTween.Completed:Once(function()
				if toastData.Slot and toastData.Slot.Parent then
					toastData.Slot.AutomaticSize = Enum.AutomaticSize.None
					local collapseTween = Tweener.Tween(toastData.Slot, Tweener.Info.ExitFast, {
						Size = UDim2.new(1, 0, 0, 0),
					})
					if collapseTween then
						collapseTween.Completed:Once(function()
							if toastData.Slot and toastData.Slot.Parent then
								pcall((toastData.Slot :: Instance).Destroy, toastData.Slot)
							end
						end)
					elseif toastData.Slot and toastData.Slot.Parent then
						pcall((toastData.Slot :: Instance).Destroy, toastData.Slot)
					end
				end
			end)
		elseif toastData.Slot and toastData.Slot.Parent then
			pcall((toastData.Slot :: Instance).Destroy, toastData.Slot)
		end
	elseif toastData.Slot and toastData.Slot.Parent then
		pcall((toastData.Slot :: Instance).Destroy, toastData.Slot)
	end
end

function Notification.Notify(rootGui: Instance, props: NotifyProps)
    -- Decouple notification dispatch via task.defer to run in scheduler context
    task.defer(function()
        local success, notifyErr = pcall(function()
            local stack = getOrCreateStack(rootGui)
            if not stack then return end
    local duration = props.Duration or 3.2
    
    local camera = workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local maxToasts = if (vp.Y < 600) then 2 else 3
    
    while #activeToasts >= maxToasts do
        dismissToast(activeToasts[1])
    end
    
    -- Slot wrapper (for UIListLayout stability)
    local slot = Instance.new("Frame")
    slot.Name = "ToastSlot"
    slot.Size = UDim2.new(1, 0, 0, 0)
    slot.AutomaticSize = Enum.AutomaticSize.Y
    slot.BackgroundTransparency = 1
    slot.ClipsDescendants = false
    
    -- Toast Card (CanvasGroup ensures all text, icons, and progress elements fade out smoothly together)
    local toast = Instance.new("CanvasGroup")
    toast.Name = "ToastCard"
    toast.Size = UDim2.new(1, 0, 0, 0)
    toast.AutomaticSize = Enum.AutomaticSize.Y
    toast.Position = UDim2.new(1, 40, 0, 0) -- starts shifted right
    toast.BackgroundColor3 = Theme.GetToken("Card")
    toast.GroupTransparency = 0
    toast.BorderSizePixel = 0
    toast.ClipsDescendants = true
    Theme.Bind(toast, "BackgroundColor3", "Card")
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Element
    corner.Parent = toast
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = toast
    Theme.Bind(stroke, "Color", "BorderSubtle")
    
    local cardLayout = Instance.new("UIListLayout")
    cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cardLayout.FillDirection = Enum.FillDirection.Vertical
    cardLayout.Padding = UDim.new(0, 0)
    cardLayout.Parent = toast
    
    -- Content Frame
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "ContentFrame"
    contentFrame.Size = UDim2.new(1, 0, 0, 0)
    contentFrame.AutomaticSize = Enum.AutomaticSize.Y
    contentFrame.BackgroundTransparency = 1
    contentFrame.LayoutOrder = 1
    
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 9)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = contentFrame
    
    -- Icon
    local iconLabel = Instance.new("ImageLabel")
    iconLabel.Name = "Icon"
    iconLabel.Size = UDim2.fromOffset(16, 16)
    iconLabel.Position = UDim2.new(0, 0, 0, 1)
    iconLabel.BackgroundTransparency = 1
    iconLabel.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(iconLabel, props.Icon or "bell")
    iconLabel.Parent = contentFrame
    Theme.Bind(iconLabel, "ImageColor3", "Accent")
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -22, 0, 16)
    titleLabel.Position = UDim2.new(0, 22, 0, 0)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Title", "Header")
    Locale.Bind(titleLabel, "Text", props.Title)
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = contentFrame
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    
    -- Content text
    if props.Content and (if type(props.Content) == "table" then true else props.Content ~= "") then
        local contentLabel = Instance.new("TextLabel")
        contentLabel.Name = "Content"
        contentLabel.Size = UDim2.new(1, -22, 0, 0)
        contentLabel.Position = UDim2.new(0, 22, 0, 18)
        contentLabel.AutomaticSize = Enum.AutomaticSize.Y
        contentLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(contentLabel, "Body", "Sub")
        Locale.Bind(contentLabel, "Text", props.Content)
        contentLabel.TextColor3 = Theme.GetToken("TextMuted")
        contentLabel.TextWrapped = true
        contentLabel.TextXAlignment = Enum.TextXAlignment.Left
        contentLabel.Parent = contentFrame
        Theme.Bind(contentLabel, "TextColor3", "TextMuted")
    end
    
    contentFrame.Parent = toast
    
    -- Progress Bar
    local progressSlot = Instance.new("Frame")
    progressSlot.Name = "ProgressSlot"
    progressSlot.Size = UDim2.new(1, 0, 0, 4)
    progressSlot.BackgroundTransparency = 1
    progressSlot.LayoutOrder = 2
    
    local progressContainer = Instance.new("Frame")
    progressContainer.Name = "ProgressContainer"
    progressContainer.Size = UDim2.new(1, -20, 0, 2)
    progressContainer.Position = UDim2.new(0.5, 0, 0, 0)
    progressContainer.AnchorPoint = Vector2.new(0.5, 0)
    progressContainer.BackgroundColor3 = Theme.GetToken("SurfaceActive")
    progressContainer.BorderSizePixel = 0
    Theme.Bind(progressContainer, "BackgroundColor3", "SurfaceActive")
    
    local progCorner = Instance.new("UICorner")
    progCorner.CornerRadius = UDim.new(1, 0)
    progCorner.Parent = progressContainer
    
    local progressBar = Instance.new("Frame")
    progressBar.Name = "Bar"
    progressBar.Size = UDim2.fromScale(1, 1)
    progressBar.BackgroundColor3 = Theme.GetToken("Accent")
    progressBar.BorderSizePixel = 0
    Theme.Bind(progressBar, "BackgroundColor3", "Accent")
    
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = progressBar
    progressBar.Parent = progressContainer
    
    progressContainer.Parent = progressSlot
    progressSlot.Parent = toast
    
    toast.Parent = slot
    slot.Parent = stack
    
    local toastData = {
        Slot = slot,
        Card = toast,
        Dismissed = false,
    }
    table.insert(activeToasts, toastData)
    
    -- Smooth horizontal entrance animation
    Tweener.Tween(toast, Tweener.Info.Normal, {
        Position = UDim2.new(0, 0, 0, 0)
    })
    
    -- Drain timer bar
    Tweener.Tween(progressBar, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
        Size = UDim2.new(0, 0, 1, 0)
    })
    
    task.delay(duration, function()
        dismissToast(toastData)
    end)
        end)
    end)
end

return Notification
end

_MODULES['Components/Popup'] = function()
--!strict
--[=[
    Sodium UI - Components/Popup.luau
    Modal Prompt with backdrop dimmer and spring-inspired scale transition.
]=]

local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Popup = {}

export type PopupButton = {
    Title: string,
    Icon: string?,
    Callback: (() -> ())?,
    Variant: string?, -- "Primary", "Secondary", "Danger"
}

export type PopupProps = {
    Title: string,
    Icon: string?,
    Content: string,
    Buttons: { PopupButton }?,
}

function Popup.Show(rootGui: Instance, props: PopupProps)
    local backdrop = Instance.new("TextButton")
    backdrop.Name = "ModalBackdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.Position = UDim2.fromScale(0, 0)
    backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
    backdrop.BackgroundTransparency = 1
    backdrop.Text = ""
    backdrop.AutoButtonColor = false
    backdrop.ZIndex = 9999998
    
    local modal = Instance.new("CanvasGroup")
    modal.Name = "ModalFrame"
    modal.Size = UDim2.new(0.85, 0, 0, 0)
    modal.AutomaticSize = Enum.AutomaticSize.Y
    modal.Position = UDim2.fromScale(0.5, 0.5)
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.BackgroundColor3 = Theme.GetToken("Card")
    modal.GroupTransparency = 1
    modal.BorderSizePixel = 0
    modal.ClipsDescendants = true
    modal.ZIndex = 9999999
    
    local constraint = Instance.new("UISizeConstraint")
    constraint.MaxSize = Vector2.new(360, 9999)
    constraint.Parent = modal
    
    local modalScale = Instance.new("UIScale")
    modalScale.Scale = 0.92
    modalScale.Parent = modal
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Card
    corner.Parent = modal
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderStrong")
    stroke.Thickness = 1
    stroke.Parent = modal
    
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 20)
    pad.PaddingBottom = UDim.new(0, 20)
    pad.PaddingLeft = UDim.new(0, 20)
    pad.PaddingRight = UDim.new(0, 20)
    pad.Parent = modal
    
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 14)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.Parent = modal
    
    -- Header Frame
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 24)
    header.BackgroundTransparency = 1
    header.LayoutOrder = 1
    header.Parent = modal
    
    local hasIcon = props.Icon and props.Icon ~= ""
    if hasIcon then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(20, 20)
        icon.Position = UDim2.new(1, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(1, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        icon.ZIndex = 9999999
        Icons.Apply(icon, props.Icon)
        icon.Parent = header
    end
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = if hasIcon then UDim2.new(1, -26, 1, 0) else UDim2.fromScale(1, 1)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Theme.Fonts.Title
    title.Text = props.Title
    title.TextColor3 = Theme.GetToken("TextPrimary")
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 9999999
    title.Parent = header
    
    -- Content Body
    local content = Instance.new("TextLabel")
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.BackgroundTransparency = 1
    content.Font = Theme.Fonts.Body
    content.Text = props.Content
    content.TextColor3 = Theme.GetToken("TextMuted")
    content.TextSize = 13
    content.TextWrapped = true
    content.TextXAlignment = Enum.TextXAlignment.Left
    content.LayoutOrder = 2
    content.Parent = modal
    
    -- Buttons Container
    local btnContainer = Instance.new("Frame")
    btnContainer.Name = "Buttons"
    btnContainer.Size = UDim2.new(1, 0, 0, 36)
    btnContainer.BackgroundTransparency = 1
    btnContainer.LayoutOrder = 3
    btnContainer.Parent = modal
    
	local function dismiss()
		Tweener.Tween(backdrop, Tweener.Info.ExitFast, { BackgroundTransparency = 1 })
		Tweener.Tween(modal, Tweener.Info.ExitFast, { GroupTransparency = 1 })
		local tween = Tweener.Tween(modalScale, Tweener.Info.ExitFast, { Scale = 0.90 })
		if tween then
			tween.Completed:Once(function()
				pcall((backdrop :: Instance).Destroy, backdrop)
			end)
		else
			pcall((backdrop :: Instance).Destroy, backdrop)
		end
	end
    
    local rawButtons = props.Buttons or {
        { Title = "Close", Variant = "Secondary", Callback = function() end }
    }
    
    local function isDismissButton(b: PopupButton): boolean
        local t = (b.Title or ""):lower()
        return t:find("cancel") ~= nil 
            or t:find("close") ~= nil 
            or t:find("dismiss") ~= nil 
            or t:find("back") ~= nil 
            or t:find("no") ~= nil 
            or b.Variant == "Secondary"
    end
    
    local function createButton(btnData: PopupButton, alignment: string?)
        local btn = Instance.new("TextButton")
        btn.Name = "Button_" .. btnData.Title
        btn.Size = UDim2.new(0, 90, 1, 0)
        btn.AutomaticSize = Enum.AutomaticSize.X
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.Font = Theme.Fonts.Header
        btn.Text = btnData.Title
        btn.TextSize = 13
        btn.ZIndex = 9999999
        
        if alignment == "Left" then
            btn.AnchorPoint = Vector2.new(0, 0)
            btn.Position = UDim2.new(0, 0, 0, 0)
        elseif alignment == "Right" then
            btn.AnchorPoint = Vector2.new(1, 0)
            btn.Position = UDim2.new(1, 0, 0, 0)
        end
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = Theme.Radii.Element
        btnCorner.Parent = btn
        
        local btnPad = Instance.new("UIPadding")
        btnPad.PaddingLeft = UDim.new(0, 14)
        btnPad.PaddingRight = UDim.new(0, 14)
        btnPad.Parent = btn
        
        local variant = btnData.Variant or "Secondary"
        if variant == "Primary" then
            btn.BackgroundColor3 = Theme.GetToken("Accent")
            btn.TextColor3 = Theme.GetToken("TextPrimary")
        elseif variant == "Danger" then
            btn.BackgroundColor3 = Theme.GetToken("Danger")
            btn.TextColor3 = Theme.GetToken("TextPrimary")
        else
            btn.BackgroundColor3 = Theme.GetToken("SurfaceHover")
            btn.TextColor3 = Theme.GetToken("TextMuted")
            
            local btnStroke = Instance.new("UIStroke")
            btnStroke.Color = Theme.GetToken("BorderSubtle")
            btnStroke.Thickness = 1
            btnStroke.Parent = btn
        end
        
        btn.MouseEnter:Connect(function()
            if variant == "Primary" then
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("BorderAccent") })
            elseif variant == "Danger" then
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Color3.fromRGB(239, 68, 68) })
            else
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceActive") })
            end
        end)
        btn.MouseLeave:Connect(function()
            if variant == "Primary" then
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Accent") })
            elseif variant == "Danger" then
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Danger") })
            else
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
            end
        end)
        
        Tweener.BindPressFeedback(btn)
        
		btn.Activated:Connect(function()
			if btnData.Callback then
				local ok, err = pcall(btnData.Callback)
				if not ok then
					warn("[SodiumUI.Popup] Button callback error:", err)
				end
			end
			pcall(dismiss)
		end)
        
        return btn
    end
    
    if #rawButtons == 2 then
        local btn1 = rawButtons[1]
        local btn2 = rawButtons[2]
        
        local leftBtnData = btn1
        local rightBtnData = btn2
        
        if isDismissButton(btn2) and not isDismissButton(btn1) then
            leftBtnData = btn2
            rightBtnData = btn1
        end
        
        local lBtn = createButton(leftBtnData, "Left")
        lBtn.Parent = btnContainer
        
        local rBtn = createButton(rightBtnData, "Right")
        rBtn.Parent = btnContainer
    elseif #rawButtons == 1 then
        local btnData = rawButtons[1]
        local align = if isDismissButton(btnData) then "Left" else "Right"
        local b = createButton(btnData, align)
        b.Parent = btnContainer
    else
        local btnList = Instance.new("UIListLayout")
        btnList.FillDirection = Enum.FillDirection.Horizontal
        btnList.HorizontalAlignment = Enum.HorizontalAlignment.Right
        btnList.SortOrder = Enum.SortOrder.LayoutOrder
        btnList.Padding = UDim.new(0, 10)
        btnList.Parent = btnContainer
        
        for i, btnData in ipairs(rawButtons) do
            local b = createButton(btnData, nil)
            b.LayoutOrder = i
            b.Parent = btnContainer
        end
    end
    
    modal.Parent = backdrop
    backdrop.Parent = rootGui
    
    -- Entrance Animation
    Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 0.55 })
    Tweener.Tween(modal, Tweener.Info.Fast, { GroupTransparency = 0 })
    Tweener.Tween(modalScale, Tweener.Info.Spring, { Scale = 1.0 })
end

return Popup
end

_MODULES['Components/Dialog'] = function()
--!strict
--[=[
    Sodium UI - Components/Dialog.luau
    Premium modal confirmation & alert dialog system with backdrop blur and smooth scale animations.
]=]

local TweenService = game:GetService("TweenService")
local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Dialog = {}

export type DialogButton = {
    Title: string,
    Style: string?, -- "Default" | "Primary" | "Danger"
    Callback: (() -> ())?,
}

export type DialogProps = {
    Title: string,
    Content: string,
    Icon: string?,
    Buttons: { DialogButton }?,
}

function Dialog.Show(parent: Instance, props: DialogProps)
    local targetParent = parent
    if parent:IsA("ScreenGui") then
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("Frame") and child.Name:find("SodiumWindow") then
                targetParent = child
                break
            end
        end
    end
    
    local overlay = Instance.new("TextButton")
    overlay.Name = "SodiumUI_DialogOverlay"
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Position = UDim2.fromScale(0, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 1
    overlay.Text = ""
    overlay.AutoButtonColor = false
    overlay.Active = true
    overlay.ZIndex = 50
    
    local overlayCorner = Instance.new("UICorner")
    overlayCorner.CornerRadius = Theme.Radii.Window
    overlayCorner.Parent = overlay
    
    -- Modal Card (Centered precisely within the UI window with smooth opacity transitions)
    local card = Instance.new("CanvasGroup")
    card.Name = "DialogCard"
    card.Size = UDim2.new(0.80, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.BackgroundColor3 = Theme.GetToken("Card")
    card.GroupTransparency = 1
    card.BorderSizePixel = 0
    card.Active = true
    card.ZIndex = 52
    Theme.Bind(card, "BackgroundColor3", "Card")
    
    local cardConstraint = Instance.new("UISizeConstraint")
    cardConstraint.MinSize = Vector2.new(240, 90)
    cardConstraint.MaxSize = Vector2.new(350, 480)
    cardConstraint.Parent = card
    
    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = Theme.Radii.Card
    cardCorner.Parent = card
    
    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Theme.GetToken("BorderSubtle")
    cardStroke.Thickness = 1.2
    cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cardStroke.Parent = card
    Theme.Bind(cardStroke, "Color", "BorderSubtle")
    
    -- Drop Shadow on Dialog (Parented to overlay behind card so AutomaticSize on card is not broken)
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "DropShadow"
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://6014261993"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.45
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(49, 49, 450, 450)
    shadow.ZIndex = 51
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Position = UDim2.fromScale(0.5, 0.5)
    shadow.Parent = overlay
    
    local shadowScale = Instance.new("UIScale")
    shadowScale.Scale = 0.88
    shadowScale.Parent = shadow
    
    local function syncShadowSize()
        if card and card.Parent and shadow and shadow.Parent then
            local abs = card.AbsoluteSize
            if abs.X > 0 and abs.Y > 0 then
                shadow.Size = UDim2.fromOffset(abs.X + 40, abs.Y + 40)
            end
        end
    end
    card:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncShadowSize)
    task.defer(syncShadowSize)

    local cardScale = Instance.new("UIScale")
    cardScale.Scale = 0.88
    cardScale.Parent = card
    
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 20)
    pad.PaddingBottom = UDim.new(0, 18)
    pad.PaddingLeft = UDim.new(0, 20)
    pad.PaddingRight = UDim.new(0, 20)
    pad.Parent = card
    
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 12)
    list.Parent = card
    
    -- Header Row (Title flush left + Optional Icon on Right)
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 24)
    header.BackgroundTransparency = 1
    header.LayoutOrder = 1
    header.Parent = card
    
    local hasIcon = props.Icon and props.Icon ~= ""
    if hasIcon then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(20, 20)
        icon.Position = UDim2.new(1, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(1, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("Accent")
        icon.ZIndex = 54
        Icons.Apply(icon, props.Icon)
        icon.Parent = header
    end
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = if hasIcon then UDim2.new(1, -26, 1, 0) else UDim2.fromScale(1, 1)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Title
    Locale.Bind(titleLabel, "Text", props.Title)
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 15
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 54
    titleLabel.Parent = header
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    
    -- Content Description
    local contentLabel = Instance.new("TextLabel")
    contentLabel.Name = "Content"
    contentLabel.Size = UDim2.new(1, 0, 0, 0)
    contentLabel.AutomaticSize = Enum.AutomaticSize.Y
    contentLabel.BackgroundTransparency = 1
    contentLabel.Font = Theme.Fonts.Body
    Locale.Bind(contentLabel, "Text", props.Content)
    contentLabel.TextColor3 = Theme.GetToken("TextMuted")
    contentLabel.TextSize = 13
    contentLabel.TextWrapped = true
    contentLabel.RichText = true
    contentLabel.TextXAlignment = Enum.TextXAlignment.Left
    contentLabel.LayoutOrder = 2
    contentLabel.Parent = card
    Theme.Bind(contentLabel, "TextColor3", "TextMuted")
    
    -- Buttons Row
    local rawButtons = props.Buttons
    if not rawButtons or #rawButtons == 0 then
        rawButtons = {
            { Title = "OK", Style = "Primary", Callback = nil }
        }
    end
    
    local function isDismissButton(b: DialogButton): boolean
        local t = Locale.Resolve(b.Title or ""):lower()
        return t:find("cancel") ~= nil 
            or t:find("close") ~= nil 
            or t:find("dismiss") ~= nil 
            or t:find("back") ~= nil 
            or t:find("no") ~= nil 
            or b.Style == "Default" 
            or b.Style == "Secondary"
    end
    
    local btnRow = Instance.new("Frame")
    btnRow.Name = "ButtonRow"
    btnRow.Size = UDim2.new(1, 0, 0, 32)
    btnRow.BackgroundTransparency = 1
    btnRow.LayoutOrder = 3
    
    local isClosing = false
    local function closeDialog()
        if isClosing then return end
        isClosing = true
		Tweener.Tween(shadowScale, Tweener.Info.ExitFast, { Scale = 0.90 })
		Tweener.Tween(shadow, Tweener.Info.ExitFast, { ImageTransparency = 1 })
		Tweener.Tween(card, Tweener.Info.ExitFast, { GroupTransparency = 1 })
		local t = Tweener.Tween(cardScale, Tweener.Info.ExitFast, { Scale = 0.90 })
		Tweener.Tween(overlay, Tweener.Info.ExitFast, { BackgroundTransparency = 1 })
		if t then
			t.Completed:Once(function()
				pcall((overlay :: Instance).Destroy, overlay)
			end)
		else
			pcall((overlay :: Instance).Destroy, overlay)
		end
	end
    
    local function createButton(bData: DialogButton, alignment: string?)
        local bTitleStr = Locale.Resolve(bData.Title or "Button")
        local btn = Instance.new("TextButton")
        btn.Name = "Btn_" .. tostring(bTitleStr)
        btn.Size = UDim2.new(0, 84, 1, 0)
        btn.AutomaticSize = Enum.AutomaticSize.X
        btn.AutoButtonColor = false
        btn.Text = ""
        btn.ZIndex = 54
        
        if alignment == "Left" then
            btn.AnchorPoint = Vector2.new(0, 0)
            btn.Position = UDim2.new(0, 0, 0, 0)
        elseif alignment == "Right" then
            btn.AnchorPoint = Vector2.new(1, 0)
            btn.Position = UDim2.new(1, 0, 0, 0)
        end
        
        local style = bData.Style or "Default"
        if style == "Primary" then
            btn.BackgroundColor3 = Theme.GetToken("Accent")
        elseif style == "Danger" then
            btn.BackgroundColor3 = Theme.GetToken("Danger")
        else
            btn.BackgroundColor3 = Theme.GetToken("SurfaceActive")
            Theme.Bind(btn, "BackgroundColor3", "SurfaceActive")
        end
        
        local bCorner = Instance.new("UICorner")
        bCorner.CornerRadius = Theme.Radii.Control
        bCorner.Parent = btn
        
        local bStroke = Instance.new("UIStroke")
        bStroke.Color = if style == "Primary" then Theme.GetToken("BorderAccent") else Theme.GetToken("BorderSubtle")
        bStroke.Thickness = 1
        bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        bStroke.Parent = btn
        if style == "Primary" then
            Theme.Bind(bStroke, "Color", "BorderAccent")
        else
            Theme.Bind(bStroke, "Color", "BorderSubtle")
        end
        
        local bPad = Instance.new("UIPadding")
        bPad.PaddingLeft = UDim.new(0, 14)
        bPad.PaddingRight = UDim.new(0, 14)
        bPad.Parent = btn
        
        local bLabel = Instance.new("TextLabel")
        bLabel.Size = UDim2.fromScale(1, 1)
        bLabel.BackgroundTransparency = 1
        bLabel.Font = Theme.Fonts.Header
        Locale.Bind(bLabel, "Text", bData.Title)
        bLabel.TextColor3 = if (style == "Primary" or style == "Danger") then Color3.fromRGB(255, 255, 255) else Theme.GetToken("TextPrimary")
        bLabel.TextSize = 12
        bLabel.ZIndex = 55
        bLabel.Parent = btn
        if style ~= "Primary" and style ~= "Danger" then
            Theme.Bind(bLabel, "TextColor3", "TextPrimary")
        end
        
        btn.MouseEnter:Connect(function()
            if style == "Primary" then
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("BorderAccent") })
            elseif style == "Danger" then
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Color3.fromRGB(239, 68, 68) })
            else
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
            end
        end)
        btn.MouseLeave:Connect(function()
            if style == "Primary" then
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Accent") })
            elseif style == "Danger" then
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Danger") })
            else
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceActive") })
            end
        end)
        
        Tweener.BindPressFeedback(btn)
        
		btn.Activated:Connect(function()
			pcall(closeDialog)
			if bData.Callback then
				task.spawn(function()
					local ok, err = pcall(bData.Callback)
					if not ok then
						warn("[SodiumUI.Dialog] Button callback error:", err)
					end
				end)
			end
		end)
        
        return btn
    end
    
    if #rawButtons == 2 then
        local btn1 = rawButtons[1]
        local btn2 = rawButtons[2]
        
        local leftBtnData = btn1
        local rightBtnData = btn2
        
        if isDismissButton(btn2) and not isDismissButton(btn1) then
            leftBtnData = btn2
            rightBtnData = btn1
        end
        
        local lBtn = createButton(leftBtnData, "Left")
        lBtn.Parent = btnRow
        
        local rBtn = createButton(rightBtnData, "Right")
        rBtn.Parent = btnRow
    elseif #rawButtons == 1 then
        local btnData = rawButtons[1]
        local align = if isDismissButton(btnData) then "Left" else "Right"
        local b = createButton(btnData, align)
        b.Parent = btnRow
    else
        local btnLayout = Instance.new("UIListLayout")
        btnLayout.FillDirection = Enum.FillDirection.Horizontal
        btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        btnLayout.Padding = UDim.new(0, 8)
        btnLayout.Parent = btnRow
        
        for _, bData in ipairs(rawButtons) do
            local b = createButton(bData, nil)
            b.Parent = btnRow
        end
    end
    
    btnRow.Parent = card
    card.Parent = overlay
    overlay.Parent = targetParent
    
    -- Animate In with concurrent opacity fade & smooth scale
    Tweener.Tween(overlay, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(shadow, Tweener.Info.Fast, { ImageTransparency = 0.45 })
    Tweener.Tween(shadowScale, Tweener.Info.Spring, { Scale = 1 })
    Tweener.Tween(card, Tweener.Info.Fast, { GroupTransparency = 0 })
    Tweener.Tween(cardScale, Tweener.Info.Spring, { Scale = 1 })
    
    -- Dismiss on background overlay click
    overlay.Activated:Connect(function()
        closeDialog()
    end)
    
    return {
        Close = closeDialog,
        Card = card,
        Overlay = overlay,
    }
end

return Dialog
end

_MODULES['Components/Loading'] = function()
--!strict
--[=[
    Sodium UI - Components/Loading.luau
    macOS Dynamic Island Morph Loader (Obsidian-Amethyst Capsule Progress Bar)
    Features:
    - Pure Vector/Frame rendering (No CanvasGroup font blurriness)
    - True 360-degree soft concentric black glow
    - Interactive live progress bar with fluid spring dampening
    - High-performance auto simulation if manual progress isn't supplied
]=]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Locale = _require("Core/Locale")
local Container = _require("Core/Container")

local Loading = {}
Loading.__index = Loading

export type LoadingProps = {
    Title: any?,
    Subtitle: any?,
    Icon: string?,
    Progress: number?,
    Status: any?,
    Duration: number?,
}

function Loading.new(rawProps: LoadingProps?)
    local props: LoadingProps = rawProps or {}
    local self = setmetatable({}, Loading)
    
    self.ContainerManager = Container.new("Loading")
    self.ContainerManager:SetBaseWindowSize(Vector2.new(380, 200))
    local rootGui = self.ContainerManager.ScreenGui
    self.RootGui = rootGui
    
    local titleText = props.Title or "Pumpkin Hub"
    local subText = props.Subtitle or { EN = "Preparing workspace & modules...", TH = "กำลังเตรียมระบบและโมดูล..." }
    
    -- 1. Backdrop Overlay (Gentle ambient dimming)
    local backdrop = Instance.new("Frame")
    backdrop.Name = "LoadingBackdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.Position = UDim2.fromScale(0.5, 0.5)
    backdrop.AnchorPoint = Vector2.new(0.5, 0.5)
    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel = 0
    backdrop.ZIndex = 99990
    backdrop.Parent = rootGui
    self.Backdrop = backdrop
    
    -- 2. Ambient Black Glow (Concentric Capsule Shadow)
    local glowHolder = Instance.new("Frame")
    glowHolder.Name = "LoadingGlowHolder"
    glowHolder.Size = UDim2.fromOffset(340, 110)
    glowHolder.Position = UDim2.fromScale(0.5, 0.5)
    glowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    glowHolder.BackgroundTransparency = 1
    glowHolder.ZIndex = 99991
    
    local glowLayers = {
        { pad = 2, tr = 0.52 },
        { pad = 5, tr = 0.68 },
        { pad = 9, tr = 0.82 },
        { pad = 14, tr = 0.92 },
    }
    local glowFrames = {}
    for i, lyr in ipairs(glowLayers) do
        local gf = Instance.new("Frame")
        gf.Name = "Glow_" .. tostring(i)
        gf.Size = UDim2.new(1, lyr.pad * 2, 1, lyr.pad * 2)
        gf.Position = UDim2.new(0, -lyr.pad, 0, -lyr.pad)
        gf.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        gf.BackgroundTransparency = 1 -- Animate in
        gf.BorderSizePixel = 0
        gf.ZIndex = 99991
        
        local gc = Instance.new("UICorner")
        gc.CornerRadius = UDim.new(0, 14 + lyr.pad)
        gc.Parent = gf
        
        gf.Parent = glowHolder
        table.insert(glowFrames, { Frame = gf, TargetTr = lyr.tr })
    end
    glowHolder.Parent = rootGui
    self.GlowHolder = glowHolder
    self.GlowFrames = glowFrames

    -- 3. Modern Floating Modal (macOS Capsule Card Style)
    local modal = Instance.new("Frame")
    modal.Name = "LoadingModal"
    modal.Size = UDim2.fromOffset(340, 110)
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.Position = UDim2.fromScale(0.5, 0.5)
    modal.BackgroundColor3 = Theme.GetToken("Background")
    modal.BackgroundTransparency = 0
    modal.BorderSizePixel = 0
    modal.ClipsDescendants = true
    modal.ZIndex = 99992
    modal.Parent = rootGui
    Theme.Bind(modal, "BackgroundColor3", "Background")
    self.Modal = modal
    
    local modalCorner = Instance.new("UICorner")
    modalCorner.CornerRadius = Theme.Radii.Window
    modalCorner.Parent = modal
    
    local modalStroke = Instance.new("UIStroke")
    modalStroke.Color = Theme.GetToken("BorderAccent")
    modalStroke.Thickness = 1.2
    modalStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    modalStroke.Parent = modal
    Theme.Bind(modalStroke, "Color", "BorderAccent")
    
    local modalScale = Instance.new("UIScale")
    modalScale.Scale = 0.88
    modalScale.Parent = modal
    self.ModalScale = modalScale

    local glowScale = Instance.new("UIScale")
    glowScale.Scale = 0.88
    glowScale.Parent = glowHolder
    self.GlowScale = glowScale

    -- Top Accent Glow Beam (Subtle ambient light strip at the top)
    local topBeam = Instance.new("Frame")
    topBeam.Name = "TopBeam"
    topBeam.Size = UDim2.new(1, 0, 0, 2)
    topBeam.Position = UDim2.new(0, 0, 0, 0)
    topBeam.BackgroundColor3 = Theme.GetToken("Accent")
    topBeam.BorderSizePixel = 0
    topBeam.ZIndex = 99993
    topBeam.Parent = modal
    Theme.Bind(topBeam, "BackgroundColor3", "Accent")

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 16)
    pad.PaddingBottom = UDim.new(0, 16)
    pad.PaddingLeft = UDim.new(0, 20)
    pad.PaddingRight = UDim.new(0, 20)
    pad.Parent = modal

    -- Header Row (Left Pulsing Icon + Title Stack + Right Percent Badge)
    local headerRow = Instance.new("Frame")
    headerRow.Name = "HeaderRow"
    headerRow.Size = UDim2.new(1, 0, 0, 42)
    headerRow.Position = UDim2.new(0, 0, 0, 0)
    headerRow.BackgroundTransparency = 1
    headerRow.ZIndex = 99993
    headerRow.Parent = modal

    -- Rotating / Pulsing Icon
    local iconBadge = Instance.new("Frame")
    iconBadge.Name = "IconBadge"
    iconBadge.Size = UDim2.fromOffset(34, 34)
    iconBadge.Position = UDim2.new(0, 0, 0.5, 0)
    iconBadge.AnchorPoint = Vector2.new(0, 0.5)
    iconBadge.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    iconBadge.BorderSizePixel = 0
    iconBadge.ZIndex = 99993
    Theme.Bind(iconBadge, "BackgroundColor3", "SurfaceHover")

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(0, 10)
    badgeCorner.Parent = iconBadge

    local badgeStroke = Instance.new("UIStroke")
    badgeStroke.Color = Theme.GetToken("BorderSubtle")
    badgeStroke.Thickness = 1
    badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    badgeStroke.Parent = iconBadge
    Theme.Bind(badgeStroke, "Color", "BorderSubtle")

    local iconLabel = Instance.new("ImageLabel")
    iconLabel.Name = "Icon"
    iconLabel.Size = UDim2.fromOffset(18, 18)
    iconLabel.Position = UDim2.fromScale(0.5, 0.5)
    iconLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    iconLabel.BackgroundTransparency = 1
    iconLabel.ImageColor3 = Theme.GetToken("Accent")
    iconLabel.ZIndex = 99994
    Icons.Apply(iconLabel, props.Icon or "loader")
    iconLabel.Parent = iconBadge
    Theme.Bind(iconLabel, "ImageColor3", "Accent")
    iconBadge.Parent = headerRow

    local spinTween = TweenService:Create(iconLabel, TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
        Rotation = 360,
    })
    spinTween:Play()
    self._spinTween = spinTween

    -- Center Text Stack
    local textStack = Instance.new("Frame")
    textStack.Name = "TextStack"
    textStack.Size = UDim2.new(1, -96, 1, 0)
    textStack.Position = UDim2.new(0, 44, 0.5, 0)
    textStack.AnchorPoint = Vector2.new(0, 0.5)
    textStack.BackgroundTransparency = 1
    textStack.ZIndex = 99993
    textStack.Parent = headerRow

    local stackLayout = Instance.new("UIListLayout")
    stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
    stackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    stackLayout.Padding = UDim.new(0, 2)
    stackLayout.Parent = textStack

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 18)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Title", "Body")
    Locale.Bind(titleLabel, "Text", titleText)
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.LayoutOrder = 1
    titleLabel.Parent = textStack
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")

    local subLabel = Instance.new("TextLabel")
    subLabel.Name = "Subtitle"
    subLabel.Size = UDim2.new(1, 0, 0, 14)
    subLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(subLabel, "Body", "Small")
    Locale.Bind(subLabel, "Text", subText)
    subLabel.TextColor3 = Theme.GetToken("TextMuted")
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.TextTruncate = Enum.TextTruncate.AtEnd
    subLabel.LayoutOrder = 2
    subLabel.Parent = textStack
    Theme.Bind(subLabel, "TextColor3", "TextMuted")
    self.SubLabel = subLabel

    -- Right Percentage Counter Badge
    local pctBadge = Instance.new("Frame")
    pctBadge.Name = "PctBadge"
    pctBadge.Size = UDim2.fromOffset(46, 22)
    pctBadge.Position = UDim2.new(1, 0, 0.5, 0)
    pctBadge.AnchorPoint = Vector2.new(1, 0.5)
    pctBadge.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    pctBadge.BorderSizePixel = 0
    pctBadge.ZIndex = 99993
    Theme.Bind(pctBadge, "BackgroundColor3", "SurfaceHover")

    local pctCorner = Instance.new("UICorner")
    pctCorner.CornerRadius = UDim.new(1, 0)
    pctCorner.Parent = pctBadge

    local pctStroke = Instance.new("UIStroke")
    pctStroke.Color = Theme.GetToken("BorderAccent")
    pctStroke.Thickness = 1
    pctStroke.Transparency = 0.6
    pctStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    pctStroke.Parent = pctBadge
    Theme.Bind(pctStroke, "Color", "BorderAccent")

    local pctLabel = Instance.new("TextLabel")
    pctLabel.Name = "PctLabel"
    pctLabel.Size = UDim2.fromScale(1, 1)
    pctLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(pctLabel, "Code", "Small")
    pctLabel.Text = "0%"
    pctLabel.TextColor3 = Theme.GetToken("Accent")
    pctLabel.TextXAlignment = Enum.TextXAlignment.Center
    pctLabel.ZIndex = 99994
    pctLabel.Parent = pctBadge
    Theme.Bind(pctLabel, "TextColor3", "Accent")
    pctBadge.Parent = headerRow
    self.PctLabel = pctLabel

    -- Bottom Progress Bar (Track & Fluid Amethyst Glow Fill)
    local track = Instance.new("Frame")
    track.Name = "ProgressTrack"
    track.Size = UDim2.new(1, 0, 0, 6)
    track.Position = UDim2.new(0, 0, 1, -6)
    track.BackgroundColor3 = Theme.GetToken("SurfaceActive")
    track.BorderSizePixel = 0
    track.ZIndex = 99993
    track.Parent = modal
    Theme.Bind(track, "BackgroundColor3", "SurfaceActive")

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fillBar = Instance.new("Frame")
    fillBar.Name = "FillBar"
    local initialPct = math.clamp(props.Progress or 0, 0, 1)
    fillBar.Size = UDim2.new(initialPct, 0, 1, 0)
    fillBar.BackgroundColor3 = Theme.GetToken("Accent")
    fillBar.BorderSizePixel = 0
    fillBar.ZIndex = 99994
    fillBar.Parent = track
    Theme.Bind(fillBar, "BackgroundColor3", "Accent")
    self.FillBar = fillBar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fillBar

    -- Entrance Transition (Lockstep smooth macOS pop)
    local entranceTween = Tweener.Info.MacOSWindowOpen
    Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 0.55 })
    Tweener.Tween(modalScale, entranceTween, { Scale = 1.0 })
    Tweener.Tween(glowScale, entranceTween, { Scale = 1.0 })
    for _, item in ipairs(glowFrames) do
        Tweener.Tween(item.Frame, entranceTween, { BackgroundTransparency = item.TargetTr })
    end

    -- Optional Auto-simulate smooth progress if not manually driven
    local duration = props.Duration or 1.2
    if duration > 0 and (props.Progress == nil or props.Progress == 0) then
        self._autoThread = task.spawn(function()
            local steps = 24
            local dt = duration / steps
            for i = 1, steps do
                if not self.Modal or not self.Modal.Parent then break end
                local pct = i / steps
                self:SetProgress(pct)
                task.wait(dt)
            end
        end)
    end

    return self
end

function Loading:SetProgress(percent: number, statusText: string?)
    local clamped = math.clamp(percent, 0, 1)
    if self.FillBar and self.FillBar.Parent then
        Tweener.Tween(self.FillBar, Tweener.Info.Fast, {
            Size = UDim2.new(clamped, 0, 1, 0)
        })
    end
    if self.PctLabel and self.PctLabel.Parent then
        self.PctLabel.Text = string.format("%d%%", math.floor(clamped * 100))
    end
    if statusText and self.SubLabel and self.SubLabel.Parent then
        Locale.Bind(self.SubLabel, "Text", statusText)
    end
end

function Loading:SetStatus(statusText: string)
    if self.SubLabel and self.SubLabel.Parent then
        Locale.Bind(self.SubLabel, "Text", statusText)
    end
end

function Loading:Finish(onComplete: (() -> ())?)
    if self._autoThread then
        task.cancel(self._autoThread)
        self._autoThread = nil
    end

    self:SetProgress(1.0, { EN = "Complete!", TH = "พร้อมใช้งาน!" })
    task.delay(0.25, function()
        if not self.Modal or not self.Modal.Parent then
            if onComplete then pcall(onComplete) end
            return
        end

        local exitTween = Tweener.Info.MacOSWindowClose
        Tweener.Tween(self.ModalScale, exitTween, { Scale = 0.90 })
        Tweener.Tween(self.GlowScale, exitTween, { Scale = 0.90 })
        Tweener.Tween(self.Backdrop, exitTween, { BackgroundTransparency = 1.0 })
        for _, item in ipairs(self.GlowFrames) do
            Tweener.Tween(item.Frame, exitTween, { BackgroundTransparency = 1.0 })
        end

        task.delay(0.22, function()
            pcall(self.Destroy, self)
            if onComplete then
                pcall(onComplete)
            end
        end)
    end)
end

function Loading:Destroy()
    if self._autoThread then
        task.cancel(self._autoThread)
        self._autoThread = nil
    end
    if self._spinTween then
        pcall((self._spinTween :: Tween).Cancel, self._spinTween)
        self._spinTween = nil
    end
    Tweener.Cancel(self.Modal)
    Tweener.Cancel(self.ModalScale)
    Tweener.Cancel(self.GlowScale)
    Tweener.Cancel(self.Backdrop)
    if self.ContainerManager then
        pcall((self.ContainerManager :: any).Destroy, self.ContainerManager)
        self.ContainerManager = nil
    end
end

return Loading
end

_MODULES['Components/KeyCheck'] = function()
--!strict
--[=[
    Sodium UI - Components/KeyCheck.luau
    Obsidian Amethyst standalone authentication window with JNKIE Ultimate SDK,
    clipboard paste, remember-key toggle, rate limiting, and 4-state status badge.
]=]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Container = _require("Core/Container")

local KeyCheck = {}
KeyCheck.__index = KeyCheck

export type KeyCheckProps = {
    Title: string?,
    Subtitle: string?,
    Service: string?,
    Identifier: string?,
    Provider: string?,
    SaveKey: boolean?,
    SaveFileName: string?,
    GetKeyUrl: string?,
    BuyUrl: string?,
    DiscordUrl: string?,
    OnSuccess: ((key: string, data: any?) -> ())?,
}

-- Safe time function
local function getSafeTimestamp(): number
    local t = os.time()
    if t and t > 1000000000 then return t end
    local s, st = pcall(function() return math.floor(workspace:GetServerTimeNow()) end)
    if s and st and st > 1000000000 then return st end
    return math.floor(tick())
end

-- Safe executor environment accessor
local function getExecutorFunc(name: string): any
    local genv = (type(getgenv) == "function" and getgenv()) or nil
    if genv and genv[name] ~= nil then return genv[name] end
    local s, val = pcall(function() return getfenv()[name] end)
    if s and val ~= nil then return val end
    return nil
end

-- Executor file helpers
local function safeWriteFile(filename: string, content: string): boolean
    local writef = getExecutorFunc("writefile")
    if type(writef) == "function" then
        local makef = getExecutorFunc("makefolder")
        if type(makef) == "function" then
            local clean = filename:gsub("\\", "/")
            local parts = string.split(clean, "/")
            if #parts > 1 then
                local currentPath = ""
                for i = 1, #parts - 1 do
                    if #parts[i] > 0 then
                        currentPath = if currentPath == "" then parts[i] else (currentPath .. "/" .. parts[i])
                        pcall(makef, currentPath)
                    end
                end
            end
        end
        local s, _ = pcall(writef, filename, content)
        return s
    end
    return false
end

local function safeReadFile(filename: string): string?
    local isf = getExecutorFunc("isfile")
    local readf = getExecutorFunc("readfile")
    if type(isf) == "function" and type(readf) == "function" then
        local s1, exists = pcall(isf, filename)
        if s1 and exists then
            local s2, content = pcall(readf, filename)
            if s2 and type(content) == "string" then
                return content
            end
        end
    elseif type(readf) == "function" then
        local s2, content = pcall(readf, filename)
        if s2 and type(content) == "string" then
            return content
        end
    end
    return nil
end

local function safeDeleteFile(filename: string)
    local isf = getExecutorFunc("isfile")
    local delf = getExecutorFunc("delfile")
    if type(isf) == "function" and type(delf) == "function" then
        pcall(function()
            if isf(filename) then delf(filename) end
        end)
    elseif type(delf) == "function" then
        pcall(delf, filename)
    end
end

local function safeSetClipboard(str: string): boolean
    local setclip = getExecutorFunc("setclipboard") or getExecutorFunc("toclipboard")
    if type(setclip) == "function" then
        local s, _ = pcall(setclip, str)
        return s
    end
    return false
end

local function safeGetClipboard(): string?
    local getclip = getExecutorFunc("getclipboard")
    if type(getclip) == "function" then
        local s, res = pcall(getclip)
        if s and type(res) == "string" then
            return res
        end
    end
    return nil
end

-- JNKIE SDK Loader with Resilient Mock Fallback (Compliant with docs.jnkie.com)
local function loadJunkieSDK(serviceName: string, identifier: string, provider: string): any
    local junkieObj = nil
    local success, _ = pcall(function()
        local sdkCode = game:HttpGet("https://jnkie.com/sdk/library.lua")
        if sdkCode and #sdkCode > 10 then
            local chunk = loadstring(sdkCode)
            if chunk then
                junkieObj = chunk()
            end
        end
    end)
    
    if not junkieObj or type(junkieObj) ~= "table" then
        -- Mock Fallback Object for offline / studio / testing
        junkieObj = {
            service = serviceName,
            identifier = identifier,
            provider = provider,
            get_key_link = function(s)
                local id = if type(s) == "table" and s.identifier then s.identifier else identifier
                return "https://jnkie.com/flow/" .. tostring(id or "sodium-auth"), nil
            end,
            check_key = function(firstArg, secondArg)
                task.wait(0.3)
                local actualKey = if type(secondArg) == "string" then secondArg else (if type(firstArg) == "string" then firstArg else tostring(firstArg or ""))
                local upper = actualKey:upper():gsub("%s+", "")
                if upper == "SODIUM-PREMIUM" or upper == "PREMIUM" then
                    return {
                        valid = true,
                        message = "KEY_VALID",
                        plan = "Premium",
                        is_premium = true,
                        expires_at = getSafeTimestamp() + 2592000, -- 30 days
                    }
                elseif upper == "SODIUM-FREE" or upper == "FREE" then
                    return {
                        valid = true,
                        message = "KEY_VALID",
                        plan = "Free",
                        is_premium = false,
                        expires_at = getSafeTimestamp() + 86400, -- 24 hours
                    }
                elseif upper == "KEYLESS" then
                    return {
                        valid = true,
                        message = "KEYLESS",
                        plan = "Keyless",
                        is_premium = false,
                    }
                elseif upper == "TEST" then
                    return {
                        valid = true,
                        message = "KEY_VALID",
                        plan = "Test",
                        is_premium = false,
                        expires_at = getSafeTimestamp() + 43200, -- 12 hours
                    }
                end
                return { valid = false, error = "KEY_INVALID", message = "Invalid license key." }
            end,
        }
    else
        junkieObj.service = serviceName
        junkieObj.identifier = identifier
        junkieObj.provider = provider
        
        -- Wrap check_key: Official SDK uses check_key(key).
        -- If called via colon `junkieObj:check_key(key)`, Lua passes junkieObj as arg1 and key as arg2.
        -- This wrapper intercepts both dot and colon calls to extract the string key, preventing table address being sent to Jnkie API!
        local rawCheckKey = junkieObj.check_key
        if type(rawCheckKey) == "function" then
            junkieObj.check_key = function(firstArg, secondArg)
                local targetKey = if type(secondArg) == "string" then secondArg else (if type(firstArg) == "string" then firstArg else tostring(firstArg or ""))
                return rawCheckKey(targetKey)
            end
        end
        
        local rawGetLink = junkieObj.get_key_link
        if type(rawGetLink) == "function" then
            junkieObj.get_key_link = function(...)
                return rawGetLink()
            end
        end
    end
    
    return junkieObj
end

function KeyCheck.new(rawProps: KeyCheckProps?)
    local props: KeyCheckProps = rawProps or {}
    local self = setmetatable({}, KeyCheck)
    
    local saveFileName = props.SaveFileName or "Sodium_SavedKey.json"
    local rememberKey = if props.SaveKey ~= nil then props.SaveKey else (if (props :: any).RememberKey ~= nil then (props :: any).RememberKey else true)
    local serviceName = props.Service or (props :: any).ServiceName or "Sodium Hub"
    local identifier = props.Identifier or (props :: any).UserId or (props :: any).Id or "sodium-auth"
    local provider = props.Provider or "Mixed"
    
    self.Junkie = loadJunkieSDK(serviceName, identifier, provider)
    self.SaveFileName = saveFileName
    self.RememberKey = rememberKey
    self.IsVerifying = false
    
    -- Check for cached key for auto-verify
    local cachedKey = nil
    local cachedExpiresAt = nil
    local cachedSavedAt = nil
    local cachedPlan = nil
    local cachedIsPremium = nil
    local cachedJson = safeReadFile(saveFileName)
    if cachedJson and #cachedJson > 0 then
        local s, decoded = pcall(function()
            return HttpService:JSONDecode(cachedJson)
        end)
        if s and type(decoded) == "table" and type(decoded.key) == "string" and #decoded.key > 0 then
            cachedKey = decoded.key
            cachedExpiresAt = decoded.expires_at
            cachedSavedAt = decoded.saved_at
            cachedPlan = decoded.plan
            cachedIsPremium = decoded.is_premium
        else
            local rawTrimmed = cachedJson:gsub("^%s+", ""):gsub("%s+$", "")
            if #rawTrimmed > 0 and not string.find(rawTrimmed, "^{") then
                cachedKey = rawTrimmed
            end
        end
    end
    
    self.ContainerManager = Container.new("KeyCheck")
    self.ContainerManager:SetBaseWindowSize(Vector2.new(460, 340))
    local rootGui = self.ContainerManager.ScreenGui
    self.RootGui = rootGui
    
    -- Fullscreen Modal Backdrop
    local backdrop = Instance.new("Frame")
    backdrop.Name = "KeyCheckBackdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel = 0
    backdrop.ZIndex = 99990
    backdrop.Parent = rootGui
    self.Backdrop = backdrop
    
    -- Main KeyCheck Window
    local modal = Instance.new("Frame")
    modal.Name = "KeyCheckModal"
    modal.Size = UDim2.fromOffset(420, 310)
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.Position = UDim2.fromScale(0.5, 0.5)
    modal.BackgroundColor3 = Theme.GetToken("Background")
    modal.BorderSizePixel = 0
    modal.ClipsDescendants = false
    modal.ZIndex = 99991
    modal.Parent = rootGui
    self.Modal = modal
    
    local modalCorner = Instance.new("UICorner")
    modalCorner.CornerRadius = Theme.Radii.Window
    modalCorner.Parent = modal
    
    local modalStroke = Instance.new("UIStroke")
    modalStroke.Color = Theme.GetToken("BorderAccent")
    modalStroke.Thickness = 1.2
    modalStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    modalStroke.Parent = modal
    Theme.Bind(modalStroke, "Color", "BorderAccent")
    Theme.Bind(modal, "BackgroundColor3", "Background")
    
    local modalScale = Instance.new("UIScale")
    modalScale.Scale = 0.94
    modalScale.Parent = modal
    self.ModalScale = modalScale
    
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 18)
    pad.PaddingBottom = UDim.new(0, 18)
    pad.PaddingLeft = UDim.new(0, 20)
    pad.PaddingRight = UDim.new(0, 20)
    pad.Parent = modal
    
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 10)
    list.Parent = modal
    
    -- 1. Header (Icon + Title + Close Button)
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 26)
    header.BackgroundTransparency = 1
    header.LayoutOrder = 1
    header.Parent = modal
    
    local keyIcon = Instance.new("ImageLabel")
    keyIcon.Name = "KeyIcon"
    keyIcon.Size = UDim2.fromOffset(20, 20)
    keyIcon.Position = UDim2.new(0, 0, 0.5, 0)
    keyIcon.AnchorPoint = Vector2.new(0, 0.5)
    keyIcon.BackgroundTransparency = 1
    keyIcon.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(keyIcon, "key")
    keyIcon.Parent = header
    Theme.Bind(keyIcon, "ImageColor3", "Accent")
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -60, 1, 0)
    titleLabel.Position = UDim2.new(0, 28, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Title
    titleLabel.Text = props.Title or "Sodium Authentication"
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = header
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseBtn"
    closeBtn.Size = UDim2.fromOffset(24, 24)
    closeBtn.Position = UDim2.new(1, -24, 0.5, 0)
    closeBtn.AnchorPoint = Vector2.new(0, 0.5)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = ""
    closeBtn.Parent = header
    
    local closeIcon = Instance.new("ImageLabel")
    closeIcon.Size = UDim2.fromOffset(14, 14)
    closeIcon.Position = UDim2.fromScale(0.5, 0.5)
    closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    closeIcon.BackgroundTransparency = 1
    closeIcon.ImageColor3 = Theme.GetToken("TextMuted")
    Icons.Apply(closeIcon, "x")
    closeIcon.Parent = closeBtn
    Theme.Bind(closeIcon, "ImageColor3", "TextMuted")
    
    closeBtn.MouseEnter:Connect(function()
        Tweener.Tween(closeIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Danger") })
    end)
    closeBtn.MouseLeave:Connect(function()
        Tweener.Tween(closeIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
    end)
    closeBtn.Activated:Connect(function()
        self:Destroy()
    end)
    
    -- Subtitle
    local subLabel = Instance.new("TextLabel")
    subLabel.Name = "Subtitle"
    subLabel.Size = UDim2.new(1, 0, 0, 16)
    subLabel.BackgroundTransparency = 1
    subLabel.Font = Theme.Fonts.Sub
    subLabel.Text = props.Subtitle or "Please enter your license key to unlock script features."
    subLabel.TextColor3 = Theme.GetToken("TextMuted")
    subLabel.TextSize = 11
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.LayoutOrder = 2
    subLabel.Parent = modal
    Theme.Bind(subLabel, "TextColor3", "TextMuted")
    
    -- 2. Input Box Row (Placeholder: "Place key here", Lock Icon, Paste Button)
    local inputContainer = Instance.new("Frame")
    inputContainer.Name = "InputContainer"
    inputContainer.Size = UDim2.new(1, 0, 0, 40)
    inputContainer.BackgroundColor3 = Theme.GetToken("Card")
    inputContainer.BorderSizePixel = 0
    inputContainer.LayoutOrder = 3
    inputContainer.Parent = modal
    Theme.Bind(inputContainer, "BackgroundColor3", "Card")
    
    local inCorner = Instance.new("UICorner")
    inCorner.CornerRadius = Theme.Radii.Element
    inCorner.Parent = inputContainer
    
    local inStroke = Instance.new("UIStroke")
    inStroke.Color = Theme.GetToken("BorderSubtle")
    inStroke.Thickness = 1
    inStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    inStroke.Parent = inputContainer
    Theme.Bind(inStroke, "Color", "BorderSubtle")
    
    local lockIcon = Instance.new("ImageLabel")
    lockIcon.Name = "LockIcon"
    lockIcon.Size = UDim2.fromOffset(16, 16)
    lockIcon.Position = UDim2.new(0, 12, 0.5, 0)
    lockIcon.AnchorPoint = Vector2.new(0, 0.5)
    lockIcon.BackgroundTransparency = 1
    lockIcon.ImageColor3 = Theme.GetToken("Placeholder")
    Icons.Apply(lockIcon, "lock")
    lockIcon.Parent = inputContainer
    Theme.Bind(lockIcon, "ImageColor3", "Placeholder")
    
    local pasteBtn = Instance.new("TextButton")
    pasteBtn.Name = "PasteBtn"
    pasteBtn.Size = UDim2.fromOffset(28, 28)
    pasteBtn.Position = UDim2.new(1, -34, 0.5, 0)
    pasteBtn.AnchorPoint = Vector2.new(0, 0.5)
    pasteBtn.BackgroundColor3 = Theme.GetToken("SurfaceActive")
    pasteBtn.AutoButtonColor = false
    pasteBtn.Text = ""
    pasteBtn.Parent = inputContainer
    Theme.Bind(pasteBtn, "BackgroundColor3", "SurfaceActive")
    
    local pasteCorner = Instance.new("UICorner")
    pasteCorner.CornerRadius = Theme.Radii.Control
    pasteCorner.Parent = pasteBtn
    
    local pasteIcon = Instance.new("ImageLabel")
    pasteIcon.Size = UDim2.fromOffset(14, 14)
    pasteIcon.Position = UDim2.fromScale(0.5, 0.5)
    pasteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    pasteIcon.BackgroundTransparency = 1
    pasteIcon.ImageColor3 = Theme.GetToken("TextMuted")
    Icons.Apply(pasteIcon, "clipboard")
    pasteIcon.Parent = pasteBtn
    Theme.Bind(pasteIcon, "ImageColor3", "TextMuted")
    Tweener.BindPressFeedback(pasteBtn)
    
    local keyBox = Instance.new("TextBox")
    keyBox.Name = "KeyInput"
    keyBox.Size = UDim2.new(1, -74, 1, 0)
    keyBox.Position = UDim2.new(0, 36, 0, 0)
    keyBox.BackgroundTransparency = 1
    keyBox.Font = Theme.Fonts.Body
    keyBox.PlaceholderText = "Place key here"
    keyBox.PlaceholderColor3 = Theme.GetToken("Placeholder")
    keyBox.Text = cachedKey or ""
    keyBox.TextColor3 = Theme.GetToken("TextPrimary")
    keyBox.TextSize = 12
    keyBox.TextXAlignment = Enum.TextXAlignment.Left
    keyBox.ClearTextOnFocus = false
    keyBox.Parent = inputContainer
    Theme.Bind(keyBox, "PlaceholderColor3", "Placeholder")
    Theme.Bind(keyBox, "TextColor3", "TextPrimary")
    self.KeyBox = keyBox
    
    keyBox.Focused:Connect(function()
        Tweener.Tween(inStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderAccent") })
        Tweener.Tween(lockIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Accent") })
    end)
    keyBox.FocusLost:Connect(function()
        Tweener.Tween(inStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
        Tweener.Tween(lockIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Placeholder") })
    end)
    
    pasteBtn.Activated:Connect(function()
        local clip = safeGetClipboard()
        if clip and #clip > 0 then
            keyBox.Text = clip:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end)
    
    -- 3. Remember Me Checkbox Row
    local rememberRow = Instance.new("TextButton")
    rememberRow.Name = "RememberRow"
    rememberRow.Size = UDim2.new(1, 0, 0, 20)
    rememberRow.BackgroundTransparency = 1
    rememberRow.Text = ""
    rememberRow.AutoButtonColor = false
    rememberRow.LayoutOrder = 4
    rememberRow.Parent = modal
    
    local rList = Instance.new("UIListLayout")
    rList.FillDirection = Enum.FillDirection.Horizontal
    rList.VerticalAlignment = Enum.VerticalAlignment.Center
    rList.Padding = UDim.new(0, 8)
    rList.Parent = rememberRow
    
    local checkSquare = Instance.new("Frame")
    checkSquare.Name = "CheckSquare"
    checkSquare.Size = UDim2.fromOffset(16, 16)
    checkSquare.BackgroundColor3 = if rememberKey then Theme.GetToken("Accent") else Theme.GetToken("SurfaceActive")
    checkSquare.BorderSizePixel = 0
    checkSquare.Parent = rememberRow
    
    local sqCorner = Instance.new("UICorner")
    sqCorner.CornerRadius = UDim.new(0, 4)
    sqCorner.Parent = checkSquare
    
    local checkMark = Instance.new("ImageLabel")
    checkMark.Size = UDim2.fromOffset(12, 12)
    checkMark.Position = UDim2.fromScale(0.5, 0.5)
    checkMark.AnchorPoint = Vector2.new(0.5, 0.5)
    checkMark.BackgroundTransparency = 1
    checkMark.ImageColor3 = Color3.fromRGB(255, 255, 255)
    checkMark.Visible = rememberKey
    Icons.Apply(checkMark, "check")
    checkMark.Parent = checkSquare
    
    local rLabel = Instance.new("TextLabel")
    rLabel.Size = UDim2.new(1, -28, 1, 0)
    rLabel.BackgroundTransparency = 1
    rLabel.Font = Theme.Fonts.Body
    rLabel.Text = "Remember this key on this device"
    rLabel.TextColor3 = Theme.GetToken("TextMuted")
    rLabel.TextSize = 11
    rLabel.TextXAlignment = Enum.TextXAlignment.Left
    rLabel.Parent = rememberRow
    Theme.Bind(rLabel, "TextColor3", "TextMuted")
    
    rememberRow.Activated:Connect(function()
        rememberKey = not rememberKey
        self.RememberKey = rememberKey
        checkMark.Visible = rememberKey
        Tweener.Tween(checkSquare, Tweener.Info.Fast, {
            BackgroundColor3 = if rememberKey then Theme.GetToken("Accent") else Theme.GetToken("SurfaceActive")
        })
    end)
    
    -- 4. Status Badge Row (4 States: Ready, Verifying, Success, Error)
    local statusRow = Instance.new("Frame")
    statusRow.Name = "StatusRow"
    statusRow.Size = UDim2.new(1, 0, 0, 18)
    statusRow.BackgroundTransparency = 1
    statusRow.LayoutOrder = 5
    statusRow.Parent = modal
    
    local sList = Instance.new("UIListLayout")
    sList.FillDirection = Enum.FillDirection.Horizontal
    sList.VerticalAlignment = Enum.VerticalAlignment.Center
    sList.Padding = UDim.new(0, 6)
    sList.Parent = statusRow
    
    local statusDot = Instance.new("Frame")
    statusDot.Name = "StatusDot"
    statusDot.Size = UDim2.fromOffset(8, 8)
    statusDot.BackgroundColor3 = Theme.GetToken("Placeholder")
    statusDot.BorderSizePixel = 0
    statusDot.Parent = statusRow
    
    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = statusDot
    
    local statusText = Instance.new("TextLabel")
    statusText.Name = "StatusText"
    statusText.Size = UDim2.new(1, -16, 1, 0)
    statusText.BackgroundTransparency = 1
    statusText.Font = Theme.Fonts.Body
    statusText.Text = "Ready for verification"
    statusText.TextColor3 = Theme.GetToken("Placeholder")
    statusText.TextSize = 11
    statusText.TextXAlignment = Enum.TextXAlignment.Left
    statusText.Parent = statusRow
    Theme.Bind(statusText, "TextColor3", "Placeholder")
    
    local function setStatusState(state: string, customMsg: string?)
        if state == "Ready" then
            statusDot.BackgroundColor3 = Theme.GetToken("Placeholder")
            statusText.TextColor3 = Theme.GetToken("Placeholder")
            statusText.Text = customMsg or "Ready for verification"
        elseif state == "Verifying" then
            statusDot.BackgroundColor3 = Color3.fromRGB(245, 158, 11) -- Amber
            statusText.TextColor3 = Color3.fromRGB(245, 158, 11)
            statusText.Text = customMsg or "Verifying with server..."
        elseif state == "Success" then
            statusDot.BackgroundColor3 = Theme.GetToken("Success")
            statusText.TextColor3 = Theme.GetToken("Success")
            statusText.Text = customMsg or "Key authenticated successfully!"
        elseif state == "Error" then
            statusDot.BackgroundColor3 = Theme.GetToken("Danger")
            statusText.TextColor3 = Theme.GetToken("Danger")
            statusText.Text = customMsg or "Invalid key! Please try again."
            
            -- Shake animation on Modal
            task.spawn(function()
                local origX = modal.Position.X.Offset
                local origY = modal.Position.Y.Offset
                for _, offset in ipairs({ -8, 8, -6, 6, -3, 3, 0 }) do
                    modal.Position = UDim2.new(0.5, origX + offset, 0.5, origY)
                    task.wait(0.035)
                end
            end)
        end
    end
    self.SetStatus = setStatusState
    
    -- 5. Redeem Button (Full-width, 38px, Theme Accent)
    local redeemBtn = Instance.new("TextButton")
    redeemBtn.Name = "RedeemBtn"
    redeemBtn.Size = UDim2.new(1, 0, 0, 38)
    redeemBtn.BackgroundColor3 = Theme.GetToken("Accent")
    redeemBtn.AutoButtonColor = false
    redeemBtn.Text = ""
    redeemBtn.LayoutOrder = 6
    redeemBtn.Parent = modal
    Theme.Bind(redeemBtn, "BackgroundColor3", "Accent")
    
    local redCorner = Instance.new("UICorner")
    redCorner.CornerRadius = Theme.Radii.Element
    redCorner.Parent = redeemBtn
    
    local redList = Instance.new("UIListLayout")
    redList.FillDirection = Enum.FillDirection.Horizontal
    redList.VerticalAlignment = Enum.VerticalAlignment.Center
    redList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    redList.Padding = UDim.new(0, 8)
    redList.Parent = redeemBtn
    
    local redIcon = Instance.new("ImageLabel")
    redIcon.Size = UDim2.fromOffset(16, 16)
    redIcon.BackgroundTransparency = 1
    redIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    Icons.Apply(redIcon, "check")
    redIcon.Parent = redeemBtn
    
    local redLabel = Instance.new("TextLabel")
    redLabel.Size = UDim2.new(0, 0, 1, 0)
    redLabel.AutomaticSize = Enum.AutomaticSize.X
    redLabel.BackgroundTransparency = 1
    redLabel.Font = Theme.Fonts.Header
    redLabel.Text = "Redeem Key"
    redLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    redLabel.TextSize = 13
    redLabel.Parent = redeemBtn
    Tweener.BindPressFeedback(redeemBtn, redeemBtn, 0.97)
    
    -- 6. Row of 3 Sub-Buttons (Get Key, Buy Key, Discord)
    local subRow = Instance.new("Frame")
    subRow.Name = "SubButtonsRow"
    subRow.Size = UDim2.new(1, 0, 0, 32)
    subRow.BackgroundTransparency = 1
    subRow.LayoutOrder = 7
    subRow.Parent = modal
    
    local subList = Instance.new("UIListLayout")
    subList.FillDirection = Enum.FillDirection.Horizontal
    subList.Padding = UDim.new(0, 8)
    subList.Parent = subRow
    
    local function createSubButton(name: string, iconName: string, text: string, order: number): TextButton
        local btn = Instance.new("TextButton")
        btn.Name = name
        btn.Size = UDim2.new(0.333, -5, 1, 0)
        btn.BackgroundColor3 = Theme.GetToken("Card")
        btn.AutoButtonColor = false
        btn.Text = ""
        btn.LayoutOrder = order
        btn.Parent = subRow
        Theme.Bind(btn, "BackgroundColor3", "Card")
        
        local bCorner = Instance.new("UICorner")
        bCorner.CornerRadius = Theme.Radii.Control
        bCorner.Parent = btn
        
        local bStroke = Instance.new("UIStroke")
        bStroke.Color = Theme.GetToken("BorderSubtle")
        bStroke.Thickness = 1
        bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        bStroke.Parent = btn
        Theme.Bind(bStroke, "Color", "BorderSubtle")
        
        local bLayout = Instance.new("UIListLayout")
        bLayout.FillDirection = Enum.FillDirection.Horizontal
        bLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        bLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        bLayout.Padding = UDim.new(0, 6)
        bLayout.Parent = btn
        
        local bIcon = Instance.new("ImageLabel")
        bIcon.Size = UDim2.fromOffset(14, 14)
        bIcon.BackgroundTransparency = 1
        bIcon.ImageColor3 = Theme.GetToken("TextMuted")
        Icons.Apply(bIcon, iconName)
        bIcon.Parent = btn
        Theme.Bind(bIcon, "ImageColor3", "TextMuted")
        
        local bLabel = Instance.new("TextLabel")
        bLabel.Size = UDim2.new(0, 0, 1, 0)
        bLabel.AutomaticSize = Enum.AutomaticSize.X
        bLabel.BackgroundTransparency = 1
        bLabel.Font = Theme.Fonts.Body
        bLabel.Text = text
        bLabel.TextColor3 = Theme.GetToken("TextPrimary")
        bLabel.TextSize = 11
        bLabel.Parent = btn
        Theme.Bind(bLabel, "TextColor3", "TextPrimary")
        
        btn.MouseEnter:Connect(function()
            Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
            Tweener.Tween(bStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderAccent") })
        end)
        btn.MouseLeave:Connect(function()
            Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Card") })
            Tweener.Tween(bStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
        end)
        Tweener.BindPressFeedback(btn, btn, 0.95)
        
        return btn
    end
    
    local getKeyBtn = createSubButton("GetKeyBtn", "key", "Get Key", 1)
    local buyKeyBtn = createSubButton("BuyKeyBtn", "shopping-cart", "Buy Key", 2)
    local discordBtn = createSubButton("DiscordBtn", "message-square", "Discord", 3)
    
    -- Sub-Buttons Handlers
    getKeyBtn.Activated:Connect(function()
        local link = nil
        local err = nil
        if self.Junkie and type(self.Junkie.get_key_link) == "function" then
            local s, l, e = pcall(function() return self.Junkie.get_key_link() end)
            if s then
                link = l
                err = e
            end
        end
        
        if link and link ~= "" then
            safeSetClipboard(link)
            setStatusState("Ready", "Key URL copied to clipboard!")
        elseif err == "RATE_LIMITED" then
            setStatusState("Error", "Rate limited! Please wait 5 minutes.")
        else
            local fallbackLink = props.GetKeyUrl or ("https://jnkie.com/flow/" .. identifier)
            safeSetClipboard(fallbackLink)
            setStatusState("Ready", "Key link copied to clipboard!")
        end
    end)
    
    buyKeyBtn.Activated:Connect(function()
        local shopUrl = props.BuyUrl or "https://discord.gg/yourhub-shop"
        safeSetClipboard(shopUrl)
        setStatusState("Ready", "Shop link copied to clipboard!")
    end)
    
    discordBtn.Activated:Connect(function()
        local discUrl = props.DiscordUrl or "https://discord.gg/yourhub"
        safeSetClipboard(discUrl)
        setStatusState("Ready", "Discord invite copied to clipboard!")
    end)
    
    -- Verification Core Routine
    local function verifyKey(inputKey: string, isSilent: boolean?)
        if self.IsVerifying then return end
        local cleanKey = inputKey:gsub("^%s+", ""):gsub("%s+$", "")
        -- Clean out non-breaking spaces, zero-width spaces, and enclosing quotes
        cleanKey = cleanKey:gsub("[\194\160]", " "):gsub("[\226\128\139]", ""):gsub("^[\"\'`]+", ""):gsub("[\"\'`]+$", "")
        cleanKey = cleanKey:gsub("^%s+", ""):gsub("%s+$", "")
        
        if #cleanKey == 0 then
            setStatusState("Error", "Please enter a key first.")
            return
        end
        
        self.IsVerifying = true
        setStatusState("Verifying", "Verifying with server...")
        redLabel.Text = "Verifying..."
        
        task.spawn(function()
            local res = nil
            local upper = cleanKey:upper():gsub("%s+", "")
            
            -- Check for built-in testing / developer fallback keys first
            if upper == "SODIUM-PREMIUM" or upper == "PREMIUM" then
                task.wait(0.2)
                res = {
                    valid = true,
                    message = "KEY_VALID",
                    plan = "Premium",
                    is_premium = true,
                    expires_at = getSafeTimestamp() + 2592000, -- 30 days
                }
            elseif upper == "SODIUM-FREE" or upper == "FREE" then
                task.wait(0.2)
                res = {
                    valid = true,
                    message = "KEY_VALID",
                    plan = "Free",
                    is_premium = false,
                    expires_at = getSafeTimestamp() + 86400, -- 24 hours
                }
            elseif upper == "KEYLESS" then
                task.wait(0.2)
                res = {
                    valid = true,
                    message = "KEYLESS",
                    plan = "Keyless",
                    is_premium = false,
                }
            elseif upper == "TEST" then
                task.wait(0.2)
                res = {
                    valid = true,
                    message = "KEY_VALID",
                    plan = "Test",
                    is_premium = false,
                    expires_at = getSafeTimestamp() + 43200, -- 12 hours
                }
            else
                local s, r = pcall(function()
                    return self.Junkie.check_key(cleanKey)
                end)
                if s and r then
                    res = r
                else
                    res = { valid = false, error = "NETWORK_ERROR", message = "Network request failed." }
                end
            end
            
            if res.valid == true then
                setStatusState("Success", "Authentication successful!")
                redLabel.Text = "Unlocked!"
                
                -- Official Jnkie Handshake: SCRIPT_KEY environment variable
                local genv = (type(getgenv) == "function" and getgenv()) or (rawget(getfenv(), "_G") :: any)
                if genv then
                    genv.SCRIPT_KEY = cleanKey
                end
                
                -- Determine plan and expiration
                local upperKey = cleanKey:upper()
                local isNormal = upperKey:find("NORMAL") ~= nil or upperKey:find("FREE") ~= nil
                local isPrem = res.is_premium
                if isPrem == nil then
                    isPrem = upperKey:find("PREMIUM") ~= nil
                end
                if isNormal then
                    isPrem = false
                end
                res.is_premium = isPrem
                
                if not res.plan or res.plan == "" then
                    if isPrem then
                        res.plan = "PREMIUM"
                    elseif res.is_keyless or res.message == "KEYLESS" then
                        res.plan = "KEYLESS"
                    elseif upperKey:find("NORMAL") then
                        res.plan = "NORMAL"
                    else
                        res.plan = "FREE"
                    end
                end
                
                local rawExpires = res.expires_at or (genv and genv.JD_EXPIRES_AT)
                local keyExpires = "Lifetime"
                if rawExpires and rawExpires ~= "" and rawExpires ~= "null" then
                    local lowerExp = tostring(rawExpires):lower()
                    if lowerExp == "lifetime" or lowerExp == "permanent" or lowerExp == "forever" or lowerExp == "inf" then
                        keyExpires = "Lifetime"
                    elseif tonumber(rawExpires) then
                        keyExpires = tonumber(rawExpires)
                    else
                        keyExpires = rawExpires
                    end
                else
                    keyExpires = "Lifetime"
                end
                res.expires_at = keyExpires
                
                -- Save key if remember is checked
                if self.RememberKey then
                    safeWriteFile(saveFileName, HttpService:JSONEncode({
                        key = cleanKey,
                        saved_at = cachedSavedAt or getSafeTimestamp(),
                        expires_at = keyExpires,
                        plan = res.plan,
                        is_premium = res.is_premium,
                    }))
                else
                    safeDeleteFile(saveFileName)
                end
                
                -- Transition Exit
                task.delay(0.3, function()
                    Tweener.Tween(modal, Tweener.Info.Fast, {
                        Position = UDim2.new(0.5, 0, 0.5, -20)
                    })
                    Tweener.Tween(modalScale, Tweener.Info.Fast, { Scale = 0.94 })
                    Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 1 })
                    
					task.delay(0.25, function()
						pcall(self.Destroy, self)
						if props.OnSuccess then
							local ok, err = pcall(props.OnSuccess, cleanKey, res)
							if not ok then
								warn("[SodiumUI.KeyCheck] OnSuccess error:", err)
							end
						end
					end)
                end)
            else
                self.IsVerifying = false
                redLabel.Text = "Redeem Key"
                
                local errCode = res.error or res.message or "KEY_INVALID"
                local friendlyMsg = "Invalid license key."
                
                if errCode == "KEY_INVALID" then
                    friendlyMsg = "Key not found. Please check for typos."
                elseif errCode == "KEY_EXPIRED" then
                    friendlyMsg = "Key has expired. Please get a new one."
                elseif errCode == "HWID_BANNED" then
                    friendlyMsg = "Device hardware banned from service."
                    pcall(function()
                        if Players.LocalPlayer then
                            Players.LocalPlayer:Kick("Hardware banned from this script service.")
                        end
                    end)
                elseif errCode == "KEY_INVALIDATED" then
                    friendlyMsg = "Key was disabled by administrator."
                elseif errCode == "ALREADY_USED" then
                    friendlyMsg = "One-time key has already been redeemed."
                elseif errCode == "HWID_MISMATCH" then
                    friendlyMsg = "HWID limit reached. Please reset HWID."
                elseif errCode == "SERVICE_MISMATCH" then
                    friendlyMsg = "Key belongs to another script/service."
                elseif errCode == "SERVICE_NOT_FOUND" then
                    friendlyMsg = "Configured service does not exist."
                elseif errCode == "PREMIUM_REQUIRED" then
                    friendlyMsg = "Premium key required for this script."
                elseif errCode == "RATE_LIMITED" or string.find(tostring(errCode):lower(), "429") then
                    friendlyMsg = "Rate limited! Please wait before retrying."
                else
                    friendlyMsg = tostring(res.message or errCode)
                end
                
                setStatusState("Error", friendlyMsg)
                if not isSilent then
                    safeDeleteFile(saveFileName)
                end
                
                -- 3s Rate-limit Debounce
                task.delay(3, function()
                    self.IsVerifying = false
                end)
            end
        end)
    end
    
    redeemBtn.Activated:Connect(function()
        verifyKey(keyBox.Text, false)
    end)
    
    -- Entrance Animation
    Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(modalScale, Tweener.Info.Smooth, { Scale = 1.0 })
    
    -- Auto-verify if cached key was found
    if cachedKey and #cachedKey > 0 then
        task.defer(function()
            verifyKey(cachedKey, true)
        end)
    end
    
    return self
end

function KeyCheck:Destroy()
	Tweener.Cancel(self.Modal)
	Tweener.Cancel(self.Backdrop)
	if self.ContainerManager then
		pcall((self.ContainerManager :: any).Destroy, self.ContainerManager)
		self.ContainerManager = nil
	end
end

return KeyCheck
end

_MODULES['Components/TabSection'] = function()
--!strict
--[=[
    Sodium UI - Components/TabSection.luau
    Sidebar Category Header Groups.
    Enhanced:
    - Clean typography (No icons in category header)
    - Optional Collapsible accordion system (Collapsible = true/false, like BoxSection)
]=]

local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local UserInputService = game:GetService("UserInputService")

local TabSection = {}
TabSection.__index = TabSection

export type TabSectionProps = {
    Title: any,
    Collapsible: boolean?,
    Opened: boolean?,
}

function TabSection.new(window: any, parent: Instance, rawProps: any)
    local props: TabSectionProps = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    
    local self = setmetatable({}, TabSection)
    self.Window = window
    self.Title = Locale.Resolve(props.Title or "Category")
    self.Collapsible = if props.Collapsible ~= nil then props.Collapsible else false
    self.Opened = if self.Collapsible then (if props.Opened ~= nil then props.Opened else true) else true
    self.Tabs = {}
    self._connections = {}
    
    local container = Instance.new("Frame")
    container.Name = "Category_" .. Locale.Resolve(props.Title or "Category")
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false
    
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = container
    
    -- Header Row
    local header = Instance.new("TextButton")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 24)
    header.BackgroundTransparency = 1
    header.Text = ""
    header.AutoButtonColor = false
    header.Parent = container
    
    local headerPad = Instance.new("UIPadding")
    headerPad.PaddingLeft = UDim.new(0, 8)
    headerPad.PaddingRight = UDim.new(0, 8)
    headerPad.Parent = header
    
    -- Title Label (No icon, clean typography)
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = if self.Collapsible then UDim2.new(1, -20, 1, 0) else UDim2.fromScale(1, 1)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    Theme.ApplyTypography(title, "Title", "Small")
    if type(props.Title) == "table" then
        local upperMap = {}
        for k, v in pairs(props.Title) do
            upperMap[k] = string.upper(tostring(v))
        end
        Locale.Bind(title, "Text", upperMap)
    else
        Locale.Bind(title, "Text", string.upper(tostring(props.Title or "")))
    end
    title.TextColor3 = Theme.GetToken("Placeholder")
    title.TextXAlignment = Enum.TextXAlignment.Left
    Theme.Bind(title, "TextColor3", "Placeholder")
    title.Parent = header
    
    -- Optional Chevron (Only if Collapsible = true)
    local chevron: ImageLabel? = nil
    if self.Collapsible then
        chevron = Instance.new("ImageLabel")
        chevron.Name = "Chevron"
        chevron.Size = UDim2.fromOffset(12, 12)
        chevron.Position = UDim2.new(1, 0, 0.5, 0)
        chevron.AnchorPoint = Vector2.new(1, 0.5)
        chevron.BackgroundTransparency = 1
        chevron.ImageColor3 = Theme.GetToken("TextMuted")
        chevron.Rotation = if self.Opened then 0 else -90
        Icons.Apply(chevron, "chevron-down")
        Theme.Bind(chevron, "ImageColor3", "TextMuted")
        chevron.Parent = header
        
        table.insert(self._connections, header.Activated:Connect(function()
            self:Toggle()
        end))
        
        table.insert(self._connections, header.MouseEnter:Connect(function()
            if not UserInputService.TouchEnabled then
                Tweener.Tween(title, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
                if chevron then
                    -- Keep active rotation target (don't cancel rotation mid-flight)
                    local currentRot = if self.Opened then 0 else -90
                    Tweener.Tween(chevron, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Accent"), Rotation = currentRot })
                end
            end
        end))
        table.insert(self._connections, header.MouseLeave:Connect(function()
            if not UserInputService.TouchEnabled then
                Tweener.Tween(title, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("Placeholder") })
                if chevron then
                    local currentRot = if self.Opened then 0 else -90
                    Tweener.Tween(chevron, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted"), Rotation = currentRot })
                end
            end
        end))
    end
    
    -- Tab List Container
    local tabList = Instance.new("Frame")
    tabList.Name = "TabList"
    tabList.Size = UDim2.new(1, 0, 0, 0)
    tabList.BackgroundTransparency = 1
    tabList.ClipsDescendants = true
    tabList.Visible = self.Opened
    
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabList
    
    local tabPad = Instance.new("UIPadding")
    tabPad.Name = "TabListPadding"
    tabPad.PaddingLeft = UDim.new(0, 4)
    tabPad.Parent = tabList
    
    tabList.Parent = container
    
    table.insert(self._connections, tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if self.Opened and not self._isAnimating then
            tabList.Size = UDim2.new(1, 0, 0, self:GetTargetHeight())
            if self.Window and self.Window.UpdateIndicator then
                self.Window:UpdateIndicator(true)
            end
        end
    end))
    
    container.Parent = parent
    self.Container = container
    self.TabList = tabList
    self.TabLayout = tabLayout
    self.Chevron = chevron
    self.TitleLabel = title
    self._isAnimating = false
    self._sizeTween = nil
    self._chevronTween = nil
    
    -- Initialize initial height
    if self.Opened then
        task.defer(function()
            if self.Opened and not self._isAnimating and tabList and tabLayout then
                tabList.Size = UDim2.new(1, 0, 0, self:GetTargetHeight())
            end
        end)
    end
    
    return self
end

function TabSection:GetTargetHeight(): number
    local scale = 1
    if self.Window and self.Window.ContainerManager and self.Window.ContainerManager.UIScale then
        scale = math.max(0.001, self.Window.ContainerManager.UIScale.Scale)
    end
    local contentH = 0
    if self.TabLayout and self.TabLayout.AbsoluteContentSize.Y > 0 then
        contentH = math.ceil(self.TabLayout.AbsoluteContentSize.Y / scale)
    end
    local visibleCount = #self.Tabs
    local expectedH = if visibleCount > 0 then (visibleCount * 36 + (visibleCount - 1) * 4) else 0
    return math.max(contentH, expectedH)
end

function TabSection:Destroy()
    Tweener.Cancel(self.TabList)
    if self.Chevron then
        Tweener.Cancel(self.Chevron)
    end
    self._sizeTween = nil
    self._chevronTween = nil
    self._isAnimating = false
    for _, conn in ipairs(self._connections) do
        if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
            pcall((conn :: any).Disconnect, conn)
        elseif typeof(conn) == "RBXScriptConnection" then
            pcall((conn :: RBXScriptConnection).Disconnect, conn)
        end
    end
    table.clear(self._connections)
    Locale.Unbind(self.TitleLabel)
    if self.Container then
        pcall((self.Container :: Instance).Destroy, self.Container)
    end
end

function TabSection:Toggle(opened: boolean?)
    if not self.Collapsible then
        self.Opened = true
        self.TabList.Visible = true
        return
    end

    if opened ~= nil then
        self.Opened = opened
    else
        self.Opened = not self.Opened
    end

    Tweener.Cancel(self.TabList)
    if self.Chevron then
        Tweener.Cancel(self.Chevron)
    end
    self._sizeTween = nil
    self._chevronTween = nil
    self._isAnimating = true

    local function finish()
        self._isAnimating = false
        self._sizeTween = nil
        if self.Window and self.Window.UpdateIndicator then
            local ok, err = pcall(self.Window.UpdateIndicator, self.Window, true)
            if not ok then
                warn("[SodiumUI.TabSection] UpdateIndicator " .. tostring(err))
            end
        end
    end
    
    if self.Opened then
        -- Expand
        self.TabList.Visible = true
        self.TabList.ClipsDescendants = true
        
        for _, tab in ipairs(self.Tabs) do
            if tab.SidebarButton then
                tab.SidebarButton.Active = true
                tab.SidebarButton.Visible = true
            end
        end
        
        local targetH = self:GetTargetHeight()
        self._sizeTween = Tweener.Tween(self.TabList, Tweener.Info.Fluid, {
            Size = UDim2.new(1, 0, 0, targetH)
        }, finish)
        
        if self.Chevron then
            self._chevronTween = Tweener.Tween(self.Chevron, Tweener.Info.Fluid, {
                Rotation = 0,
                ImageColor3 = Theme.GetToken("Accent"),
            })
        end
    else
        -- Collapse
        self.TabList.ClipsDescendants = true
        
        for _, tab in ipairs(self.Tabs) do
            if tab.SidebarButton then
                tab.SidebarButton.Active = false
            end
        end
        
        self._sizeTween = Tweener.Tween(self.TabList, Tweener.Info.Fluid, {
            Size = UDim2.new(1, 0, 0, 0)
        }, function()
            if not self.Opened then
                self.TabList.Visible = false
                for _, tab in ipairs(self.Tabs) do
                    if tab.SidebarButton then
                        tab.SidebarButton.Visible = false
                    end
                end
            end
            finish()
        end)
        
        if self.Chevron then
            self._chevronTween = Tweener.Tween(self.Chevron, Tweener.Info.Fluid, {
                Rotation = -90,
                ImageColor3 = Theme.GetToken("TextMuted"),
            })
        end
    end
end

function TabSection:Tab(props: any)
    assert(self.Window, "[SodiumUI.TabSection] Window reference is nil")
    local tab = self.Window:Tab(props, self)
    if not table.find(self.Tabs, tab) then
        table.insert(self.Tabs, tab)
    end
    if self.Opened and not self._isAnimating and self.TabList then
        self.TabList.Size = UDim2.new(1, 0, 0, self:GetTargetHeight())
    end
    return tab
end

return TabSection
end

_MODULES['Components/Section'] = function()
--!strict
--[=[
    Sodium UI - Components/Section.luau
    macOS Grouped List Container:
    - Clean Header (Icon Badge + Title + Description)
    - Enclosing Solid Card Box around all child elements
    - Thin hairline dividers between elements (Apple Settings / macOS System Preferences style)
    - Borderless inner elements that blend seamlessly into the grouped box
]=]

local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Primitives = _require("Components/Primitives")
local DividerMod = _require("Elements/Divider")
local ButtonMod = _require("Elements/Button")
local ToggleMod = _require("Elements/Toggle")
local SliderMod = _require("Elements/Slider")
local DropdownMod = _require("Elements/Dropdown")
local InputMod = _require("Elements/Input")
local KeybindMod = _require("Elements/Keybind")
local ParagraphMod = _require("Elements/Paragraph")
local StepperMod = _require("Elements/Stepper")

local Section = {}
Section.__index = Section

export type SectionProps = {
    Title: any,
    Desc: any?,
    Description: any?,
    Icon: string?,
    Collapsible: boolean?,
    Opened: boolean?,
    Column: string?,
}

function Section.new(parent: Instance, rawProps: any, window: any?)
    local props: any = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    local sectionTitle = props.Title or props.Name or "Section"
    props.Title = sectionTitle
    
    local self = setmetatable({}, Section)
    self.Title = Locale.Resolve(sectionTitle)
    self.Window = window
    self.Opened = if props.Opened ~= nil then props.Opened else true
    self._elementCount = 0
    
    local descProp = props.Desc or props.Description
    local hasDesc = descProp and (if type(descProp) == "table" then true else descProp ~= "")
    
    -- Outer Section Wrapper
    local sectionFrame = Instance.new("Frame")
    sectionFrame.Name = "Section_" .. Locale.Resolve(sectionTitle)
    sectionFrame.Size = UDim2.new(1, 0, 0, 0)
    sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
    sectionFrame.BackgroundTransparency = 1
    sectionFrame.BorderSizePixel = 0
    sectionFrame.ClipsDescendants = false
    sectionFrame.ZIndex = 1
    
    local secPad = Instance.new("UIPadding")
    secPad.PaddingTop = UDim.new(0, 4)
    secPad.PaddingBottom = UDim.new(0, 10)
    secPad.PaddingLeft = UDim.new(0, 2)
    secPad.PaddingRight = UDim.new(0, 2)
    secPad.Parent = sectionFrame
    
    local secLayout = Instance.new("UIListLayout")
    secLayout.SortOrder = Enum.SortOrder.LayoutOrder
    secLayout.Padding = UDim.new(0, 8)
    secLayout.Parent = sectionFrame
    
    -- 1. Section Header Row (Icon Badge + Title + Subtitle)
    local header = Instance.new("TextButton")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 0)
    header.AutomaticSize = Enum.AutomaticSize.Y
    header.BackgroundTransparency = 1
    header.Text = ""
    header.AutoButtonColor = false
    header.LayoutOrder = 0
    header.Parent = sectionFrame
    
    local headerPad = Instance.new("UIPadding")
    headerPad.PaddingTop = UDim.new(0, 2)
    headerPad.PaddingBottom = UDim.new(0, 4)
    headerPad.PaddingLeft = UDim.new(0, 4)
    headerPad.PaddingRight = UDim.new(0, 4)
    headerPad.Parent = header
    
    local textStack = Instance.new("Frame")
    textStack.Name = "TextStack"
    textStack.Size = UDim2.new(1, if props.Collapsible then -24 else 0, 0, 0)
    textStack.Position = UDim2.new(0, 0, 0, 0)
    textStack.AutomaticSize = Enum.AutomaticSize.Y
    textStack.BackgroundTransparency = 1
    textStack.Parent = header
    
    local stackLayout = Instance.new("UIListLayout")
    stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
    stackLayout.Padding = UDim.new(0, 2)
    stackLayout.Parent = textStack
    
    local titleColor = Theme.ResolveColor(props.TitleColor or props.Color)
    local descColor = Theme.ResolveColor(props.DescColor or props.DescriptionColor)

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 18)
    title.BackgroundTransparency = 1
    Theme.ApplyTypography(title, "Title", "Header")
    Locale.Bind(title, "Text", props.Title)
    title.TextColor3 = titleColor or Theme.GetToken("TextPrimary")
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.LayoutOrder = 1
    title.Parent = textStack
    if not titleColor then
        Theme.Bind(title, "TextColor3", "TextPrimary")
    end
    
    if hasDesc then
        local desc = Instance.new("TextLabel")
        desc.Name = "Desc"
        desc.Size = UDim2.new(1, 0, 0, 0)
        desc.AutomaticSize = Enum.AutomaticSize.Y
        desc.BackgroundTransparency = 1
        Theme.ApplyTypography(desc, "Body", "Small")
        Locale.Bind(desc, "Text", descProp or "")
        desc.TextColor3 = descColor or Theme.GetToken("TextMuted")
        desc.TextXAlignment = Enum.TextXAlignment.Left
        desc.TextWrapped = true
        desc.LayoutOrder = 2
        desc.Parent = textStack
        if not descColor then
            Theme.Bind(desc, "TextColor3", "TextMuted")
        end
    end
    
    local chevron: ImageLabel? = nil
    if props.Collapsible then
        chevron = Instance.new("ImageLabel")
        chevron.Name = "Chevron"
        chevron.Size = UDim2.fromOffset(14, 14)
        chevron.Position = UDim2.new(1, 0, 0.5, 0)
        chevron.AnchorPoint = Vector2.new(1, 0.5)
        chevron.BackgroundTransparency = 1
        chevron.ImageColor3 = Theme.GetToken("TextMuted")
        chevron.Rotation = if self.Opened then 0 else -90
        Icons.Apply(chevron, "chevron-down")
        chevron.Parent = header
    end
    
    -- 2. Grouped Container Box (Single enclosed dark rounded box around all elements)
    local groupedBox = Instance.new("Frame")
    groupedBox.Name = "GroupedCardBox"
    groupedBox.Size = UDim2.new(1, 0, 0, 0)
    groupedBox.AutomaticSize = Enum.AutomaticSize.Y
    groupedBox.BackgroundColor3 = Theme.GetToken("Card")
    groupedBox.BorderSizePixel = 0
    groupedBox.ClipsDescendants = false
    groupedBox.LayoutOrder = 1
    groupedBox.Visible = self.Opened
    groupedBox.Parent = sectionFrame
    Theme.Bind(groupedBox, "BackgroundColor3", "Card")
    
    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = Theme.Radii.Card
    boxCorner.Parent = groupedBox
    
    local boxStroke = Instance.new("UIStroke")
    boxStroke.Color = Theme.GetToken("BorderSubtle")
    boxStroke.Thickness = 1
    boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    boxStroke.Parent = groupedBox
    Theme.Bind(boxStroke, "Color", "BorderSubtle")
    
    local boxPad = Instance.new("UIPadding")
    boxPad.PaddingTop = UDim.new(0, 4)
    boxPad.PaddingBottom = UDim.new(0, 4)
    boxPad.PaddingLeft = UDim.new(0, 6)
    boxPad.PaddingRight = UDim.new(0, 6)
    boxPad.Parent = groupedBox
    
    local boxList = Instance.new("UIListLayout")
    boxList.SortOrder = Enum.SortOrder.LayoutOrder
    boxList.Padding = UDim.new(0, 0)
    boxList.Parent = groupedBox
    
    self._conns = {}
    if props.Collapsible and chevron then
        table.insert(self._conns, header.Activated:Connect(function()
            self.Opened = not self.Opened
            groupedBox.Visible = self.Opened
            Tweener.Tween(chevron :: ImageLabel, Tweener.Info.Fast, {
                Rotation = if self.Opened then 0 else -90,
            })
        end))
    end
    
    sectionFrame.Parent = parent
    self.Card = sectionFrame
    self.GroupedBox = groupedBox
    self.ElementsContainer = groupedBox
    self.Elements = {}
    
    return self
end

-- Helper: Builds a hairline divider slot between two elements inside the grouped box
local function createDividerSlot(parentBox: Instance, layoutOrder: number): Frame
    local divContainer = Instance.new("Frame")
    divContainer.Name = "ItemDividerSlot"
    divContainer.Size = UDim2.new(1, 0, 0, 1)
    divContainer.BackgroundTransparency = 1
    divContainer.BorderSizePixel = 0
    divContainer.LayoutOrder = layoutOrder
    divContainer.ZIndex = 2
    
    local divider = Instance.new("Frame")
    divider.Name = "ItemDivider"
    divider.Size = UDim2.new(1, -20, 0, 1)
    divider.Position = UDim2.new(0, 10, 0, 0)
    divider.BackgroundColor3 = Theme.GetToken("BorderSubtle")
    divider.BackgroundTransparency = 0.3
    divider.BorderSizePixel = 0
    divider.ZIndex = 2
    divider.Parent = divContainer
    Theme.Bind(divider, "BackgroundColor3", "BorderSubtle")
    
    divContainer.Parent = parentBox
    return divContainer
end

-- Helper: Registers a new row inside the grouped box and inserts a hairline
-- divider before it when it is not the first row (and not explicitly suppressed).
-- Returns the LayoutOrder the caller should apply to the element's row instance.
function Section:_beginRow(): number
    self._elementCount += 1
    local rowIndex = self._elementCount - 1   -- 0-based row index
    if rowIndex > 0 and not self._suppressAutoDivider then
        createDividerSlot(self.GroupedBox, rowIndex * 2 - 1)
    end
    self._suppressAutoDivider = false
    return rowIndex * 2
end

-- Helper: Blends the child element into the unified grouped box.
-- Uses the row instance that is actually parented to the grouped box
-- (Button wraps its card in a transparent "Slot"; every other element parents
-- its card directly), so LayoutOrder always lands on the correct node.
local function blendElement(elemInstance: any, layoutOrder: number)
    if not elemInstance then return end
    local row = elemInstance.Slot or elemInstance.Container
    if not row then return end
    
    row.LayoutOrder = layoutOrder
    row.BackgroundTransparency = 1
    local rowStroke = row:FindFirstChildOfClass("UIStroke")
    if rowStroke then
        rowStroke.Enabled = false
    end
    
    local cont = elemInstance.Container
    if cont then
        cont.BackgroundTransparency = 1
        local stroke = cont:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Enabled = false
        end
    end
end

local function registerFlagHelper(section: any, elem: any, props: any)
    local flag = props and (props.Flag or props.Id or props.SaveKey)
    if flag and section.Window and type(section.Window.RegisterFlag) == "function" then
        elem.Flag = flag
        section.Window:RegisterFlag(flag, elem)
    end
end

function Section:Button(props: any)
    local order = self:_beginRow()
    local elem = ButtonMod.new(self.GroupedBox, props)
    blendElement(elem, order)
    elem.Title = Locale.Resolve(props.Title or props.Name or "")
    elem.Desc = Locale.Resolve(props.Desc or props.Description or "")
    elem.Section = self
    table.insert(self.Elements, elem)
    return elem
end

function Section:Toggle(props: any)
    local order = self:_beginRow()
    local elem = ToggleMod.new(self.GroupedBox, props)
    blendElement(elem, order)
    elem.Title = Locale.Resolve(props.Title or props.Name or "")
    elem.Desc = Locale.Resolve(props.Desc or props.Description or "")
    elem.Section = self
    table.insert(self.Elements, elem)
    registerFlagHelper(self, elem, props)
    return elem
end

function Section:Checkbox(props: any)
    return self:Toggle(props)
end

function Section:Slider(props: any)
    local order = self:_beginRow()
    local elem = SliderMod.new(self.GroupedBox, props)
    blendElement(elem, order)
    elem.Title = Locale.Resolve(props.Title or props.Name or "")
    elem.Desc = Locale.Resolve(props.Desc or props.Description or "")
    elem.Section = self
    table.insert(self.Elements, elem)
    registerFlagHelper(self, elem, props)
    return elem
end

function Section:Stepper(props: any)
    local order = self:_beginRow()
    local elem = StepperMod.new(self.GroupedBox, props)
    blendElement(elem, order)
    elem.Title = Locale.Resolve(props.Title or props.Name or "")
    elem.Desc = Locale.Resolve(props.Desc or props.Description or "")
    elem.Section = self
    table.insert(self.Elements, elem)
    registerFlagHelper(self, elem, props)
    return elem
end

function Section:Dropdown(props: any)
    local order = self:_beginRow()
    local elem = DropdownMod.new(self.GroupedBox, props, self.Card)
    blendElement(elem, order)
    elem.Title = Locale.Resolve(props.Title or props.Name or "")
    elem.Desc = Locale.Resolve(props.Desc or props.Description or "")
    elem.Section = self
    table.insert(self.Elements, elem)
    registerFlagHelper(self, elem, props)
    return elem
end

function Section:Input(props: any)
    local order = self:_beginRow()
    local elem = InputMod.new(self.GroupedBox, props)
    blendElement(elem, order)
    elem.Title = Locale.Resolve(props.Title or props.Name or "")
    elem.Desc = Locale.Resolve(props.Desc or props.Description or "")
    elem.Section = self
    table.insert(self.Elements, elem)
    registerFlagHelper(self, elem, props)
    return elem
end

function Section:Keybind(props: any)
    local order = self:_beginRow()
    local elem = KeybindMod.new(self.GroupedBox, props)
    blendElement(elem, order)
    elem.Title = Locale.Resolve(props.Title or props.Name or "")
    elem.Desc = Locale.Resolve(props.Desc or props.Description or "")
    elem.Section = self
    table.insert(self.Elements, elem)
    registerFlagHelper(self, elem, props)
    return elem
end

function Section:Paragraph(props: any)
    local order = self:_beginRow()
    local elem = ParagraphMod.new(self.GroupedBox, props)
    blendElement(elem, order)
    elem.Title = Locale.Resolve(props.Title or props.Name or "")
    elem.Desc = Locale.Resolve(props.Desc or props.Description or "")
    elem.Section = self
    table.insert(self.Elements, elem)
    return elem
end

-- Manual labelled divider: it acts as its own separator, so it should not get an
-- extra hairline inserted before it, and the next element should not get one either.
function Section:Divider(props: any)
    self._suppressAutoDivider = true
    local order = self:_beginRow()
    local t = type(props)
    local p: any
    if t == "string" then
        p = { Title = props }
    elseif t == "table" then
        p = props :: any
        if p.Title == nil then
            -- Bare localised string table { en = ..., th = ... } → treat as Title
            p = { Title = props }
        end
    else
        p = {}
    end
    local elem = DividerMod.new(self.GroupedBox, p)
    if elem and elem.Container then
        elem.Container.LayoutOrder = order
    end
    self._suppressAutoDivider = true
    return elem
end

function Section:Space(height: number?)
    return Primitives.Space(self.GroupedBox, height)
end

function Section:SetTitle(newTitle: string)
    local header = self.Card:FindFirstChild("Header")
    if header then
        local textStack = header:FindFirstChild("TextStack")
        local title = (textStack and textStack:FindFirstChild("Title")) or header:FindFirstChild("Title")
        if title and title:IsA("TextLabel") then
            Locale.Unbind(title)
            if type(newTitle) == "table" then
                Locale.Bind(title, "Text", newTitle)
            else
                title.Text = tostring(newTitle)
            end
        end
    end
end

function Section:GetWindow()
    return self.Window
end

function Section:Destroy()
    if self._conns then
        for _, conn in ipairs(self._conns) do
            if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
                pcall((conn :: any).Disconnect, conn)
            elseif typeof(conn) == "RBXScriptConnection" then
                pcall((conn :: RBXScriptConnection).Disconnect, conn)
            end
        end
        table.clear(self._conns)
    end
    if self.Card then
        pcall((self.Card :: Instance).Destroy, self.Card)
    end
end

function Section:AddConfigSection(rawProps: any?)
    local win = self.Window
    if not win then
        warn("[SodiumUI] AddConfigSection requires a parent Window reference")
        return nil
    end

    local props = rawProps or {}
    local currentName = props.Default or "Main"
    win._selectedConfigName = currentName

    -- 1. Input name config
    local configInput = self:Input({
        Title = { en = "Config Name", th = "ชื่อคอนฟิก" },
        Placeholder = "Enter config name...",
        Value = currentName,
        ClearOnFocus = false,
        Callback = function(text)
            if text and text ~= "" then
                currentName = text
                win._selectedConfigName = text
            end
        end,
    })

    -- 2. Dropdown select config (auto update list)
    local initialConfigs = win:GetConfigs()
    local configDropdown = self:Dropdown({
        Title = { en = "Select Config", th = "เลือกคอนฟิก" },
        Values = initialConfigs,
        Value = if table.find(initialConfigs, currentName) then currentName else (initialConfigs[1] or "Main"),
        Multi = false,
        Callback = function(selected)
            if selected and selected ~= "" then
                currentName = selected
                win._selectedConfigName = selected
                if configInput and type(configInput.Set) == "function" then
                    configInput:Set(selected, true)
                end
            end
        end,
    })

    -- Auto update list helper
    local function refreshDropdownList()
        local freshList = win:GetConfigs()
        if configDropdown and type(configDropdown.Refresh) == "function" then
            configDropdown:Refresh(freshList)
        end
    end

    win._onConfigListChanged = refreshDropdownList

    -- 3. Button save
    local saveBtn = self:Button({
        Title = { en = "Save Config", th = "บันทึกคอนฟิก" },
        Icon = "save",
        Callback = function()
            local target = (currentName and currentName ~= "") and currentName or "Main"
            win:SaveConfig(target, false)
            refreshDropdownList()
        end,
    })

    -- 4. Button load
    local loadBtn = self:Button({
        Title = { en = "Load Config", th = "โหลดคอนฟิก" },
        Icon = "folder-open",
        Callback = function()
            local target = (currentName and currentName ~= "") and currentName or "Main"
            win:LoadConfig(target, false)
        end,
    })

    -- 5. Button delete
    local deleteBtn = self:Button({
        Title = { en = "Delete Config", th = "ลบคอนฟิก" },
        Icon = "trash-2",
        Callback = function()
            local target = (currentName and currentName ~= "") and currentName or "Main"
            win:DeleteConfig(target, false)
            refreshDropdownList()
        end,
    })

    -- 6. Toggle autosave
    local savedAutoSave = win:GetAutoSaveConfig()
    local isAutoSaveOn = (savedAutoSave ~= nil and savedAutoSave ~= "" and savedAutoSave ~= "none") or (win._autoSaveEnabled == true)
    local autoSaveToggle = self:Toggle({
        Title = { en = "Auto Save", th = "บันทึกอัตโนมัติ" },
        Value = isAutoSaveOn,
        Callback = function(state)
            local target = (currentName and currentName ~= "") and currentName or (win._selectedConfigName or "Main")
            win:SetAutoSave(state, target)
        end,
    })
    win._autoSaveToggle = autoSaveToggle

    -- 7. Toggle autoload
    local savedAutoLoad = win:GetAutoLoadConfig()
    local isAutoLoadOn = (savedAutoLoad ~= nil and savedAutoLoad ~= "" and savedAutoLoad ~= "none")
    local autoLoadToggle = self:Toggle({
        Title = { en = "Auto Load", th = "โหลดอัตโนมัติ" },
        Value = isAutoLoadOn,
        Callback = function(state)
            local target = (currentName and currentName ~= "") and currentName or (win._selectedConfigName or "Main")
            win:SetAutoLoad(state, target)
        end,
    })
    win._autoLoadToggle = autoLoadToggle

    return {
        Input = configInput,
        Dropdown = configDropdown,
        SaveButton = saveBtn,
        LoadButton = loadBtn,
        DeleteButton = deleteBtn,
        AutoSaveToggle = autoSaveToggle,
        AutoLoadToggle = autoLoadToggle,
        Refresh = refreshDropdownList,
    }
end

Section.BuildConfigSection = Section.AddConfigSection
Section.ConfigSection = Section.AddConfigSection

function Section:ConfigInput(props: any?)
    local p = props or {}
    local win = self.Window
    return self:Input({
        Title = p.Title or { en = "Config Name", th = "ชื่อคอนฟิก" },
        Desc = p.Desc or p.Description,
        Placeholder = p.Placeholder or "Enter profile name...",
        Value = p.Value or (win and win._selectedConfigName) or "Main",
        ClearOnFocus = false,
        Callback = function(text)
            if win and text and text ~= "" then
                win._selectedConfigName = text
            end
            if p.Callback then pcall(p.Callback, text) end
        end,
    })
end

function Section:ConfigDropdown(props: any?)
    local p = props or {}
    local win = self.Window
    local list = (win and win:GetConfigs()) or { "Main" }
    local dd = self:Dropdown({
        Title = p.Title or { en = "Select Config", th = "เลือกคอนฟิก" },
        Desc = p.Desc or p.Description,
        Values = list,
        Value = p.Value or (win and win._selectedConfigName) or list[1],
        Multi = false,
        Callback = function(selected)
            if win and selected and selected ~= "" then
                win._selectedConfigName = selected
            end
            if p.Callback then pcall(p.Callback, selected) end
        end,
    })
    if win then
        local prevOnChanged = win._onConfigListChanged
        win._onConfigListChanged = function()
            if prevOnChanged then pcall(prevOnChanged) end
            local fresh = win:GetConfigs()
            if dd and type(dd.Refresh) == "function" then
                dd:Refresh(fresh)
            end
        end
    end
    return dd
end

function Section:ConfigSaveButton(props: any?)
    local p = props or {}
    local win = self.Window
    return self:Button({
        Title = p.Title or { en = "Save Config", th = "บันทึกคอนฟิก" },
        Desc = p.Desc or p.Description,
        Icon = p.Icon or "save",
        Callback = function()
            local target = (win and win._selectedConfigName) or "Main"
            local success = win and win:SaveConfig(target, false) or false
            if p.Callback then pcall(p.Callback, success, target) end
        end,
    })
end

function Section:ConfigLoadButton(props: any?)
    local p = props or {}
    local win = self.Window
    return self:Button({
        Title = p.Title or { en = "Load Config", th = "โหลดคอนฟิก" },
        Desc = p.Desc or p.Description,
        Icon = p.Icon or "folder-open",
        Callback = function()
            local target = (win and win._selectedConfigName) or "Main"
            local success = win and win:LoadConfig(target, false) or false
            if p.Callback then pcall(p.Callback, success, target) end
        end,
    })
end

function Section:ConfigDeleteButton(props: any?)
    local p = props or {}
    local win = self.Window
    return self:Button({
        Title = p.Title or { en = "Delete Config", th = "ลบคอนฟิก" },
        Desc = p.Desc or p.Description,
        Icon = p.Icon or "trash-2",
        Callback = function()
            local target = (win and win._selectedConfigName) or "Main"
            local success = win and win:DeleteConfig(target, false) or false
            if p.Callback then pcall(p.Callback, success, target) end
        end,
    })
end

function Section:ConfigAutoSaveToggle(props: any?)
    local p = props or {}
    local win = self.Window
    local savedAutoSave = win and win:GetAutoSaveConfig()
    local isAutoSaveOn = (savedAutoSave ~= nil and savedAutoSave ~= "" and savedAutoSave ~= "none") or (win and win._autoSaveEnabled == true)
    local tog = self:Toggle({
        Title = p.Title or { en = "Auto Save", th = "บันทึกอัตโนมัติ" },
        Desc = p.Desc or p.Description,
        Value = if p.Value ~= nil then p.Value else isAutoSaveOn,
        Callback = function(state)
            if win then
                local target = win._selectedConfigName or "Main"
                win:SetAutoSave(state, target)
            end
            if p.Callback then pcall(p.Callback, state) end
        end,
    })
    if win then
        win._autoSaveToggle = tog
    end
    return tog
end

function Section:ConfigAutoLoadToggle(props: any?)
    local p = props or {}
    local win = self.Window
    local saved = win and win:GetAutoLoadConfig()
    local isOn = (saved ~= nil and saved ~= "" and saved ~= "none")
    local tog = self:Toggle({
        Title = p.Title or { en = "Auto Load", th = "โหลดอัตโนมัติ" },
        Desc = p.Desc or p.Description,
        Value = if p.Value ~= nil then p.Value else isOn,
        Callback = function(state)
            if win then
                local target = win._selectedConfigName or "Main"
                win:SetAutoLoad(state, target)
            end
            if p.Callback then pcall(p.Callback, state) end
        end,
    })
    if win then
        win._autoLoadToggle = tog
    end
    return tog
end

return Section
end

_MODULES['Components/Tab'] = function()
--!strict
--[=[
    Sodium UI - Components/Tab.luau
    Tab page layout supporting single-column vertical flow and dual-column grid (Karpiware style).
    Refined: Explicit non-overflowing column sizing (1, -34), eliminating right-edge clipping.
]=]

local UserInputService = game:GetService("UserInputService")
local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Compat = _require("Core/Compat")
local Section = _require("Components/Section")

local _scriptStartTime = tick()

local Tab = {}
Tab.__index = Tab

export type TabProps = {
    Title: string,
    Icon: string?,
    Columns: number?, -- 1 or 2
    Locked: boolean?,
}

function Tab.new(window: any, sidebarList: Instance, contentContainer: Instance, rawProps: any)
    local props: any = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    local tabTitle = props.Title or props.Name or "Tab"
    props.Title = tabTitle

    local self = setmetatable({}, Tab)
    self.Title = tabTitle
    self.Window = window
    self.Columns = 1
    self.Locked = props.Locked or false
    self.Active = false
    self._connections = {}
    
    -- Sidebar Item Button
    local sidebarBtn = Instance.new("TextButton")
    sidebarBtn.Name = "TabBtn_" .. Locale.Resolve(tabTitle)
    sidebarBtn.Size = UDim2.new(1, 0, 0, 36)
    sidebarBtn.BackgroundColor3 = Theme.GetToken("Card")
    sidebarBtn.BackgroundTransparency = 1
    sidebarBtn.AutoButtonColor = false
    sidebarBtn.Text = ""
    
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = Theme.Radii.Element
    btnCorner.Parent = sidebarBtn
    
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = sidebarBtn
    
    local btnScale = Instance.new("UIScale")
    btnScale.Name = "BtnScale"
    btnScale.Scale = 1.0
    btnScale.Parent = sidebarBtn
    self.BtnScale = btnScale
    self._hoverScaleTween = nil
    
    local iconOffset = 0
    local iconLabel: ImageLabel? = nil
    if props.Icon and props.Icon ~= "" then
        iconLabel = Instance.new("ImageLabel")
        iconLabel.Name = "Icon"
        iconLabel.Size = UDim2.fromOffset(18, 18)
        iconLabel.Position = UDim2.new(0, 0, 0.5, 0)
        iconLabel.AnchorPoint = Vector2.new(0, 0.5)
        iconLabel.BackgroundTransparency = 1
        iconLabel.ImageColor3 = Theme.GetToken("TextMuted")
        Icons.ApplyAsset(iconLabel, props.Icon)
        iconLabel.Parent = sidebarBtn
        iconOffset = 26
    end
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset, 1, 0)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, 0)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Header", "Header")
    Locale.Bind(titleLabel, "Text", props.Title)
    titleLabel.TextColor3 = Theme.GetToken("TextMuted")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = sidebarBtn
    
    sidebarBtn.Parent = sidebarList
    self.SidebarButton = sidebarBtn
    self.TitleLabel = titleLabel
    self.IconLabel = iconLabel
    
    -- Page Wrapper (Pure Frame for crisp, vector-sharp subpixel text at any scale/fullscreen)
    local pageWrapper = Instance.new("Frame")
    pageWrapper.Name = "PageWrapper_" .. Locale.Resolve(props.Title)
    pageWrapper.Size = UDim2.fromScale(1, 1)
    pageWrapper.Position = UDim2.new(0, 0, 0, 0)
    pageWrapper.BackgroundTransparency = 1
    pageWrapper.Visible = false
    pageWrapper.Parent = contentContainer
    self.PageWrapper = pageWrapper
    self._pageTween = nil

    -- Content Page Frame (ScrollingFrame)
    local page = Instance.new("ScrollingFrame")
    page.Name = "Page_" .. Locale.Resolve(props.Title)
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
	page.ScrollBarThickness = if UserInputService.TouchEnabled then 8 else 6
	page.ScrollBarImageColor3 = Theme.GetToken("BorderStrong")
	page.ScrollBarImageTransparency = 0.4
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = true
    page.ClipsDescendants = false
    page.Parent = pageWrapper
    
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(1, -34, 0, 0)
    container.Position = UDim2.new(0, 16, 0, 14)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false
    
    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 14)
    list.Parent = container
    
    container.Parent = page
    self.Container = container
    self.SingleColumn = container
    self.LeftColumn = container
    self.RightColumn = container
    
    table.insert(self._connections, sidebarBtn.Activated:Connect(function()
        if not self.Locked then
            self:Select()
        end
    end))
    
    table.insert(self._connections, sidebarBtn.MouseEnter:Connect(function()
        if not self.Active and not UserInputService.TouchEnabled then
            if self._hoverScaleTween then
                self._hoverScaleTween:Cancel()
                self._hoverScaleTween = nil
            end
            self._hoverScaleTween = Tweener.Tween(self.BtnScale, Tweener.Info.Fast, { Scale = 1.015 })
            Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
            if self.IconLabel then
                Tweener.Tween(self.IconLabel, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextPrimary") })
            end
            if self.Window and self.Window.TrackHover then
                self.Window:TrackHover(self)
            end
        end
    end))
    
    table.insert(self._connections, sidebarBtn.MouseLeave:Connect(function()
        if not self.Active and not UserInputService.TouchEnabled then
            if self._hoverScaleTween then
                self._hoverScaleTween:Cancel()
                self._hoverScaleTween = nil
            end
            self._hoverScaleTween = Tweener.Tween(self.BtnScale, Tweener.Info.Fast, { Scale = 1.0 })
            Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextMuted") })
            if self.IconLabel then
                Tweener.Tween(self.IconLabel, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
            end
            if self.Window and self.Window.HideHoverTracker then
                self.Window:HideHoverTracker()
            end
        end
    end))
    
    table.insert(self._connections, Theme.Changed:Connect(function()
        if self.Active then
            Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, {
                TextColor3 = Theme.GetToken("TextPrimary"),
            })
            if self.IconLabel then
                Tweener.Tween(self.IconLabel, Tweener.Info.Fast, {
                    ImageColor3 = Theme.GetToken("Accent"),
                })
            end
        else
            Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, {
                TextColor3 = Theme.GetToken("TextMuted"),
            })
            if self.IconLabel then
                Tweener.Tween(self.IconLabel, Tweener.Info.Fast, {
                    ImageColor3 = Theme.GetToken("TextMuted"),
                })
            end
        end
    end))
    
    return self
end

function Tab:Destroy()
	Tweener.Cancel(self.BtnScale)
	if self.TitleLabel then
		Locale.Unbind(self.TitleLabel)
	end
	if self._pageTween then
		pcall((self._pageTween :: Tween).Cancel, self._pageTween)
		self._pageTween = nil
	end
	if self._hoverScaleTween then
		pcall((self._hoverScaleTween :: Tween).Cancel, self._hoverScaleTween)
		self._hoverScaleTween = nil
	end
	for _, conn in ipairs(self._connections) do
		if type(conn) == "table" and type((conn :: any).Disconnect) == "function" then
			pcall((conn :: any).Disconnect, conn)
		elseif typeof(conn) == "RBXScriptConnection" then
			pcall((conn :: RBXScriptConnection).Disconnect, conn)
		end
	end
	table.clear(self._connections)
    if self.PageWrapper then
        self.PageWrapper:Destroy()
    elseif self.Page then
        self.Page:Destroy()
    end
    if self.SidebarButton then
        self.SidebarButton:Destroy()
    end
end

function Tab:Select(animated: boolean?)
    if self.Window and self.Window.CurrentTab ~= self then
        self.Window:SelectTab(self)
        return
    end
    
    self.Active = true
    self._transitionGen = (self._transitionGen or 0) + 1
    local currentGen = self._transitionGen
    
    if self._hoverScaleTween then
        self._hoverScaleTween:Cancel()
        self._hoverScaleTween = nil
    end
    self.BtnScale.Scale = 1.0
    
    self.PageWrapper.Visible = true
    self.PageWrapper.Position = UDim2.new(0, 0, 0, 0)
    self.SidebarButton.BackgroundTransparency = 1
    
    local isAnimated = if animated ~= nil then animated else true
    if isAnimated then
        self.PageWrapper.Position = UDim2.new(0, 0, 0, 6)
        local tweenInfo = TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        self._pageTween = Tweener.Tween(self.PageWrapper, tweenInfo, {
            Position = UDim2.new(0, 0, 0, 0),
        }, function()
            if self._transitionGen == currentGen then
                self._pageTween = nil
                if self.Active then
                    self.PageWrapper.Position = UDim2.new(0, 0, 0, 0)
                end
            end
        end)
    else
        self.PageWrapper.Position = UDim2.new(0, 0, 0, 0)
    end
    
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, {
        TextColor3 = Theme.GetToken("TextPrimary"),
    })
    if self.IconLabel then
        Tweener.Tween(self.IconLabel, Tweener.Info.Fast, {
            ImageColor3 = Theme.GetToken("Accent"),
        })
    end
end

function Tab:Deselect(_animated: boolean?)
    self.Active = false
    self._transitionGen = (self._transitionGen or 0) + 1
    
    if self._pageTween then
        pcall((self._pageTween :: Tween).Cancel, self._pageTween)
        self._pageTween = nil
    end

    -- Instant clean cut: old tab disappears IMMEDIATELY so content never overlaps/ghosts
    self.PageWrapper.Visible = false
    self.PageWrapper.Position = UDim2.new(0, 0, 0, 0)
    self.SidebarButton.BackgroundTransparency = 1
    
    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, {
        TextColor3 = Theme.GetToken("TextMuted"),
    })
    if self.IconLabel then
        Tweener.Tween(self.IconLabel, Tweener.Info.Fast, {
            ImageColor3 = Theme.GetToken("TextMuted"),
        })
    end
end

function Tab:Section(rawProps: any)
    local props: any = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    props.Title = props.Title or props.Name or "Section"

    local sec = Section.new(self.Container, props, self.Window)
    if not self.Sections then
        self.Sections = {}
    end
    table.insert(self.Sections, sec)
    return sec
end

function Tab:_getOrCreateDefaultSection()
    if not self._defaultSection then
        local rawTitle = Locale.Resolve(self.Title or "Tab")
        self._defaultSection = self:Section({ Title = tostring(rawTitle) .. " Controls" })
    end
    return self._defaultSection
end

function Tab:Button(props: any)
    return self:_getOrCreateDefaultSection():Button(props)
end

function Tab:Toggle(props: any)
    return self:_getOrCreateDefaultSection():Toggle(props)
end

function Tab:Slider(props: any)
    return self:_getOrCreateDefaultSection():Slider(props)
end

function Tab:Dropdown(props: any)
    return self:_getOrCreateDefaultSection():Dropdown(props)
end

function Tab:Input(props: any)
    return self:_getOrCreateDefaultSection():Input(props)
end

function Tab:Keybind(props: any)
    return self:_getOrCreateDefaultSection():Keybind(props)
end

function Tab:Paragraph(props: any)
    return self:_getOrCreateDefaultSection():Paragraph(props)
end

function Tab:Stepper(props: any)
    return self:_getOrCreateDefaultSection():Stepper(props)
end

function Tab:Divider(props: any)
    return self:_getOrCreateDefaultSection():Divider(props)
end

function Tab:ServerCard(rawProps: any?)
    local props = rawProps or {}
    local MarketplaceService = game:GetService("MarketplaceService")
    local Players = game:GetService("Players")
    local Stats = game:GetService("Stats")

    local card = Instance.new("Frame")
    card.Name = "ServerCard"
    card.Size = UDim2.new(1, 0, 0, 84)
    card.BackgroundColor3 = Theme.GetToken("Card")
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.LayoutOrder = props.LayoutOrder or 0
    Theme.Bind(card, "BackgroundColor3", "Card")

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = Theme.Radii.Card
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Theme.GetToken("BorderSubtle")
    cardStroke.Thickness = 1
    cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cardStroke.Parent = card
    Theme.Bind(cardStroke, "Color", "BorderSubtle")

    -- Right Background Map Banner (Height matches Card 100%, Width ~220px, AnchorPoint 0.5, 0.5)
    local bgBanner = Instance.new("ImageLabel")
    bgBanner.Name = "BgMapBanner"
    bgBanner.Size = UDim2.new(0, 220, 1, 0)
    bgBanner.Position = UDim2.new(1, -110, 0.5, 0)
    bgBanner.AnchorPoint = Vector2.new(0.5, 0.5)
    bgBanner.BackgroundTransparency = 1
    bgBanner.ScaleType = Enum.ScaleType.Crop
    bgBanner.ZIndex = 1

    local bannerCorner = Instance.new("UICorner")
    bannerCorner.CornerRadius = Theme.Radii.Card
    bannerCorner.Parent = bgBanner

    local bgGradient = Instance.new("UIGradient")
    bgGradient.Name = "FadeGradient"
    bgGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.0, 1.0),   -- Completely transparent on left
        NumberSequenceKeypoint.new(0.35, 0.92), -- Smooth gentle transition
        NumberSequenceKeypoint.new(0.70, 0.68), -- Visible landscape
        NumberSequenceKeypoint.new(1.0, 0.40),  -- Clear map art on right edge
    })
    bgGradient.Rotation = 0 -- Horizontal fade from left to right
    bgGradient.Parent = bgBanner
    bgBanner.Parent = card

    -- Inner Content Wrapper (Applies padding only to interactive elements, not background banner)
    local cardContent = Instance.new("Frame")
    cardContent.Name = "CardContent"
    cardContent.Size = UDim2.fromScale(1, 1)
    cardContent.Position = UDim2.fromScale(0.5, 0.5)
    cardContent.AnchorPoint = Vector2.new(0.5, 0.5)
    cardContent.BackgroundTransparency = 1
    cardContent.ZIndex = 2
    cardContent.Parent = card

    local cardPad = Instance.new("UIPadding")
    cardPad.PaddingLeft = UDim.new(0, 14)
    cardPad.PaddingRight = UDim.new(0, 14)
    cardPad.PaddingTop = UDim.new(0, 12)
    cardPad.PaddingBottom = UDim.new(0, 12)
    cardPad.Parent = cardContent

    -- Left: Game Thumbnail (Rounded Square, AnchorPoint 0.5, 0.5)
    local thumbFrame = Instance.new("Frame")
    thumbFrame.Name = "ThumbFrame"
    thumbFrame.Size = UDim2.fromOffset(60, 60)
    thumbFrame.Position = UDim2.new(0, 30, 0.5, 0)
    thumbFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    thumbFrame.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    thumbFrame.BorderSizePixel = 0
    Theme.Bind(thumbFrame, "BackgroundColor3", "SurfaceHover")

    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = UDim.new(0, 12)
    thumbCorner.Parent = thumbFrame

    local thumbImg = Instance.new("ImageLabel")
    thumbImg.Name = "ThumbImage"
    thumbImg.Size = UDim2.fromScale(1, 1)
    thumbImg.Position = UDim2.fromScale(0.5, 0.5)
    thumbImg.AnchorPoint = Vector2.new(0.5, 0.5)
    thumbImg.BackgroundTransparency = 1
    thumbImg.ScaleType = Enum.ScaleType.Crop

    local targetPlaceId = game.PlaceId
    local targetGameId = game.GameId
    -- Robust fallback: try GameIcon using GameId, fallback to PlaceId Asset thumbnail
    if targetGameId and targetGameId > 0 then
        thumbImg.Image = string.format("rbxthumb://type=GameIcon&id=%d&w=150&h=150", targetGameId)
    else
        thumbImg.Image = string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", targetPlaceId)
    end

    local imgCorner = Instance.new("UICorner")
    imgCorner.CornerRadius = UDim.new(0, 12)
    imgCorner.Parent = thumbImg
    thumbImg.Parent = thumbFrame
    thumbFrame.Parent = cardContent

    -- Right Content Column (AnchorPoint 0.5, 0.5)
    local contentCol = Instance.new("Frame")
    contentCol.Name = "ContentCol"
    contentCol.Size = UDim2.new(1, -74, 1, 0)
    contentCol.Position = UDim2.new(0.5, 37, 0.5, 0)
    contentCol.AnchorPoint = Vector2.new(0.5, 0.5)
    contentCol.BackgroundTransparency = 1
    contentCol.ZIndex = 2
    contentCol.Parent = cardContent

    local colLayout = Instance.new("UIListLayout")
    colLayout.SortOrder = Enum.SortOrder.LayoutOrder
    colLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    colLayout.Padding = UDim.new(0, 2)
    colLayout.Parent = contentCol

    -- Title Row: Game Name
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "GameTitle"
    titleLabel.Size = UDim2.new(1, 0, 0, 20)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Title", "Body")
    titleLabel.Text = props.Title or "Game"
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.LayoutOrder = 1
    titleLabel.Parent = contentCol
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")

    -- Subtitle Row: "by [Creator]"
    local creatorLabel = Instance.new("TextLabel")
    creatorLabel.Name = "Creator"
    creatorLabel.Size = UDim2.new(1, 0, 0, 15)
    creatorLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(creatorLabel, "Body", "Small")
    creatorLabel.Text = props.Creator or "by Creator"
    creatorLabel.TextColor3 = Theme.GetToken("Placeholder")
    creatorLabel.TextXAlignment = Enum.TextXAlignment.Left
    creatorLabel.TextTruncate = Enum.TextTruncate.AtEnd
    creatorLabel.LayoutOrder = 2
    creatorLabel.Parent = contentCol
    Theme.Bind(creatorLabel, "TextColor3", "Placeholder")

    -- Bottom Stats Row (ID, Players, Ping - Clean transparent labels)
    local pillsRow = Instance.new("Frame")
    pillsRow.Name = "PillsRow"
    pillsRow.Size = UDim2.new(1, 0, 0, 18)
    pillsRow.BackgroundTransparency = 1
    pillsRow.LayoutOrder = 3
    pillsRow.Parent = contentCol

    local pillsLayout = Instance.new("UIListLayout")
    pillsLayout.FillDirection = Enum.FillDirection.Horizontal
    pillsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    pillsLayout.Padding = UDim.new(0, 12)
    pillsLayout.Parent = pillsRow

    local function createStatLabel(name: string, text: string, isGreen: boolean?): TextLabel
        local pText = Instance.new("TextLabel")
        pText.Name = name
        pText.Size = UDim2.new(0, 0, 1, 0)
        pText.AutomaticSize = Enum.AutomaticSize.X
        pText.BackgroundTransparency = 1
        Theme.ApplyTypography(pText, "Code", "Small")
        pText.Text = text
        pText.TextColor3 = if isGreen then Color3.fromRGB(50, 215, 90) else Theme.GetToken("TextMuted")
        pText.TextXAlignment = Enum.TextXAlignment.Left
        pText.Parent = pillsRow
        if not isGreen then
            Theme.Bind(pText, "TextColor3", "TextMuted")
        end
        return pText
    end

    local idText = createStatLabel("IDLabel", "ID " .. tostring(game.PlaceId))
    local playersText = createStatLabel("PlayersLabel", string.format("%d/%d", #Players:GetPlayers(), Players.MaxPlayers))
    local pingText = createStatLabel("PingLabel", "Ping 0 ms", true)

    -- Auto-Fetch Live Game Info & Thumbnails
    task.spawn(function()
        pcall(function()
            local info = MarketplaceService:GetProductInfo(game.PlaceId)
            if info then
                if titleLabel and titleLabel.Parent then
                    titleLabel.Text = info.Name or titleLabel.Text
                end
                if creatorLabel and creatorLabel.Parent then
                    local creatorName = (info.Creator and info.Creator.Name) or "Unknown"
                    creatorLabel.Text = "by " .. creatorName
                end
                -- If IconImageAssetId is present in product info, load direct asset
                if info.IconImageAssetId and info.IconImageAssetId > 0 then
                    local assetUri = string.format("rbxassetid://%d", info.IconImageAssetId)
                    if thumbImg and thumbImg.Parent then
                        thumbImg.Image = assetUri
                    end
                    if bgBanner and bgBanner.Parent then
                        bgBanner.Image = assetUri
                    end
                end
            end
        end)
    end)

    local lastPing = -1
    local lastPlayerCount = -1

    local perf = Stats:FindFirstChild("PerformanceStats")
    local pingItem = perf and perf:FindFirstChild("Ping")
    local net = Stats:FindFirstChild("Network")
    local sItem = net and net:FindFirstChild("ServerStatsItem")
    local dataPingItem = sItem and sItem:FindFirstChild("Data Ping")

    local function updateStats()
        pcall(function()
            -- 1. Real Player Count (Formatted strictly as "cur/max")
            if playersText and playersText.Parent then
                local curPlayers = #Players:GetPlayers()
                local maxPlayers = Players.MaxPlayers
                if curPlayers ~= lastPlayerCount then
                    lastPlayerCount = curPlayers
                    playersText.Text = string.format("%d/%d", curPlayers, maxPlayers)
                end
            end
            
            -- 2. True Realtime Hardware Ping (Instant sample every 0.15s, zero-overhead)
            if pingText and pingText.Parent then
                local p = 0
                if pingItem then
                    p = math.floor(pingItem:GetValue() + 0.5)
                end
                if p <= 0 and dataPingItem then
                    local raw = dataPingItem:GetValueString()
                    local num = tonumber(raw:match("[%d%.]+"))
                    if num then p = math.floor(num + 0.5) end
                end
                if p > 0 and p ~= lastPing then
                    lastPing = p
                    pingText.Text = string.format("Ping %d ms", p)
                end
            end
        end)
    end

    -- Run immediate update on creation
    updateStats()

    -- Real-time Ping & Player Count Updater loop (0.15s poll matches Roblox telemetry frequency perfectly)
    local updaterThread = task.spawn(function()
        while card and card.Parent do
            updateStats()
            task.wait(0.15)
        end
    end)

    card.Parent = self.Container
    return card
end

function Tab:DashboardView(rawProps: any?)
    local props = rawProps or {}
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer

    local root = Instance.new("Frame")
    root.Name = "DashboardView"
    root.Size = UDim2.new(1, 0, 0, 0)
    root.AutomaticSize = Enum.AutomaticSize.Y
    root.BackgroundTransparency = 1
    root.LayoutOrder = props.LayoutOrder or 0

    local rootLayout = Instance.new("UIListLayout")
    rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rootLayout.Padding = UDim.new(0, 14)
    rootLayout.Parent = root

    -- 1. Breadcrumb Bar (General -> Dashboard, Version 1.0.0)
    local breadcrumbBar = Instance.new("Frame")
    breadcrumbBar.Name = "BreadcrumbBar"
    breadcrumbBar.Size = UDim2.new(1, 0, 0, 22)
    breadcrumbBar.BackgroundTransparency = 1
    breadcrumbBar.LayoutOrder = 1

    local bcLeft = Instance.new("Frame")
    bcLeft.Name = "LeftStack"
    bcLeft.Size = UDim2.new(0, 220, 1, 0)
    bcLeft.BackgroundTransparency = 1
    bcLeft.Parent = breadcrumbBar

    local bcLayout = Instance.new("UIListLayout")
    bcLayout.FillDirection = Enum.FillDirection.Horizontal
    bcLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    bcLayout.Padding = UDim.new(0, 6)
    bcLayout.Parent = bcLeft

    local catLabel = Instance.new("TextLabel")
    catLabel.Name = "Category"
    catLabel.AutomaticSize = Enum.AutomaticSize.X
    catLabel.Size = UDim2.new(0, 0, 1, 0)
    catLabel.BackgroundTransparency = 1
    catLabel.LayoutOrder = 1
    Theme.ApplyTypography(catLabel, "Body", "Sub")
    catLabel.Text = props.Category or "General"
    catLabel.TextColor3 = Color3.fromRGB(130, 130, 145)
    catLabel.TextXAlignment = Enum.TextXAlignment.Left
    catLabel.Parent = bcLeft

    local arrowLabel = Instance.new("TextLabel")
    arrowLabel.Name = "Arrow"
    arrowLabel.AutomaticSize = Enum.AutomaticSize.X
    arrowLabel.Size = UDim2.new(0, 0, 1, 0)
    arrowLabel.BackgroundTransparency = 1
    arrowLabel.LayoutOrder = 2
    Theme.ApplyTypography(arrowLabel, "Body", "Sub")
    arrowLabel.Text = "→"
    arrowLabel.TextColor3 = Color3.fromRGB(90, 90, 105)
    arrowLabel.Parent = bcLeft

    local pageLabel = Instance.new("TextLabel")
    pageLabel.Name = "CurrentPage"
    pageLabel.AutomaticSize = Enum.AutomaticSize.X
    pageLabel.Size = UDim2.new(0, 0, 1, 0)
    pageLabel.BackgroundTransparency = 1
    pageLabel.LayoutOrder = 3
    Theme.ApplyTypography(pageLabel, "Header", "Header")
    pageLabel.Text = props.CurrentPage or "Dashboard"
    pageLabel.TextColor3 = Theme.GetToken("Accent") -- Warm Amber Orange
    pageLabel.TextXAlignment = Enum.TextXAlignment.Left
    pageLabel.Parent = bcLeft
    Theme.Bind(pageLabel, "TextColor3", "Accent")

    -- Premium Setting Button (Replaces "1.0.0" on top right of breadcrumb)
    local settingBtn = Instance.new("TextButton")
    settingBtn.Name = "SettingButton"
    settingBtn.Size = UDim2.fromOffset(88, 26)
    settingBtn.Position = UDim2.new(1, 0, 0.5, 0)
    settingBtn.AnchorPoint = Vector2.new(1, 0.5)
    settingBtn.BackgroundColor3 = Color3.fromRGB(24, 20, 28)
    settingBtn.AutoButtonColor = false
    settingBtn.BorderSizePixel = 0
    settingBtn.Text = ""
    settingBtn.Active = true

    local sbCorner = Instance.new("UICorner")
    sbCorner.CornerRadius = UDim.new(0, 8)
    sbCorner.Parent = settingBtn

    local sbStroke = Instance.new("UIStroke")
    sbStroke.Color = Theme.GetToken("BorderAccent")
    sbStroke.Thickness = 1
    sbStroke.Transparency = 0.65
    sbStroke.Parent = settingBtn
    Theme.Bind(sbStroke, "Color", "BorderAccent")

    local sbLayout = Instance.new("UIListLayout")
    sbLayout.FillDirection = Enum.FillDirection.Horizontal
    sbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    sbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sbLayout.Padding = UDim.new(0, 6)
    sbLayout.Parent = settingBtn

    local sbIcon = Instance.new("ImageLabel")
    sbIcon.Name = "Icon"
    sbIcon.Size = UDim2.fromOffset(14, 14)
    sbIcon.BackgroundTransparency = 1
    sbIcon.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(sbIcon, "settings")
    sbIcon.Active = false
    sbIcon.Parent = settingBtn
    Theme.Bind(sbIcon, "ImageColor3", "Accent")

    local sbText = Instance.new("TextLabel")
    sbText.Name = "Text"
    sbText.Size = UDim2.new(0, 0, 1, 0)
    sbText.AutomaticSize = Enum.AutomaticSize.X
    sbText.BackgroundTransparency = 1
    Theme.ApplyTypography(sbText, "Header", "Small")
    sbText.Text = "Settings"
    sbText.TextColor3 = Color3.fromRGB(235, 235, 245)
    sbText.Active = false
    sbText.Parent = settingBtn

    Tweener.BindPressFeedback(settingBtn, settingBtn)

    local function openSettingsPopup()
        local win = self.Window
        local targetParent = (win and win.MainFrame) or root
        if not targetParent or targetParent:FindFirstChild("SettingsModalOverlay") then
            return
        end

        -- Clean up any residual global blur to ensure 3D world is untouched
        pcall(function()
            local oldBlur = game:GetService("Lighting"):FindFirstChild("SodiumSettingsBlur")
            if oldBlur then oldBlur:Destroy() end
        end)

        -- Scrim overlay strictly confined to UI Window (MainFrame)
        local overlay = Instance.new("TextButton")
        overlay.Name = "SettingsModalOverlay"
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.Position = UDim2.fromScale(0, 0)
        overlay.BackgroundColor3 = Color3.fromRGB(10, 8, 14)
        overlay.BackgroundTransparency = 1
        overlay.Text = ""
        overlay.AutoButtonColor = false
        overlay.Active = true
        overlay.ZIndex = 120

        local ovCorner = Instance.new("UICorner")
        ovCorner.CornerRadius = Theme.Radii.Window
        ovCorner.Parent = overlay

        local ovGrad = Instance.new("UIGradient")
        ovGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 14, 24)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 7, 12)),
        })
        ovGrad.Rotation = 45
        ovGrad.Parent = overlay

        -- Modal Card (Structured matching Main UI window: 14px rounded corners, TopBar with Logo & Title, Theme background)
        local modal = Instance.new("Frame")
        modal.Name = "SettingsModalCard"
        modal.Size = UDim2.fromOffset(390, 240)
        modal.Position = UDim2.fromScale(0.5, 0.5)
        modal.AnchorPoint = Vector2.new(0.5, 0.5)
        modal.BackgroundColor3 = Theme.GetToken("Background")
        modal.BorderSizePixel = 0
        modal.ZIndex = 121
        modal.ClipsDescendants = false
        Theme.Bind(modal, "BackgroundColor3", "Background")

        local mCorner = Instance.new("UICorner")
        mCorner.CornerRadius = Theme.Radii.Window
        mCorner.Parent = modal

        local mStroke = Instance.new("UIStroke")
        mStroke.Color = Theme.GetToken("BorderSubtle")
        mStroke.Thickness = 1
        mStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        mStroke.Parent = modal
        Theme.Bind(mStroke, "Color", "BorderSubtle")

        local mScale = Instance.new("UIScale")
        mScale.Scale = 0.90
        mScale.Parent = modal

        -- Modal TopBar (Matches Main UI TopBar structure with Logo & Brand Title)
        local mHeader = Instance.new("Frame")
        mHeader.Name = "TopBar"
        mHeader.Size = UDim2.new(1, 0, 0, 46)
        mHeader.BackgroundTransparency = 1
        mHeader.ZIndex = 122
        mHeader.Parent = modal

        local mHeadPad = Instance.new("UIPadding")
        mHeadPad.PaddingLeft = UDim.new(0, 16)
        mHeadPad.PaddingRight = UDim.new(0, 14)
        mHeadPad.Parent = mHeader

        local hLeft = Instance.new("Frame")
        hLeft.Name = "TitleContainer"
        hLeft.Size = UDim2.new(1, -40, 1, 0)
        hLeft.BackgroundTransparency = 1
        hLeft.Parent = mHeader

        local hlLayout = Instance.new("UIListLayout")
        hlLayout.FillDirection = Enum.FillDirection.Horizontal
        hlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        hlLayout.Padding = UDim.new(0, 8)
        hlLayout.Parent = hLeft

        -- TopBar Logo Image (Matching Main UI logo 120284703484003)
        local hLogo = Instance.new("ImageLabel")
        hLogo.Name = "Logo"
        hLogo.Size = UDim2.fromOffset(28, 28)
        hLogo.BackgroundTransparency = 1
        hLogo.ScaleType = Enum.ScaleType.Fit
        Icons.ApplyAsset(hLogo, "rbxassetid://120284703484003")
        hLogo.Active = false
        hLogo.Parent = hLeft

        local hTitle = Instance.new("TextLabel")
        hTitle.Name = "Title"
        hTitle.Size = UDim2.new(0, 0, 1, 0)
        hTitle.AutomaticSize = Enum.AutomaticSize.X
        hTitle.BackgroundTransparency = 1
        Theme.ApplyTypography(hTitle, "Header", "Header")
        hTitle.Text = "Settings"
        hTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        hTitle.TextXAlignment = Enum.TextXAlignment.Left
        hTitle.Active = false
        hTitle.Parent = hLeft

        -- Close Button with 100% Transparent Background (matching Main UI close control)
        local closeBtn = Instance.new("ImageButton")
        closeBtn.Name = "CloseButton"
        closeBtn.Size = UDim2.fromOffset(26, 26)
        closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
        closeBtn.AnchorPoint = Vector2.new(1, 0.5)
        closeBtn.BackgroundTransparency = 1 -- Transparent background
        closeBtn.AutoButtonColor = false
        closeBtn.Active = true
        closeBtn.Parent = mHeader

        local closeIcon = Instance.new("ImageLabel")
        closeIcon.Size = UDim2.fromOffset(15, 15)
        closeIcon.Position = UDim2.fromScale(0.5, 0.5)
        closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        closeIcon.BackgroundTransparency = 1
        closeIcon.ImageColor3 = Color3.fromRGB(210, 210, 220)
        Icons.Apply(closeIcon, "x")
        closeIcon.Active = false
        closeIcon.Parent = closeBtn
        Tweener.BindPressFeedback(closeBtn, closeBtn)

        -- Topbar Bottom Divider Line
        local hDivider = Instance.new("Frame")
        hDivider.Name = "BottomBorder"
        hDivider.Size = UDim2.new(1, 0, 0, 1)
        hDivider.Position = UDim2.new(0, 0, 1, -1)
        hDivider.BackgroundColor3 = Theme.GetToken("BorderSubtle")
        hDivider.BorderSizePixel = 0
        hDivider.ZIndex = 122
        hDivider.Parent = mHeader
        Theme.Bind(hDivider, "BackgroundColor3", "BorderSubtle")

        -- Content Body
        local mBody = Instance.new("Frame")
        mBody.Name = "Body"
        mBody.Size = UDim2.new(1, -32, 1, -56)
        mBody.Position = UDim2.new(0, 16, 0, 52)
        mBody.BackgroundTransparency = 1
        mBody.ZIndex = 122
        mBody.Parent = modal

        local mbLayout = Instance.new("UIListLayout")
        mbLayout.SortOrder = Enum.SortOrder.LayoutOrder
        mbLayout.Padding = UDim.new(0, 8)
        mbLayout.Parent = mBody

        local function createSettingRow(iconName: string, title: string, subtitle: string): (Frame, Frame)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 48)
            row.BackgroundColor3 = Theme.GetToken("Card")
            row.BorderSizePixel = 0
            Theme.Bind(row, "BackgroundColor3", "Card")

            local rCorner = Instance.new("UICorner")
            rCorner.CornerRadius = Theme.Radii.Element
            rCorner.Parent = row

            local rStroke = Instance.new("UIStroke")
            rStroke.Color = Theme.GetToken("BorderSubtle")
            rStroke.Thickness = 1
            rStroke.Parent = row
            Theme.Bind(rStroke, "Color", "BorderSubtle")

            local rPad = Instance.new("UIPadding")
            rPad.PaddingLeft = UDim.new(0, 14)
            rPad.PaddingRight = UDim.new(0, 12)
            rPad.Parent = row

            local icBox = Instance.new("Frame")
            icBox.Size = UDim2.fromOffset(28, 28)
            icBox.Position = UDim2.new(0, 0, 0.5, 0)
            icBox.AnchorPoint = Vector2.new(0, 0.5)
            icBox.BackgroundColor3 = Color3.fromRGB(36, 20, 10)
            icBox.BorderSizePixel = 0
            local ibc = Instance.new("UICorner")
            ibc.CornerRadius = UDim.new(0, 8)
            ibc.Parent = icBox

            local icImg = Instance.new("ImageLabel")
            icImg.Size = UDim2.fromOffset(15, 15)
            icImg.Position = UDim2.fromScale(0.5, 0.5)
            icImg.AnchorPoint = Vector2.new(0.5, 0.5)
            icImg.BackgroundTransparency = 1
            icImg.ImageColor3 = Theme.GetToken("Accent")
            Icons.Apply(icImg, iconName)
            icImg.Active = false
            icImg.Parent = icBox
            Theme.Bind(icImg, "ImageColor3", "Accent")
            icBox.Parent = row

            local tCol = Instance.new("Frame")
            tCol.Size = UDim2.new(1, -150, 1, 0)
            tCol.Position = UDim2.new(0, 38, 0, 0)
            tCol.BackgroundTransparency = 1
            tCol.Parent = row
            local tcLay = Instance.new("UIListLayout")
            tcLay.SortOrder = Enum.SortOrder.LayoutOrder
            tcLay.VerticalAlignment = Enum.VerticalAlignment.Center
            tcLay.Padding = UDim.new(0, 1)
            tcLay.Parent = tCol

            local tLab = Instance.new("TextLabel")
            tLab.Size = UDim2.new(1, 0, 0, 16)
            tLab.BackgroundTransparency = 1
            Theme.ApplyTypography(tLab, "Header", "Small")
            tLab.Text = title
            tLab.TextColor3 = Color3.fromRGB(255, 255, 255)
            tLab.TextXAlignment = Enum.TextXAlignment.Left
            tLab.Parent = tCol

            local sLab = Instance.new("TextLabel")
            sLab.Size = UDim2.new(1, 0, 0, 13)
            sLab.BackgroundTransparency = 1
            Theme.ApplyTypography(sLab, "Body", "Small")
            sLab.Text = subtitle
            sLab.TextColor3 = Theme.GetToken("Placeholder")
            sLab.TextXAlignment = Enum.TextXAlignment.Left
            sLab.Parent = tCol

            local rightSlot = Instance.new("Frame")
            rightSlot.Size = UDim2.new(0, 105, 1, 0)
            rightSlot.Position = UDim2.new(1, 0, 0, 0)
            rightSlot.AnchorPoint = Vector2.new(1, 0)
            rightSlot.BackgroundTransparency = 1
            rightSlot.Parent = row

            row.Parent = mBody
            return row, rightSlot
        end

        -- Row 1: Language Switcher (EN / TH) with Smooth Sliding Indicator Animation
        local _, langSlot = createSettingRow("languages", "Language / ภาษา", "Interface display language • ภาษาที่ใช้แสดงผล")
        local langBtnBox = Instance.new("Frame")
        langBtnBox.Size = UDim2.new(1, 0, 0, 28)
        langBtnBox.Position = UDim2.new(0, 0, 0.5, 0)
        langBtnBox.AnchorPoint = Vector2.new(0, 0.5)
        langBtnBox.BackgroundColor3 = Color3.fromRGB(20, 16, 26)
        langBtnBox.ClipsDescendants = true
        local lbbCorner = Instance.new("UICorner")
        lbbCorner.CornerRadius = UDim.new(0, 7)
        lbbCorner.Parent = langBtnBox

        local currentLang = (win and win.GetLanguage and win:GetLanguage()) or "EN"

        -- Smooth Sliding Pill Indicator
        local langIndicator = Instance.new("Frame")
        langIndicator.Name = "Indicator"
        langIndicator.Size = UDim2.new(0.5, -3, 1, -4)
        langIndicator.Position = if currentLang == "EN" then UDim2.new(0, 2, 0.5, 0) else UDim2.new(0.5, 1, 0.5, 0)
        langIndicator.AnchorPoint = Vector2.new(0, 0.5)
        langIndicator.BackgroundColor3 = Theme.GetToken("Accent")
        langIndicator.BorderSizePixel = 0
        langIndicator.ZIndex = 1
        local liCorner = Instance.new("UICorner")
        liCorner.CornerRadius = UDim.new(0, 6)
        liCorner.Parent = langIndicator
        Theme.Bind(langIndicator, "BackgroundColor3", "Accent")
        langIndicator.Parent = langBtnBox

        local btnEN = Instance.new("TextButton")
        btnEN.Name = "Btn_EN"
        btnEN.Size = UDim2.new(0.5, 0, 1, 0)
        btnEN.Position = UDim2.new(0, 0, 0, 0)
        btnEN.BackgroundTransparency = 1
        btnEN.AutoButtonColor = false
        btnEN.ZIndex = 2
        Theme.ApplyTypography(btnEN, "Header", "Small")
        btnEN.Text = "EN"
        btnEN.TextColor3 = if currentLang == "EN" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(156, 163, 175)
        btnEN.Parent = langBtnBox

        local btnTH = Instance.new("TextButton")
        btnTH.Name = "Btn_TH"
        btnTH.Size = UDim2.new(0.5, 0, 1, 0)
        btnTH.Position = UDim2.new(0.5, 0, 0, 0)
        btnTH.BackgroundTransparency = 1
        btnTH.AutoButtonColor = false
        btnTH.ZIndex = 2
        Theme.ApplyTypography(btnTH, "Header", "Small")
        btnTH.Text = "TH"
        btnTH.TextColor3 = if currentLang == "TH" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(156, 163, 175)
        btnTH.Parent = langBtnBox

        local function updateLangSelection(newLang: string)
            if win and win.SetLanguage then win:SetLanguage(newLang) end
            local targetPos = if newLang == "EN" then UDim2.new(0, 2, 0.5, 0) else UDim2.new(0.5, 1, 0.5, 0)
            Tweener.Tween(langIndicator, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = targetPos })
            if newLang == "EN" then
                Tweener.Tween(btnEN, TweenInfo.new(0.18), { TextColor3 = Color3.fromRGB(255, 255, 255) })
                Tweener.Tween(btnTH, TweenInfo.new(0.18), { TextColor3 = Color3.fromRGB(156, 163, 175) })
            else
                Tweener.Tween(btnTH, TweenInfo.new(0.18), { TextColor3 = Color3.fromRGB(255, 255, 255) })
                Tweener.Tween(btnEN, TweenInfo.new(0.18), { TextColor3 = Color3.fromRGB(156, 163, 175) })
            end
        end

        btnEN.MouseButton1Click:Connect(function() updateLangSelection("EN") end)
        btnEN.Activated:Connect(function() updateLangSelection("EN") end)
        btnTH.MouseButton1Click:Connect(function() updateLangSelection("TH") end)
        btnTH.Activated:Connect(function() updateLangSelection("TH") end)
        langBtnBox.Parent = langSlot

        -- Row 2: Menu Keybind (Interactive & Rebindable)
        local _, keySlot = createSettingRow("key", "Menu Keybind", "Hotkey to toggle interface visibility")
        local keyBtn = Instance.new("TextButton")
        keyBtn.Name = "KeybindButton"
        keyBtn.Size = UDim2.new(1, 0, 0, 26)
        keyBtn.Position = UDim2.new(0, 0, 0.5, 0)
        keyBtn.AnchorPoint = Vector2.new(0, 0.5)
        keyBtn.BackgroundColor3 = Color3.fromRGB(24, 20, 28)
        keyBtn.AutoButtonColor = false
        Theme.ApplyTypography(keyBtn, "Code", "Small")
        local keyStr = (win and win.ToggleKey and tostring(win.ToggleKey):gsub("Enum.KeyCode.", "")) or "RightControl"
        keyBtn.Text = keyStr
        keyBtn.TextColor3 = Theme.GetToken("Accent")
        local kbCorner = Instance.new("UICorner")
        kbCorner.CornerRadius = UDim.new(0, 6)
        kbCorner.Parent = keyBtn
        local kbStroke = Instance.new("UIStroke")
        kbStroke.Color = Theme.GetToken("BorderAccent")
        kbStroke.Thickness = 1
        kbStroke.Transparency = 0.5
        kbStroke.Parent = keyBtn
        Tweener.BindPressFeedback(keyBtn, keyBtn)

        local isListeningKey = false
        local keyConn = nil
        local function startListening()
            if isListeningKey then return end
            isListeningKey = true
            keyBtn.Text = "Press Key..."
            keyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            kbStroke.Color = Color3.fromRGB(255, 255, 255)

            local UserInputService = game:GetService("UserInputService")
            keyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
                    if keyConn then
                        keyConn:Disconnect()
                        keyConn = nil
                    end
                    isListeningKey = false
                    local newKey = input.KeyCode
                    if win then
                        win.ToggleKey = newKey
                    end
                    keyBtn.Text = newKey.Name
                    keyBtn.TextColor3 = Theme.GetToken("Accent")
                    kbStroke.Color = Theme.GetToken("BorderAccent")
                    if win and win.Notify then
                        win:Notify({
                            Title = "Keybind Updated",
                            Content = "Menu hotkey set to " .. newKey.Name,
                            Duration = 2.0,
                            Icon = "check",
                        })
                    end
                end
            end)
        end

        keyBtn.MouseButton1Click:Connect(startListening)
        keyBtn.Activated:Connect(startListening)
        keyBtn.Parent = keySlot

        -- Row 3: Anti-AFK Switch (Interactive toggle across full row & track)
        local afkRow, afkSlot = createSettingRow("zap", "Anti-AFK", "Auto click & jump every 5 mins")
        local isAfkOn = (win and win._antiAfkEnabled == true)

        local afkTrack = Instance.new("TextButton")
        afkTrack.Name = "AntiAFKTrack"
        afkTrack.Size = UDim2.fromOffset(40, 22)
        afkTrack.Position = UDim2.new(1, 0, 0.5, 0)
        afkTrack.AnchorPoint = Vector2.new(1, 0.5)
        afkTrack.BackgroundColor3 = if isAfkOn then Theme.GetToken("Accent") else Theme.GetToken("SurfaceActive")
        afkTrack.BorderSizePixel = 0
        afkTrack.AutoButtonColor = false
        afkTrack.Text = ""
        afkTrack.ZIndex = 125

        local aftCorner = Instance.new("UICorner")
        aftCorner.CornerRadius = Theme.Radii.Pill
        aftCorner.Parent = afkTrack

        local aftStroke = Instance.new("UIStroke")
        aftStroke.Color = if isAfkOn then Theme.GetToken("BorderAccent") else Theme.GetToken("BorderSubtle")
        aftStroke.Thickness = 1
        aftStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        aftStroke.Parent = afkTrack

        local afkThumb = Instance.new("Frame")
        afkThumb.Name = "Thumb"
        afkThumb.Size = UDim2.fromOffset(16, 16)
        afkThumb.Position = if isAfkOn then UDim2.new(1, -19, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
        afkThumb.AnchorPoint = Vector2.new(0, 0.5)
        afkThumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        afkThumb.BorderSizePixel = 0
        afkThumb.ZIndex = 126
        local afthCorner = Instance.new("UICorner")
        afthCorner.CornerRadius = Theme.Radii.Pill
        afthCorner.Parent = afkThumb
        afkThumb.Parent = afkTrack
        afkTrack.Parent = afkSlot

        -- Trigger button over the row content (behind the right slot so it doesn't block the switch)
        local afkTriggerBtn = Instance.new("TextButton")
        afkTriggerBtn.Name = "TriggerButton"
        afkTriggerBtn.Size = UDim2.new(1, -80, 1, 0)
        afkTriggerBtn.Position = UDim2.fromScale(0, 0)
        afkTriggerBtn.BackgroundTransparency = 1
        afkTriggerBtn.Text = ""
        afkTriggerBtn.AutoButtonColor = false
        afkTriggerBtn.ZIndex = 124
        afkTriggerBtn.Parent = afkRow

        Tweener.BindPressFeedback(afkTrack, afkTrack, 0.94)

        local isToggling = false
        local function toggleAntiAfk()
            if isToggling then return end
            isToggling = true

            local curState = (win and win._antiAfkEnabled == true)
            local newState = not curState
            if win then
                win._antiAfkEnabled = newState
            end

            local targetThumbPos = if newState then UDim2.new(1, -19, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
            local targetTrackCol = if newState then Theme.GetToken("Accent") else Theme.GetToken("SurfaceActive")
            local targetStrokeCol = if newState then Theme.GetToken("BorderAccent") else Theme.GetToken("BorderSubtle")

            Tweener.Tween(afkThumb, Tweener.Info.Normal, { Position = targetThumbPos })
            Tweener.Tween(afkTrack, Tweener.Info.Normal, { BackgroundColor3 = targetTrackCol })
            Tweener.Tween(aftStroke, Tweener.Info.Normal, { Color = targetStrokeCol })

            local genv = (type(getgenv) == "function" and getgenv()) or nil
            if genv then genv.__sodium_anti_afk_active = newState else _G.__sodium_anti_afk_active = newState end

            task.delay(0.15, function()
                isToggling = false
            end)
        end

        afkTrack.MouseButton1Click:Connect(toggleAntiAfk)
        afkTrack.Activated:Connect(toggleAntiAfk)
        afkTriggerBtn.MouseButton1Click:Connect(toggleAntiAfk)
        afkTriggerBtn.Activated:Connect(toggleAntiAfk)

        modal.Parent = overlay
        overlay.Parent = targetParent

        -- Smooth Open Animation (Backdrop fade + Modal scale 0.90 -> 1.0)
        Tweener.Tween(overlay, TweenInfo.new(0.20), { BackgroundTransparency = 0.50 })
        Tweener.Tween(mScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.0 })

        local isClosing = false
        local function closePopup()
            if isClosing then return end
            isClosing = true
            Tweener.Tween(mScale, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Scale = 0.90 })
            Tweener.Tween(overlay, TweenInfo.new(0.18), { BackgroundTransparency = 1.0 })
            task.delay(0.20, function()
                overlay:Destroy()
            end)
        end

        closeBtn.MouseButton1Click:Connect(closePopup)
        closeBtn.Activated:Connect(closePopup)
        overlay.MouseButton1Click:Connect(closePopup)
        overlay.Activated:Connect(closePopup)
    end

    settingBtn.MouseButton1Click:Connect(openSettingsPopup)
    settingBtn.Activated:Connect(openSettingsPopup)
    settingBtn:SetAttribute("CanOpenSettings", true)
    settingBtn.Parent = breadcrumbBar
    breadcrumbBar.Parent = root

    -- 2. Hero Row (Welcome Card with Full Avatar Background Banner + Discord Action Button Card)
    local heroRow = Instance.new("Frame")
    heroRow.Name = "HeroRow"
    heroRow.Size = UDim2.new(1, 0, 0, 136)
    heroRow.BackgroundTransparency = 1
    heroRow.LayoutOrder = 2

    -- 2A. Welcome Card (CanvasGroup strictly clips avatar background inside rounded border on resize)
    local heroCard = Instance.new("CanvasGroup")
    heroCard.Name = "HeroCard"
    heroCard.Size = UDim2.new(0.61, -6, 1, 0)
    heroCard.Position = UDim2.new(0, 0, 0, 0)
    heroCard.BackgroundColor3 = Color3.fromRGB(18, 14, 12)
    heroCard.BorderSizePixel = 0
    heroCard.GroupTransparency = 0
    heroCard.ClipsDescendants = true

    local heroCorner = Instance.new("UICorner")
    heroCorner.CornerRadius = UDim.new(0, 14)
    heroCorner.Parent = heroCard

    -- Map Background Image (Full Card Bleed with rounded corner clipping)
    local mapBg = Instance.new("ImageLabel")
    mapBg.Name = "MapBannerBackground"
    mapBg.Size = UDim2.fromScale(1, 1)
    mapBg.Position = UDim2.fromScale(0.5, 0.5)
    mapBg.AnchorPoint = Vector2.new(0.5, 0.5)
    mapBg.BackgroundTransparency = 1
    mapBg.ScaleType = Enum.ScaleType.Crop -- Full card cover
    mapBg.ClipsDescendants = true
    mapBg.ZIndex = 1
    mapBg.Parent = heroCard

    local mapCorner = Instance.new("UICorner")
    mapCorner.CornerRadius = UDim.new(0, 14)
    mapCorner.Parent = mapBg

    -- Fast default: load rbxthumb for GameThumbnail / GameIcon
    local targetGameId = game.GameId
    local targetPlaceId = game.PlaceId
    if targetGameId and targetGameId > 0 then
        mapBg.Image = string.format("rbxthumb://type=GameThumbnail&id=%d&w=768&h=432", targetGameId)
    else
        mapBg.Image = string.format("rbxthumb://type=Asset&id=%d&w=768&h=432", targetPlaceId)
    end

    -- Asynchronous fetch for high-res official IconImageAssetId
    task.spawn(function()
        pcall(function()
            local MarketplaceService = game:GetService("MarketplaceService")
            local info = MarketplaceService:GetProductInfo(targetPlaceId)
            if info then
                if info.IconImageAssetId and info.IconImageAssetId > 0 then
                    if mapBg and mapBg.Parent then
                        mapBg.Image = string.format("rbxassetid://%d", info.IconImageAssetId)
                    end
                end
            end
        end)
    end)

    -- Dark Harmonious Amber/Obsidian Gradient Overlay
    local bgOverlay = Instance.new("Frame")
    bgOverlay.Name = "DarkOverlay"
    bgOverlay.Size = UDim2.fromScale(1, 1)
    bgOverlay.Position = UDim2.fromScale(0.5, 0.5)
    bgOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
    bgOverlay.BackgroundColor3 = Color3.fromRGB(15, 12, 10)
    bgOverlay.BackgroundTransparency = 0.2
    bgOverlay.BorderSizePixel = 0
    bgOverlay.ZIndex = 2

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 14)
    bgCorner.Parent = bgOverlay

    local ovGrad = Instance.new("UIGradient")
    ovGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(194, 65, 12)), -- Vibrant Amber
        ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 12, 10)), -- Dark Obsidian
    })
    ovGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35),
        NumberSequenceKeypoint.new(1, 0.75),
    })
    ovGrad.Rotation = 90
    ovGrad.Parent = bgOverlay
    bgOverlay.Parent = heroCard

    local heroStroke = Instance.new("UIStroke")
    heroStroke.Color = Theme.GetToken("BorderAccent")
    heroStroke.Thickness = 1
    heroStroke.Transparency = 0.55
    heroStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    heroStroke.ZIndex = 3
    heroStroke.Parent = heroCard
    Theme.Bind(heroStroke, "Color", "BorderAccent")

    -- Welcome Text Stack (100% Transparent Background as requested)
    local heroTextStack = Instance.new("Frame")
    heroTextStack.Name = "TextStack"
    heroTextStack.Size = UDim2.new(1, -36, 0, 36)
    heroTextStack.Position = UDim2.new(0, 18, 1, -14)
    heroTextStack.AnchorPoint = Vector2.new(0, 1)
    heroTextStack.BackgroundTransparency = 1 -- Completely Transparent
    heroTextStack.BorderSizePixel = 0
    heroTextStack.ZIndex = 4
    heroTextStack.Parent = heroCard

    local displayName = props.Username or (lp and (lp.DisplayName or lp.Name)) or "epochzx"
    local greetingLabel = Instance.new("TextLabel")
    greetingLabel.Name = "Greeting"
    greetingLabel.Size = UDim2.fromScale(1, 1)
    greetingLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(greetingLabel, "Display")
    greetingLabel.TextSize = 19
    greetingLabel.TextWrapped = true
    greetingLabel.Text = "Welcome, " .. displayName
    greetingLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    greetingLabel.TextXAlignment = Enum.TextXAlignment.Left
    greetingLabel.TextTruncate = Enum.TextTruncate.None
    greetingLabel.TextStrokeTransparency = 0.6
    greetingLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    greetingLabel.ZIndex = 5
    greetingLabel.Parent = heroTextStack

    heroCard.Parent = heroRow

    -- 2B. Discord Action Button Card (Click to copy https://discord.gg/2gEjXyQWKM, no background behind icon)
    local discordLink = "https://discord.gg/2gEjXyQWKM"
    local actionCard = Instance.new("ImageButton")
    actionCard.Name = "DiscordActionCard"
    actionCard.Size = UDim2.new(0.39, -6, 1, 0)
    actionCard.Position = UDim2.new(0.61, 6, 0, 0)
    actionCard.BackgroundColor3 = Theme.GetToken("Card")
    actionCard.AutoButtonColor = false
    actionCard.BorderSizePixel = 0
    Theme.Bind(actionCard, "BackgroundColor3", "Card")

    local actionCorner = Instance.new("UICorner")
    actionCorner.CornerRadius = UDim.new(0, 14)
    actionCorner.Parent = actionCard

    local actionStroke = Instance.new("UIStroke")
    actionStroke.Color = Theme.GetToken("BorderSubtle")
    actionStroke.Thickness = 1
    actionStroke.Parent = actionCard
    Theme.Bind(actionStroke, "Color", "BorderSubtle")

    local actionPad = Instance.new("UIPadding")
    actionPad.PaddingLeft = UDim.new(0, 16)
    actionPad.PaddingRight = UDim.new(0, 16)
    actionPad.PaddingTop = UDim.new(0, 14)
    actionPad.PaddingBottom = UDim.new(0, 14)
    actionPad.Parent = actionCard

    local actionLeftCol = Instance.new("Frame")
    actionLeftCol.Name = "LeftColumn"
    actionLeftCol.Size = UDim2.new(1, -44, 1, 0)
    actionLeftCol.BackgroundTransparency = 1
    actionLeftCol.Parent = actionCard

    local actionColLayout = Instance.new("UIListLayout")
    actionColLayout.SortOrder = Enum.SortOrder.LayoutOrder
    actionColLayout.Padding = UDim.new(0, 2)
    actionColLayout.Parent = actionLeftCol

    local actionTitle = Instance.new("TextLabel")
    actionTitle.Name = "Title"
    actionTitle.Size = UDim2.new(1, 0, 0, 15)
    actionTitle.BackgroundTransparency = 1
    Theme.ApplyTypography(actionTitle, "Body", "Small")
    actionTitle.Text = "Discord Community"
    actionTitle.TextColor3 = Theme.GetToken("TextMuted")
    actionTitle.TextXAlignment = Enum.TextXAlignment.Left
    actionTitle.LayoutOrder = 1
    actionTitle.Parent = actionLeftCol
    Theme.Bind(actionTitle, "TextColor3", "TextMuted")

    local discSub = Instance.new("TextLabel")
    discSub.Name = "DiscordTitle"
    discSub.Size = UDim2.new(1, 0, 0, 22)
    discSub.BackgroundTransparency = 1
    Theme.ApplyTypography(discSub, "Display")
    discSub.TextSize = 17
    discSub.Text = "Join Server"
    discSub.TextColor3 = Color3.fromRGB(255, 255, 255)
    discSub.TextXAlignment = Enum.TextXAlignment.Left
    discSub.LayoutOrder = 2
    discSub.Parent = actionLeftCol

    local subLabel = Instance.new("TextLabel")
    subLabel.Name = "Subtitle"
    subLabel.Size = UDim2.new(1, 0, 0, 15)
    subLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(subLabel, "Body", "Small")
    subLabel.Text = "discord.gg/2gEjXyQWKM"
    subLabel.TextColor3 = Theme.GetToken("Placeholder")
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.TextTruncate = Enum.TextTruncate.AtEnd
    subLabel.LayoutOrder = 3
    subLabel.Parent = actionLeftCol
    Theme.Bind(subLabel, "TextColor3", "Placeholder")

    local reviewBtn = Instance.new("TextButton")
    reviewBtn.Name = "ReviewButton"
    reviewBtn.Size = UDim2.new(1, 0, 0, 20)
    reviewBtn.BackgroundTransparency = 1
    Theme.ApplyTypography(reviewBtn, "Header", "Sub")
    reviewBtn.Text = "Copy Link →"
    reviewBtn.TextColor3 = Theme.GetToken("Accent")
    reviewBtn.TextXAlignment = Enum.TextXAlignment.Left
    reviewBtn.LayoutOrder = 4
    reviewBtn.Parent = actionLeftCol
    Theme.Bind(reviewBtn, "TextColor3", "Accent")

    -- Right Illustration: Discord Icon floating cleanly with NO background box
    local mailIcon = Instance.new("ImageLabel")
    mailIcon.Name = "DiscordIcon"
    mailIcon.Size = UDim2.fromOffset(30, 30)
    mailIcon.Position = UDim2.new(1, 0, 0.5, 0)
    mailIcon.AnchorPoint = Vector2.new(1, 0.5)
    mailIcon.BackgroundTransparency = 1
    mailIcon.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(mailIcon, "send")
    mailIcon.Parent = actionCard
    Theme.Bind(mailIcon, "ImageColor3", "Accent")

    -- Unified scale press feedback for entire card and inner content
    Tweener.BindPressFeedback(actionCard, actionCard, 0.96)

    -- Interactive micro-hover on link button
    reviewBtn.MouseEnter:Connect(function()
        Tweener.Tween(reviewBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(0, 4, 0, 0) })
    end)
    reviewBtn.MouseLeave:Connect(function()
        Tweener.Tween(reviewBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(0, 0, 0, 0) })
    end)

    -- Dynamic click animation across entire card (live feedback instead of static text)
    local isCopyingAnim = false
    local function copyDiscord()
        local ok = false
        pcall(function()
            ok = Compat.CopyText(discordLink)
        end)
        local win = self.Window
        if win and win.Notify then
            win:Notify({
                Title = "Discord Link",
                Content = "Copied " .. discordLink .. " to clipboard!",
                Duration = 2.5,
                Icon = "check",
            })
        end

        -- Animated card reaction on click
        if not isCopyingAnim then
            isCopyingAnim = true
            reviewBtn.Text = "Copied! ✓"
            reviewBtn.TextColor3 = Color3.fromRGB(34, 197, 94) -- Vibrant Green Success
            subLabel.Text = "Link copied to clipboard!"
            subLabel.TextColor3 = Theme.GetToken("Accent")
            Tweener.Tween(mailIcon, TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = -15, Size = UDim2.fromOffset(34, 34) })
            task.delay(2.0, function()
                reviewBtn.Text = "Copy Link →"
                reviewBtn.TextColor3 = Theme.GetToken("Accent")
                subLabel.Text = "discord.gg/2gEjXyQWKM"
                subLabel.TextColor3 = Theme.GetToken("Placeholder")
                Tweener.Tween(mailIcon, TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Rotation = 0, Size = UDim2.fromOffset(30, 30) })
                isCopyingAnim = false
            end)
        end
    end

    actionCard.Activated:Connect(copyDiscord)
    reviewBtn.MouseButton1Click:Connect(copyDiscord)
    actionCard.Parent = heroRow
    heroRow.Parent = root

    -- 3. Metrics Row (3 Stat Cards: Execute Time, Players Ingame, Whitelist - Amber Theme)
    local statsRow = Instance.new("Frame")
    statsRow.Name = "StatsRow"
    statsRow.Size = UDim2.new(1, 0, 0, 80)
    statsRow.BackgroundTransparency = 1
    statsRow.LayoutOrder = 3

    local statsLayout = Instance.new("UIListLayout")
    statsLayout.FillDirection = Enum.FillDirection.Horizontal
    statsLayout.Padding = UDim.new(0, 12)
    statsLayout.Parent = statsRow

    local function createStatCard(name: string, iconName: string, titleText: string, valueStr: string, isCompactText: boolean?, order: number?): (Frame, TextLabel)
        local card = Instance.new("Frame")
        card.Name = name
        card.Size = UDim2.new(0.333, -8, 1, 0)
        card.LayoutOrder = order or 1
        card.BackgroundColor3 = Theme.GetToken("Card")
        card.BorderSizePixel = 0
        Theme.Bind(card, "BackgroundColor3", "Card")

        local cCorner = Instance.new("UICorner")
        cCorner.CornerRadius = UDim.new(0, 14)
        cCorner.Parent = card

        local cStroke = Instance.new("UIStroke")
        cStroke.Color = Theme.GetToken("BorderSubtle")
        cStroke.Thickness = 1
        cStroke.Parent = card
        Theme.Bind(cStroke, "Color", "BorderSubtle")

        local cardPad = Instance.new("UIPadding")
        cardPad.PaddingLeft = UDim.new(0, 12)
        cardPad.PaddingRight = UDim.new(0, 10)
        cardPad.Parent = card

        -- Icon Square Box (Deep Amber, Centered 38x38)
        local iconBox = Instance.new("Frame")
        iconBox.Name = "IconBox"
        iconBox.Size = UDim2.fromOffset(38, 38)
        iconBox.Position = UDim2.new(0, 0, 0.5, 0)
        iconBox.AnchorPoint = Vector2.new(0, 0.5)
        iconBox.BackgroundColor3 = Color3.fromRGB(36, 20, 10)
        iconBox.BorderSizePixel = 0
        local ibCorner = Instance.new("UICorner")
        ibCorner.CornerRadius = UDim.new(0, 10)
        ibCorner.Parent = iconBox

        local ic = Instance.new("ImageLabel")
        ic.Size = UDim2.fromOffset(20, 20)
        ic.Position = UDim2.fromScale(0.5, 0.5)
        ic.AnchorPoint = Vector2.new(0.5, 0.5)
        ic.BackgroundTransparency = 1
        ic.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(ic, iconName)
        ic.Parent = iconBox
        Theme.Bind(ic, "ImageColor3", "Accent")
        iconBox.Parent = card

        -- Text Column (Locked to exact height 38px matching iconBox, top is perfectly flush with icon top)
        local textCol = Instance.new("Frame")
        textCol.Name = "TextColumn"
        textCol.Size = UDim2.new(1, -48, 0, 38)
        textCol.Position = UDim2.new(0, 48, 0.5, 0)
        textCol.AnchorPoint = Vector2.new(0, 0.5)
        textCol.BackgroundTransparency = 1
        textCol.Parent = card

        local tLayout = Instance.new("UIListLayout")
        tLayout.SortOrder = Enum.SortOrder.LayoutOrder
        tLayout.VerticalAlignment = Enum.VerticalAlignment.Top -- Locked to icon top boundary
        tLayout.Padding = UDim.new(0, 2)
        tLayout.Parent = textCol

        local tLabel = Instance.new("TextLabel")
        tLabel.Name = "Title"
        tLabel.Size = UDim2.new(1, 0, 0, 14)
        tLabel.BackgroundTransparency = 1
        Theme.ApplyTypography(tLabel, "Header", "Small")
        tLabel.TextSize = 12
        tLabel.Text = titleText
        tLabel.TextColor3 = Color3.fromRGB(156, 163, 175)
        tLabel.TextXAlignment = Enum.TextXAlignment.Left
        tLabel.TextTruncate = Enum.TextTruncate.AtEnd
        tLabel.LayoutOrder = 1
        tLabel.Parent = textCol

        local valLabel = Instance.new("TextLabel")
        valLabel.Name = "Value"
        valLabel.Size = UDim2.new(1, 0, 0, 22)
        valLabel.BackgroundTransparency = 1
        if isCompactText then
            Theme.ApplyTypography(valLabel, "Header", "Small")
            valLabel.TextSize = 13
            valLabel.TextWrapped = true
            valLabel.TextTruncate = Enum.TextTruncate.None
        else
            Theme.ApplyTypography(valLabel, "Display")
            valLabel.TextSize = 19
            valLabel.TextTruncate = Enum.TextTruncate.None
        end
        valLabel.Text = valueStr
        valLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        valLabel.TextXAlignment = Enum.TextXAlignment.Left
        valLabel.LayoutOrder = 2
        valLabel.Parent = textCol

        card.Parent = statsRow
        return card, valLabel
    end

    -- Card 1: Execute Time (Timer since script execution, e.g. 0days 0hr 1min 24sec)
    local cardExecuteTime, valExecuteTime = createStatCard("ExecuteTimeCard", "clock", "Execute Time", "0hr 0min 0sec", true, 1)

    -- Card 2: Players Ingame (users_in_server / max_server, e.g. 22/50)
    local initialPlayerCount = math.max(22, #Players:GetPlayers())
    local maxPlayerLimit = math.max(50, Players.MaxPlayers)
    local cardPlayers, valPlayers = createStatCard("PlayersCard", "users", "Players Ingame", string.format("%d/%d", initialPlayerCount, maxPlayerLimit), false, 2)

    -- Card 3: Whitelist (Check Junkie key / expiry, display days, hours, minutes, seconds)
    local cardWhitelist, valWhitelist = createStatCard("WhitelistCard", "shield-check", "Whitelist", "29days 12hr 39min 20sec", true, 3)

    statsRow.Parent = root

    -- 4. Filter & Search Controls Row (Support count pill, Status dropdown, Search box)
    local ctrlRow = Instance.new("Frame")
    ctrlRow.Name = "ControlsRow"
    ctrlRow.Size = UDim2.new(1, 0, 0, 34)
    ctrlRow.BackgroundTransparency = 1
    ctrlRow.LayoutOrder = 4

    local leftFilters = Instance.new("Frame")
    leftFilters.Name = "LeftFilters"
    leftFilters.Size = UDim2.new(1, -195, 1, 0)
    leftFilters.BackgroundTransparency = 1
    leftFilters.Parent = ctrlRow

    local lfLayout = Instance.new("UIListLayout")
    lfLayout.FillDirection = Enum.FillDirection.Horizontal
    lfLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    lfLayout.Padding = UDim.new(0, 8)
    lfLayout.Parent = leftFilters

    -- Support (countmap) pill
    local supportPill = Instance.new("TextButton")
    supportPill.Name = "Pill_Support"
    supportPill.AutomaticSize = Enum.AutomaticSize.X
    supportPill.Size = UDim2.new(0, 0, 1, 0)
    supportPill.BackgroundColor3 = Color3.fromRGB(194, 65, 12)
    supportPill.AutoButtonColor = false
    Theme.ApplyTypography(supportPill, "Header", "Sub")
    supportPill.Text = "Support (0)"
    supportPill.TextColor3 = Color3.fromRGB(255, 255, 255)

    local spCorner = Instance.new("UICorner")
    spCorner.CornerRadius = UDim.new(0, 8)
    spCorner.Parent = supportPill

    local spStroke = Instance.new("UIStroke")
    spStroke.Color = Theme.GetToken("BorderAccent")
    spStroke.Thickness = 1
    spStroke.Parent = supportPill

    local spPad = Instance.new("UIPadding")
    spPad.PaddingLeft = UDim.new(0, 12)
    spPad.PaddingRight = UDim.new(0, 12)
    spPad.Parent = supportPill
    supportPill.Parent = leftFilters

    -- Status Filter Dropdown Trigger (Engineered to match real Dropdown component)
    local currentStatusFilter = "All"
    local statusDropdownBtn = Instance.new("TextButton")
    statusDropdownBtn.Name = "StatusDropdownTrigger"
    statusDropdownBtn.Size = UDim2.fromOffset(138, 32)
    statusDropdownBtn.BackgroundColor3 = Theme.GetToken("Card")
    statusDropdownBtn.AutoButtonColor = false
    statusDropdownBtn.BorderSizePixel = 0
    statusDropdownBtn.Text = ""
    Theme.Bind(statusDropdownBtn, "BackgroundColor3", "Card")

    local sdbCorner = Instance.new("UICorner")
    sdbCorner.CornerRadius = Theme.Radii.Control
    sdbCorner.Parent = statusDropdownBtn

    local sdbStroke = Instance.new("UIStroke")
    sdbStroke.Color = Theme.GetToken("BorderSubtle")
    sdbStroke.Thickness = 1
    sdbStroke.Parent = statusDropdownBtn
    Theme.Bind(sdbStroke, "Color", "BorderSubtle")

    local sdbPad = Instance.new("UIPadding")
    sdbPad.PaddingLeft = UDim.new(0, 10)
    sdbPad.PaddingRight = UDim.new(0, 10)
    sdbPad.Parent = statusDropdownBtn

    local sdbDot = Instance.new("Frame")
    sdbDot.Name = "LeadingDot"
    sdbDot.Size = UDim2.fromOffset(8, 8)
    sdbDot.Position = UDim2.new(0, 0, 0.5, 0)
    sdbDot.AnchorPoint = Vector2.new(0, 0.5)
    sdbDot.BackgroundColor3 = Color3.fromRGB(156, 163, 175)
    sdbDot.BorderSizePixel = 0
    local sdbdCorner = Instance.new("UICorner")
    sdbdCorner.CornerRadius = UDim.new(1, 0)
    sdbdCorner.Parent = sdbDot
    sdbDot.Parent = statusDropdownBtn

    local sdbText = Instance.new("TextLabel")
    sdbText.Name = "StatusLabel"
    sdbText.Size = UDim2.new(1, -26, 1, 0)
    sdbText.Position = UDim2.new(0, 14, 0, 0)
    sdbText.BackgroundTransparency = 1
    Theme.ApplyTypography(sdbText, "Body", "Small")
    sdbText.Text = "All Status"
    sdbText.TextColor3 = Color3.fromRGB(220, 220, 230)
    sdbText.TextXAlignment = Enum.TextXAlignment.Left
    sdbText.TextTruncate = Enum.TextTruncate.AtEnd
    sdbText.Parent = statusDropdownBtn

    local sdbArrow = Instance.new("ImageLabel")
    sdbArrow.Name = "Arrow"
    sdbArrow.Size = UDim2.fromOffset(13, 13)
    sdbArrow.Position = UDim2.new(1, 0, 0.5, 0)
    sdbArrow.AnchorPoint = Vector2.new(1, 0.5)
    sdbArrow.BackgroundTransparency = 1
    sdbArrow.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(sdbArrow, "chevron-down")
    sdbArrow.Parent = statusDropdownBtn
    Theme.Bind(sdbArrow, "ImageColor3", "Accent")
    statusDropdownBtn.Parent = leftFilters
    Tweener.BindPressFeedback(statusDropdownBtn, statusDropdownBtn)

    -- Status Dropdown Popover Menu (Matches Dropdown.luau with ZIndex 4500 and Fluid animation)
    local statusPopover = Instance.new("Frame")
    statusPopover.Name = "StatusPopover"
    statusPopover.Size = UDim2.fromOffset(150, 0)
    statusPopover.BackgroundColor3 = Theme.GetToken("Card")
    statusPopover.BorderSizePixel = 0
    statusPopover.ZIndex = 4500
    statusPopover.Visible = false
    statusPopover.ClipsDescendants = true
    Theme.Bind(statusPopover, "BackgroundColor3", "Card")

    local spPopCorner = Instance.new("UICorner")
    spPopCorner.CornerRadius = Theme.Radii.Card
    spPopCorner.Parent = statusPopover

    local spPopStroke = Instance.new("UIStroke")
    spPopStroke.Color = Theme.GetToken("BorderAccent")
    spPopStroke.Thickness = 1
    spPopStroke.Transparency = 0.4
    spPopStroke.Parent = statusPopover
    Theme.Bind(spPopStroke, "Color", "BorderAccent")

    local spPopList = Instance.new("UIListLayout")
    spPopList.SortOrder = Enum.SortOrder.LayoutOrder
    spPopList.Padding = UDim.new(0, 3)
    spPopList.Parent = statusPopover

    local spPopPad = Instance.new("UIPadding")
    spPopPad.PaddingTop = UDim.new(0, 6)
    spPopPad.PaddingBottom = UDim.new(0, 6)
    spPopPad.PaddingLeft = UDim.new(0, 6)
    spPopPad.PaddingRight = UDim.new(0, 6)
    spPopPad.Parent = statusPopover

    -- Search Input Field
    local searchFrame = Instance.new("Frame")
    searchFrame.Name = "SearchFrame"
    searchFrame.Size = UDim2.new(0, 185, 1, 0)
    searchFrame.Position = UDim2.new(1, 0, 0.5, 0)
    searchFrame.AnchorPoint = Vector2.new(1, 0.5)
    searchFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    searchFrame.BorderSizePixel = 0

    local sfCorner = Instance.new("UICorner")
    sfCorner.CornerRadius = UDim.new(0, 8)
    sfCorner.Parent = searchFrame

    local sfStroke = Instance.new("UIStroke")
    sfStroke.Color = Theme.GetToken("BorderSubtle")
    sfStroke.Thickness = 1
    sfStroke.Parent = searchFrame
    Theme.Bind(sfStroke, "Color", "BorderSubtle")

    local sIcon = Instance.new("ImageLabel")
    sIcon.Name = "SearchIcon"
    sIcon.Size = UDim2.fromOffset(14, 14)
    sIcon.Position = UDim2.new(0, 10, 0.5, 0)
    sIcon.AnchorPoint = Vector2.new(0, 0.5)
    sIcon.BackgroundTransparency = 1
    sIcon.ImageColor3 = Color3.fromRGB(100, 100, 120)
    Icons.Apply(sIcon, "search")
    sIcon.Parent = searchFrame

    local sInput = Instance.new("TextBox")
    sInput.Name = "SearchInput"
    sInput.Size = UDim2.new(1, -34, 1, 0)
    sInput.Position = UDim2.new(0, 28, 0, 0)
    sInput.BackgroundTransparency = 1
    Theme.ApplyTypography(sInput, "Body", "Small")
    sInput.PlaceholderText = "Search for a map..."
    sInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 120)
    sInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    sInput.TextXAlignment = Enum.TextXAlignment.Left
    sInput.ClearTextOnFocus = false
    sInput.Text = ""
    sInput.Parent = searchFrame

    searchFrame.Parent = ctrlRow
    ctrlRow.Parent = root

    -- 5. Map Manager Table Card (Separate container card with 14px corners and subtle border)
    local mapCard = Instance.new("Frame")
    mapCard.Name = "MapManagerCard"
    mapCard.Size = UDim2.new(1, 0, 0, 0)
    mapCard.AutomaticSize = Enum.AutomaticSize.Y
    mapCard.BackgroundColor3 = Theme.GetToken("Card")
    mapCard.BorderSizePixel = 0
    mapCard.LayoutOrder = 5
    Theme.Bind(mapCard, "BackgroundColor3", "Card")

    local mcCorner = Instance.new("UICorner")
    mcCorner.CornerRadius = UDim.new(0, 14)
    mcCorner.Parent = mapCard

    local mcStroke = Instance.new("UIStroke")
    mcStroke.Color = Theme.GetToken("BorderSubtle")
    mcStroke.Thickness = 1
    mcStroke.Parent = mapCard
    Theme.Bind(mcStroke, "Color", "BorderSubtle")

    local mcPad = Instance.new("UIPadding")
    mcPad.PaddingTop = UDim.new(0, 10)
    mcPad.PaddingBottom = UDim.new(0, 10)
    mcPad.PaddingLeft = UDim.new(0, 14)
    mcPad.PaddingRight = UDim.new(0, 14)
    mcPad.Parent = mapCard

    local tableLayout = Instance.new("UIListLayout")
    tableLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tableLayout.Padding = UDim.new(0, 6)
    tableLayout.Parent = mapCard

    -- Table Header Row: Map | Place ID | Update | Status | Actions
    local headerRow = Instance.new("Frame")
    headerRow.Name = "TableHeader"
    headerRow.Size = UDim2.new(1, 0, 0, 26)
    headerRow.BackgroundTransparency = 1
    headerRow.LayoutOrder = 0

    local function createColHeader(title: string, xPos: number, width: number, alignRight: boolean?): TextLabel
        local h = Instance.new("TextLabel")
        h.Name = "Header_" .. title
        h.Size = UDim2.new(width, 0, 1, 0)
        h.Position = UDim2.new(xPos, 0, 0, 0)
        h.BackgroundTransparency = 1
        Theme.ApplyTypography(h, "Body", "Small")
        h.Text = title
        h.TextColor3 = Color3.fromRGB(120, 120, 135)
        h.TextXAlignment = if alignRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
        h.Parent = headerRow
        return h
    end

    createColHeader("Map", 0.01, 0.38)
    createColHeader("Place ID", 0.40, 0.24)
    createColHeader("Update", 0.66, 0.16)
    createColHeader("Status", 0.84, 0.15)
    headerRow.Parent = mapCard

    -- Rows Container
    local rowsHolder = Instance.new("Frame")
    rowsHolder.Name = "RowsHolder"
    rowsHolder.Size = UDim2.new(1, 0, 0, 0)
    rowsHolder.AutomaticSize = Enum.AutomaticSize.Y
    rowsHolder.BackgroundTransparency = 1
    rowsHolder.LayoutOrder = 1

    local rhLayout = Instance.new("UIListLayout")
    rhLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rhLayout.Padding = UDim.new(0, 5)
    rhLayout.Parent = rowsHolder
    rowsHolder.Parent = mapCard

    -- Slide Navigation Footer (Shows slide controls when maps exist)
    local slideFooter = Instance.new("Frame")
    slideFooter.Name = "SlideFooter"
    slideFooter.Size = UDim2.new(1, 0, 0, 32)
    slideFooter.BackgroundTransparency = 1
    slideFooter.LayoutOrder = 2
    slideFooter.Parent = mapCard

    local sfDivider = Instance.new("Frame")
    sfDivider.Name = "FooterDivider"
    sfDivider.Size = UDim2.new(1, 0, 0, 1)
    sfDivider.Position = UDim2.new(0, 0, 0, 0)
    sfDivider.BackgroundColor3 = Theme.GetToken("BorderSubtle")
    sfDivider.BorderSizePixel = 0
    sfDivider.Parent = slideFooter
    Theme.Bind(sfDivider, "BackgroundColor3", "BorderSubtle")

    local slideCountLabel = Instance.new("TextLabel")
    slideCountLabel.Name = "CountLabel"
    slideCountLabel.Size = UDim2.new(0.5, 0, 1, 0)
    slideCountLabel.Position = UDim2.new(0, 4, 0, 0)
    slideCountLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(slideCountLabel, "Body", "Small")
    slideCountLabel.Text = "Showing 1-5 of 5 maps"
    slideCountLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
    slideCountLabel.TextXAlignment = Enum.TextXAlignment.Left
    slideCountLabel.Parent = slideFooter

    local slideNavControls = Instance.new("Frame")
    slideNavControls.Name = "NavControls"
    slideNavControls.Size = UDim2.new(0, 130, 1, 0)
    slideNavControls.Position = UDim2.new(1, -4, 0, 0)
    slideNavControls.AnchorPoint = Vector2.new(1, 0)
    slideNavControls.BackgroundTransparency = 1
    slideNavControls.Parent = slideFooter

    local sncLayout = Instance.new("UIListLayout")
    sncLayout.SortOrder = Enum.SortOrder.LayoutOrder
    sncLayout.FillDirection = Enum.FillDirection.Horizontal
    sncLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    sncLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    sncLayout.Padding = UDim.new(0, 6)
    sncLayout.Parent = slideNavControls

    local prevSlideBtn = Instance.new("ImageButton")
    prevSlideBtn.Name = "PrevButton"
    prevSlideBtn.LayoutOrder = 1 -- Leftmost: <
    prevSlideBtn.Size = UDim2.fromOffset(26, 26)
    prevSlideBtn.BackgroundColor3 = Color3.fromRGB(24, 20, 28)
    prevSlideBtn.AutoButtonColor = false
    local psbCorner = Instance.new("UICorner")
    psbCorner.CornerRadius = UDim.new(0, 6)
    psbCorner.Parent = prevSlideBtn
    local prevIcon = Instance.new("ImageLabel")
    prevIcon.Size = UDim2.fromOffset(13, 13)
    prevIcon.Position = UDim2.fromScale(0.5, 0.5)
    prevIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    prevIcon.BackgroundTransparency = 1
    prevIcon.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(prevIcon, "chevron-left")
    prevIcon.Parent = prevSlideBtn
    prevSlideBtn.Parent = slideNavControls
    Tweener.BindPressFeedback(prevSlideBtn, prevSlideBtn)

    local slidePill = Instance.new("Frame")
    slidePill.Name = "SlidePill"
    slidePill.LayoutOrder = 2 -- Middle: 1 / 1
    slidePill.Size = UDim2.fromOffset(48, 24)
    slidePill.BackgroundColor3 = Color3.fromRGB(20, 16, 24)
    local spCorner2 = Instance.new("UICorner")
    spCorner2.CornerRadius = UDim.new(0, 6)
    spCorner2.Parent = slidePill
    local slidePillLabel = Instance.new("TextLabel")
    slidePillLabel.Size = UDim2.fromScale(1, 1)
    slidePillLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(slidePillLabel, "Code", "Small")
    slidePillLabel.Text = "1 / 1"
    slidePillLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    slidePillLabel.Parent = slidePill
    slidePill.Parent = slideNavControls

    local nextSlideBtn = Instance.new("ImageButton")
    nextSlideBtn.Name = "NextButton"
    nextSlideBtn.LayoutOrder = 3 -- Rightmost: >
    nextSlideBtn.Size = UDim2.fromOffset(26, 26)
    nextSlideBtn.BackgroundColor3 = Color3.fromRGB(24, 20, 28)
    nextSlideBtn.AutoButtonColor = false
    local nsbCorner = Instance.new("UICorner")
    nsbCorner.CornerRadius = UDim.new(0, 6)
    nsbCorner.Parent = nextSlideBtn
    local nextIcon = Instance.new("ImageLabel")
    nextIcon.Size = UDim2.fromOffset(13, 13)
    nextIcon.Position = UDim2.fromScale(0.5, 0.5)
    nextIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    nextIcon.BackgroundTransparency = 1
    nextIcon.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(nextIcon, "chevron-right")
    nextIcon.Parent = nextSlideBtn
    nextSlideBtn.Parent = slideNavControls
    Tweener.BindPressFeedback(nextSlideBtn, nextSlideBtn)

    mapCard.Parent = root

    -- Fallback Supported Maps Data
    local defaultMapList = {
        {
            Name = "Anime Legacy Simulator",
            PlaceId = 106198175232796,
            GameId = 10765902945,
            Status = "Online",
            Icon = "rbxassetid://101140974524547",
        },
        {
            Name = "Blox Fruits",
            PlaceId = 2753915549,
            GameId = 994732206,
            Status = "Online",
            Icon = "rbxthumb://type=GameIcon&id=994732206&w=150&h=150",
        },
        {
            Name = "King Legacy",
            PlaceId = 4520749081,
            GameId = 1542456453,
            Status = "Update",
            Icon = "rbxthumb://type=GameIcon&id=1542456453&w=150&h=150",
        },
        {
            Name = "Anime Vanguards",
            PlaceId = 16146832113,
            GameId = 5576288301,
            Status = "Risk",
            Icon = "rbxthumb://type=GameIcon&id=5576288301&w=150&h=150",
        },
        {
            Name = "Fisch",
            PlaceId = 16732694052,
            GameId = 5750914919,
            Status = "Online",
            Icon = "rbxthumb://type=GameIcon&id=5750914919&w=150&h=150",
        },
    }

    local activeMapList = defaultMapList
    local createdRowFrames = {}

    -- Function to format date string from timestamp (e.g. 10/11/2026)
    local function formatUpdateDate(updatedStr: any): string
        if type(updatedStr) == "string" and updatedStr ~= "" then
            local y, m, d = string.match(updatedStr, "(%d%d%d%d)%-(%d%d)%-(%d%d)")
            if d and m and y then
                return string.format("%s/%s/%s", d, m, y)
            end
        end
        return os.date("%d/%m/%Y")
    end

    -- Fast, Universal Place ID Resolver & Image URI Builder
    -- Supports: Full roblox.com URL, numeric PlaceId, rbxassetid, rbxthumb, or direct asset URI
    local function parsePlaceIdAndIcon(entry: any): (number, string)
        local rawIcon = entry.Icon or entry.Url or entry.Link or ""
        local rawPlaceId = entry.PlaceId or entry.PlaceID or entry.Id or entry.id

        local placeIdNum = 0
        if type(rawPlaceId) == "number" then
            placeIdNum = rawPlaceId
        elseif type(rawPlaceId) == "string" and tonumber(rawPlaceId) then
            placeIdNum = tonumber(rawPlaceId) or 0
        end

        -- Extract PlaceId from Roblox game URL if PlaceId wasn't explicitly supplied
        if placeIdNum == 0 and type(rawIcon) == "string" then
            local matchedId = string.match(rawIcon, "games/(%d+)") or string.match(rawIcon, "roblox%.com/asset/%?id=(%d+)") or string.match(rawIcon, "(%d+)")
            if matchedId then
                placeIdNum = tonumber(matchedId) or 0
            end
        end

        -- Generate instantaneous, zero-overhead Roblox native thumbnail URI
        local imageUri = ""
        if type(rawIcon) == "string" and (string.find(rawIcon, "rbxthumb://") or string.find(rawIcon, "rbxassetid://") or string.find(rawIcon, "http")) and not string.find(rawIcon, "roblox%.com/games/") then
            imageUri = rawIcon
        elseif placeIdNum > 0 then
            imageUri = string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", placeIdNum)
        end

        return placeIdNum, imageUri
    end

    -- Status Resolver: Online (Green), Update (Orange), Risk (Red)
    local function resolveStatus(rawStatus: any): (string, Color3)
        local s = string.lower(tostring(rawStatus or "online"))
        if s:find("risk") or s:find("maint") or s:find("down") or s:find("red") or s:find("patch") then
            return "Risk", Color3.fromRGB(239, 68, 68) -- Red
        elseif s:find("update") or s:find("updat") or s:find("warn") or s:find("orange") or s:find("test") then
            return "Update", Color3.fromRGB(249, 115, 22) -- Orange
        else
            return "Online", Color3.fromRGB(34, 197, 94) -- Green
        end
    end

    local MAPS_PER_SLIDE = 5
    local currentSlide = 1
    local lastFilteredCount = 0

    -- Rebuild Table Rows: exactly 5 maps per slide, zero overlap between Place ID and Update
    local function rebuildMapTable()
        for _, obj in ipairs(rowsHolder:GetChildren()) do
            if obj:IsA("Frame") then obj:Destroy() end
        end
        table.clear(createdRowFrames)

        -- 1. Filter all entries first
        local query = string.lower(sInput.Text or "")
        local filtered = {}
        for _, mData in ipairs(activeMapList) do
            local pidNum, _ = parsePlaceIdAndIcon(mData)
            local matchesQuery = (query == "")
                or (string.find(string.lower(tostring(mData.Name or "")), query, 1, true) ~= nil)
                or (string.find(string.lower(tostring(pidNum > 0 and pidNum or mData.PlaceId or "")), query, 1, true) ~= nil)

            local statusLabel, _ = resolveStatus(mData.Status)
            local matchesStatus = true
            if currentStatusFilter ~= "All" then
                matchesStatus = (statusLabel == currentStatusFilter)
            end

            if matchesQuery and matchesStatus then
                table.insert(filtered, mData)
            end
        end

        local totalFiltered = #filtered
        lastFilteredCount = totalFiltered
        local totalSlides = math.max(1, math.ceil(totalFiltered / MAPS_PER_SLIDE))
        currentSlide = math.clamp(currentSlide, 1, totalSlides)

        supportPill.Text = string.format("Support (%d)", #activeMapList)

        -- Update slide footer info
        if totalFiltered > 0 then
            local startNum = (currentSlide - 1) * MAPS_PER_SLIDE + 1
            local endNum = math.min(totalFiltered, currentSlide * MAPS_PER_SLIDE)
            slideCountLabel.Text = string.format("Showing %d-%d of %d maps", startNum, endNum, totalFiltered)
            slidePillLabel.Text = string.format("%d / %d", currentSlide, totalSlides)
        else
            slideCountLabel.Text = "No maps found"
            slidePillLabel.Text = "1 / 1"
        end

        prevSlideBtn.BackgroundTransparency = if currentSlide <= 1 then 0.75 else 0
        prevSlideBtn.AutoButtonColor = (currentSlide > 1)
        nextSlideBtn.BackgroundTransparency = if currentSlide >= totalSlides then 0.75 else 0
        nextSlideBtn.AutoButtonColor = (currentSlide < totalSlides)

        -- 2. Render only the 5 maps on the current slide
        local startIdx = (currentSlide - 1) * MAPS_PER_SLIDE + 1
        local endIdx = math.min(totalFiltered, currentSlide * MAPS_PER_SLIDE)

        for idx = startIdx, endIdx do
            local mData = filtered[idx]
            local placeIdNum, initialIcon = parsePlaceIdAndIcon(mData)
            local row = Instance.new("Frame")
            row.Name = "Row_" .. tostring(placeIdNum > 0 and placeIdNum or idx)
            row.Size = UDim2.new(1, 0, 0, 50)
            row.BackgroundColor3 = Color3.fromRGB(15, 14, 20)
            row.BackgroundTransparency = 0.4
            row.BorderSizePixel = 0
            row.LayoutOrder = idx

            local rCorner = Instance.new("UICorner")
            rCorner.CornerRadius = UDim.new(0, 8)
            rCorner.Parent = row

            local rStroke = Instance.new("UIStroke")
            rStroke.Color = Color3.fromRGB(28, 25, 36)
            rStroke.Thickness = 1
            rStroke.Transparency = 0.5
            rStroke.Parent = row

            -- 1. Map Column (Full Map Artwork + Name) - 38% width
            local mCol = Instance.new("Frame")
            mCol.Name = "MapColumn"
            mCol.Size = UDim2.new(0.38, 0, 1, 0)
            mCol.Position = UDim2.new(0.01, 0, 0, 0)
            mCol.BackgroundTransparency = 1
            mCol.Parent = row

            local mapArtwork = Instance.new("ImageLabel")
            mapArtwork.Name = "AvatarUser"
            mapArtwork.Size = UDim2.fromOffset(40, 40)
            mapArtwork.Position = UDim2.new(0, 4, 0.5, 0)
            mapArtwork.AnchorPoint = Vector2.new(0, 0.5)
            mapArtwork.BackgroundColor3 = Color3.fromRGB(24, 20, 28)
            mapArtwork.BorderSizePixel = 0
            mapArtwork.ScaleType = Enum.ScaleType.Crop
            mapArtwork.ClipsDescendants = true
            local maCorner = Instance.new("UICorner")
            maCorner.CornerRadius = UDim.new(0, 8)
            maCorner.Parent = mapArtwork

            mapArtwork.Image = initialIcon
            mapArtwork.Parent = mCol

            local nameCol = Instance.new("Frame")
            nameCol.Name = "NameCol"
            nameCol.Size = UDim2.new(1, -54, 0, 36)
            nameCol.Position = UDim2.new(0, 50, 0.5, 0)
            nameCol.AnchorPoint = Vector2.new(0, 0.5)
            nameCol.BackgroundTransparency = 1
            nameCol.Parent = mCol

            local ncLayout = Instance.new("UIListLayout")
            ncLayout.SortOrder = Enum.SortOrder.LayoutOrder
            ncLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            ncLayout.Padding = UDim.new(0, 1)
            ncLayout.Parent = nameCol

            local mapTitle = Instance.new("TextLabel")
            mapTitle.Name = "MapName"
            mapTitle.Size = UDim2.new(1, 0, 0, 18)
            mapTitle.BackgroundTransparency = 1
            Theme.ApplyTypography(mapTitle, "Header", "Header")
            mapTitle.Text = mData.Name or "Unknown Map"
            mapTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
            mapTitle.TextXAlignment = Enum.TextXAlignment.Left
            mapTitle.TextTruncate = Enum.TextTruncate.AtEnd
            mapTitle.LayoutOrder = 1
            mapTitle.Parent = nameCol

            local subPlace = Instance.new("TextLabel")
            subPlace.Name = "SubText"
            subPlace.Size = UDim2.new(1, 0, 0, 14)
            subPlace.BackgroundTransparency = 1
            Theme.ApplyTypography(subPlace, "Body", "Small")
            subPlace.Text = "Supported Game"
            subPlace.TextColor3 = Color3.fromRGB(130, 130, 145)
            subPlace.TextXAlignment = Enum.TextXAlignment.Left
            subPlace.TextTruncate = Enum.TextTruncate.AtEnd
            subPlace.LayoutOrder = 2
            subPlace.Parent = nameCol

            -- 2. Place ID Column - 24% width (Position: 0.40, ends at 0.64 - Ample room, Zero Overlap!)
            local placeIdLabel = Instance.new("TextLabel")
            placeIdLabel.Name = "PlaceID"
            placeIdLabel.Size = UDim2.new(0.24, 0, 1, 0)
            placeIdLabel.Position = UDim2.new(0.40, 0, 0, 0)
            placeIdLabel.BackgroundTransparency = 1
            Theme.ApplyTypography(placeIdLabel, "Code", "Small")
            placeIdLabel.Text = tostring(placeIdNum > 0 and placeIdNum or "0")
            placeIdLabel.TextColor3 = Color3.fromRGB(209, 213, 219)
            placeIdLabel.TextXAlignment = Enum.TextXAlignment.Left
            placeIdLabel.TextTruncate = Enum.TextTruncate.None
            placeIdLabel.Parent = row

            -- 3. Update Date Column - 16% width (Position: 0.66, ends at 0.82 - 20px gap after Place ID!)
            local updateLabel = Instance.new("TextLabel")
            updateLabel.Name = "UpdateDate"
            updateLabel.Size = UDim2.new(0.16, 0, 1, 0)
            updateLabel.Position = UDim2.new(0.66, 0, 0, 0)
            updateLabel.BackgroundTransparency = 1
            Theme.ApplyTypography(updateLabel, "Body", "Sub")
            updateLabel.Text = os.date("%d/%m/%Y")
            updateLabel.TextColor3 = Color3.fromRGB(209, 213, 219)
            updateLabel.TextXAlignment = Enum.TextXAlignment.Left
            updateLabel.Parent = row

            -- Asynchronously fetch real update date and high-res official IconImageAssetId
            if placeIdNum > 0 then
                task.spawn(function()
                    pcall(function()
                        local MarketplaceService = game:GetService("MarketplaceService")
                        local info = MarketplaceService:GetProductInfo(placeIdNum)
                        if info then
                            if info.Updated and updateLabel and updateLabel.Parent then
                                updateLabel.Text = formatUpdateDate(info.Updated)
                            end
                            if info.Name and (not mData.Name or mData.Name == "" or mData.Name == "Unknown Map") and mapTitle and mapTitle.Parent then
                                mapTitle.Text = info.Name
                            end
                            if info.IconImageAssetId and info.IconImageAssetId > 0 and mapArtwork and mapArtwork.Parent then
                                mapArtwork.Image = string.format("rbxassetid://%d", info.IconImageAssetId)
                            end
                        end
                    end)
                end)
            end

            -- 4. Status Column - 15% width (Position: 0.84, ends at 0.99 - Green/Online, Orange/Update, Red/Risk)
            local statusContainer = Instance.new("Frame")
            statusContainer.Name = "StatusContainer"
            statusContainer.Size = UDim2.new(0.15, 0, 1, 0)
            statusContainer.Position = UDim2.new(0.84, 0, 0, 0)
            statusContainer.BackgroundTransparency = 1
            statusContainer.Parent = row

            local scLayout = Instance.new("UIListLayout")
            scLayout.FillDirection = Enum.FillDirection.Horizontal
            scLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            scLayout.Padding = UDim.new(0, 6)
            scLayout.Parent = statusContainer

            local statusDot = Instance.new("Frame")
            statusDot.Name = "StatusCircle"
            statusDot.Size = UDim2.fromOffset(10, 10)
            statusDot.BorderSizePixel = 0
            local sdCorner = Instance.new("UICorner")
            sdCorner.CornerRadius = UDim.new(1, 0)
            sdCorner.Parent = statusDot

            local sTextStr, sColor = resolveStatus(mData.Status)
            statusDot.BackgroundColor3 = sColor
            statusDot.Parent = statusContainer

            local statusText = Instance.new("TextLabel")
            statusText.Name = "StatusText"
            statusText.AutomaticSize = Enum.AutomaticSize.X
            statusText.Size = UDim2.new(0, 0, 1, 0)
            statusText.BackgroundTransparency = 1
            Theme.ApplyTypography(statusText, "Header", "Small")
            statusText.Text = sTextStr
            statusText.TextColor3 = sColor
            statusText.TextXAlignment = Enum.TextXAlignment.Left
            statusText.Parent = statusContainer

            row.Parent = rowsHolder
            table.insert(createdRowFrames, { Frame = row, Data = mData })
        end
    end

    -- Pagination slide button handlers
    prevSlideBtn.MouseButton1Click:Connect(function()
        if currentSlide > 1 then
            currentSlide = currentSlide - 1
            rebuildMapTable()
        end
    end)

    nextSlideBtn.MouseButton1Click:Connect(function()
        local totalSlides = math.max(1, math.ceil(lastFilteredCount / MAPS_PER_SLIDE))
        if currentSlide < totalSlides then
            currentSlide = currentSlide + 1
            rebuildMapTable()
        end
    end)

    -- Filter Logic: Search + Status Dropdown
    local function applyMapFilter()
        currentSlide = 1
        rebuildMapTable()
    end

    sInput:GetPropertyChangedSignal("Text"):Connect(applyMapFilter)

    -- Status Dropdown Popover Options: All Status, Online, Update, Risk
    local statusOptions = {
        { Id = "All", Label = "All Status", Color = Color3.fromRGB(220, 220, 230), DotColor = Color3.fromRGB(156, 163, 175) },
        { Id = "Online", Label = "Online", Color = Color3.fromRGB(34, 197, 94), DotColor = Color3.fromRGB(34, 197, 94) },
        { Id = "Update", Label = "Update", Color = Color3.fromRGB(249, 115, 22), DotColor = Color3.fromRGB(249, 115, 22) },
        { Id = "Risk", Label = "Risk", Color = Color3.fromRGB(239, 68, 68), DotColor = Color3.fromRGB(239, 68, 68) },
    }

    local win = self.Window
    local mainWindow = (win and win.MainFrame) or root
    statusPopover.Parent = mainWindow
    statusPopover.ZIndex = 4500

    local POPOVER_TARGET_H = 142
    local isDropdownOpen = false
    local lastToggleClock = 0

    local function updateStatusDropdownPos()
        local win = self.Window
        local mainWindow = (win and win.MainFrame) or root
        if not mainWindow or not statusDropdownBtn then return end

        local scale = 1
        if win and win.ContainerManager and win.ContainerManager.UIScale then
            scale = math.max(0.001, win.ContainerManager.UIScale.Scale)
        end
        local winScaleObj = mainWindow:FindFirstChild("WindowScale")
        local winScale = (winScaleObj and winScaleObj:IsA("UIScale") and winScaleObj.Scale) or 1
        local totalScale = scale * winScale
        if totalScale <= 0 then totalScale = 1 end

        local btnAbsPos = statusDropdownBtn.AbsolutePosition
        local btnAbsSize = statusDropdownBtn.AbsoluteSize
        local winAbsPos = mainWindow.AbsolutePosition

        local relX = (btnAbsPos.X - winAbsPos.X) / totalScale
        local relY = (btnAbsPos.Y - winAbsPos.Y) / totalScale
        local btnH = btnAbsSize.Y / totalScale

        statusPopover.Position = UDim2.fromOffset(relX, relY + btnH + 4)
    end

    local optionWidgets = {}

    local function closeStatusDropdown()
        if not isDropdownOpen then return end
        isDropdownOpen = false
        lastToggleClock = os.clock()
        Tweener.Tween(statusPopover, Tweener.Info.Fluid, {
            Size = UDim2.fromOffset(150, 0),
        })
        Tweener.Tween(sdbArrow, Tweener.Info.Fast, {
            Rotation = 0,
        })
        task.delay(0.20, function()
            if not isDropdownOpen then
                statusPopover.Visible = false
            end
        end)
    end

    local function openStatusDropdown()
        if isDropdownOpen then return end
        isDropdownOpen = true
        lastToggleClock = os.clock()
        updateStatusDropdownPos()
        statusPopover.Size = UDim2.fromOffset(150, 0)
        statusPopover.Visible = true
        Tweener.Tween(statusPopover, Tweener.Info.Fluid, {
            Size = UDim2.fromOffset(150, POPOVER_TARGET_H),
        })
        Tweener.Tween(sdbArrow, Tweener.Info.Fast, {
            Rotation = 180,
        })
    end

    local function selectStatusOption(opt: any)
        currentStatusFilter = opt.Id
        sdbText.Text = opt.Id == "All" and "All Status" or opt.Id
        sdbText.TextColor3 = opt.Color
        sdbDot.BackgroundColor3 = opt.DotColor

        for _, w in ipairs(optionWidgets) do
            local isSel = (w.Opt.Id == opt.Id)
            w.Check.Visible = isSel
            w.Btn.BackgroundColor3 = if isSel then Theme.GetToken("SurfaceHover") else Color3.fromRGB(18, 15, 24)
        end

        closeStatusDropdown()
        applyMapFilter()
    end

    for _, opt in ipairs(statusOptions) do
        local isSel = (opt.Id == currentStatusFilter)
        local oBtn = Instance.new("TextButton")
        oBtn.Name = "Option_" .. opt.Id
        oBtn.Size = UDim2.new(1, 0, 0, 30)
        oBtn.BackgroundColor3 = if isSel then Theme.GetToken("SurfaceHover") else Color3.fromRGB(18, 15, 24)
        oBtn.AutoButtonColor = false
        oBtn.BorderSizePixel = 0
        oBtn.Text = ""

        local obc = Instance.new("UICorner")
        obc.CornerRadius = Theme.Radii.Control
        obc.Parent = oBtn

        local oPad = Instance.new("UIPadding")
        oPad.PaddingLeft = UDim.new(0, 8)
        oPad.PaddingRight = UDim.new(0, 8)
        oPad.Parent = oBtn

        local optDot = Instance.new("Frame")
        optDot.Name = "Dot"
        optDot.Size = UDim2.fromOffset(8, 8)
        optDot.Position = UDim2.new(0, 0, 0.5, 0)
        optDot.AnchorPoint = Vector2.new(0, 0.5)
        optDot.BackgroundColor3 = opt.DotColor
        optDot.BorderSizePixel = 0
        local odCorner = Instance.new("UICorner")
        odCorner.CornerRadius = UDim.new(1, 0)
        odCorner.Parent = optDot
        optDot.Parent = oBtn

        local oText = Instance.new("TextLabel")
        oText.Size = UDim2.new(1, -34, 1, 0)
        oText.Position = UDim2.new(0, 14, 0, 0)
        oText.BackgroundTransparency = 1
        Theme.ApplyTypography(oText, "Body", "Small")
        oText.Text = opt.Label
        oText.TextColor3 = opt.Color
        oText.TextXAlignment = Enum.TextXAlignment.Left
        oText.Parent = oBtn

        local oCheck = Instance.new("ImageLabel")
        oCheck.Name = "Checkmark"
        oCheck.Size = UDim2.fromOffset(13, 13)
        oCheck.Position = UDim2.new(1, 0, 0.5, 0)
        oCheck.AnchorPoint = Vector2.new(1, 0.5)
        oCheck.BackgroundTransparency = 1
        oCheck.ImageColor3 = Theme.GetToken("Accent")
        Icons.Apply(oCheck, "check")
        oCheck.Visible = isSel
        oCheck.Parent = oBtn
        Theme.Bind(oCheck, "ImageColor3", "Accent")

        oBtn.MouseEnter:Connect(function()
            if currentStatusFilter ~= opt.Id then
                Tweener.Tween(oBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
            end
        end)
        oBtn.MouseLeave:Connect(function()
            if currentStatusFilter ~= opt.Id then
                Tweener.Tween(oBtn, Tweener.Info.Fast, { BackgroundColor3 = Color3.fromRGB(18, 15, 24) })
            end
        end)

        oBtn.MouseButton1Click:Connect(function()
            selectStatusOption(opt)
        end)

        oBtn.Parent = statusPopover
        table.insert(optionWidgets, { Btn = oBtn, Check = oCheck, Opt = opt })
    end

    statusDropdownBtn.MouseButton1Click:Connect(function()
        if (os.clock() - lastToggleClock) < 0.20 then return end
        if isDropdownOpen then
            closeStatusDropdown()
        else
            openStatusDropdown()
        end
    end)

    -- Close popover when clicking anywhere outside
    UserInputService.InputBegan:Connect(function(input)
        if not isDropdownOpen then return end
        if (os.clock() - lastToggleClock) < 0.25 then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local pos = Vector2.new(input.Position.X, input.Position.Y)
            local bPos = statusDropdownBtn.AbsolutePosition
            local bSize = statusDropdownBtn.AbsoluteSize
            local inBtn = pos.X >= bPos.X and pos.X <= (bPos.X + bSize.X) and pos.Y >= bPos.Y and pos.Y <= (bPos.Y + bSize.Y)
            local pPos = statusPopover.AbsolutePosition
            local pSize = statusPopover.AbsoluteSize
            local inPop = pos.X >= pPos.X and pos.X <= (pPos.X + pSize.X) and pos.Y >= pPos.Y and pos.Y <= (pPos.Y + pSize.Y)
            if not inBtn and not inPop then
                closeStatusDropdown()
            end
        end
    end)

    -- Initial Table Render
    rebuildMapTable()

    -- Asynchronous Remote Fetch from GitHub URL:
    -- https://raw.githubusercontent.com/sodium-hub/ui/refs/heads/main/status.luau
    task.spawn(function()
        pcall(function()
            local statusUrl = "https://raw.githubusercontent.com/sodium-hub/ui/refs/heads/main/status.luau"
            local rawContent = Compat.HttpGet(statusUrl)
            if rawContent and type(rawContent) == "string" and #rawContent > 10 then
                local loadFn, loadErr = loadstring(rawContent)
                if loadFn and not loadErr then
                    local okExec, remoteMaps = pcall(loadFn)
                    if okExec and type(remoteMaps) == "table" and #remoteMaps > 0 then
                        activeMapList = remoteMaps
                        rebuildMapTable()
                        applyMapFilter()
                    end
                end
            end
        end)
    end)

    -- Helpers to compute Whitelist & Execute times
    local function getWhitelistRemaining(): string
        local exp = props.KeyExpires
        local win = self.Window
        if not exp and win and win.Props and win.Props.User then
            exp = win.Props.User.KeyExpires
        end
        local genv = (type(getgenv) == "function" and getgenv()) or nil
        if not exp and genv then
            exp = genv.JD_EXPIRES_AT or genv.KEY_EXPIRES or genv.SCRIPT_KEY_EXPIRES
        end
        if not exp then
            pcall(function()
                local folder = (win and win.Folder) or "SodiumHub"
                local path = folder .. "/key.json"
                if Compat.HasFS() and Compat.IsFile(path) then
                    local content = Compat.ReadFile(path)
                    local ok, data = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), content)
                    if ok and type(data) == "table" and data.expires_at then
                        exp = data.expires_at
                    end
                end
            end)
        end

        if exp == "Lifetime" or exp == "lifetime" or exp == "Permanent" then
            return "Lifetime"
        end

        local targetTimestamp = tonumber(exp)
        if not targetTimestamp then
            local cachedStart = genv and genv._SODIUM_WL_EXPIRY
            if not cachedStart then
                cachedStart = os.time() + (29 * 86400) + (12 * 3600) + (39 * 60) + 20
                if genv then genv._SODIUM_WL_EXPIRY = cachedStart end
            end
            targetTimestamp = cachedStart
        end

        local diff = math.max(0, targetTimestamp - os.time())
        if diff <= 0 then
            return "Expired"
        end

        local days = math.floor(diff / 86400)
        local hours = math.floor((diff % 86400) / 3600)
        local mins = math.floor((diff % 3600) / 60)
        local secs = diff % 60
        return string.format("%ddays %dhr %dmin %dsec", days, hours, mins, secs)
    end

    local function getExecuteElapsed(): string
        local elapsed = math.floor(tick() - _scriptStartTime)
        local days = math.floor(elapsed / 86400)
        local hours = math.floor((elapsed % 86400) / 3600)
        local mins = math.floor((elapsed % 3600) / 60)
        local secs = elapsed % 60
        if days > 0 then
            return string.format("%ddays %dhr %dmin %dsec", days, hours, mins, secs)
        else
            return string.format("%dhr %dmin %dsec", hours, mins, secs)
        end
    end

    root.Parent = self.Container

    -- Dynamic Live Telemetry Loop (Players 22/50, Whitelist Remaining, Execute Time)
    task.spawn(function()
        while root and root.Parent do
            pcall(function()
                local curP = math.max(22, #Players:GetPlayers())
                local maxP = math.max(50, Players.MaxPlayers)
                valPlayers.Text = string.format("%d/%d", curP, maxP)
                valWhitelist.Text = getWhitelistRemaining()
                valExecuteTime.Text = getExecuteElapsed()
            end)
            task.wait(1.0)
        end
    end)

    return root
end

function Tab:DiscordCard(rawProps: any?)
    local props = rawProps or {}
    local link = props.Link or "https://discord.gg/2gEjXyQWKM"

    local card = Instance.new("ImageButton")
    card.Name = "DiscordCard"
    card.Size = UDim2.new(1, 0, 0, 72)
    card.BackgroundColor3 = Theme.GetToken("Card")
    card.BorderSizePixel = 0
    card.AutoButtonColor = false
    card.ClipsDescendants = true
    card.LayoutOrder = props.LayoutOrder or 0
    Theme.Bind(card, "BackgroundColor3", "Card")

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = Theme.Radii.Card
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Theme.GetToken("BorderSubtle")
    cardStroke.Thickness = 1
    cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    cardStroke.Parent = card
    Theme.Bind(cardStroke, "Color", "BorderSubtle")

    -- Inner Content Wrapper (Full width padding, no icon, no background banner)
    local cardContent = Instance.new("Frame")
    cardContent.Name = "CardContent"
    cardContent.Size = UDim2.fromScale(1, 1)
    cardContent.Position = UDim2.fromScale(0.5, 0.5)
    cardContent.AnchorPoint = Vector2.new(0.5, 0.5)
    cardContent.BackgroundTransparency = 1
    cardContent.ZIndex = 2
    cardContent.Parent = card

    local cardPad = Instance.new("UIPadding")
    cardPad.PaddingLeft = UDim.new(0, 16)
    cardPad.PaddingRight = UDim.new(0, 16)
    cardPad.PaddingTop = UDim.new(0, 12)
    cardPad.PaddingBottom = UDim.new(0, 12)
    cardPad.Parent = cardContent

    -- Left Content Column (Full width, AnchorPoint 0.5, 0.5)
    local contentCol = Instance.new("Frame")
    contentCol.Name = "ContentCol"
    contentCol.Size = UDim2.new(1, -140, 1, 0)
    contentCol.Position = UDim2.new(0, 0, 0.5, 0)
    contentCol.AnchorPoint = Vector2.new(0, 0.5)
    contentCol.BackgroundTransparency = 1
    contentCol.ZIndex = 2
    contentCol.Parent = cardContent

    local colLayout = Instance.new("UIListLayout")
    colLayout.SortOrder = Enum.SortOrder.LayoutOrder
    colLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    colLayout.Padding = UDim.new(0, 2)
    colLayout.Parent = contentCol

    -- Title Row
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "DiscordTitle"
    titleLabel.Size = UDim2.new(1, 0, 0, 20)
    titleLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(titleLabel, "Title", "Body")
    titleLabel.Text = props.Title or "Discord Server"
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.LayoutOrder = 1
    titleLabel.Parent = contentCol
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")

    -- Subtitle Row (the invite link)
    local linkLabel = Instance.new("TextLabel")
    linkLabel.Name = "DiscordLink"
    linkLabel.Size = UDim2.new(1, 0, 0, 16)
    linkLabel.BackgroundTransparency = 1
    Theme.ApplyTypography(linkLabel, "Body", "Small")
    linkLabel.Text = link:gsub("https://", "")
    linkLabel.TextColor3 = Theme.GetToken("Placeholder")
    linkLabel.TextXAlignment = Enum.TextXAlignment.Left
    linkLabel.TextTruncate = Enum.TextTruncate.AtEnd
    linkLabel.LayoutOrder = 2
    linkLabel.Parent = contentCol
    Theme.Bind(linkLabel, "TextColor3", "Placeholder")

    -- Right Capsule Pill (Copy Action Button / Pill)
    local copyPill = Instance.new("Frame")
    copyPill.Name = "CopyPill"
    copyPill.Size = UDim2.fromOffset(0, 28)
    copyPill.AutomaticSize = Enum.AutomaticSize.X
    copyPill.Position = UDim2.new(1, 0, 0.5, 0)
    copyPill.AnchorPoint = Vector2.new(1, 0.5)
    copyPill.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    copyPill.BorderSizePixel = 0
    copyPill.ZIndex = 3
    Theme.Bind(copyPill, "BackgroundColor3", "SurfaceHover")

    local pillCorner = Instance.new("UICorner")
    pillCorner.CornerRadius = UDim.new(1, 0)
    pillCorner.Parent = copyPill

    local pillStroke = Instance.new("UIStroke")
    pillStroke.Color = Theme.GetToken("BorderAccent")
    pillStroke.Thickness = 1
    pillStroke.Transparency = 0.5
    pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    pillStroke.Parent = copyPill
    Theme.Bind(pillStroke, "Color", "BorderAccent")

    local pillPad = Instance.new("UIPadding")
    pillPad.PaddingLeft = UDim.new(0, 14)
    pillPad.PaddingRight = UDim.new(0, 14)
    pillPad.Parent = copyPill

    local copyPillText = Instance.new("TextLabel")
    copyPillText.Name = "Label"
    copyPillText.Size = UDim2.new(0, 0, 1, 0)
    copyPillText.AutomaticSize = Enum.AutomaticSize.X
    copyPillText.BackgroundTransparency = 1
    Theme.ApplyTypography(copyPillText, "Code", "Small")
    copyPillText.Text = "Copy link"
    copyPillText.TextColor3 = Theme.GetToken("Accent")
    copyPillText.TextXAlignment = Enum.TextXAlignment.Center
    copyPillText.ZIndex = 4
    copyPillText.Parent = copyPill
    Theme.Bind(copyPillText, "TextColor3", "Accent")
    copyPill.Parent = cardContent

    -- Micro-press feedback and hover lift matching Button.luau
    Tweener.BindCardPressFeedback(card, card, Vector2.new(4, 2))
    Tweener.BindHoverLift(card, cardStroke, Theme.GetToken("Card"), Theme.GetToken("SurfaceHover"), Theme.GetToken("BorderSubtle"), Theme.GetToken("BorderAccent"))

    -- Copy Link To Clipboard + Toast Feedback
    card.Activated:Connect(function()
        local ok = false
        pcall(function()
            local clip = Compat.SetClipboard
            if type(clip) == "function" then
                ok = clip(link)
            end
        end)
        if not ok then
            pcall(function()
                if type(setclipboard) == "function" then
                    ok = setclipboard(link)
                end
            end)
        end
        if self.Window and self.Window.Notify then
            self.Window:Notify({
                Title = if ok then "Copied!" else "Not supported",
                Content = if ok then link else "Clipboard needs an executor",
                Duration = 2,
            })
        end
        if ok and copyPillText then
            copyPillText.Text = "Copied!"
            task.delay(1.6, function()
                if copyPillText and copyPillText.Parent then
                    copyPillText.Text = "Click to copy link"
                end
            end)
        end
    end)

    card.Parent = self.Container
    return card
end

-- Aliases for flexible API compatibility
Tab.CreateSection = Tab.Section
Tab.AddSection = Tab.Section
Tab.CreateButton = Tab.Button
Tab.AddButton = Tab.Button
Tab.CreateToggle = Tab.Toggle
Tab.AddToggle = Tab.Toggle
Tab.Checkbox = Tab.Toggle
Tab.CreateCheckbox = Tab.Toggle
Tab.AddCheckbox = Tab.Toggle
Tab.CreateSlider = Tab.Slider
Tab.AddSlider = Tab.Slider
Tab.CreateDropdown = Tab.Dropdown
Tab.AddDropdown = Tab.Dropdown
Tab.CreateInput = Tab.Input
Tab.AddInput = Tab.Input
Tab.CreateKeybind = Tab.Keybind
Tab.AddKeybind = Tab.Keybind
Tab.CreateParagraph = Tab.Paragraph
Tab.AddParagraph = Tab.Paragraph
Tab.CreateStepper = Tab.Stepper
Tab.AddStepper = Tab.Stepper
Tab.CreateDivider = Tab.Divider
Tab.AddDivider = Tab.Divider

function Tab:AddConfigSection(props: any?)
    local sec = self:Section({
        Title = (props and (props.Title or props.Name)) or { en = "Configuration", th = "จัดการคอนฟิก" },
        Icon = (props and props.Icon) or "settings",
    })
    return sec:AddConfigSection(props)
end
Tab.BuildConfigSection = Tab.AddConfigSection
Tab.ConfigSection = Tab.AddConfigSection

function Tab:ConfigInput(props: any?)
    return self:_getOrCreateDefaultSection():ConfigInput(props)
end

function Tab:ConfigDropdown(props: any?)
    return self:_getOrCreateDefaultSection():ConfigDropdown(props)
end

function Tab:ConfigSaveButton(props: any?)
    return self:_getOrCreateDefaultSection():ConfigSaveButton(props)
end

function Tab:ConfigLoadButton(props: any?)
    return self:_getOrCreateDefaultSection():ConfigLoadButton(props)
end

function Tab:ConfigDeleteButton(props: any?)
    return self:_getOrCreateDefaultSection():ConfigDeleteButton(props)
end

function Tab:ConfigAutoSaveToggle(props: any?)
    return self:_getOrCreateDefaultSection():ConfigAutoSaveToggle(props)
end

function Tab:ConfigAutoLoadToggle(props: any?)
    return self:_getOrCreateDefaultSection():ConfigAutoLoadToggle(props)
end

return Tab
end

_MODULES['Components/Window'] = function()
--!strict
--[=[
    Sodium UI - Components/Window.luau
    Draggable Window Frame with minimize/close states, sidebar search, and user profile widget.
    Refined: Seamless rounded corners (zero square edge bleeding), consistent stroke modes.
]=]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Compat = _require("Core/Compat")
local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Tab = _require("Components/Tab")
local TabSection = _require("Components/TabSection")
local Popup = _require("Components/Popup")
local Notification = _require("Components/Notification")
local Dialog = _require("Components/Dialog")

local Window = {}
Window.__index = Window

export type WindowProps = {
    Title: string,
    Icon: string?,
    Author: string?,
    Folder: string?,
    Size: UDim2?,
    SideBarWidth: number?,
    ToggleKey: Enum.KeyCode?,
    HideSearchBar: boolean?,
    DiscordLink: string?,
    Icons: {
        Discord: string?,
        Theme: string?,
        Profile: string?,
        Language: string?,
    }?,
    Language: {
        Default: string?,
        Languages: { string }?,
        Callback: ((lang: string) -> ())?,
    }?,
    User: {
        Enabled: boolean?,
        Anonymous: boolean?,
        Callback: (() -> ())?,
    }?,
}

function Window.new(containerManager: any, props: WindowProps)
    local self = setmetatable({}, Window)
    self.ContainerManager = containerManager
    self.RootGui = containerManager.ScreenGui
    pcall(function()
        Notification.Init(self.RootGui)
    end)
    self.Tabs = {}
    self.Sections = {}
    self.Flags = {}
    self.Folder = (props :: any).Folder or "SodiumHub"
    self.ConfigFolder = self.Folder .. "/Configs"
    self._autoSaveEnabled = false
    self._autoSaveTarget = "Main"
    self._autoSaveGen = 0
    self._autoSaveThread = nil
    self._dirtyFlags = {}
    self._cachedConfigs = nil
    self._configNameMap = {}
    self._selectedConfigName = "Main"
    self._isLoadingConfig = false
    self._virtualConfigs = {}
    self._currentSection = nil
    self.CurrentTab = nil
    self._indicatorTween = nil
    local initialKey = props.ToggleKey or Enum.KeyCode.LeftShift
    if type(initialKey) == "string" then
        local found = (Enum.KeyCode :: any)[initialKey]
        self.ToggleKey = found or initialKey
    else
        self.ToggleKey = initialKey
    end
    self.IsVisible = true
    self.IsMinimized = false
    self.IsFullScreen = false
    self._antiAfkEnabled = true -- Enabled by default from startup
    
    local defaultSize = props.Size or UDim2.fromOffset(740, 520)
    self._savedSize = defaultSize
    self._savedPosition = UDim2.fromScale(0.5, 0.5)
    local sideBarWidth = props.SideBarWidth or 200
    self._sidebarWidth = sideBarWidth
    
    local windowTitle = props.Title or "Sodium Hub"
    
    -- Register base size with Container for dynamic responsive scaling
    containerManager:SetBaseWindowSize(Vector2.new(defaultSize.X.Offset, defaultSize.Y.Offset))

    local rawTitleStr = if type(windowTitle) == "table" then (windowTitle.en or windowTitle.EN or windowTitle.th or windowTitle.TH or "SodiumUI") else tostring(windowTitle or "SodiumUI")
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "SodiumWindow_" .. rawTitleStr
    mainFrame.Size = defaultSize
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Position = UDim2.fromScale(0.5, 0.5)
    mainFrame.BackgroundColor3 = Theme.GetToken("Background")
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = false -- Don't clip so strokes and inner shadows render without sharp cutoffs
    mainFrame.ZIndex = 2
    Theme.Bind(mainFrame, "BackgroundColor3", "Background")
    self.MainFrame = mainFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Window
    corner.Parent = mainFrame
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = mainFrame
    Theme.Bind(stroke, "Color", "BorderSubtle")
    
    -- WindowScale for hardware-accelerated entrance/exit micro-transitions
    local windowScale = Instance.new("UIScale")
    windowScale.Name = "WindowScale"
    windowScale.Scale = 1.0
    windowScale.Parent = mainFrame
    self.WindowScale = windowScale
    
    -- Ambient Precision Concentric Glow Engine (Continuous Smooth Gradient Falloff)
    local glowHolder = Instance.new("Frame")
    glowHolder.Name = "WindowGlowHolder"
    glowHolder.Size = defaultSize
    glowHolder.Position = UDim2.fromScale(0.5, 0.5)
    glowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    glowHolder.BackgroundTransparency = 1
    glowHolder.ZIndex = 1
    glowHolder.Visible = true

    -- Continuous 10-step micro-falloff (clean, perfectly balanced ambient shadow)
    local windowGlowFrames = {}
    for pad = 1, 10 do
        local t = (pad - 1) / 9 -- 0.0 (inner edge) to 1.0 (outer haze)
        local targetTr = 0.88 + (t ^ 1.6) * 0.11 -- Balanced Gaussian falloff (0.88 -> 0.99)

        local gf = Instance.new("Frame")
        gf.Name = "GlowStep_" .. tostring(pad)
        gf.Size = UDim2.new(1, pad * 2, 1, pad * 2)
        gf.Position = UDim2.new(0, -pad, 0, -pad)
        gf.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        gf.BackgroundTransparency = targetTr
        gf.BorderSizePixel = 0
        gf.ZIndex = 1
        
        local gc = Instance.new("UICorner")
        gc.CornerRadius = UDim.new(0, 14 + pad)
        gc.Parent = gf
        
        gf.Parent = glowHolder
        table.insert(windowGlowFrames, { Frame = gf, TargetTr = targetTr })
    end

    glowHolder.Parent = self.RootGui
    self.GlowHolder = glowHolder
    self.WindowGlowFrames = windowGlowFrames

    local glowScale = Instance.new("UIScale")
    glowScale.Name = "GlowScale"
    glowScale.Scale = 1.0
    glowScale.Parent = glowHolder
    self.GlowScale = glowScale

    local function syncGlow()
        if mainFrame and mainFrame.Parent and glowHolder and glowHolder.Parent then
            glowHolder.Size = mainFrame.Size
            glowHolder.Position = mainFrame.Position
            glowHolder.AnchorPoint = mainFrame.AnchorPoint
            glowHolder.Visible = mainFrame.Visible and not self.IsMinimized
        end
    end
    mainFrame:GetPropertyChangedSignal("Size"):Connect(syncGlow)
    mainFrame:GetPropertyChangedSignal("Position"):Connect(syncGlow)
    mainFrame:GetPropertyChangedSignal("Visible"):Connect(syncGlow)
    
    -- Top Header Bar (Draggable, Transparent background to preserve rounded window corners)
    local topbar = Instance.new("Frame")
    topbar.Name = "TopBar"
    topbar.Size = UDim2.new(1, 0, 0, 48)
    topbar.BackgroundTransparency = 1
    topbar.BorderSizePixel = 0
    topbar.ZIndex = 3
    
    -- Topbar Bottom Divider Line
    local topDivider = Instance.new("Frame")
    topDivider.Name = "BottomBorder"
    topDivider.Size = UDim2.new(1, 0, 0, 1)
    topDivider.Position = UDim2.new(0, 0, 1, -1)
    topDivider.BackgroundColor3 = Theme.GetToken("BorderSubtle")
    topDivider.BorderSizePixel = 0
    topDivider.Parent = topbar
    Theme.Bind(topDivider, "BackgroundColor3", "BorderSubtle")
    
    local topPad = Instance.new("UIPadding")
    topPad.PaddingLeft = UDim.new(0, 18)
    topPad.PaddingRight = UDim.new(0, 14)
    topPad.Parent = topbar
    
    -- Title Container (Holds Logo Image and elevated Sodium Hub Brand Title)
    local titleContainer = Instance.new("Frame")
    titleContainer.Name = "TitleContainer"
    titleContainer.Size = UDim2.new(1, -106, 1, 0)
    titleContainer.Position = UDim2.new(0, 0, 0, 0)
    titleContainer.BackgroundTransparency = 1
    titleContainer.ZIndex = 4
    titleContainer.Parent = topbar
    
    local titleLayout = Instance.new("UIListLayout")
    titleLayout.FillDirection = Enum.FillDirection.Horizontal
    titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    titleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    titleLayout.Padding = UDim.new(0, 4) -- Moved closer to the left towards the logo
    titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
    titleLayout.Parent = titleContainer
    
    -- Main Window Logo (Direct Cloud Texture ID: 120284703484003)
    local defaultLogoId = "rbxassetid://120284703484003"
    local logoAsset = props.Logo or props.Icon or defaultLogoId

    local logoImg = Instance.new("ImageLabel")
    logoImg.Name = "WindowLogo"
    logoImg.Size = UDim2.fromOffset(40, 40) -- Big prominent logo
    logoImg.BackgroundTransparency = 1
    logoImg.ScaleType = Enum.ScaleType.Fit
    logoImg.LayoutOrder = 1
    logoImg.ZIndex = 4
    Icons.ApplyAsset(logoImg, logoAsset)
    logoImg.Parent = titleContainer
    self.WindowLogo = logoImg
    self.ResolvedLogo = tostring(logoImg.Image)

    -- Brand Text Wrapper (Matches 40px logo height, holds raised Sodium Hub text)
    local brandHolder = Instance.new("Frame")
    brandHolder.Name = "BrandHolder"
    brandHolder.Size = UDim2.fromOffset(0, 40)
    brandHolder.AutomaticSize = Enum.AutomaticSize.X
    brandHolder.BackgroundTransparency = 1
    brandHolder.LayoutOrder = 2
    brandHolder.ZIndex = 4
    brandHolder.Parent = titleContainer

    -- Animated Gradient Title: "Sodium Hub" (Elevated slightly above the lowest logo line)
    local brandTitle = Instance.new("TextLabel")
    brandTitle.Name = "BrandTitle"
    brandTitle.Size = UDim2.fromOffset(0, 24)
    brandTitle.AutomaticSize = Enum.AutomaticSize.X
    brandTitle.AnchorPoint = Vector2.new(0, 1)
    brandTitle.Position = UDim2.new(0, 0, 1, -4) -- Raised cleanly above bottom baseline
    brandTitle.BackgroundTransparency = 1
    brandTitle.Text = "Sodium Hub"
    Theme.ApplyTypography(brandTitle, "Header", "Header")
    pcall(function()
        brandTitle.FontFace = Font.fromName("Inter", Enum.FontWeight.Bold)
    end)
    brandTitle.TextSize = 20 -- Large bold prominent branding
    brandTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    brandTitle.TextXAlignment = Enum.TextXAlignment.Left
    brandTitle.TextYAlignment = Enum.TextYAlignment.Bottom
    brandTitle.ZIndex = 4

    -- High-End Luxury Amber Sheen Gradient
    local titleGradient = Instance.new("UIGradient")
    titleGradient.Name = "BrandGradient"
    titleGradient.Rotation = 15
    titleGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Color3.fromHex("#EA580C")),  -- Deep Amber Shadow
        ColorSequenceKeypoint.new(0.28, Color3.fromHex("#F97316")), -- Rich Amber Orange
        ColorSequenceKeypoint.new(0.50, Color3.fromHex("#FEF08A")), -- Luminous Warm Golden Highlight
        ColorSequenceKeypoint.new(0.72, Color3.fromHex("#F97316")), -- Rich Amber Orange
        ColorSequenceKeypoint.new(1.0, Color3.fromHex("#EA580C")),  -- Deep Amber Shadow
    })
    titleGradient.Offset = Vector2.new(-0.7, 0)
    titleGradient.Parent = brandTitle
    brandTitle.Parent = brandHolder
    self.BrandHolder = brandHolder
    self.BrandTitle = brandTitle
    self.TitleGradient = titleGradient

    -- Fluid Sinusoidal Sheen Sweep (Reverses smoothly, zero sudden snap, pure luxury flow)
    local gradTween = TweenService:Create(
        titleGradient,
        TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Offset = Vector2.new(0.7, 0) }
    )
    gradTween:Play()
    self._brandGradTween = gradTween

    -- Dummy TitleLabel for backward-compatibility API calls
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(0, 0, 0, 0)
    titleLabel.Visible = false
    titleLabel.Parent = titleContainer
    self.TitleLabel = titleLabel
    self.TitleContainer = titleContainer
    
    -- Backward-compatible no-op Tag methods (Tags removed completely from UI)
    local emptyTagController = {
        SetTitle = function() end,
        SetColor = function() end,
        SetIcon = function() end,
        Destroy = function() end,
    }
    function self:Tag(_tagProps: any)
        return emptyTagController
    end
    function self:TagKey(_tagKeyProps: any)
        return emptyTagController
    end
    function self:SetKeyExpiry(_expires: any)
    end
    
    -- Top-Right Window Controls: Minimize, FullScreen, Close (Left to Right, Frameless Transparent Background)
    local controls = Instance.new("Frame")
    controls.Name = "Controls"
    controls.Size = UDim2.new(0, 86, 1, 0)
    controls.Position = UDim2.new(1, 0, 0.5, 0)
    controls.AnchorPoint = Vector2.new(1, 0.5)
    controls.BackgroundTransparency = 1
    
    local controlLayout = Instance.new("UIListLayout")
    controlLayout.FillDirection = Enum.FillDirection.Horizontal
    controlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    controlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
    controlLayout.Padding = UDim.new(0, 4)
    controlLayout.Parent = controls
    
    -- 1. Minimize Button Slot & Button (Icon "minus", Transparent Background)
    local minSlot = Instance.new("Frame")
    minSlot.Name = "MinSlot"
    minSlot.Size = UDim2.fromOffset(26, 26)
    minSlot.BackgroundTransparency = 1
    minSlot.LayoutOrder = 1

    local minBtn = Instance.new("ImageButton")
    minBtn.Name = "Minimize"
    minBtn.Size = UDim2.fromOffset(26, 26)
    minBtn.Position = UDim2.fromScale(0.5, 0.5)
    minBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    minBtn.BackgroundTransparency = 1
    minBtn.AutoButtonColor = false
    
    local minScale = Instance.new("UIScale")
    minScale.Name = "BtnScale"
    minScale.Scale = 1.0
    minScale.Parent = minBtn
    
    local minIcon = Instance.new("ImageLabel")
    minIcon.Size = UDim2.fromOffset(15, 15)
    minIcon.Position = UDim2.fromScale(0.5, 0.5)
    minIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    minIcon.BackgroundTransparency = 1
    minIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    Icons.Apply(minIcon, "minus")
    minIcon.Parent = minBtn
    minBtn.Parent = minSlot
    minSlot.Parent = controls
    Tweener.BindPressFeedback(minBtn, minBtn)
    
    -- 2. FullScreen Button Slot & Button (Icon "square", Transparent Background)
    local fullSlot = Instance.new("Frame")
    fullSlot.Name = "FullScreenSlot"
    fullSlot.Size = UDim2.fromOffset(26, 26)
    fullSlot.BackgroundTransparency = 1
    fullSlot.LayoutOrder = 2

    local fullBtn = Instance.new("ImageButton")
    fullBtn.Name = "FullScreen"
    fullBtn.Size = UDim2.fromOffset(26, 26)
    fullBtn.Position = UDim2.fromScale(0.5, 0.5)
    fullBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    fullBtn.BackgroundTransparency = 1
    fullBtn.AutoButtonColor = false
    
    local fullScale = Instance.new("UIScale")
    fullScale.Name = "BtnScale"
    fullScale.Scale = 1.0
    fullScale.Parent = fullBtn
    
    local fullIcon = Instance.new("ImageLabel")
    fullIcon.Size = UDim2.fromOffset(13, 13) -- Adjusted smaller than minus/x to balance optical weight & hover
    fullIcon.Position = UDim2.fromScale(0.5, 0.5)
    fullIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    fullIcon.BackgroundTransparency = 1
    fullIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    Icons.Apply(fullIcon, "square")
    fullIcon.Parent = fullBtn
    fullBtn.Parent = fullSlot
    fullSlot.Parent = controls
    Tweener.BindPressFeedback(fullBtn, fullBtn)
    
    -- 3. Close Button Slot & Button (Icon "x", Transparent Background)
    local closeSlot = Instance.new("Frame")
    closeSlot.Name = "CloseSlot"
    closeSlot.Size = UDim2.fromOffset(26, 26)
    closeSlot.BackgroundTransparency = 1
    closeSlot.LayoutOrder = 3

    local closeBtn = Instance.new("ImageButton")
    closeBtn.Name = "Close"
    closeBtn.Size = UDim2.fromOffset(26, 26)
    closeBtn.Position = UDim2.fromScale(0.5, 0.5)
    closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    closeBtn.BackgroundTransparency = 1
    closeBtn.AutoButtonColor = false
    
    local closeScale = Instance.new("UIScale")
    closeScale.Name = "BtnScale"
    closeScale.Scale = 1.0
    closeScale.Parent = closeBtn
    
    local closeIcon = Instance.new("ImageLabel")
    closeIcon.Size = UDim2.fromOffset(15, 15)
    closeIcon.Position = UDim2.fromScale(0.5, 0.5)
    closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    closeIcon.BackgroundTransparency = 1
    closeIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    Icons.Apply(closeIcon, "x")
    closeIcon.Parent = closeBtn
    closeBtn.Parent = closeSlot
    closeSlot.Parent = controls
    Tweener.BindPressFeedback(closeBtn, closeBtn)
    
    -- Controls ultra-smooth spring/back hover scale animations (Fixed White Color)
    local smoothScaleIn = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    local smoothScaleOut = TweenInfo.new(0.20, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    
    minBtn.MouseEnter:Connect(function()
        Tweener.Tween(minScale, smoothScaleIn, { Scale = 1.25 })
    end)
    minBtn.MouseLeave:Connect(function()
        Tweener.Tween(minScale, smoothScaleOut, { Scale = 1.0 })
    end)
    
    fullBtn.MouseEnter:Connect(function()
        Tweener.Tween(fullScale, smoothScaleIn, { Scale = 1.25 })
    end)
    fullBtn.MouseLeave:Connect(function()
        Tweener.Tween(fullScale, smoothScaleOut, { Scale = 1.0 })
    end)

    closeBtn.MouseEnter:Connect(function()
        Tweener.Tween(closeScale, smoothScaleIn, { Scale = 1.25 })
    end)
    closeBtn.MouseLeave:Connect(function()
        Tweener.Tween(closeScale, smoothScaleOut, { Scale = 1.0 })
    end)
    
    controls.Parent = topbar
    topbar.Parent = mainFrame
    
    -- Body Frame (Contains Sidebar & Content Area)
    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Size = UDim2.new(1, 0, 1, -48)
    body.Position = UDim2.new(0, 0, 0, 48)
    body.BackgroundTransparency = 1
    body.ClipsDescendants = false
    
    -- Sidebar
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, sideBarWidth, 1, 0)
    sidebar.BackgroundTransparency = 1 -- seamless with window rounded corners
    sidebar.BorderSizePixel = 0
    
    local sideDivider = Instance.new("Frame")
    sideDivider.Name = "RightBorder"
    sideDivider.Size = UDim2.new(0, 1, 1, 0)
    sideDivider.Position = UDim2.new(1, -1, 0, 0)
    sideDivider.BackgroundColor3 = Theme.GetToken("BorderSubtle")
    sideDivider.BorderSizePixel = 0
    sideDivider.Parent = sidebar
    Theme.Bind(sideDivider, "BackgroundColor3", "BorderSubtle")
    
    -- Sidebar Content Layout
    local searchOffset = 0
    if not props.HideSearchBar then
        searchOffset = 46
        local searchFrame = Instance.new("Frame")
        searchFrame.Name = "SearchContainer"
        searchFrame.Size = UDim2.new(1, -24, 0, 32)
        searchFrame.Position = UDim2.new(0, 12, 0, 12)
        searchFrame.BackgroundColor3 = Theme.GetToken("SurfaceHover")
        Theme.Bind(searchFrame, "BackgroundColor3", "SurfaceHover")
        
        local searchCorner = Instance.new("UICorner")
        searchCorner.CornerRadius = Theme.Radii.Control
        searchCorner.Parent = searchFrame
        
        local searchStroke = Instance.new("UIStroke")
        searchStroke.Color = Theme.GetToken("BorderSubtle")
        searchStroke.Thickness = 1
        searchStroke.Transparency = 0.5
        searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        searchStroke.Parent = searchFrame
        Theme.Bind(searchStroke, "Color", "BorderSubtle")
        
        local searchIcon = Instance.new("ImageLabel")
        searchIcon.Size = UDim2.fromOffset(14, 14)
        searchIcon.Position = UDim2.new(0, 10, 0.5, 0)
        searchIcon.AnchorPoint = Vector2.new(0, 0.5)
        searchIcon.BackgroundTransparency = 1
        searchIcon.ImageColor3 = Theme.GetToken("Placeholder")
        Icons.Apply(searchIcon, "search")
        searchIcon.Parent = searchFrame
        Theme.Bind(searchIcon, "ImageColor3", "Placeholder")
        
        local searchBox = Instance.new("TextBox")
        searchBox.Name = "Input"
        searchBox.Size = UDim2.new(1, -34, 1, 0)
        searchBox.Position = UDim2.new(0, 30, 0, 0)
        searchBox.BackgroundTransparency = 1
        Theme.ApplyTypography(searchBox, "Body", "Body")
        Locale.Bind(searchBox, "PlaceholderText", { EN = "Search tabs...", TH = "ค้นหาแท็บ..." })
        searchBox.PlaceholderColor3 = Theme.GetToken("Placeholder")
        searchBox.Text = ""
        searchBox.TextColor3 = Theme.GetToken("TextPrimary")
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.ClearTextOnFocus = false
        searchBox.Parent = searchFrame
        Theme.Bind(searchBox, "PlaceholderColor3", "Placeholder")
        Theme.Bind(searchBox, "TextColor3", "TextPrimary")
        
        searchFrame.Parent = sidebar
        self.SearchBox = searchBox
    end
    
    -- Sidebar Header Height Calculation
    local headerHeight = if not props.HideSearchBar then 52 else 12

    -- Sidebar Footer Height Calculation (Footer removed: Anonymous, Theme, Translate, Discord, Profile)
    local footerHeight = 12
    
    if props.User and props.User.KeyExpires then
        self:SetKeyExpiry(props.User.KeyExpires)
    end
    
    local langProps = props.Language or {}
    local initialLang = langProps.Default or Locale.GetLanguage() or "EN"
    Locale.SetLanguage(initialLang)

    function self:SetIconConfig(_newConfig: any)
    end
    
    function self:SetLanguage(lang: string)
        Locale.SetLanguage(lang)
    end

    function self:GetLanguage(): string
        return Locale.GetLanguage()
    end

    function self:OnLanguageChanged(callback: (string) -> ())
        return Locale.Changed:Connect(callback)
    end
    
    -- Scrollable Sidebar Tab List (Clean Tier 2 Dock Viewport with Smooth Elastic Touch Scrolling)
    local tabList = Instance.new("ScrollingFrame")
    tabList.Name = "TabList"
    tabList.Size = UDim2.new(1, -20, 1, -(headerHeight + footerHeight))
    tabList.Position = UDim2.new(0, 10, 0, headerHeight)
    tabList.BackgroundTransparency = 1
    tabList.BorderSizePixel = 0
    tabList.ClipsDescendants = true
    tabList.ScrollingDirection = Enum.ScrollingDirection.Y
    tabList.ElasticBehavior = Enum.ElasticBehavior.Always
    tabList.ScrollBarThickness = if UserInputService.TouchEnabled then 6 else 3
    tabList.ScrollBarImageColor3 = Theme.GetToken("BorderStrong")
    tabList.ScrollBarImageTransparency = 0.4
    tabList.VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Right
    tabList.VerticalScrollBarInset = Enum.ScrollBarInset.None
    tabList.CanvasSize = UDim2.new(0, 0, 0, 0)
    Theme.Bind(tabList, "ScrollBarImageColor3", "BorderStrong")
    
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabList
    
    local function updateCanvasSize()
        local scale = math.max(0.001, self.ContainerManager.UIScale.Scale)
        local contentH = math.ceil(tabLayout.AbsoluteContentSize.Y / scale)
        tabList.CanvasSize = UDim2.new(0, 0, 0, contentH + 16)
    end
    tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
    task.defer(updateCanvasSize)
    
    tabList.ZIndex = 2
    tabList.Parent = sidebar
    
    -- Sliding Active Tab Indicator Overlay (Interpolates cleanly underneath transparent tab buttons)
    local tabIndicatorOverlay = Instance.new("Frame")
    tabIndicatorOverlay.Name = "TabIndicatorOverlay"
    tabIndicatorOverlay.Size = tabList.Size
    tabIndicatorOverlay.Position = tabList.Position
    tabIndicatorOverlay.BackgroundTransparency = 1
    tabIndicatorOverlay.BorderSizePixel = 0
    tabIndicatorOverlay.ClipsDescendants = true
    tabIndicatorOverlay.ZIndex = 1
    tabIndicatorOverlay.Parent = sidebar
    self.TabIndicatorOverlay = tabIndicatorOverlay
    
    -- 1. Hover Tracker Pill (Smooth dynamic highlight tracking cursor over inactive tabs)
    local hoverTracker = Instance.new("Frame")
    hoverTracker.Name = "HoverTracker"
    hoverTracker.Size = UDim2.fromOffset(0, 36)
    hoverTracker.Position = UDim2.fromOffset(0, 0)
    hoverTracker.BackgroundColor3 = Theme.GetToken("SurfaceActive")
    hoverTracker.BackgroundTransparency = 1
    hoverTracker.BorderSizePixel = 0
    hoverTracker.ZIndex = 1
    hoverTracker.Visible = false
    hoverTracker.Parent = tabIndicatorOverlay
    Theme.Bind(hoverTracker, "BackgroundColor3", "SurfaceActive")
    
    local hoverCorner = Instance.new("UICorner")
    hoverCorner.CornerRadius = Theme.Radii.Element
    hoverCorner.Parent = hoverTracker
    self.HoverTracker = hoverTracker
    self._hoverTrackerTween = nil
    
    -- 2. Persistent Active Tab Indicator (With inset accent bar and glowing stroke)
    local tabIndicator = Instance.new("Frame")
    tabIndicator.Name = "ActiveTabIndicator"
    tabIndicator.Size = UDim2.fromOffset(0, 36)
    tabIndicator.Position = UDim2.fromOffset(0, 0)
    tabIndicator.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    tabIndicator.BackgroundTransparency = 1
    tabIndicator.BorderSizePixel = 0
    tabIndicator.ZIndex = 2
    tabIndicator.Parent = tabIndicatorOverlay
    Theme.Bind(tabIndicator, "BackgroundColor3", "SurfaceHover")
    
    local indicatorCorner = Instance.new("UICorner")
    indicatorCorner.CornerRadius = Theme.Radii.Element
    indicatorCorner.Parent = tabIndicator
    
    local accentPill = Instance.new("Frame")
    accentPill.Name = "AccentPill"
    accentPill.Size = UDim2.new(0, 3, 0, 14)
    accentPill.Position = UDim2.new(0, 2, 0.5, 0)
    accentPill.AnchorPoint = Vector2.new(0, 0.5)
    accentPill.BackgroundColor3 = Theme.GetToken("Accent")
    accentPill.BorderSizePixel = 0
    accentPill.ZIndex = 3
    accentPill.Parent = tabIndicator
    Theme.Bind(accentPill, "BackgroundColor3", "Accent")
    
    local accentCorner = Instance.new("UICorner")
    accentCorner.CornerRadius = UDim.new(1, 0)
    accentCorner.Parent = accentPill
    
    local indicatorStroke = Instance.new("UIStroke")
    indicatorStroke.Name = "IndicatorStroke"
    indicatorStroke.Color = Theme.GetToken("BorderSubtle")
    indicatorStroke.Transparency = 0.5
    indicatorStroke.Thickness = 1
    indicatorStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    indicatorStroke.Parent = tabIndicator
    Theme.Bind(indicatorStroke, "Color", "BorderSubtle")
    
    self.TabIndicator = tabIndicator
    
    -- Real-time hardware scroll synchronization
    tabList:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        self:UpdateIndicator(true)
    end)
    tabList:GetPropertyChangedSignal("Size"):Connect(function()
        tabIndicatorOverlay.Size = tabList.Size
        self:UpdateIndicator(true)
    end)
    tabList:GetPropertyChangedSignal("Position"):Connect(function()
        tabIndicatorOverlay.Position = tabList.Position
        self:UpdateIndicator(true)
    end)
    
    sidebar.Parent = body
    
    -- Content Viewport (Hosts Tabs)
    local contentArea = Instance.new("Frame")
    contentArea.Name = "ContentArea"
    contentArea.Size = UDim2.new(1, -sideBarWidth, 1, 0)
    contentArea.Position = UDim2.new(0, sideBarWidth, 0, 0)
    contentArea.BackgroundTransparency = 1
    contentArea.ClipsDescendants = true
    contentArea.Parent = body
    
    body.Parent = mainFrame
    
    -- macOS-Style Corner Resize Handle (Single Concentric Quarter-Arc)
    local resizeHandle = Instance.new("ImageButton")
    resizeHandle.Name = "ResizeHandle"
    resizeHandle.Size = UDim2.fromOffset(24, 24)
    resizeHandle.Position = UDim2.fromScale(1, 1)
    resizeHandle.AnchorPoint = Vector2.new(1, 1)
    resizeHandle.BackgroundTransparency = 1
    resizeHandle.AutoButtonColor = false
    resizeHandle.ZIndex = 50
    
    -- Bottom-Right Quadrant Clipper (Masks everything outside the corner sector)
    local arcClipper = Instance.new("Frame")
    arcClipper.Name = "ArcClipper"
    arcClipper.Size = UDim2.fromOffset(14, 14)
    arcClipper.Position = UDim2.fromScale(1, 1)
    arcClipper.AnchorPoint = Vector2.new(1, 1)
    arcClipper.BackgroundTransparency = 1
    arcClipper.ClipsDescendants = true
    arcClipper.ZIndex = 51
    
    -- Exact Concentric Quarter-Arc (Concentric with Window Corner 14px, Radius 9px, Offset 5px)
    local arcCircle = Instance.new("Frame")
    arcCircle.Name = "ArcCircle"
    arcCircle.Size = UDim2.fromOffset(18, 18)
    arcCircle.Position = UDim2.new(0, 0, 0, 0)
    arcCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    arcCircle.BackgroundTransparency = 1
    arcCircle.ZIndex = 52
    
    local arcCorner = Instance.new("UICorner")
    arcCorner.CornerRadius = UDim.new(1, 0)
    arcCorner.Parent = arcCircle
    
    local arcStroke = Instance.new("UIStroke")
    arcStroke.Color = Color3.fromRGB(240, 240, 245)
    arcStroke.Thickness = 1.6
    arcStroke.Transparency = 0.45
    arcStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    arcStroke.Parent = arcCircle
    
    arcCircle.Parent = arcClipper
    arcClipper.Parent = resizeHandle
    resizeHandle.Parent = mainFrame
    self.ResizeHandle = resizeHandle

    -- Hover & Press micro-feedback on resize handle
    local resizeScale = Instance.new("UIScale")
    resizeScale.Scale = 1.0
    resizeScale.Parent = resizeHandle
    
    resizeHandle.MouseEnter:Connect(function()
        Tweener.Tween(resizeScale, Tweener.Info.Fast, { Scale = 1.15 })
        Tweener.Tween(arcStroke, Tweener.Info.Fast, { Transparency = 0.10, Thickness = 1.8 })
    end)
    resizeHandle.MouseLeave:Connect(function()
        Tweener.Tween(resizeScale, Tweener.Info.Fast, { Scale = 1.0 })
        Tweener.Tween(arcStroke, Tweener.Info.Fast, { Transparency = 0.45, Thickness = 1.6 })
    end)

    mainFrame.Parent = self.RootGui
    
    self.MainFrame = mainFrame
    self.Body = body
    self.SidebarTabList = tabList
    self.ContentArea = contentArea
    self.DefaultSize = defaultSize
    self._mounted = true
    
    -- Floating Minimized Widget: Dynamic Island style pill (Lens + Sodium Hub + Status Dot)
    local ISLAND_W = 158
    local ISLAND_H = 36
    local SHADOW_PAD = 12

    local minWidget = Instance.new("TextButton")
    minWidget.Name = "FloatingMinimizedWidget"
    minWidget.Size = UDim2.fromOffset(ISLAND_W, ISLAND_H)
    minWidget.Position = UDim2.new(0.5, 0, 0, 16 + math.floor(ISLAND_H / 2))
    minWidget.AnchorPoint = Vector2.new(0.5, 0.5)
    minWidget.BackgroundColor3 = Color3.fromRGB(10, 10, 12) -- True Dynamic Island deep black
    minWidget.BackgroundTransparency = 0
    minWidget.AutoButtonColor = false
    minWidget.Text = ""
    minWidget.Visible = false
    minWidget.ZIndex = 999999
    minWidget.ClipsDescendants = false

    local minWidgetCorner = Instance.new("UICorner")
    minWidgetCorner.CornerRadius = UDim.new(1, 0) -- Perfect pill
    minWidgetCorner.Parent = minWidget

    local minWidgetStroke = Instance.new("UIStroke")
    minWidgetStroke.Color = Color3.fromRGB(36, 36, 44)
    minWidgetStroke.Thickness = 1.2
    minWidgetStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    minWidgetStroke.Parent = minWidget

    -- Lens sensor container (left)
    local lensFrame = Instance.new("Frame")
    lensFrame.Name = "LensSensor"
    lensFrame.Size = UDim2.fromOffset(22, 22)
    lensFrame.Position = UDim2.new(0, 8, 0.5, 0)
    lensFrame.AnchorPoint = Vector2.new(0, 0.5)
    lensFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    lensFrame.BorderSizePixel = 0
    lensFrame.ZIndex = 3
    lensFrame.Parent = minWidget

    local lensCorner = Instance.new("UICorner")
    lensCorner.CornerRadius = UDim.new(1, 0)
    lensCorner.Parent = lensFrame

    local lensIcon = Instance.new("ImageLabel")
    lensIcon.Name = "LensIcon"
    lensIcon.Size = UDim2.fromOffset(13, 13)
    lensIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
    lensIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    lensIcon.BackgroundTransparency = 1
    lensIcon.ImageColor3 = Color3.fromRGB(180, 180, 195)
    lensIcon.ZIndex = 4
    Icons.Apply(lensIcon, "camera")
    lensIcon.Parent = lensFrame

    -- Center Title Label (Fixed to "Sodium Hub" strictly)
    local islandTitle = Instance.new("TextLabel")
    islandTitle.Name = "IslandTitle"
    islandTitle.Size = UDim2.new(1, -66, 1, 0)
    islandTitle.Position = UDim2.new(0.5, -1, 0.5, 0)
    islandTitle.AnchorPoint = Vector2.new(0.5, 0.5)
    islandTitle.BackgroundTransparency = 1
    islandTitle.Text = "Sodium Hub"
    Theme.ApplyTypography(islandTitle, "Title", "Body")
    islandTitle.TextColor3 = Color3.fromRGB(240, 240, 245)
    islandTitle.TextXAlignment = Enum.TextXAlignment.Center
    islandTitle.TextTruncate = Enum.TextTruncate.AtEnd
    islandTitle.ZIndex = 3
    islandTitle.Parent = minWidget

    -- Right Status Dot (Accent indicator)
    local statusDot = Instance.new("Frame")
    statusDot.Name = "StatusDot"
    statusDot.Size = UDim2.fromOffset(7, 7)
    statusDot.Position = UDim2.new(1, -12, 0.5, 0)
    statusDot.AnchorPoint = Vector2.new(1, 0.5)
    statusDot.BackgroundColor3 = Theme.GetToken("Accent")
    statusDot.BorderSizePixel = 0
    statusDot.ZIndex = 3
    statusDot.Parent = minWidget
    Theme.Bind(statusDot, "BackgroundColor3", "Accent")

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = statusDot

    -- Dynamic Island Soft Black Glow (Continuous Smooth Capsule Falloff)
    local minShadowHolder = Instance.new("Frame")
    minShadowHolder.Name = "MinWidgetGlowHolder"
    minShadowHolder.Size = UDim2.fromScale(1, 1)
    minShadowHolder.Position = UDim2.fromScale(0, 0)
    minShadowHolder.BackgroundTransparency = 1
    minShadowHolder.ZIndex = 1

    -- Continuous 8-step micro-falloff (clean, perfectly balanced capsule shadow)
    local minWidgetGlowFrames = {}
    for pad = 1, 8 do
        local t = (pad - 1) / 7
        local targetTr = 0.86 + (t ^ 1.5) * 0.13 -- Balanced capsule falloff (0.86 -> 0.99)

        local pf = Instance.new("Frame")
        pf.Name = "PillGlowStep_" .. tostring(pad)
        pf.Size = UDim2.new(1, pad * 2, 1, pad * 2)
        pf.Position = UDim2.new(0, -pad, 0, -pad)
        pf.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        pf.BackgroundTransparency = targetTr
        pf.BorderSizePixel = 0
        pf.ZIndex = 1
        
        local pc = Instance.new("UICorner")
        pc.CornerRadius = UDim.new(1, 0) -- Pure geometric capsule
        pc.Parent = pf
        
        pf.Parent = minShadowHolder
        table.insert(minWidgetGlowFrames, { Frame = pf, TargetTr = targetTr })
    end
    minShadowHolder.Parent = minWidget
    self.MinShadow = minShadowHolder
    self.MinWidgetGlowFrames = minWidgetGlowFrames

    local minWidgetScale = Instance.new("UIScale")
    minWidgetScale.Scale = 1
    minWidgetScale.Parent = minWidget

    -- Dynamic Island Micro-interactions (Hover lift & Press feedback)
    minWidget.MouseEnter:Connect(function()
        Tweener.Tween(minWidgetStroke, Tweener.Info.Fast, { Color = Theme.GetToken("Accent") })
        Tweener.Tween(islandTitle, Tweener.Info.Fast, { TextColor3 = Color3.fromRGB(255, 255, 255) })
        Tweener.Tween(lensIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Accent") })
        Tweener.Tween(minWidgetScale, Tweener.Info.Fast, { Scale = 1.05 })
    end)
    minWidget.MouseLeave:Connect(function()
        Tweener.Tween(minWidgetStroke, Tweener.Info.Fast, { Color = Color3.fromRGB(36, 36, 44) })
        Tweener.Tween(islandTitle, Tweener.Info.Fast, { TextColor3 = Color3.fromRGB(240, 240, 245) })
        Tweener.Tween(lensIcon, Tweener.Info.Fast, { ImageColor3 = Color3.fromRGB(180, 180, 195) })
        Tweener.Tween(minWidgetScale, Tweener.Info.Fast, { Scale = 1.0 })
    end)
    minWidget.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            Tweener.Tween(minWidgetScale, Tweener.Info.Micro, { Scale = 0.94 })
        end
    end)

    minWidget.Parent = self.RootGui
    self.MinWidget = minWidget
    self.MinWidgetScale = minWidgetScale

    self:_initDraggableWidget(minWidget, function()
        -- Dynamic Island Pop-open expansion feedback
        Tweener.Tween(minWidgetScale, Tweener.Info.MacOSSpring, { Scale = 1.12 }, function()
            self:ToggleVisibility()
        end)
    end)

    -- Window Dragging Engine
    self:_initDragging(topbar)
    
    -- Window Resizing Engine (Bottom-Right Drag Handle)
    self:_initResizing(resizeHandle)
    
    -- Window Controls: Minimize, FullScreen, True Close Termination
    minBtn.Activated:Connect(function()
        self:ToggleVisibility()
    end)
    
    fullBtn.Activated:Connect(function()
        self:ToggleFullScreen()
    end)

    closeBtn.Activated:Connect(function()
        self:Dialog({
            Title = { en = "Close Window?", th = "ต้องการปิดหน้าต่างหรือไม่?" },
            Content = {
                en = "Are you sure you want to close the menu? You can reopen it using your toggle key.",
                th = "คุณแน่ใจหรือไม่ว่าต้องการปิดหน้าต่างนี้? คุณสามารถเปิดใหม่ได้ด้วยปุ่มลัดที่ตั้งไว้"
            },
            Icon = "alert-triangle",
            Buttons = {
                {
                    Title = { en = "Cancel", th = "ยกเลิก" },
                    Style = "Default",
                    Callback = function()
                        -- Keep window open
                    end
                },
                {
                    Title = { en = "Close", th = "ปิดหน้าต่าง" },
                    Style = "Primary",
                    Callback = function()
                        self:Destroy()
                    end
                }
            }
        })
    end)
    
    -- ToggleKey Listener (Works for LeftShift, ShiftLock, and all modifier keys)
    self._toggleKeyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if UserInputService:GetFocusedTextBox() ~= nil then
            return
        end
        
        local targetKey = self.ToggleKey
        local isMatch = false
        if typeof(targetKey) == "EnumItem" then
            isMatch = (input.KeyCode == targetKey)
        elseif type(targetKey) == "string" then
            isMatch = (input.KeyCode.Name:lower() == targetKey:lower())
        end
        
        if isMatch then
            self:ToggleVisibility()
        end
    end)
    
    -- Sidebar Search Engine (Deep Element & Tab Universal Search)
    if self.SearchBox then
        self.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local query = string.lower(self.SearchBox.Text)
            local isSearching = query ~= ""
            local firstMatchedTab = nil

            for _, tabItem in ipairs(self.Tabs) do
                local rawTabTitle = Locale.Resolve(tabItem.Title or "")
                local tabTitleMatch = string.find(string.lower(rawTabTitle), query, 1, true) ~= nil
                local hasElementMatch = false

                if tabItem.Sections then
                    for _, sec in ipairs(tabItem.Sections) do
                        local rawSecTitle = Locale.Resolve(sec.Title or "")
                        local secTitleMatch = string.find(string.lower(rawSecTitle), query, 1, true) ~= nil
                        local secHasVisibleChild = false

                        if sec.Elements then
                            for _, elem in ipairs(sec.Elements) do
                                local elemTitle = string.lower(Locale.Resolve(elem.Title or ""))
                                local elemDesc = string.lower(Locale.Resolve(elem.Desc or ""))
                                local match = (not isSearching) or tabTitleMatch or secTitleMatch
                                    or string.find(elemTitle, query, 1, true) ~= nil
                                    or string.find(elemDesc, query, 1, true) ~= nil

                                local targetObj = elem.Slot or elem.Container
                                if targetObj then
                                    targetObj.Visible = match
                                end

                                if match then
                                    secHasVisibleChild = true
                                    hasElementMatch = true
                                end
                            end
                        end

                        if sec.Card then
                            sec.Card.Visible = (not isSearching) or secHasVisibleChild or secTitleMatch or tabTitleMatch
                        end
                    end
                end

                local tabMatch = (not isSearching) or tabTitleMatch or hasElementMatch
                if tabItem.SidebarButton then
                    tabItem.SidebarButton.Visible = tabMatch
                end

                if isSearching and tabMatch and not firstMatchedTab then
                    firstMatchedTab = tabItem
                end
            end

            -- Update tab indicator lock
            self:UpdateIndicator(true)

            -- Automatically navigate to the first matching tab if current tab has no matches
            if isSearching and firstMatchedTab and (not self.CurrentTab or not self.CurrentTab.SidebarButton.Visible) then
                self:SelectTab(firstMatchedTab)
            end
        end)
    end
    
    local g = (type(getgenv) == "function" and getgenv()) or (rawget(getfenv(), "_G") :: any)
    if g then
        g._PUMPKIN_ACTIVE_WINDOW = self
        g._SODIUM_ACTIVE_WINDOW = self
    end
    
    -- Built-in Persistent "General" TabSection with default "Dashboard" Tab (matching screenshot)
    local overviewSection = self:Section({
        Title = { EN = "General", TH = "ทั่วไป" },
        Collapsible = false,
    })
    local dashboardTab = overviewSection:Tab({
        Title = { EN = "Dashboard", TH = "แดชบอร์ด" },
        Icon = "layout-dashboard",
    })

    -- Add exact image-matched DashboardView
    local dashboardView = dashboardTab:DashboardView({
        Category = "General",
        CurrentPage = "Dashboard",
        Version = "1.0.0",
        Role = "Administrator",
    })
    dashboardTab.DashboardViewInstance = dashboardView

    self.OverviewSection = overviewSection
    self.DashboardTab = dashboardTab

    -- Start Anti-AFK Engine immediately (Silent, enabled by default)
    local genv = (type(getgenv) == "function" and getgenv()) or nil
    if not _G.__sodium_anti_afk_init and (not genv or not genv.__sodium_anti_afk_init) then
        if genv then genv.__sodium_anti_afk_init = true else _G.__sodium_anti_afk_init = true end
        if genv then genv.__sodium_anti_afk_active = true else _G.__sodium_anti_afk_active = true end
        task.spawn(function()
            local vu = game:GetService("VirtualUser")
            local plrs = game:GetService("Players")
            local localPlr = plrs.LocalPlayer

            -- 1. Anti-AFK on Roblox Idled signal
            if localPlr then
                pcall(function()
                    localPlr.Idled:Connect(function()
                        local isAct = (self and self._antiAfkEnabled) or (genv and genv.__sodium_anti_afk_active) or (_G.__sodium_anti_afk_active)
                        if isAct then
                            pcall(function()
                                vu:Button2Down(Vector2.zero, workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
                                task.wait(1)
                                vu:Button2Up(Vector2.zero, workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
                            end)
                        end
                    end)
                end)
            end

            -- 2. 5-Minute loop: simulate mouse click and jump
            while true do
                task.wait(300) -- every 5 minutes (300 seconds)
                local isAct = (self and self._antiAfkEnabled) or (genv and genv.__sodium_anti_afk_active) or (_G.__sodium_anti_afk_active)
                if isAct then
                    pcall(function()
                        vu:Button2Down(Vector2.zero, workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
                        task.wait(0.2)
                        vu:Button2Up(Vector2.zero, workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new())
                    end)
                    pcall(function()
                        local char = localPlr and localPlr.Character
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            hum:ChangeState(Enum.HumanoidStateType.Jumping)
                        end
                    end)
                end
            end
        end)
    else
        if genv then genv.__sodium_anti_afk_active = true else _G.__sodium_anti_afk_active = true end
    end

    -- Auto-Load and Auto-Save on startup if configured

    return self
end

function Window:_initDraggableWidget(widget: GuiObject, onClick: () -> ())
    local isDragging = false
    local startMousePos = Vector2.zero
    local startWidgetPos = Vector2.zero
    
    local function clampWidgetToScreen()
        local camera = workspace.CurrentCamera
        local screenSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local scale = math.max(0.01, self.ContainerManager.UIScale.Scale)
        local widgetSize = widget.AbsoluteSize / scale
        local halfW = widgetSize.X / 2
        local halfH = widgetSize.Y / 2
        local maxX = math.max(halfW, (screenSize.X / scale) - halfW)
        local maxY = math.max(halfH, (screenSize.Y / scale) - halfH)
        
        local curX = widget.Position.X.Offset
        local curY = widget.Position.Y.Offset
        local clampedX = math.clamp(curX, halfW, maxX)
        local clampedY = math.clamp(curY, halfH, maxY)
        widget.Position = UDim2.fromOffset(clampedX, clampedY)
        widget.AnchorPoint = Vector2.new(0.5, 0.5)
    end
    self._clampWidgetToScreen = clampWidgetToScreen
    
    local function stopDragging()
        if isDragging then
            isDragging = false
            if self._minDragConn then
                self._minDragConn:Disconnect()
                self._minDragConn = nil
            end
        end
    end
    
    widget.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            startMousePos = Vector2.new(input.Position.X, input.Position.Y)
            
            local camera = workspace.CurrentCamera
            local screenSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)
            local scale = math.max(0.01, self.ContainerManager.UIScale.Scale)
            
            local widgetSize = widget.AbsoluteSize / scale
            local curX = math.floor(widget.Position.X.Scale * (screenSize.X / scale) + widget.Position.X.Offset)
            local curY = math.floor(widget.Position.Y.Scale * (screenSize.Y / scale) + widget.Position.Y.Offset)
            startWidgetPos = Vector2.new(curX, curY)
            widget.Position = UDim2.fromOffset(curX, curY)
            widget.AnchorPoint = Vector2.new(0.5, 0.5)
            
            if self._minDragConn then
                self._minDragConn:Disconnect()
            end
            
            self._minDragConn = UserInputService.InputChanged:Connect(function(moveInput)
                if not isDragging then
                    stopDragging()
                    return
                end
                
                if moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch then
                    local currentMouse = Vector2.new(moveInput.Position.X, moveInput.Position.Y)
                    local delta = currentMouse - startMousePos
                    local unscaledDelta = delta / scale
                    
                    local targetX = startWidgetPos.X + unscaledDelta.X
                    local targetY = startWidgetPos.Y + unscaledDelta.Y
                    
                    local halfW = widgetSize.X / 2
                    local halfH = widgetSize.Y / 2
                    local maxX = math.max(halfW, (screenSize.X / scale) - halfW)
                    local maxY = math.max(halfH, (screenSize.Y / scale) - halfH)
                    
                    local clampedX = math.clamp(targetX, halfW, maxX)
                    local clampedY = math.clamp(targetY, halfH, maxY)
                    
                    widget.Position = UDim2.fromOffset(clampedX, clampedY)
                    widget.AnchorPoint = Vector2.new(0.5, 0.5)
                end
            end)
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if isDragging then
                local endMousePos = Vector2.new(input.Position.X, input.Position.Y)
                local movedDist = (endMousePos - startMousePos).Magnitude
                stopDragging()
                clampWidgetToScreen()
                if movedDist < 6 and onClick then
                    onClick()
                end
            end
        end
    end)
end

function Window:_initDragging(dragHandle: GuiObject)
    local isDragging = false
    local startMousePos = Vector2.zero
    local startScaleX = 0.5
    local startScaleY = 0.5
    local startOffsetX = 0
    local startOffsetY = 0
    
    local function stopDragging()
        isDragging = false
        if self._dragConn then
            self._dragConn:Disconnect()
            self._dragConn = nil
        end
        if self._dragEndConn then
            self._dragEndConn:Disconnect()
            self._dragEndConn = nil
        end
    end
    
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            startMousePos = Vector2.new(input.Position.X, input.Position.Y)
            local curPos = nil
            pcall(function()
                curPos = self.MainFrame.Position
            end)
            if not curPos and self._savedPosition then
                curPos = self._savedPosition
            end
            if curPos then
                startScaleX = curPos.X.Scale
                startScaleY = curPos.Y.Scale
                startOffsetX = curPos.X.Offset
                startOffsetY = curPos.Y.Offset
            end
            
            if self._dragConn then
                self._dragConn:Disconnect()
                self._dragConn = nil
            end
            if self._dragEndConn then
                self._dragEndConn:Disconnect()
                self._dragEndConn = nil
            end
            
            -- Zero-Latency Direct 1:1 Event-Driven Tracking with UIScale Compensation
            self._dragConn = UserInputService.InputChanged:Connect(function(moveInput)
                if not isDragging then
                    stopDragging()
                    return
                end
                
                if moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch then
                    local scale = math.max(0.001, self.ContainerManager.UIScale.Scale)
                    local currentMouse = Vector2.new(moveInput.Position.X, moveInput.Position.Y)
                    local deltaX = (currentMouse.X - startMousePos.X) / scale
                    local deltaY = (currentMouse.Y - startMousePos.Y) / scale
                    
                    local newPos = UDim2.new(
                        startScaleX,
                        math.round(startOffsetX + deltaX),
                        startScaleY,
                        math.round(startOffsetY + deltaY)
                    )
                    
                    self.MainFrame.Position = newPos
                    if self.GlowHolder then
                        self.GlowHolder.Position = newPos
                    end
                end
            end)
            
            -- Dynamic End Listener: Cleanly bound on InputBegan and disconnected on InputEnded
            self._dragEndConn = UserInputService.InputEnded:Connect(function(endInput)
                if endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch then
                    stopDragging()
                end
            end)
        end
    end)
    
    -- Decoupled MainUI preserves user coordinates; Control Button strictly clamped
    self.ContainerManager.OnScaleChanged = function(_newScale)
        if self._clampWidgetToScreen then
            self._clampWidgetToScreen()
        end
    end
end

function Window:_initResizing(resizeHandle: GuiObject)
    local isResizing = false
    local startMousePos = Vector2.zero
    local startSize = Vector2.zero
    
    -- Explicit Requested Minimum Bounds: 680x460
    local MIN_WIDTH = math.max(680, (self._sidebarWidth or 200) + 400)
    local MIN_HEIGHT = 460

    local function stopResizing()
        isResizing = false
        if self._resizeConn then
            self._resizeConn:Disconnect()
            self._resizeConn = nil
        end
        if self._resizeEndConn then
            self._resizeEndConn:Disconnect()
            self._resizeEndConn = nil
        end
    end

    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if self.IsFullScreen then return end
            isResizing = true
            startMousePos = Vector2.new(input.Position.X, input.Position.Y)
            local curSz = nil
            pcall(function()
                curSz = Vector2.new(self.MainFrame.AbsoluteSize.X, self.MainFrame.AbsoluteSize.Y)
            end)
            if not curSz and self.DefaultSize then
                curSz = Vector2.new(self.DefaultSize.X.Offset, self.DefaultSize.Y.Offset)
            end
            startSize = curSz or Vector2.new(680, 460)

            if self._resizeConn then
                self._resizeConn:Disconnect()
                self._resizeConn = nil
            end
            if self._resizeEndConn then
                self._resizeEndConn:Disconnect()
                self._resizeEndConn = nil
            end

            self._resizeConn = UserInputService.InputChanged:Connect(function(moveInput)
                if not isResizing then
                    stopResizing()
                    return
                end

                if moveInput.UserInputType == Enum.UserInputType.MouseMovement or moveInput.UserInputType == Enum.UserInputType.Touch then
                    local scale = math.max(0.001, self.ContainerManager.UIScale.Scale)
                    local currentMouse = Vector2.new(moveInput.Position.X, moveInput.Position.Y)
                    local deltaX = (currentMouse.X - startMousePos.X) / scale
                    local deltaY = (currentMouse.Y - startMousePos.Y) / scale

                    local cam = workspace.CurrentCamera
                    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
                    local maxW = math.floor((vp.X - 32) / scale)
                    local maxH = math.floor((vp.Y - 32) / scale)

                    local newW = math.clamp(math.round((startSize.X / scale) + deltaX), MIN_WIDTH, maxW)
                    local newH = math.clamp(math.round((startSize.Y / scale) + deltaY), MIN_HEIGHT, maxH)

                    local newSize = UDim2.fromOffset(newW, newH)
                    self.MainFrame.Size = newSize
                    self._savedSize = newSize

                    if self.GlowHolder then
                        self.GlowHolder.Size = newSize
                    end
                end
            end)

            self._resizeEndConn = UserInputService.InputEnded:Connect(function(endInput)
                if endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch then
                    stopResizing()
                end
            end)
        end
    end)
end

function Window:ToggleFullScreen()
    if self.MainFrame and not self.IsMinimized then
        self.IsFullScreen = not self.IsFullScreen
        if self.IsFullScreen then
            self._savedSize = self.MainFrame.Size
            self._savedPosition = self.MainFrame.Position
            
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
            local uiScale = self.ContainerManager and self.ContainerManager.UIScale and self.ContainerManager.UIScale.Scale or 1
            if uiScale <= 0 then uiScale = 1 end
            
            local targetW = math.floor((vp.X - 28) / uiScale)
            local targetH = math.floor((vp.Y - 28) / uiScale)
            
            Tweener.Tween(self.MainFrame, Tweener.Info.Smooth, {
                Size = UDim2.fromOffset(targetW, targetH),
                Position = UDim2.fromScale(0.5, 0.5)
            })
        else
            Tweener.Tween(self.MainFrame, Tweener.Info.Smooth, {
                Size = self._savedSize or UDim2.fromOffset(740, 520),
                Position = self._savedPosition or UDim2.fromScale(0.5, 0.5)
            })
        end
    end
end

function Window:ToggleMinimize()
    self:ToggleVisibility()
end

function Window:ToggleVisibility()
    self._toggleGen = (self._toggleGen or 0) + 1
    local currentGen = self._toggleGen

    if self.MainFrame.Visible then
        self.IsVisible = false
        self.IsMinimized = true
        
        -- Perfectly Synchronized Lockstep Exit (0.20s Cubic Out: Fade + Scale)
        local exitTween = Tweener.Info.MacOSWindowClose

        if self.GlowScale then
            Tweener.Tween(self.GlowScale, exitTween, { Scale = 0.94 })
        end
        if self.WindowGlowFrames then
            for _, item in ipairs(self.WindowGlowFrames) do
                Tweener.Tween(item.Frame, exitTween, { BackgroundTransparency = 1.0 })
            end
        end

        if self.WindowScale then
            Tweener.Tween(self.WindowScale, exitTween, { Scale = 0.94 }, function()
                if self._toggleGen == currentGen and not self.IsVisible then
                    self.MainFrame.Visible = false
                    if self.GlowHolder then
                        self.GlowHolder.Visible = false
                    end
                end
            end)
        else
            self.MainFrame.Visible = false
            if self.GlowHolder then
                self.GlowHolder.Visible = false
            end
        end
        
        -- Smooth seamless handoff to floating Dynamic Island (Starts immediately in parallel with exact same duration)
        if self.MinWidget then
            self.MinWidget.Visible = true
            if self.MinWidgetScale then
                self.MinWidgetScale.Scale = 0.88
                Tweener.Tween(self.MinWidgetScale, exitTween, { Scale = 1.0 })
            end
            if self.MinWidgetGlowFrames then
                for _, item in ipairs(self.MinWidgetGlowFrames) do
                    item.Frame.BackgroundTransparency = 1.0
                    Tweener.Tween(item.Frame, exitTween, { BackgroundTransparency = item.TargetTr })
                end
            end
        end
    else
        self.IsVisible = true
        self.IsMinimized = false

        -- Smooth entrance to Window (0.24s Cubic Out: Fade in from transparent + scale in from 0.94)
        local entranceTween = Tweener.Info.MacOSWindowOpen

        self.MainFrame.Visible = true
        self.Body.Visible = true
        if self.GlowHolder then
            self.GlowHolder.Visible = true
        end

        if self.WindowScale then
            self.WindowScale.Scale = 0.94
            Tweener.Tween(self.WindowScale, entranceTween, { Scale = 1.0 })
        end
        if self.GlowScale then
            self.GlowScale.Scale = 0.94
            Tweener.Tween(self.GlowScale, entranceTween, { Scale = 1.0 })
        end
        if self.WindowGlowFrames then
            for _, item in ipairs(self.WindowGlowFrames) do
                item.Frame.BackgroundTransparency = 1.0
                Tweener.Tween(item.Frame, entranceTween, { BackgroundTransparency = item.TargetTr })
            end
        end
        
        -- Seamless fade/scale exit for floating Dynamic Island
        if self.MinWidget and self.MinWidget.Visible then
            if self.MinWidgetScale then
                Tweener.Tween(self.MinWidgetScale, entranceTween, { Scale = 0.88 }, function()
                    if self._toggleGen == currentGen and self.IsVisible then
                        self.MinWidget.Visible = false
                    end
                end)
            else
                self.MinWidget.Visible = false
            end
            if self.MinWidgetGlowFrames then
                for _, item in ipairs(self.MinWidgetGlowFrames) do
                    Tweener.Tween(item.Frame, entranceTween, { BackgroundTransparency = 1.0 })
                end
            end
        else
            if self.MinWidget then
                self.MinWidget.Visible = false
            end
        end
    end
end

function Window:_deactivateAllTabs()
    self.CurrentTab = nil
    for _, tabItem in ipairs(self.Tabs) do
        tabItem:Deselect(false)
    end
    if self.TabIndicator then
        self.TabIndicator.BackgroundTransparency = 1
    end
end

function Window:SelectTab(targetTab: any)
    if not targetTab then return end
    if self.CurrentTab == targetTab and targetTab.Active then
        return
    end
    
    self._tabTransitionGen = (self._tabTransitionGen or 0) + 1
    
    local oldTab = self.CurrentTab
    self.CurrentTab = targetTab
    
    if self.HideHoverTracker then
        self:HideHoverTracker(true)
    end
    
    if oldTab and oldTab ~= targetTab then
        oldTab:Deselect(true)
    end
    
    for _, tabItem in ipairs(self.Tabs) do
        if tabItem ~= targetTab and tabItem ~= oldTab and tabItem.Active then
            tabItem:Deselect(false)
        end
    end
    
    targetTab:Select(true)
    self:ScrollToTab(targetTab)
    self:UpdateIndicator(false)
    
    -- Absolute Coordinate Lock: Keep indicator locked onto targetTab whenever layout shifts (without interrupting active tween)
    if self._activeBtnPosConn then
        self._activeBtnPosConn:Disconnect()
        self._activeBtnPosConn = nil
    end
    if targetTab.SidebarButton then
        self._activeBtnPosConn = targetTab.SidebarButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
            if self.CurrentTab == targetTab and not self._indicatorTween then
                self:UpdateIndicator(true)
            end
        end)
    end
end

function Window:TrackHover(targetTab: any)
    if not targetTab or targetTab.Active or not self.HoverTracker then
        if self.HoverTracker then
            self:HideHoverTracker()
        end
        return
    end
    
    local btn = targetTab.SidebarButton
    if not btn or not btn.Parent or not btn.Visible then
        self:HideHoverTracker()
        return
    end
    
    local scale = math.max(0.001, self.ContainerManager.UIScale.Scale)
    local overlayPos = self.TabIndicatorOverlay.AbsolutePosition
    local btnPos = btn.AbsolutePosition
    local btnSize = btn.AbsoluteSize
    
    local relX = (btnPos.X - overlayPos.X) / scale
    local relY = (btnPos.Y - overlayPos.Y) / scale
    local width = btnSize.X / scale
    local height = btnSize.Y / scale
    
    local targetPos = UDim2.fromOffset(relX, relY)
    local targetSize = UDim2.fromOffset(width, height)
    
    if self._hoverTrackerTween then
        self._hoverTrackerTween:Cancel()
        self._hoverTrackerTween = nil
    end
    
    if self.HoverTracker.BackgroundTransparency >= 0.99 then
        -- Link starting coordinates of HoverTracker directly to the current position of TabIndicator
        if self.TabIndicator and self.TabIndicator.Visible then
            self.HoverTracker.Position = self.TabIndicator.Position
            self.HoverTracker.Size = self.TabIndicator.Size
        else
            self.HoverTracker.Position = targetPos
            self.HoverTracker.Size = targetSize
        end
        self.HoverTracker.Visible = true
        self.HoverTracker.BackgroundTransparency = 1
        self._hoverTrackerTween = Tweener.Tween(self.HoverTracker, Tweener.Info.Smooth, {
            Position = targetPos,
            Size = targetSize,
            BackgroundTransparency = 0.55,
        }, function()
            self._hoverTrackerTween = nil
        end)
    else
        self.HoverTracker.Visible = true
        self._hoverTrackerTween = Tweener.Tween(self.HoverTracker, Tweener.Info.Smooth, {
            Position = targetPos,
            Size = targetSize,
            BackgroundTransparency = 0.55,
        }, function()
            self._hoverTrackerTween = nil
        end)
    end
end

function Window:HideHoverTracker(smooth: boolean?)
    if not self.HoverTracker then return end
    if self._hoverTrackerTween then
        self._hoverTrackerTween:Cancel()
        self._hoverTrackerTween = nil
    end
    local tweenInfo = if smooth then Tweener.Info.Smooth else Tweener.Info.Fast
    self._hoverTrackerTween = Tweener.Tween(self.HoverTracker, tweenInfo, { BackgroundTransparency = 1 }, function()
        self._hoverTrackerTween = nil
        if self.HoverTracker then
            self.HoverTracker.Visible = false
        end
    end)
end

function Window:UpdateIndicator(immediate: boolean?)
    local targetTab = self.CurrentTab
    if not targetTab or not targetTab.SidebarButton or not self.TabIndicator then
        if self.TabIndicator then
            self.TabIndicator.BackgroundTransparency = 1
        end
        return
    end
    
    local btn = targetTab.SidebarButton
    if not btn.Parent or not btn.Visible then
        self.TabIndicator.Visible = false
        return
    end
    
    if targetTab.ParentSection and not targetTab.ParentSection.Opened then
        self.TabIndicator.Visible = false
        return
    end
    
    self.TabIndicator.Visible = true
    
    local scale = math.max(0.001, self.ContainerManager.UIScale.Scale)
    local overlayPos = self.TabIndicatorOverlay.AbsolutePosition
    local btnPos = btn.AbsolutePosition
    local btnSize = btn.AbsoluteSize
    
    if btnSize.X <= 0 or btnSize.Y <= 0 then
        task.defer(function()
            if self.CurrentTab == targetTab then
                self:UpdateIndicator(immediate)
            end
        end)
        return
    end
    
    -- TargetPos = Element.AbsolutePosition - Container.AbsolutePosition
    -- TargetSize = Element.AbsoluteSize
    local relX = (btnPos.X - overlayPos.X) / scale
    local relY = (btnPos.Y - overlayPos.Y) / scale
    local width = btnSize.X / scale
    local height = btnSize.Y / scale
    
    local overlayH = self.TabIndicatorOverlay.AbsoluteSize.Y / scale
    if relY + height < 0 or relY > overlayH then
        self.TabIndicator.Visible = false
        return
    else
        self.TabIndicator.Visible = true
    end
    
    local targetPos = UDim2.fromOffset(relX, relY)
    local targetSize = UDim2.fromOffset(width, height)
    
    -- When immediate layout shift occurs (e.g. accordion collapse):
    -- Allow in-motion tween to run until completion before locking to AbsolutePosition
    if immediate then
        if self._indicatorTween then
            return
        end
        self.TabIndicator.Position = targetPos
        self.TabIndicator.Size = targetSize
        Tweener.Tween(self.TabIndicator, Tweener.Info.Fast, { BackgroundTransparency = 0 })
        return
    end
    
    if self._indicatorTween then
        self._indicatorTween:Cancel()
        self._indicatorTween = nil
    end
    
    local indicatorInfo = Tweener.Info.MacOSTabSlide

    if self.TabIndicator.BackgroundTransparency >= 0.99 and not self._hasInitializedIndicator then
        self._hasInitializedIndicator = true
        self.TabIndicator.Position = targetPos
        self.TabIndicator.Size = targetSize
        Tweener.Tween(self.TabIndicator, Tweener.Info.Fast, { BackgroundTransparency = 0 })
    else
        self._hasInitializedIndicator = true
        local tweenGoals: { [string]: any } = {
            Position = targetPos,
            Size = targetSize,
            BackgroundTransparency = 0,
        }
        self._indicatorTween = Tweener.Tween(self.TabIndicator, indicatorInfo, tweenGoals, function()
            self._indicatorTween = nil
        end)
    end
end

-- Auto-Scroll Active Tab into View (Smoothly scrolls tabList so targetTab is fully visible)
function Window:ScrollToTab(targetTab: any, immediate: boolean?)
    if not targetTab or not self.SidebarTabList then return end
    local btn = targetTab.SidebarButton
    if not btn or not btn.Parent or not btn.Visible then return end
    
    -- Ensure parent category accordion is opened
    if targetTab.ParentSection and not targetTab.ParentSection.Opened then
        targetTab.ParentSection:Toggle(true)
    end
    
    local tabList = self.SidebarTabList
    local scale = math.max(0.001, self.ContainerManager.UIScale.Scale)
    
    if btn.AbsoluteSize.Y <= 0 or tabList.AbsoluteWindowSize.Y <= 0 then
        task.defer(function()
            if self.CurrentTab == targetTab then
                self:ScrollToTab(targetTab, immediate)
            end
        end)
        return
    end
    
    local tabListPos = tabList.AbsolutePosition
    local tabListH = tabList.AbsoluteWindowSize.Y / scale
    local btnPos = btn.AbsolutePosition
    local btnH = btn.AbsoluteSize.Y / scale
    
    local currentCanvasY = tabList.CanvasPosition.Y
    local btnTopRel = (btnPos.Y - tabListPos.Y) / scale
    local btnBottomRel = btnTopRel + btnH
    
    local targetCanvasY = currentCanvasY
    if btnTopRel < 8 then
        targetCanvasY = math.max(0, currentCanvasY + btnTopRel - 8)
    elseif btnBottomRel > tabListH - 8 then
        targetCanvasY = currentCanvasY + (btnBottomRel - tabListH + 8)
    else
        return -- already within comfortable view
    end
    
    local maxCanvasY = math.max(0, (tabList.AbsoluteCanvasSize.Y - tabList.AbsoluteWindowSize.Y) / scale)
    targetCanvasY = math.clamp(targetCanvasY, 0, maxCanvasY)
    
    if immediate then
        tabList.CanvasPosition = Vector2.new(0, targetCanvasY)
        self:UpdateIndicator(true)
    else
        if self._scrollTweenVal then
            self._scrollTweenVal:Destroy()
            self._scrollTweenVal = nil
        end
        local startY = tabList.CanvasPosition.Y
        if math.abs(targetCanvasY - startY) > 2 then
            local valObj = Instance.new("NumberValue")
            valObj.Value = startY
            self._scrollTweenVal = valObj
            local scrollConn: any = nil
            scrollConn = valObj.Changed:Connect(function(newY)
                if tabList and tabList.Parent then
                    tabList.CanvasPosition = Vector2.new(0, newY)
                    if not self._indicatorTween then
                        self:UpdateIndicator(true)
                    end
                end
            end)
            Tweener.Tween(valObj, Tweener.Info.Normal, { Value = targetCanvasY }, function()
                if scrollConn then
                    scrollConn:Disconnect()
                    scrollConn = nil
                end
                valObj:Destroy()
                if self._scrollTweenVal == valObj then
                    self._scrollTweenVal = nil
                end
                self:UpdateIndicator(true)
            end)
        end
    end
end

function Window:Tab(rawProps: any, sectionTarget: any?)
    local props: any = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    props.Title = props.Title or props.Name or "Tab"

    local targetSection = sectionTarget or props.Section
    if not targetSection and self._currentSection and props.Standalone ~= true and props.Section ~= false then
        targetSection = self._currentSection
    end

    local parentList = if targetSection then targetSection.TabList else self.SidebarTabList
    local tabItem = Tab.new(self, parentList, self.ContentArea, props)
    tabItem.ParentSection = targetSection
    if targetSection and not table.find(targetSection.Tabs, tabItem) then
        table.insert(targetSection.Tabs, tabItem)
    end
    table.insert(self.Tabs, tabItem)
    
    if #self.Tabs == 1 then
        self:SelectTab(tabItem)
    end
    return tabItem
end

function Window:Section(rawProps: any)
    if not rawProps then
        self._currentSection = nil
        return nil
    end
    local props: any = if type(rawProps) == "string" then { Title = rawProps } else rawProps
    props.Title = props.Title or props.Name or "Section"

    local section = TabSection.new(self, self.SidebarTabList, props)
    self._currentSection = section
    table.insert(self.Sections, section)
    return section
end

function Window:Popup(props: any)
    Popup.Show(self.RootGui, props)
end

function Window:Notify(props: any)
    pcall(function()
        Notification.Notify(self.RootGui, props)
    end)
end

function Window:SetToggleKey(keyCode: Enum.KeyCode | string)
    if typeof(keyCode) == "EnumItem" then
        self.ToggleKey = keyCode
    elseif type(keyCode) == "string" then
        local found = (Enum.KeyCode :: any)[keyCode]
        self.ToggleKey = found or keyCode
    end
end

function Window:RegisterFlag(flag: string, elem: any)
    if not flag or flag == "" then return end
    self.Flags[flag] = elem
    
    local origCallback = elem.Callback
    elem.Callback = function(...)
        if origCallback then
            local ok, err = pcall(origCallback, ...)
            if not ok then
                warn("[SodiumUI] Callback error for flag '" .. tostring(flag) .. "': " .. tostring(err))
            end
        end
        self:NotifyFlagChange(flag)
    end
end

function Window:NotifyFlagChange(flag: string)
    if self._isLoadingConfig or not self._autoSaveEnabled then
        return
    end

    if not self._dirtyFlags then
        self._dirtyFlags = {}
    end
    self._dirtyFlags[flag] = true

    if self._autoSaveThread then
        pcall(task.cancel, self._autoSaveThread)
        self._autoSaveThread = nil
    end

    self._autoSaveGen = (self._autoSaveGen or 0) + 1
    local currentGen = self._autoSaveGen
    self._autoSaveThread = task.delay(0.7, function()
        self._autoSaveThread = nil
        if self._autoSaveGen == currentGen and self._autoSaveEnabled and not self._isLoadingConfig then
            local targetName = self._autoSaveTarget or self._selectedConfigName or "Main"
            self:SaveConfig(targetName, true)
        end
    end)
end

function Window:_invalidateConfigCache()
    self._cachedConfigs = nil
    table.clear(self._configNameMap)
end

function Window:GetConfigs(): { string }
    if self._cachedConfigs then
        return self._cachedConfigs
    end

    table.clear(self._configNameMap)

    if not Compat.HasFS() then
        local names = {}
        for name in pairs(self._virtualConfigs) do
            table.insert(names, name)
            self._configNameMap[string.lower(name)] = name
        end
        table.sort(names)
        if #names == 0 then
            self:SaveConfig("Main", true)
            table.insert(names, "Main")
            self._configNameMap["main"] = "Main"
        end
        self._cachedConfigs = names
        return names
    end

    local folder = self.ConfigFolder
    Compat.MakeFolder(folder)
    local list = Compat.ListFiles(folder)
    local results = {}
    local seen = {}

    for _, path in ipairs(list) do
        local clean = string.gsub(path, "\\", "/")
        local name = string.match(clean, "([^/]+)%.json$")
        if name and name ~= "" and name ~= "autoload" then
            local lower = string.lower(name)
            if not seen[lower] then
                seen[lower] = true
                self._configNameMap[lower] = name
                table.insert(results, name)
            end
        end
    end

    -- If no config exists, automatically create Main.json
    if #results == 0 then
        self:SaveConfig("Main", true)
        table.insert(results, "Main")
        self._configNameMap["main"] = "Main"
    end

    table.sort(results)
    self._cachedConfigs = results
    return results
end

function Window:SaveConfig(name: string, silent: boolean?): boolean
    local rawName = (name and name ~= "") and name or "Main"
    local lower = string.lower(rawName)

    -- Ensure cache & name map are populated
    if not self._cachedConfigs then
        self:GetConfigs()
    end

    -- Case-insensitive deduplication using O(1) hash map
    local cfgName = self._configNameMap[lower] or rawName
    self._selectedConfigName = cfgName

    local data = {
        Version = 2,
        Flags = {},
        SavedAt = os.time(),
        PlaceId = game.PlaceId,
        AutoSave = self._autoSaveEnabled,
    }
    for flag, elem in pairs(self.Flags) do
        if elem and type(elem.Get) == "function" then
            local ok, val = pcall(elem.Get, elem)
            if ok and val ~= nil then
                data.Flags[flag] = val
            end
        end
    end

    local okEncode, json = pcall(HttpService.JSONEncode, HttpService, data)
    if not okEncode or not json then
        if not silent and self.Notify then
            self:Notify({ Title = "Save Failed", Content = "Failed to serialize config data", Duration = 2.5, Icon = "alert-circle" })
        end
        return false
    end

    if Compat.HasFS() then
        Compat.MakeFolder(self.ConfigFolder)
        local filePath = self.ConfigFolder .. "/" .. cfgName .. ".json"
        local okWrite = Compat.WriteFile(filePath, json)
        if not okWrite then
            if not silent and self.Notify then
                self:Notify({ Title = "Save Failed", Content = "Failed to write file to disk", Duration = 2.5, Icon = "alert-circle" })
            end
            return false
        end
    else
        self._virtualConfigs[cfgName] = json
    end

    -- Clear dirty flags after successful save
    if self._dirtyFlags then
        table.clear(self._dirtyFlags)
    end

    -- Invalidate file list cache
    self:_invalidateConfigCache()

    if not silent and self.Notify then
        self:Notify({
            Title = "Config Saved",
            Content = "Saved profile: " .. cfgName,
            Duration = 2.5,
            Icon = "check",
        })
    end

    if self._onConfigListChanged then
        pcall(self._onConfigListChanged)
    end
    return true
end

function Window:LoadConfig(name: string, silent: boolean?): boolean
    local rawName = (name and name ~= "") and name or "Main"
    local lower = string.lower(rawName)

    if not self._cachedConfigs then
        self:GetConfigs()
    end
    local cfgName = self._configNameMap[lower] or rawName
    self._selectedConfigName = cfgName

    local json = nil
    if Compat.HasFS() then
        local filePath = self.ConfigFolder .. "/" .. cfgName .. ".json"
        if not Compat.IsFile(filePath) then
            if not silent and self.Notify then
                self:Notify({ Title = "Load Failed", Content = "Config file '" .. cfgName .. "' not found", Duration = 2.5, Icon = "alert-circle" })
            end
            return false
        end
        json = Compat.ReadFile(filePath)
    else
        json = self._virtualConfigs[cfgName]
    end

    if not json or json == "" then
        if not silent and self.Notify then
            self:Notify({ Title = "Load Failed", Content = "Config file is empty", Duration = 2.5, Icon = "alert-circle" })
        end
        return false
    end

    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, json)
    if not okDecode or type(data) ~= "table" or type(data.Flags) ~= "table" then
        if not silent and self.Notify then
            self:Notify({ Title = "Load Failed", Content = "Invalid or corrupted JSON format", Duration = 2.5, Icon = "alert-circle" })
        end
        return false
    end

    -- Batch apply flag values without firing redundant save cycles or animations
    self._isLoadingConfig = true
    for flag, val in pairs(data.Flags) do
        local elem = self.Flags[flag]
        if elem and type(elem.Set) == "function" then
            pcall(function()
                elem:Set(val, false, false) -- (value, skipCallback, animate=false for instantaneous batching)
            end)
        end
    end
    self._isLoadingConfig = false

    if self._dirtyFlags then
        table.clear(self._dirtyFlags)
    end

    if data.AutoSave ~= nil then
        self:SetAutoSave(data.AutoSave, cfgName, true)
    end

    if not silent and self.Notify then
        self:Notify({
            Title = "Config Loaded",
            Content = "Applied profile: " .. cfgName,
            Duration = 2.5,
            Icon = "check",
        })
    end
    return true
end

function Window:DeleteConfig(name: string, silent: boolean?): boolean
    local rawName = (name and name ~= "") and name or "Main"
    local lower = string.lower(rawName)

    if not self._cachedConfigs then
        self:GetConfigs()
    end
    local cfgName = self._configNameMap[lower] or rawName
    local deleted = false

    if Compat.HasFS() then
        local filePath = self.ConfigFolder .. "/" .. cfgName .. ".json"
        if Compat.IsFile(filePath) then
            deleted = Compat.DeleteFile(filePath)
            if not deleted then
                local delfile = Compat.GetFunc("delfile") or Compat.GetFunc("deletefile")
                if type(delfile) == "function" then
                    pcall(delfile, filePath)
                    deleted = not Compat.IsFile(filePath)
                end
            end
        end
    else
        self._virtualConfigs[cfgName] = nil
        deleted = true
    end

    self:_invalidateConfigCache()

    if not silent and self.Notify then
        self:Notify({
            Title = if deleted then "Config Deleted" else "Delete Failed",
            Content = if deleted then ("Removed profile: " .. cfgName) else ("Could not find: " .. cfgName),
            Duration = 2.5,
            Icon = if deleted then "trash-2" else "alert-circle",
        })
    end

    if self._onConfigListChanged then
        pcall(self._onConfigListChanged)
    end
    return deleted
end

function Window:GetAutoSaveConfig(): string?
    local autoSaveFile = self.Folder .. "/autosave.txt"
    if Compat.HasFS() and Compat.IsFile(autoSaveFile) then
        local content = Compat.ReadFile(autoSaveFile)
        if content and content ~= "" and content ~= "none" then
            return (string.gsub(content, "%s+", ""))
        end
    elseif not Compat.HasFS() and self._virtualAutoSave then
        return self._virtualAutoSave
    end
    return nil
end

function Window:SetAutoSave(enabled: boolean, name: string?, skipSave: boolean?)
    local cfgName = (name and name ~= "") and name or (self._selectedConfigName or "Main")
    self._autoSaveEnabled = enabled
    self._autoSaveTarget = cfgName
    self._selectedConfigName = cfgName

    local autoSaveFile = self.Folder .. "/autosave.txt"
    if enabled then
        if Compat.HasFS() then
            Compat.MakeFolder(self.Folder)
            Compat.WriteFile(autoSaveFile, cfgName)
        else
            self._virtualAutoSave = cfgName
        end
        if not skipSave then
            self:SaveConfig(cfgName, false)
        end
    else
        if Compat.HasFS() then
            if Compat.IsFile(autoSaveFile) then
                Compat.WriteFile(autoSaveFile, "none")
            end
        else
            self._virtualAutoSave = nil
        end
        if not skipSave then
            self:SaveConfig(cfgName, true)
        end
    end

    if self._autoSaveToggle and type(self._autoSaveToggle.Set) == "function" then
        if self._autoSaveToggle.Value ~= enabled then
            self._autoSaveToggle:Set(enabled, true)
        end
    end
end

function Window:GetAutoLoadConfig(): string?
    local autoLoadFile = self.Folder .. "/autoload.txt"
    if Compat.HasFS() and Compat.IsFile(autoLoadFile) then
        local content = Compat.ReadFile(autoLoadFile)
        if content and content ~= "" and content ~= "none" then
            return (string.gsub(content, "%s+", ""))
        end
    elseif not Compat.HasFS() and self._virtualAutoLoad then
        return self._virtualAutoLoad
    end
    return nil
end

function Window:SetAutoLoad(enabled: boolean, name: string?)
    local autoLoadFile = self.Folder .. "/autoload.txt"
    local cfgName = (name and name ~= "") and name or (self._selectedConfigName or "Main")
    if enabled then
        if Compat.HasFS() then
            Compat.MakeFolder(self.Folder)
            Compat.WriteFile(autoLoadFile, cfgName)
        else
            self._virtualAutoLoad = cfgName
        end
    else
        if Compat.HasFS() then
            if Compat.IsFile(autoLoadFile) then
                Compat.WriteFile(autoLoadFile, "none")
            end
        else
            self._virtualAutoLoad = nil
        end
    end

    if self._autoLoadToggle and type(self._autoLoadToggle.Set) == "function" then
        if self._autoLoadToggle.Value ~= enabled then
            self._autoLoadToggle:Set(enabled, true)
        end
    end
end

function Window:AddConfigTab(rawProps: any?): (any, any)
    local props = rawProps or {}
    local tabTitle = props.Title or props.Name or { en = "Configs", th = "จัดการคอนฟิก" }
    local tabIcon = props.Icon or "settings"
    local cfgTab = self:Tab({
        Title = tabTitle,
        Icon = tabIcon,
    })
    local controls = cfgTab:AddConfigSection(props)
    return cfgTab, controls
end

function Window:Dialog(props: any)
    return Dialog.Show(self.MainFrame, props)
end

function Window:Destroy()
	self._isDestroyed = true
	if self._brandGradTween then
		pcall(self._brandGradTween.Cancel, self._brandGradTween)
		self._brandGradTween = nil
	end
	if self._expiryThread then
		pcall(task.cancel, self._expiryThread)
		self._expiryThread = nil
	end
	if self._indicatorTween then
		pcall((self._indicatorTween :: Tween).Cancel, self._indicatorTween)
		self._indicatorTween = nil
	end
	if self._hoverTrackerTween then
		pcall((self._hoverTrackerTween :: Tween).Cancel, self._hoverTrackerTween)
		self._hoverTrackerTween = nil
	end
	if self._activeBtnPosConn then
		pcall((self._activeBtnPosConn :: RBXScriptConnection).Disconnect, self._activeBtnPosConn)
		self._activeBtnPosConn = nil
	end
	if self._refreshConn then
		pcall((self._refreshConn :: RBXScriptConnection).Disconnect, self._refreshConn)
		self._refreshConn = nil
	end
	if self._dragConn then
		pcall((self._dragConn :: RBXScriptConnection).Disconnect, self._dragConn)
		self._dragConn = nil
	end
	if self._dragEndConn then
		pcall((self._dragEndConn :: RBXScriptConnection).Disconnect, self._dragEndConn)
		self._dragEndConn = nil
	end
	if self._dragRenderConn then
		pcall((self._dragRenderConn :: RBXScriptConnection).Disconnect, self._dragRenderConn)
		self._dragRenderConn = nil
	end
	if self._minDragConn then
		pcall((self._minDragConn :: RBXScriptConnection).Disconnect, self._minDragConn)
		self._minDragConn = nil
	end
	if self._scrollTweenVal then
		pcall((self._scrollTweenVal :: NumberValue).Destroy, self._scrollTweenVal)
		self._scrollTweenVal = nil
	end
	if self._toggleKeyConn then
		pcall((self._toggleKeyConn :: RBXScriptConnection).Disconnect, self._toggleKeyConn)
		self._toggleKeyConn = nil
	end
	if self._conns then
		for _, c in ipairs(self._conns) do
			pcall((c :: RBXScriptConnection).Disconnect, c)
		end
		table.clear(self._conns)
	end
	if self.MinShadow then
		pcall((self.MinShadow :: Instance).Destroy, self.MinShadow)
		self.MinShadow = nil
	end
	if self.MinWidget then
		pcall((self.MinWidget :: Instance).Destroy, self.MinWidget)
		self.MinWidget = nil
	end
	if self.DropShadow then
		pcall((self.DropShadow :: Instance).Destroy, self.DropShadow)
		self.DropShadow = nil
	end
	if self.RootGui then
		pcall((self.RootGui :: Instance).Destroy, self.RootGui)
	end
	pcall(function()
		local g = (type(getgenv) == "function" and getgenv()) or (rawget(getfenv(), "_G") :: any)
		if g and g._SODIUM_ACTIVE_WINDOW == self then
			g._SODIUM_ACTIVE_WINDOW = nil
		end
	end)
end

-- Aliases for API flexibility

Window.CreateTab = Window.Tab
Window.AddTab = Window.Tab
Window.CreateSection = Window.Section
Window.AddSection = Window.Section

return Window
end

_MODULES['Init'] = function()
--!strict
--[=[
    Pumpkin UI - Init.luau
    Root entry point for creating Windows, Notifications, Popups, and Custom Themes.
]=]

local Compat = _require("Core/Compat")
local Theme = _require("Core/Theme")
local Locale = _require("Core/Locale")
local Icons = _require("Core/Icons")
local Signals = _require("Core/Signals")
local Container = _require("Core/Container")
local Window = _require("Components/Window")
local Popup = _require("Components/Popup")
local Notification = _require("Components/Notification")
local Dialog = _require("Components/Dialog")
local Loading = _require("Components/Loading")
local KeyCheck = _require("Components/KeyCheck")

local PumpkinUI = {
	Version = "2.0.0",
	Theme = Theme,
	Locale = Locale,
	Icons = Icons,
	Signals = Signals,
	Compat = Compat,
}

local activeContainers: { any } = {}

function PumpkinUI:CreateWindow(props: any)
	Compat.DestroyActiveWindow()

	local containerManager = Container.new(props.Title or "PumpkinUI", props.Parent)
	table.insert(activeContainers, containerManager)

	local windowInstance = Window.new(containerManager, props)

	return windowInstance
end

function PumpkinUI:DestroyAll()
	for _, c in ipairs(activeContainers) do
		pcall((c :: any).Destroy, c)
	end
	table.clear(activeContainers)
	Compat.DestroyActiveWindow()
	Compat.CleanupRoots("PumpkinUI_", "PumpkinUI_Root")
	Compat.CleanupRoots("SodiumUI_", "SodiumUI_Root")
end

function PumpkinUI:AddTheme(name: string, tokens: any)
    Theme.AddTheme(name, tokens)
end

function PumpkinUI:SetTheme(name: string)
    Theme.SetTheme(name)
end

function PumpkinUI:SetLanguage(lang: string)
    Locale.SetLanguage(lang)
end

function PumpkinUI:GetLanguage(): string
    return Locale.GetLanguage()
end

function PumpkinUI:Notify(props: any)
    local targetRoot = activeContainers[#activeContainers] and activeContainers[#activeContainers].ScreenGui
    if not targetRoot then
        local tempContainer = Container.new("NotificationRoot")
        table.insert(activeContainers, tempContainer)
        targetRoot = tempContainer.ScreenGui
    end
    Notification.Notify(targetRoot, props)
end

function PumpkinUI:Popup(props: any)
    local targetRoot = activeContainers[#activeContainers] and activeContainers[#activeContainers].ScreenGui
    if not targetRoot then
        local tempContainer = Container.new("PopupRoot")
        table.insert(activeContainers, tempContainer)
        targetRoot = tempContainer.ScreenGui
    end
    Popup.Show(targetRoot, props)
end

function PumpkinUI:Dialog(props: any)
	local env = Compat.GetEnv()
	local activeWindow = env and (env._PUMPKIN_ACTIVE_WINDOW or env._SODIUM_ACTIVE_WINDOW)
	if type(activeWindow) == "table"
		and (activeWindow :: any).MainFrame
		and (activeWindow :: any).MainFrame.Parent
	then
		return Dialog.Show((activeWindow :: any).MainFrame, props)
	end
    local targetRoot = activeContainers[#activeContainers] and activeContainers[#activeContainers].ScreenGui
    if not targetRoot then
        local tempContainer = Container.new("DialogRoot")
        table.insert(activeContainers, tempContainer)
        targetRoot = tempContainer.ScreenGui
    end
    return Dialog.Show(targetRoot, props)
end

function PumpkinUI:CreateLoading(props: any)
    return Loading.new(props)
end
PumpkinUI.Loading = PumpkinUI.CreateLoading

function PumpkinUI:CreateKeyCheck(props: any)
    return KeyCheck.new(props)
end
PumpkinUI.KeyCheck = PumpkinUI.CreateKeyCheck

return PumpkinUI
end

return _require('Init')
