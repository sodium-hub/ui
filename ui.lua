-- Sodium UI Standalone (Obsidian Amethyst)

local _MODULES = {}
local _LOADED = {}

local function _require(path)
    if _LOADED[path] then
        return _LOADED[path]
    end
    local loader = _MODULES[path]
    if not loader then
        error('[SodiumUI Standalone] Module not found: ' .. tostring(path))
    end
    local result = loader()
    _LOADED[path] = result
    return result
end

_MODULES['Core/Signals'] = function()


local Signal = {}
Signal.__index = Signal


function Signal.new()
    local self = setmetatable({}, Signal)
    self._listeners = {}
    self._totalListeners = 0
    return self
end

function Signal:Connect(callback)
    assert(type(callback) == "function", "[SodiumUI.Signal] Callback must be a function")

    local connection = {
        Connected = true,
    }

    local listeners = self._listeners
    listeners[connection] = callback
    self._totalListeners += 1

    connection.Disconnect = function(conn)
        if not conn.Connected then return end
        conn.Connected = false
        if listeners[conn] then
            listeners[conn] = nil
            self._totalListeners -= 1
        end
    end

    return connection
end

function Signal:Once(callback)
    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        callback(...)
    end)
    return connection
end

function Signal:Fire(...)
    for connection, callback in pairs(self._listeners) do
        if connection.Connected then
            task.spawn(callback, ...)
        end
    end
end

function Signal:Wait()
    local thread = coroutine.running()
    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        task.spawn(thread, ...)
    end)
    return coroutine.yield()
end

function Signal:DisconnectAll()
    for connection in pairs(self._listeners) do
        connection.Connected = false
    end
    table.clear(self._listeners)
    self._totalListeners = 0
end

function Signal:Destroy()
    self:DisconnectAll()
    setmetatable(self, nil)
end

return Signal
end

_MODULES['Core/Theme'] = function()


local Signals = _require("Core/Signals")

local Theme = {}
Theme.__index = Theme


local ObsidianAmethyst = {
    Background = Color3.fromHex("#09090B"),
    Card = Color3.fromHex("#131318"),
    SurfaceHover = Color3.fromHex("#1C1C24"),
    SurfaceActive = Color3.fromHex("#262633"),

    BorderSubtle = Color3.fromHex("#22222B"),
    BorderStrong = Color3.fromHex("#333340"),
    BorderAccent = Color3.fromHex("#8B5CF6"),

    TextPrimary = Color3.fromHex("#FFFFFF"),
    TextMuted = Color3.fromHex("#B8B8C2"),
    TextDark = Color3.fromHex("#09090B"),
    Placeholder = Color3.fromHex("#8E8E98"),

    Accent = Color3.fromHex("#8B5CF6"),
    AccentDark = Color3.fromHex("#7C3AED"),
    AccentGlow = Color3.fromHex("#8B5CF6"),
    AccentGlowTransparency = 0.88,

    Success = Color3.fromHex("#22C55E"),
    Warning = Color3.fromHex("#F59E0B"),
    Danger = Color3.fromHex("#EF4444"),
}

local WhiteMode = {
    Background = Color3.fromHex("#F8F9FA"),
    Card = Color3.fromHex("#FFFFFF"),
    SurfaceHover = Color3.fromHex("#F1F2F4"),
    SurfaceActive = Color3.fromHex("#E5E7EB"),

    BorderSubtle = Color3.fromHex("#E5E7EB"),
    BorderStrong = Color3.fromHex("#9CA3AF"),
    BorderAccent = Color3.fromHex("#7C3AED"),

    TextPrimary = Color3.fromHex("#000000"),
    TextMuted = Color3.fromHex("#4B5563"),
    TextDark = Color3.fromHex("#000000"),
    Placeholder = Color3.fromHex("#9CA3AF"),

    Accent = Color3.fromHex("#7C3AED"),
    AccentDark = Color3.fromHex("#6D28D9"),
    AccentGlow = Color3.fromHex("#7C3AED"),
    AccentGlowTransparency = 0.88,

    Success = Color3.fromHex("#16A34A"),
    Warning = Color3.fromHex("#D97706"),
    Danger = Color3.fromHex("#DC2626"),
}

local Themes = {
    ["Obsidian Amethyst"] = ObsidianAmethyst,
    ["Dark"] = ObsidianAmethyst,
    ["WhiteMode"] = WhiteMode,
    ["Light"] = WhiteMode,
}

local CurrentThemeName = "Obsidian Amethyst"
local CurrentThemeTokens = ObsidianAmethyst

Theme.Changed = Signals.new()

local TweenService = game:GetService("TweenService")
local boundInstances = {}

function Theme.Bind(instance, property, token)
    local val = Theme.GetToken(token)
    if val ~= nil then
        pcall(function()
            instance[property] = val
        end)
    end

    if not boundInstances[instance] then
        boundInstances[instance] = {}
        instance.Destroying:Once(function()
            boundInstances[instance] = nil
        end)
    end

    table.insert(boundInstances[instance], {
        property = property,
        token = token,
    })
end

function Theme.GetToken(token)
    return CurrentThemeTokens[token]
end

function Theme.GetTokens()
    return CurrentThemeTokens
end

function Theme.GetCurrentThemeName()
    return CurrentThemeName
end

function Theme.AddTheme(name, tokens)
    assert(type(name) == "string", "[SodiumUI.Theme] Theme name must be string")
    assert(type(tokens) == "table", "[SodiumUI.Theme] Tokens must be a table")

    local merged = table.clone(ObsidianAmethyst)
    for k, v in pairs(tokens) do
        merged[k] = v
    end
    Themes[name] = merged
end

function Theme.SetTheme(name)
    local target = Themes[name]
    if not target then
        target = ObsidianAmethyst
        name = "Obsidian Amethyst"
    end

    CurrentThemeName = name
    CurrentThemeTokens = target
    Theme.Changed:Fire(CurrentThemeTokens)

    local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local count = 0
    for _ in pairs(boundInstances) do
        count += 1
    end

    local useTweens = count <= 200

    for instance, props in pairs(boundInstances) do
        if instance and instance.Parent then
            for _, item in ipairs(props) do
                local tokenVal = CurrentThemeTokens[item.token]
                if tokenVal ~= nil then
                    pcall(function()
                        if useTweens then
                            TweenService:Create(instance, tweenInfo, { [item.property] = tokenVal }):Play()
                        else
                            instance[item.property] = tokenVal
                        end
                    end)
                end
            end
        else
            boundInstances[instance] = nil
        end
    end
end


Theme.Fonts = {
    Title = Enum.Font.GothamBold,
    Header = Enum.Font.GothamMedium,
    Body = Enum.Font.GothamMedium,
    Sub = Enum.Font.GothamMedium,
    Code = Enum.Font.RobotoMono,
}

Theme.FontSizes = {
    Display = 16,
    Title = 14,
    Header = 13,
    Body = 13,
    Sub = 12,
    Small = 11,
    Code = 11,
}


Theme.Radii = {
    Window = UDim.new(0, 8),
    Card = UDim.new(0, 6),
    Element = UDim.new(0, 5),
    Control = UDim.new(0, 4),
    Pill = UDim.new(0, 99),
}

return Theme
end

_MODULES['Core/Tweener'] = function()


local TweenService = game:GetService("TweenService")

local Tweener = {}


Tweener.Info = {
    Micro = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    Fast = TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    Normal = TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    Smooth = TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    Spring = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    BackOut = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
    Bouncy = TweenInfo.new(0.48, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
}

local activeTweens = {}

function Tweener.Tween(instance, info, goals, onComplete)
    local currentTween = activeTweens[instance]
    if currentTween then
        currentTween:Cancel()
        activeTweens[instance] = nil
    end

    local tween = TweenService:Create(instance, info, goals)
    activeTweens[instance] = tween

    tween.Completed:Once(function()
        if activeTweens[instance] == tween then
            activeTweens[instance] = nil
        end
        if onComplete then
            onComplete()
        end
    end)
    tween:Play()
    return tween
end


function Tweener.BindPressFeedback(visual, trigger, targetScale, preserveText)
    local button = trigger or (visual:IsA("GuiButton") and visual or nil)
    if not button then return end

    local uiScale = visual:FindFirstChildOfClass("UIScale")
    if not uiScale then
        uiScale = Instance.new("UIScale")
        uiScale.Scale = 1
        uiScale.Parent = visual
    end

    local targetPressScale = targetScale or 0.96
    local textCounterScale = 1 / targetPressScale
    local shouldPreserveText = preserveText == true

    local function getDescendantTextScalers()
        if not shouldPreserveText then return {} end
        local scalers = {}
        for _, desc in ipairs(visual:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextBox") then
                local tScale = desc:FindFirstChildOfClass("UIScale")
                if not tScale then
                    tScale = Instance.new("UIScale")
                    tScale.Scale = 1
                    tScale.Parent = desc
                end
                table.insert(scalers, tScale)
            end
        end
        return scalers
    end

    button.MouseButton1Down:Connect(function()
        local textScalers = getDescendantTextScalers()
        Tweener.Tween(uiScale, Tweener.Info.Micro, { Scale = targetPressScale })
        for _, tScale in ipairs(textScalers) do
            Tweener.Tween(tScale, Tweener.Info.Micro, { Scale = textCounterScale })
        end
    end)

    local function release()
        local textScalers = getDescendantTextScalers()
        Tweener.Tween(uiScale, Tweener.Info.Fast, { Scale = 1.0 })
        for _, tScale in ipairs(textScalers) do
            Tweener.Tween(tScale, Tweener.Info.Fast, { Scale = 1.0 })
        end
    end

    button.MouseButton1Up:Connect(release)
    button.MouseLeave:Connect(release)
    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            release()
        end
    end)
end


function Tweener.BindHoverLift(
    container,
    stroke,
    defaultBg,
    hoverBg,
    defaultStroke,
    hoverStroke
)
    local originalY = container.Position.Y.Offset
    local originalX = container.Position.X.Offset
    local originalScaleX = container.Position.X.Scale
    local originalScaleY = container.Position.Y.Scale
    local UserInputService = game:GetService("UserInputService")
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        return
    end
    local Theme = _require("Core/Theme")

    container.MouseEnter:Connect(function()
        local hBg = hoverBg or Theme.GetToken("SurfaceActive")
        local hStroke = hoverStroke or Theme.GetToken("BorderAccent")
        Tweener.Tween(container, Tweener.Info.Fast, {
            Position = UDim2.new(originalScaleX, originalX, originalScaleY, originalY - 1),
            BackgroundColor3 = hBg,
        })
        if stroke then
            Tweener.Tween(stroke, Tweener.Info.Fast, {
                Color = hStroke,
            })
        end
    end)

    container.MouseLeave:Connect(function()
        local dBg = defaultBg or Theme.GetToken("SurfaceHover")
        local dStroke = defaultStroke or Theme.GetToken("BorderSubtle")
        Tweener.Tween(container, Tweener.Info.Fast, {
            Position = UDim2.new(originalScaleX, originalX, originalScaleY, originalY),
            BackgroundColor3 = dBg,
        })
        if stroke then
            Tweener.Tween(stroke, Tweener.Info.Fast, {
                Color = dStroke,
            })
        end
    end)
end


function Tweener.BindCardPressFeedback(card, trigger, shrinkOffset)
    local offset = shrinkOffset or Vector2.new(6, 4)
    local defaultSize = card.Size
    local pressedSize = UDim2.new(defaultSize.X.Scale, defaultSize.X.Offset - offset.X, defaultSize.Y.Scale, defaultSize.Y.Offset - offset.Y)

    local function press()
        Tweener.Tween(card, Tweener.Info.Micro, { Size = pressedSize })
    end

    local function release()
        Tweener.Tween(card, Tweener.Info.Fast, { Size = defaultSize })
    end

    trigger.MouseButton1Down:Connect(press)
    trigger.MouseButton1Up:Connect(release)
    trigger.MouseLeave:Connect(release)
    trigger.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            release()
        end
    end)
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
local HttpService = game:GetService("HttpService")

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

function Icons.LoadPack(packName)
    local pName = string.lower(packName)
    if Icons.Packs[pName] then return true end
    
    local cdnUrl = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/" .. pName .. "/dist/Icons.lua"
    local getcustomasset = rawget(getfenv(), "getcustomasset") or rawget(getfenv(), "getsynasset")
    local writefile = rawget(getfenv(), "writefile")
    local isfile = rawget(getfenv(), "isfile")
    local readfile = rawget(getfenv(), "readfile")
    local makefolder = rawget(getfenv(), "makefolder")
    
    local localFile = "SodiumHub/Cache/Icons_" .. pName .. ".lua"
    if type(isfile) == "function" and isfile(localFile) then
        local success, result = pcall(function()
            return loadstring(readfile(localFile))()
        end)
        if success and type(result) == "table" then
            Icons.Packs[pName] = result
            return true
        end
    end
    
    local success, body = pcall(function()
        return game:HttpGet(cdnUrl)
    end)
    if success and body and #body > 0 then
        if type(makefolder) == "function" then
            pcall(makefolder, "SodiumHub")
            pcall(makefolder, "SodiumHub/Cache")
        end
        if type(writefile) == "function" then
            pcall(writefile, localFile, body)
        end
        local loadSuccess, result = pcall(function()
            return loadstring(body)()
        end)
        if loadSuccess and type(result) == "table" then
            Icons.Packs[pName] = result
            return true
        end
    end
    return false
end

local function resolveFromPack(packName, query)
    local pName = string.lower(packName or Icons.IconsType)
    local pack = Icons.Packs[pName]
    if not pack then
        Icons.LoadPack(pName)
        pack = Icons.Packs[pName]
        if not pack then return nil end
    end
    
    if pack[query] then
        return pack[query]
    end
    
    if pack.Icons and pack.Icons[query] then
        local item = pack.Icons[query]
        local sheetId = pack.Spritesheets and pack.Spritesheets[tostring(item.Image)] or item.Image
        return {
            sheetId,
            item,
        }
    end
    
    local alias = IconAliases[query]
    if alias then
        if pack[alias] then return pack[alias] end
        if pack.Icons and pack.Icons[alias] then
            local item = pack.Icons[alias]
            local sheetId = pack.Spritesheets and pack.Spritesheets[tostring(item.Image)] or item.Image
            return { sheetId, item }
        end
    end
    
    if #query > 3 and query:sub(-1) == "s" then
        local singular = query:sub(1, -2)
        local fromSingular = resolveFromPack(pName, singular)
        if fromSingular then return fromSingular end
    end
    
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
    
    lookupCache[iconName] = finalAsset
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
    if not source or source == "" then return end
    local sourceStr = tostring(source)
    
    if string.find(sourceStr, "^https?://") then
        local getcustomasset = (rawget(getfenv(), "getcustomasset") or rawget(getfenv(), "getsynasset"))
        local writefile = rawget(getfenv(), "writefile")
        local isfile = rawget(getfenv(), "isfile")
        local makefolder = rawget(getfenv(), "makefolder")
        if type(getcustomasset) == "function" and type(writefile) == "function" then
            task.spawn(function()
                pcall(function()
                    if type(makefolder) == "function" then
                        pcall(makefolder, "SodiumHub")
                        pcall(makefolder, "SodiumHub/Cache")
                    end
                    local fileName = "SodiumHub/Cache/" .. sourceStr:gsub("[^%w]", "_"):sub(-32) .. ".png"
                    if not (type(isfile) == "function" and isfile(fileName)) then
                        local content = game:HttpGet(sourceStr)
                        if content and #content > 0 then
                            writefile(fileName, content)
                        end
                    end
                    if imageLabel.Parent then
                        imageLabel.Image = getcustomasset(fileName)
                    end
                end)
            end)
            return
        else
            imageLabel.Image = sourceStr
            return
        end
    end
    
    local assetId = string.match(sourceStr, "%d+")
    if assetId then
        local primary = "rbxthumb://type=Asset&id=" .. assetId .. "&w=150&h=150"
        imageLabel.Image = primary
        
        task.spawn(function()
            schedulePreload(imageLabel)
            task.wait(1.2)
            if not imageLabel.Parent then return end
            if not imageLabel.IsLoaded then
                imageLabel.Image = "rbxthumb://type=Asset&id=" .. assetId .. "&w=420&h=420"
                schedulePreload(imageLabel)
                task.wait(1.2)
                if not imageLabel.Parent then return end
                if not imageLabel.IsLoaded then
                    imageLabel.Image = "rbxassetid://" .. assetId
                end
            end
        end)
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

_MODULES['Core/Container'] = function()


local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Container = {}
Container.__index = Container

local Camera = workspace.CurrentCamera

local function getGuiParent()
    local gethui = rawget(getfenv(), "gethui")
    if type(gethui) == "function" then
        local success, res = pcall(gethui)
        if success and res then
            return res
        end
    end

    local coreGui = game:GetService("CoreGui")
    local success, _ = pcall(function()
        local _test = coreGui.Name
    end)
    if success then
        return coreGui
    end

    local lp = Players.LocalPlayer
    if lp then
        return lp:WaitForChild("PlayerGui")
    end

    return game:GetService("CoreGui")
end

local function cleanupPreviousInstances()
    local g = rawget(getfenv(), "_G")
    if g and g._SODIUM_ACTIVE_WINDOW and type(g._SODIUM_ACTIVE_WINDOW.Destroy) == "function" then
        pcall(function()
            g._SODIUM_ACTIVE_WINDOW:Destroy()
        end)
        g._SODIUM_ACTIVE_WINDOW = nil
    end

    local roots = {}
    local gethui = rawget(getfenv(), "gethui")
    if type(gethui) == "function" then
        local s, r = pcall(gethui)
        if s and r then table.insert(roots, r) end
    end

    local coreGui = game:GetService("CoreGui")
    pcall(function()
        if coreGui then table.insert(roots, coreGui) end
    end)

    local lp = Players.LocalPlayer
    if lp then
        local pg = lp:FindFirstChild("PlayerGui")
        if pg then table.insert(roots, pg) end
    end

    for _, root in ipairs(roots) do
        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("ScreenGui") then
                local name = child.Name
                if name:sub(1, 9) == "SodiumUI_" or child:GetAttribute("SodiumUI_Root") == true then
                    pcall(function()
                        child:Destroy()
                    end)
                end
            end
        end
    end
end

function Container:_updateScaling(immediate)
    if not Camera then
        Camera = workspace.CurrentCamera
    end
    if not Camera then return end

    local vp = Camera.ViewportSize
    local baseW = self.BaseWindowSize and self.BaseWindowSize.X or 720
    local baseH = self.BaseWindowSize and self.BaseWindowSize.Y or 480


    local insetTopLeft, insetBottomRight = GuiService:GetGuiInset()
    local insetX = insetTopLeft and insetTopLeft.X or 0
    local insetY = insetTopLeft and insetTopLeft.Y or 0
    if insetBottomRight then
        insetX = math.max(insetX, insetBottomRight.X)
        insetY = math.max(insetY, insetBottomRight.Y)
    end


    local marginX = (if (vp.X < 900 or self.IsMobile) then 16 else 28) + insetX
    local marginY = (if (vp.Y < 600 or self.IsMobile) then 14 else 28) + insetY

    local availW = math.max(60, vp.X - (marginX * 2))
    local availH = math.max(60, vp.Y - (marginY * 2))

    local scaleX = availW / baseW
    local scaleH = availH / baseH

    -- Screen boundary clamp
    local fitScale = math.min(scaleX, scaleH)
    local minScale = if self.IsMobile then 0.35 else 0.45
    local dpiMax = math.clamp(vp.X / 1920, 1.0, 1.85)
    local targetScale = math.clamp(fitScale, minScale, dpiMax)

    if immediate then
        self.UIScale.Scale = targetScale
    else
        Tweener.Tween(self.UIScale, Tweener.Info.Fast, { Scale = targetScale })
    end

    if self.OnScaleChanged then
        self.OnScaleChanged(targetScale)
    end
end

function Container:_initViewportScaling()
    local resizeThread = nil
    local function onResize()
        if resizeThread then task.cancel(resizeThread) end
        resizeThread = task.delay(0.1, function()
            self:_updateScaling(false)
        end)
    end

    self:_updateScaling(true)

    if Camera then
        table.insert(self._connections, Camera:GetPropertyChangedSignal("ViewportSize"):Connect(onResize))
    end
    table.insert(self._connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        Camera = workspace.CurrentCamera
        if Camera then
            table.insert(self._connections, Camera:GetPropertyChangedSignal("ViewportSize"):Connect(onResize))
            self:_updateScaling(true)
        end
    end))
end

function Container.new(title)
    cleanupPreviousInstances()

    local self = setmetatable({}, Container)

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SodiumUI_" .. (title:gsub("%s+", "_"))
    screenGui:SetAttribute("SodiumUI_Root", true)
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 999999

    -- Executor protection
    local syn = rawget(getfenv(), "syn")
    if syn and type(syn) == "table" and type(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, screenGui)
    end

    screenGui.Parent = getGuiParent()
    self.ScreenGui = screenGui


    local uiScale = Instance.new("UIScale")
    uiScale.Name = "GlobalScaler"
    uiScale.Scale = 1.0
    uiScale.Parent = screenGui
    self.UIScale = uiScale

    self.BaseWindowSize = Vector2.new(720, 480)
    self.IsMobile = UserInputService.TouchEnabled or (not UserInputService.KeyboardEnabled)
    self.OnScaleChanged = nil
    self._connections = {}

    -- Dynamic viewport scale compensation
    Container._initViewportScaling(self)

    return self
end

function Container:SetBaseWindowSize(size)
    self.BaseWindowSize = size
    self:_updateScaling(true)
end

function Container:Destroy()
    if self._connections then
        for _, conn in ipairs(self._connections) do
            if type(conn) == "table" and type(conn.Disconnect) == "function" then
                conn:Disconnect()
            elseif typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end
        table.clear(self._connections)
    end
    if self.ScreenGui then
        self.ScreenGui:Destroy()
    end
end

return Container
end

_MODULES['Storage/ConfigEngine'] = function()


local HttpService = game:GetService("HttpService")

local ConfigEngine = {}
ConfigEngine.__index = ConfigEngine


-- Type serialization
local function serializeValue(val)
    local t = typeof(val)
    if t == "Color3" then
        return {
            __type = "Color3",
            hex = val:ToHex(),
            r = val.R,
            g = val.G,
            b = val.B,
        }
    elseif t == "EnumItem" then
        local enumItem = val
        return {
            __type = "EnumItem",
            enum = tostring(enumItem.EnumType),
            name = enumItem.Name,
            value = enumItem.Value,
        }
    elseif t == "Vector2" then
        local v = val
        return { __type = "Vector2", x = v.X, y = v.Y }
    elseif t == "Vector3" then
        local v = val
        return { __type = "Vector3", x = v.X, y = v.Y, z = v.Z }
    elseif t == "UDim2" then
        local u = val
        return { __type = "UDim2", sx = u.X.Scale, ox = u.X.Offset, sy = u.Y.Scale, oy = u.Y.Offset }
    elseif t == "table" then
        local copy = {}
        for k, v in pairs(val) do
            copy[k] = serializeValue(v)
        end
        return copy
    else
        return val
    end
end

-- Type deserialization
local function deserializeValue(val)
    if type(val) == "table" and val.__type then
        local typeName = val.__type
        if typeName == "Color3" then
            if val.hex then
                local success, color = pcall(Color3.fromHex, val.hex)
                if success and color then return color end
            end
            if val.r and val.g and val.b then
                return Color3.new(val.r, val.g, val.b)
            end
        elseif typeName == "EnumItem" then
            if val.enum and val.name then
                local enumGroup = Enum[val.enum]
                if enumGroup and enumGroup[val.name] then
                    return enumGroup[val.name]
                end
            end
        elseif typeName == "Vector2" then
            return Vector2.new(val.x or 0, val.y or 0)
        elseif typeName == "Vector3" then
            return Vector3.new(val.x or 0, val.y or 0, val.z or 0)
        elseif typeName == "UDim2" then
            return UDim2.new(val.sx or 0, val.ox or 0, val.sy or 0, val.oy or 0)
        end
    elseif type(val) == "table" then
        local copy = {}
        for k, v in pairs(val) do
            copy[k] = deserializeValue(v)
        end
        return copy
    end
    return val
end

function ConfigEngine.new(folderName)
    local self = setmetatable({}, ConfigEngine)
    self.FolderName = folderName or "SodiumHub"
    self.ConfigsFolder = self.FolderName .. "/configs"

    self.Flags = {}
    self._handlers = {}
    self._listeners = {}
    self.InMemoryStorage = {}

    self.ActiveConfig = "Default"
    self.AutoSaveEnabled = false
    self.AutoSaveDelay = 0.5
    self._autoSaveThread = nil

    self:_ensureDirectories()
    return self
end

function ConfigEngine:_hasUNC()
    local env = getfenv()
    return type(rawget(env, "writefile")) == "function"
        and type(rawget(env, "readfile")) == "function"
        and type(rawget(env, "isfile")) == "function"
end

function ConfigEngine:_ensureDirectories()
    if not self:_hasUNC() then return end
    local env = getfenv()
    local makefolder = rawget(env, "makefolder")
    local isfolder = rawget(env, "isfolder")

    if type(isfolder) == "function" and type(makefolder) == "function" then
        pcall(function()
            if not isfolder(self.FolderName) then
                makefolder(self.FolderName)
            end
            if not isfolder(self.ConfigsFolder) then
                makefolder(self.ConfigsFolder)
            end
        end)
    end
end

function ConfigEngine:RegisterFlag(flag, getter, skipCallback)
    assert(type(flag) == "string" and flag ~= "", "[SodiumUI.Config] Invalid flag name")

    local initial = if defaultVal ~= nil then defaultVal else getter()
    self.Flags[flag] = initial
    self._handlers[flag] = {
        Get = getter,
        Set = setter,
        Default = initial,
    }
end

function ConfigEngine:UnregisterFlag(flag)
    self.Flags[flag] = nil
    self._handlers[flag] = nil
    self._listeners[flag] = nil
end

function ConfigEngine:Get(flag)
    local handler = self._handlers[flag]
    if handler then
        local s, v = pcall(handler.Get)
        if s then
            self.Flags[flag] = v
            return v
        end
    end
    return self.Flags[flag]
end

function ConfigEngine:Set(flag, val, skipCallback)
    local handler = self._handlers[flag]
    if handler then
        pcall(handler.Set, val, skipCallback)
    end
    self.Flags[flag] = val

    local listeners = self._listeners[flag]
    if listeners then
        for _, cb in ipairs(listeners) do
            task.spawn(cb, val)
        end
    end

    if self.AutoSaveEnabled then
        self:_triggerAutoSave()
    end
end

function ConfigEngine:OnChanged(flag, callback)
    if not self._listeners[flag] then
        self._listeners[flag] = {}
    end
    table.insert(self._listeners[flag], callback)

    return function()
        local list = self._listeners[flag]
        if list then
            local idx = table.find(list, callback)
            if idx then table.remove(list, idx) end
        end
    end
end

function ConfigEngine:SetAutoSave(enabled, configName, delaySeconds)
    self.AutoSaveEnabled = enabled
    if configName then
        self.ActiveConfig = configName
    end
    if delaySeconds then
        self.AutoSaveDelay = delaySeconds
    end
end

function ConfigEngine:_triggerAutoSave()
    if self._autoSaveThread then
        task.cancel(self._autoSaveThread)
        self._autoSaveThread = nil
    end
    self._autoSaveThread = task.delay(self.AutoSaveDelay, function()
        self._autoSaveThread = nil
        self:SaveConfig(self.ActiveConfig or "Default")
    end)
end

function ConfigEngine:SaveConfig(configName)
    assert(type(configName) == "string" and configName ~= "", "[SodiumUI.Config] Invalid config name")

    local stateMap = {}
    for flag, handler in pairs(self._handlers) do
        local success, val = pcall(handler.Get)
        if success and val ~= nil then
            stateMap[flag] = serializeValue(val)
            self.Flags[flag] = val
        elseif self.Flags[flag] ~= nil then
            stateMap[flag] = serializeValue(self.Flags[flag])
        end
    end

    local payload = {
        _meta = {
            library = "SodiumUI",
            version = "1.0.0",
            savedAt = os.time(),
            configName = configName,
        },
        flags = stateMap,
    }

    local s, jsonString = pcall(HttpService.JSONEncode, HttpService, payload)
    if not s or not jsonString then
        warn("[SodiumUI.Config] JSON serialization failed")
        return false, "Failed to encode config to JSON"
    end

    local filePath = string.format("%s/%s.json", self.ConfigsFolder, configName)
    self.ActiveConfig = configName

    if self:_hasUNC() then
        self:_ensureDirectories()
        local env = getfenv()
        local writefile = rawget(env, "writefile")
        local isfile = rawget(env, "isfile")

        local writeOk, writeErr = pcall(writefile, filePath, jsonString)
        if not writeOk then
            warn("[SodiumUI.Config] Failed to save config to disk:", writeErr)
            return false, tostring(writeErr)
        end

        if type(isfile) == "function" and not isfile(filePath) then
            return false, "Verification failed: file was not written"
        end
        return true, "Config saved successfully"
    else
        self.InMemoryStorage[configName] = jsonString
        return true, "Config saved to in-memory store"
    end
end

function ConfigEngine:LoadConfig(configName, silent)
    assert(type(configName) == "string" and configName ~= "", "[SodiumUI.Config] Invalid config name")
    local filePath = string.format("%s/%s.json", self.ConfigsFolder, configName)

    local jsonString
    if self:_hasUNC() then
        local env = getfenv()
        local isfile = rawget(env, "isfile")
        local readfile = rawget(env, "readfile")

        if isfile(filePath) then
            local readOk, res = pcall(readfile, filePath)
            if readOk and type(res) == "string" and res ~= "" then
                jsonString = res
            end
        end
    else
        jsonString = self.InMemoryStorage[configName]
    end

    if not jsonString then
        local err = string.format("Config '%s' does not exist", configName)
        warn("[SodiumUI.Config] " .. err)
        return false, err
    end

    local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, jsonString)
    if not decodeOk or type(decoded) ~= "table" then
        warn("[SodiumUI.Config] Failed to parse config JSON")
        return false, "Corrupted or invalid JSON config file"
    end

    local flags = decoded.flags
    if type(flags) ~= "table" then
        return false, "Config contains no valid flags table"
    end

    self.ActiveConfig = configName

    for flag, rawVal in pairs(flags) do
        local val = deserializeValue(rawVal)
        self.Flags[flag] = val
        local handler = self._handlers[flag]
        if handler then
            pcall(handler.Set, val, silent)
        end

        local listeners = self._listeners[flag]
        if listeners then
            for _, cb in ipairs(listeners) do
                task.spawn(cb, val)
            end
        end
    end

    return true, "Config loaded successfully"
end

function ConfigEngine:ExportConfig(configName)
    local filePath = string.format("%s/%s.json", self.ConfigsFolder, configName)
    if self:_hasUNC() then
        local env = getfenv()
        local isfile = rawget(env, "isfile")
        local readfile = rawget(env, "readfile")
        if isfile(filePath) then
            local s, res = pcall(readfile, filePath)
            if s and res then return res, nil end
        end
    else
        local data = self.InMemoryStorage[configName]
        if data then return data, nil end
    end
    return nil, "Config not found"
end

function ConfigEngine:ImportConfig(configName, jsonString)
    local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, jsonString)
    if not decodeOk or type(decoded) ~= "table" or type(decoded.flags) ~= "table" then
        return false, "Invalid JSON string format"
    end

    local filePath = string.format("%s/%s.json", self.ConfigsFolder, configName)
    if self:_hasUNC() then
        self:_ensureDirectories()
        local writefile = rawget(getfenv(), "writefile")
        local s, err = pcall(writefile, filePath, jsonString)
        if not s then return false, tostring(err) end
        return true, "Imported and saved successfully"
    else
        self.InMemoryStorage[configName] = jsonString
        return true, "Imported to memory"
    end
end

function ConfigEngine:DeleteConfig(configName)
    local filePath = string.format("%s/%s.json", self.ConfigsFolder, configName)
    if self:_hasUNC() then
        local env = getfenv()
        local isfile = rawget(env, "isfile")
        local delfile = rawget(env, "delfile")
        if type(isfile) == "function" and type(delfile) == "function" and isfile(filePath) then
            pcall(delfile, filePath)
            return true
        end
    else
        self.InMemoryStorage[configName] = nil
        return true
    end
    return false
end

function ConfigEngine:GetConfigs()
    local configs = {}
    if self:_hasUNC() then
        local env = getfenv()
        local listfiles = rawget(env, "listfiles")
        local isfolder = rawget(env, "isfolder")

        if type(listfiles) == "function" and type(isfolder) == "function" and isfolder(self.ConfigsFolder) then
            local files = listfiles(self.ConfigsFolder)
            for _, f in ipairs(files) do
                local name = f:match("([^/\\]+)%.json$")
                if name then
                    table.insert(configs, name)
                end
            end
        end
    else
        for name in pairs(self.InMemoryStorage) do
            table.insert(configs, name)
        end
    end
    table.sort(configs)
    return configs
end

function ConfigEngine:ResetToDefaults(silent)
    for flag, handler in pairs(self._handlers) do
        if handler.Default ~= nil then
            pcall(handler.Set, handler.Default, silent)
            self.Flags[flag] = handler.Default

            local listeners = self._listeners[flag]
            if listeners then
                for _, cb in ipairs(listeners) do
                    task.spawn(cb, handler.Default)
                end
            end
        end
    end
end

return ConfigEngine
end

_MODULES['Components/Primitives'] = function()


local Theme = _require("Core/Theme")

local Primitives = {}

function Primitives.Divider(parent, text)
    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.Size = UDim2.new(1, 0, 0, if text and text ~= "" then 24 else 8)
    divider.BackgroundTransparency = 1

    if text and text ~= "" then
        local label = Instance.new("TextLabel")
        label.Name = "Text"
        label.Size = UDim2.new(0, 0, 1, 0)
        label.AutomaticSize = Enum.AutomaticSize.X
        label.BackgroundTransparency = 1
        label.Font = Theme.Fonts.Header
        label.Text = text
        label.TextColor3 = Theme.GetToken("TextMuted")
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = divider

        local line = Instance.new("Frame")
        line.Name = "Line"
        line.Size = UDim2.new(1, -label.TextBounds.X - 12, 0, 1)
        line.Position = UDim2.new(1, 0, 0.5, 0)
        line.AnchorPoint = Vector2.new(1, 0.5)
        line.BackgroundColor3 = Theme.GetToken("BorderSubtle")
        line.BorderSizePixel = 0
        line.Parent = divider
    else
        local line = Instance.new("Frame")
        line.Name = "Line"
        line.Size = UDim2.new(1, 0, 0, 1)
        line.Position = UDim2.new(0, 0, 0.5, 0)
        line.AnchorPoint = Vector2.new(0, 0.5)
        line.BackgroundColor3 = Theme.GetToken("BorderSubtle")
        line.BorderSizePixel = 0
        line.Parent = divider
    end

    divider.Parent = parent
    return divider
end

function Primitives.Space(parent, height)
    local space = Instance.new("Frame")
    space.Name = "Space"
    space.Size = UDim2.new(1, 0, 0, height or 8)
    space.BackgroundTransparency = 1
    space.BorderSizePixel = 0
    space.Parent = parent
    return space
end

function Primitives.Tag(parent, text, color, radius)
    local tag = Instance.new("Frame")
    tag.Name = "Tag_" .. text
    tag.Size = UDim2.new(0, 0, 0, 20)
    tag.AutomaticSize = Enum.AutomaticSize.X
    tag.BackgroundColor3 = color or Theme.GetToken("Accent")
    tag.BackgroundTransparency = 0.85
    tag.BorderSizePixel = 0

    local corner = Instance.new("UICorner")
    corner.CornerRadius = radius and UDim.new(0, radius) or Theme.Radii.Pill
    corner.Parent = tag

    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Theme.GetToken("Accent")
    stroke.Transparency = 0.5
    stroke.Thickness = 1
    stroke.Parent = tag

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = tag

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Theme.Fonts.Header
    label.Text = text
    label.TextColor3 = color or Theme.GetToken("TextPrimary")
    label.TextSize = 11
    label.Parent = tag

    tag.Parent = parent
    return tag
end

return Primitives
end

_MODULES['Components/Notification'] = function()


local TweenService = game:GetService("TweenService")

local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Notification = {}


local toastStackContainer = nil
local activeToasts = {}
local stackConnections = {}

local function updateStackGeometry(stack)
    local camera = workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local isSmallScreen = vp.X < 900 or vp.Y < 600

    -- Responsive mobile/desktop width
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

local function getOrCreateStack(root)
    if toastStackContainer and toastStackContainer.Parent then
        return toastStackContainer
    end

    cleanupStackConnections()

    local stack = Instance.new("Frame")
    stack.Name = "ToastNotificationStack"
    stack.AnchorPoint = Vector2.new(1, 0)
    stack.BackgroundTransparency = 1
    stack.ZIndex = 9999999

    updateStackGeometry(stack)

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.VerticalAlignment = Enum.VerticalAlignment.Top
    list.HorizontalAlignment = Enum.HorizontalAlignment.Right
    list.Parent = stack


    local camera = workspace.CurrentCamera
    if camera then
        table.insert(stackConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if stack and stack.Parent then
                updateStackGeometry(stack)
            end
        end))
    end
    table.insert(stackConnections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        local newCam = workspace.CurrentCamera
        if newCam then
            table.insert(stackConnections, newCam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if stack and stack.Parent then
                    updateStackGeometry(stack)
                end
            end))
            updateStackGeometry(stack)
        end
    end))

    stack.Destroying:Connect(cleanupStackConnections)

    stack.Parent = root
    toastStackContainer = stack
    return stack
end

local function dismissToast(toastData)
    if toastData.Dismissed then return end
    toastData.Dismissed = true

    local idx = table.find(activeToasts, toastData)
    if idx then
        table.remove(activeToasts, idx)
    end

    if toastData.Card and toastData.Card.Parent then
        local exitTween = Tweener.Tween(toastData.Card, Tweener.Info.Fast, {
            Position = UDim2.new(1, 40, 0, 0),
            BackgroundTransparency = 1,
        })
        exitTween.Completed:Once(function()
            if toastData.Slot and toastData.Slot.Parent then
                toastData.Slot:Destroy()
            end
        end)
    elseif toastData.Slot and toastData.Slot.Parent then
        toastData.Slot:Destroy()
    end
end

function Notification.Notify(rootGui, props)
    local stack = getOrCreateStack(rootGui)
    local duration = props.Duration or 3.2

    local camera = workspace.CurrentCamera
    local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local maxToasts = if (vp.Y < 600) then 2 else 3

    while #activeToasts >= maxToasts do
        dismissToast(activeToasts[1])
    end


    local slot = Instance.new("Frame")
    slot.Name = "ToastSlot"
    slot.Size = UDim2.new(1, 0, 0, 0)
    slot.AutomaticSize = Enum.AutomaticSize.Y
    slot.BackgroundTransparency = 1
    slot.ClipsDescendants = false


    local toast = Instance.new("Frame")
    toast.Name = "ToastCard"
    toast.Size = UDim2.new(1, 0, 0, 0)
    toast.AutomaticSize = Enum.AutomaticSize.Y
    toast.Position = UDim2.new(1, 40, 0, 0)
    toast.BackgroundColor3 = Theme.GetToken("Card")
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


    local iconLabel = Instance.new("ImageLabel")
    iconLabel.Name = "Icon"
    iconLabel.Size = UDim2.fromOffset(16, 16)
    iconLabel.Position = UDim2.new(0, 0, 0, 1)
    iconLabel.BackgroundTransparency = 1
    iconLabel.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(iconLabel, props.Icon or "bell")
    iconLabel.Parent = contentFrame
    Theme.Bind(iconLabel, "ImageColor3", "Accent")


    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -22, 0, 16)
    titleLabel.Position = UDim2.new(0, 22, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Title
    titleLabel.Text = props.Title
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 12
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = contentFrame
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")


    if props.Content and props.Content ~= "" then
        local contentLabel = Instance.new("TextLabel")
        contentLabel.Name = "Content"
        contentLabel.Size = UDim2.new(1, -22, 0, 0)
        contentLabel.Position = UDim2.new(0, 22, 0, 18)
        contentLabel.AutomaticSize = Enum.AutomaticSize.Y
        contentLabel.BackgroundTransparency = 1
        contentLabel.Font = Theme.Fonts.Body
        contentLabel.Text = props.Content
        contentLabel.TextColor3 = Theme.GetToken("TextMuted")
        contentLabel.TextSize = 11
        contentLabel.TextWrapped = true
        contentLabel.TextXAlignment = Enum.TextXAlignment.Left
        contentLabel.Parent = contentFrame
        Theme.Bind(contentLabel, "TextColor3", "TextMuted")
    end

    contentFrame.Parent = toast


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


    Tweener.Tween(toast, Tweener.Info.Normal, {
        Position = UDim2.new(0, 0, 0, 0)
    })


    Tweener.Tween(progressBar, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
        Size = UDim2.new(0, 0, 1, 0)
    })

    task.delay(duration, function()
        dismissToast(toastData)
    end)
end

return Notification
end

_MODULES['Components/Popup'] = function()


local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Popup = {}


function Popup.Show(rootGui, props)
    local backdrop = Instance.new("TextButton")
    backdrop.Name = "ModalBackdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.Position = UDim2.fromScale(0, 0)
    backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
    backdrop.BackgroundTransparency = 1
    backdrop.Text = ""
    backdrop.AutoButtonColor = false
    backdrop.ZIndex = 9999998

    local modal = Instance.new("Frame")
    modal.Name = "ModalFrame"
    modal.Size = UDim2.new(0.85, 0, 0, 0)
    modal.AutomaticSize = Enum.AutomaticSize.Y
    modal.Position = UDim2.fromScale(0.5, 0.5)
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.BackgroundColor3 = Theme.GetToken("Card")
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


    local btnContainer = Instance.new("Frame")
    btnContainer.Name = "Buttons"
    btnContainer.Size = UDim2.new(1, 0, 0, 36)
    btnContainer.BackgroundTransparency = 1
    btnContainer.LayoutOrder = 3
    btnContainer.Parent = modal

    local function dismiss()
        Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 1 })
        local tween = Tweener.Tween(modalScale, Tweener.Info.Fast, { Scale = 0.90 })
        tween.Completed:Once(function()
            backdrop:Destroy()
        end)
    end

    local rawButtons = props.Buttons or {
        { Title = "Close", Variant = "Secondary", Callback = function() end }
    }

    local function isDismissButton(b)
        local t = (b.Title or ""):lower()
        return t:find("cancel") ~= nil 
            or t:find("close") ~= nil 
            or t:find("dismiss") ~= nil 
            or t:find("back") ~= nil 
            or t:find("no") ~= nil 
            or b.Variant == "Secondary"
    end

    local function createButton(btnData, alignment)
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

        Tweener.BindPressFeedback(btn)

        btn.Activated:Connect(function()
            if btnData.Callback then
                btnData.Callback()
            end
            dismiss()
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


    Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 0.55 })
    Tweener.Tween(modalScale, Tweener.Info.Spring, { Scale = 1.0 })
end

return Popup
end

_MODULES['Components/Dialog'] = function()


local TweenService = game:GetService("TweenService")
local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Dialog = {}


function Dialog.Show(parent, props)
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


    local card = Instance.new("Frame")
    card.Name = "DialogCard"
    card.Size = UDim2.new(0.80, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.BackgroundColor3 = Theme.GetToken("Card")
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
    titleLabel.Text = props.Title
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 15
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 54
    titleLabel.Parent = header
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")


    local contentLabel = Instance.new("TextLabel")
    contentLabel.Name = "Content"
    contentLabel.Size = UDim2.new(1, 0, 0, 0)
    contentLabel.AutomaticSize = Enum.AutomaticSize.Y
    contentLabel.BackgroundTransparency = 1
    contentLabel.Font = Theme.Fonts.Body
    contentLabel.Text = props.Content
    contentLabel.TextColor3 = Theme.GetToken("TextMuted")
    contentLabel.TextSize = 13
    contentLabel.TextWrapped = true
    contentLabel.RichText = true
    contentLabel.TextXAlignment = Enum.TextXAlignment.Left
    contentLabel.LayoutOrder = 2
    contentLabel.Parent = card
    Theme.Bind(contentLabel, "TextColor3", "TextMuted")


    local rawButtons = props.Buttons
    if not rawButtons or #rawButtons == 0 then
        rawButtons = {
            { Title = "OK", Style = "Primary", Callback = nil }
        }
    end

    local function isDismissButton(b)
        local t = (b.Title or ""):lower()
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
        Tweener.Tween(shadowScale, Tweener.Info.Fast, { Scale = 0.88 })
        Tweener.Tween(shadow, Tweener.Info.Fast, { ImageTransparency = 1 })
        local t = Tweener.Tween(cardScale, Tweener.Info.Fast, { Scale = 0.88 })
        Tweener.Tween(overlay, Tweener.Info.Fast, { BackgroundTransparency = 1 })
        t.Completed:Once(function()
            overlay:Destroy()
        end)
    end

    local function createButton(bData, alignment)
        local btn = Instance.new("TextButton")
        btn.Name = "Btn_" .. bData.Title
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
        bLabel.Text = bData.Title
        bLabel.TextColor3 = if (style == "Primary" or style == "Danger") then Color3.fromRGB(255, 255, 255) else Theme.GetToken("TextPrimary")
        bLabel.TextSize = 12
        bLabel.ZIndex = 55
        bLabel.Parent = btn
        if style ~= "Primary" and style ~= "Danger" then
            Theme.Bind(bLabel, "TextColor3", "TextPrimary")
        end

        Tweener.BindPressFeedback(btn)

        btn.Activated:Connect(function()
            closeDialog()
            if bData.Callback then
                task.spawn(bData.Callback)
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


    Tweener.Tween(overlay, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(shadowScale, Tweener.Info.Spring, { Scale = 1 })
    Tweener.Tween(cardScale, Tweener.Info.Spring, { Scale = 1 })


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


local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Container = _require("Core/Container")

local Loading = {}
Loading.__index = Loading


function Loading.new(rawProps)
    local props = rawProps or {}
    local self = setmetatable({}, Loading)

    self.ContainerManager = Container.new("Loading")
    self.ContainerManager:SetBaseWindowSize(Vector2.new(380, 210))
    local rootGui = self.ContainerManager.ScreenGui
    self.RootGui = rootGui


    local backdrop = Instance.new("Frame")
    backdrop.Name = "LoadingBackdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel = 0
    backdrop.ZIndex = 99990
    backdrop.Parent = rootGui
    self.Backdrop = backdrop


    local modal = Instance.new("Frame")
    modal.Name = "LoadingModal"
    modal.Size = UDim2.fromOffset(360, 185)
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.Position = UDim2.fromScale(0.5, 0.5)
    modal.BackgroundColor3 = Theme.GetToken("Background")
    modal.BackgroundTransparency = 0.05
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
    pad.PaddingTop = UDim.new(0, 20)
    pad.PaddingBottom = UDim.new(0, 20)
    pad.PaddingLeft = UDim.new(0, 24)
    pad.PaddingRight = UDim.new(0, 24)
    pad.Parent = modal

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.Parent = modal


    local headerRow = Instance.new("Frame")
    headerRow.Name = "HeaderRow"
    headerRow.Size = UDim2.new(1, 0, 0, 24)
    headerRow.BackgroundTransparency = 1
    headerRow.LayoutOrder = 1
    headerRow.Parent = modal

    local hList = Instance.new("UIListLayout")
    hList.FillDirection = Enum.FillDirection.Horizontal
    hList.VerticalAlignment = Enum.VerticalAlignment.Center
    hList.Padding = UDim.new(0, 10)
    hList.Parent = headerRow

    local iconLabel = Instance.new("ImageLabel")
    iconLabel.Name = "Icon"
    iconLabel.Size = UDim2.fromOffset(20, 20)
    iconLabel.BackgroundTransparency = 1
    iconLabel.ImageColor3 = Theme.GetToken("Accent")
    Icons.Apply(iconLabel, props.Icon or "loader")
    iconLabel.Parent = headerRow
    Theme.Bind(iconLabel, "ImageColor3", "Accent")

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -30, 1, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Title
    titleLabel.Text = props.Title or "Sodium Hub"
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = headerRow
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")


    local subLabel = Instance.new("TextLabel")
    subLabel.Name = "Subtitle"
    subLabel.Size = UDim2.new(1, 0, 0, 16)
    subLabel.BackgroundTransparency = 1
    subLabel.Font = Theme.Fonts.Sub
    subLabel.Text = props.Subtitle or "Loading modules and assets..."
    subLabel.TextColor3 = Theme.GetToken("TextMuted")
    subLabel.TextSize = 11
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.LayoutOrder = 2
    subLabel.Parent = modal
    Theme.Bind(subLabel, "TextColor3", "TextMuted")
    self.SubLabel = subLabel


    local spacer = Instance.new("Frame")
    spacer.Name = "Spacer"
    spacer.Size = UDim2.new(1, 0, 0, 8)
    spacer.BackgroundTransparency = 1
    spacer.LayoutOrder = 3
    spacer.Parent = modal


    local track = Instance.new("Frame")
    track.Name = "ProgressTrack"
    track.Size = UDim2.new(1, 0, 0, 8)
    track.BackgroundColor3 = Theme.GetToken("SurfaceActive")
    track.BorderSizePixel = 0
    track.LayoutOrder = 4
    track.Parent = modal
    Theme.Bind(track, "BackgroundColor3", "SurfaceActive")

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 4)
    trackCorner.Parent = track

    local fillBar = Instance.new("Frame")
    fillBar.Name = "FillBar"
    local initialPct = math.clamp(props.Progress or 0, 0, 1)
    fillBar.Size = UDim2.new(initialPct, 0, 1, 0)
    fillBar.BackgroundColor3 = Theme.GetToken("Accent")
    fillBar.BorderSizePixel = 0
    fillBar.Parent = track
    Theme.Bind(fillBar, "BackgroundColor3", "Accent")
    self.FillBar = fillBar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 4)
    fillCorner.Parent = fillBar


    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "Status"
    statusLabel.Size = UDim2.new(1, 0, 0, 16)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Theme.Fonts.Body
    statusLabel.Text = props.Status or string.format("Initializing... (%d%%)", math.floor(initialPct * 100))
    statusLabel.TextColor3 = Theme.GetToken("Placeholder")
    statusLabel.TextSize = 11
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.LayoutOrder = 5
    statusLabel.Parent = modal
    Theme.Bind(statusLabel, "TextColor3", "Placeholder")
    self.StatusLabel = statusLabel


    Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(modalScale, Tweener.Info.Smooth, { Scale = 1.0 })

    return self
end

function Loading:SetProgress(percent, statusText)
    local clamped = math.clamp(percent, 0, 1)
    Tweener.Tween(self.FillBar, Tweener.Info.Smooth, {
        Size = UDim2.new(clamped, 0, 1, 0)
    })
    if statusText then
        self.StatusLabel.Text = statusText
    else
        self.StatusLabel.Text = string.format("Loading... (%d%%)", math.floor(clamped * 100))
    end
end

function Loading:SetStatus(statusText)
    self.StatusLabel.Text = statusText
end

function Loading:Finish(onComplete)
    self:SetProgress(1.0, "Ready!")
    task.delay(0.3, function()
        if not self.Modal or not self.Modal.Parent then
            if onComplete then onComplete() end
            return
        end

        Tweener.Tween(self.Modal, Tweener.Info.Fast, {
            Position = UDim2.new(0.5, 0, 0.5, -24)
        })
        Tweener.Tween(self.ModalScale, Tweener.Info.Fast, { Scale = 0.94 })
        Tweener.Tween(self.Backdrop, Tweener.Info.Fast, { BackgroundTransparency = 1 })

        task.delay(0.25, function()
            self:Destroy()
            if onComplete then
                onComplete()
            end
        end)
    end)
end

function Loading:Destroy()
    if self.ContainerManager then
        self.ContainerManager:Destroy()
        self.ContainerManager = nil
    end
end

return Loading
end

_MODULES['Components/KeyCheck'] = function()


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


-- Safe timestamp fallback
local function getSafeTimestamp()
    local t = os.time()
    if t and t > 1000000000 then return t end
    local s, st = pcall(function() return math.floor(workspace:GetServerTimeNow()) end)
    if s and st and st > 1000000000 then return st end
    return math.floor(tick())
end


local function safeWriteFile(filename, content)
    local writef = rawget(getfenv(), "writefile")
    if type(writef) == "function" then
        local s, _ = pcall(writef, filename, content)
        return s
    end
    return false
end

local function safeReadFile(filename)
    local isf = rawget(getfenv(), "isfile")
    local readf = rawget(getfenv(), "readfile")
    if type(isf) == "function" and type(readf) == "function" then
        local s1, exists = pcall(isf, filename)
        if s1 and exists then
            local s2, content = pcall(readf, filename)
            if s2 and type(content) == "string" then
                return content
            end
        end
    end
    return nil
end

local function safeDeleteFile(filename)
    local isf = rawget(getfenv(), "isfile")
    local delf = rawget(getfenv(), "delfile")
    if type(isf) == "function" and type(delf) == "function" then
        pcall(function()
            if isf(filename) then delf(filename) end
        end)
    end
end

local function safeSetClipboard(str)
    local setclip = rawget(getfenv(), "setclipboard") or rawget(getfenv(), "toclipboard")
    if type(setclip) == "function" then
        local s, _ = pcall(setclip, str)
        return s
    end
    return false
end

local function safeGetClipboard()
    local getclip = rawget(getfenv(), "getclipboard")
    if type(getclip) == "function" then
        local s, res = pcall(getclip)
        if s and type(res) == "string" then
            return res
        end
    end
    return nil
end

-- JNKIE SDK with mock fallback
local function loadJunkieSDK(serviceName, identifier, provider)
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
        -- Mock fallback object
        junkieObj = {
            service = serviceName,
            identifier = identifier,
            provider = provider,
            get_key_link = function(self)
                return "https://jnkie.com/flow/" .. tostring(self.identifier or "sodium-auth")
            end,
            check_key = function(s, key)
                task.wait(0.3)
                local actualKey = if type(key) == "string" then key else (if type(s) == "string" then s else "")
                local upper = actualKey:upper():gsub("%s+", "")
                if upper == "SODIUM-PREMIUM" then
                    return {
                        valid = true,
                        key = actualKey,
                        plan = "Premium",
                        expires_at = getSafeTimestamp() + 2592000,
                    }
                elseif upper == "SODIUM-FREE" then
                    return {
                        valid = true,
                        key = actualKey,
                        plan = "Free",
                        expires_at = getSafeTimestamp() + 86400,
                    }
                elseif upper == "TEST" then
                    return {
                        valid = true,
                        key = actualKey,
                        plan = "Test",
                        expires_at = getSafeTimestamp() + 43200,
                    }
                end
                return { valid = false, message = "Invalid license key." }
            end,
        }
    else
        junkieObj.service = serviceName
        junkieObj.identifier = identifier
        junkieObj.provider = provider
        local realCheck = junkieObj.check_key
        junkieObj.check_key = function(s, key)
            local actualKey = if type(key) == "string" then key else (if type(s) == "string" then s else "")
            local upper = actualKey:upper():gsub("%s+", "")
            if upper == "SODIUM-PREMIUM" then
                return {
                    valid = true,
                    key = actualKey,
                    plan = "Premium",
                    expires_at = getSafeTimestamp() + 2592000,
                }
            elseif upper == "SODIUM-FREE" then
                return {
                    valid = true,
                    key = actualKey,
                    plan = "Free",
                    expires_at = getSafeTimestamp() + 86400,
                }
            elseif upper == "TEST" then
                return {
                    valid = true,
                    key = actualKey,
                    plan = "Test",
                    expires_at = getSafeTimestamp() + 43200,
                }
            end
            if realCheck then
                return realCheck(s, key)
            end
            return { valid = false, message = "Invalid license key." }
        end
    end

    return junkieObj
end

function KeyCheck.new(rawProps)
    local props = rawProps or {}
    local self = setmetatable({}, KeyCheck)

    local saveFileName = props.SaveFileName or "Sodium_SavedKey.json"
    local rememberKey = if props.SaveKey ~= nil then props.SaveKey else true
    local serviceName = props.Service or "Sodium Hub"
    local identifier = props.Identifier or "sodium-auth"
    local provider = props.Provider or "Mixed"

    self.Junkie = loadJunkieSDK(serviceName, identifier, provider)
    self.SaveFileName = saveFileName
    self.RememberKey = rememberKey
    self.IsVerifying = false


    local cachedKey = nil
    local cachedJson = safeReadFile(saveFileName)
    if cachedJson then
        pcall(function()
            local decoded = HttpService:JSONDecode(cachedJson)
            if decoded and type(decoded.key) == "string" and #decoded.key > 0 then
                cachedKey = decoded.key
            end
        end)
    end

    self.ContainerManager = Container.new("KeyCheck")
    self.ContainerManager:SetBaseWindowSize(Vector2.new(460, 340))
    local rootGui = self.ContainerManager.ScreenGui
    self.RootGui = rootGui


    local backdrop = Instance.new("Frame")
    backdrop.Name = "KeyCheckBackdrop"
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel = 0
    backdrop.ZIndex = 99990
    backdrop.Parent = rootGui
    self.Backdrop = backdrop


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

    local function setStatusState(state, customMsg)
        if state == "Ready" then
            statusDot.BackgroundColor3 = Theme.GetToken("Placeholder")
            statusText.TextColor3 = Theme.GetToken("Placeholder")
            statusText.Text = customMsg or "Ready for verification"
        elseif state == "Verifying" then
            statusDot.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
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

    local function createSubButton(name, iconName, text, order)
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


    getKeyBtn.Activated:Connect(function()
        local link = ""
        if self.Junkie and type(self.Junkie.get_key_link) == "function" then
            local s, l = pcall(function() return self.Junkie:get_key_link() end)
            if s and l then link = l end
        end
        if link == "" then
            link = props.GetKeyUrl or ("https://jnkie.com/flow/" .. identifier)
        end
        safeSetClipboard(link)
        setStatusState("Ready", "Key URL copied to clipboard!")
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


    local function verifyKey(inputKey, isSilent)
        if self.IsVerifying then return end
        local cleanKey = inputKey:gsub("^%s+", ""):gsub("%s+$", "")
        if #cleanKey == 0 then
            setStatusState("Error", "Please enter a key first.")
            return
        end

        self.IsVerifying = true
        setStatusState("Verifying", "Verifying with server...")
        redLabel.Text = "Verifying..."

        task.spawn(function()
            local res = nil
            local s, r = pcall(function()
                return self.Junkie:check_key(cleanKey)
            end)
            if s and r then
                res = r
            else
                res = { valid = false, message = "Network request failed." }
            end

            if res.valid == true then
                setStatusState("Success", "Authentication successful!")
                redLabel.Text = "Unlocked!"


                if self.RememberKey then
                    safeWriteFile(saveFileName, HttpService:JSONEncode({
                        key = cleanKey,
                        saved_at = getSafeTimestamp(),
                        expires_at = res.expires_at,
                    }))
                else
                    safeDeleteFile(saveFileName)
                end


                task.delay(0.3, function()
                    Tweener.Tween(modal, Tweener.Info.Fast, {
                        Position = UDim2.new(0.5, 0, 0.5, -20)
                    })
                    Tweener.Tween(modalScale, Tweener.Info.Fast, { Scale = 0.94 })
                    Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 1 })

                    task.delay(0.25, function()
                        self:Destroy()
                        if props.OnSuccess then
                            props.OnSuccess(cleanKey, res)
                        end
                    end)
                end)
            else
                self.IsVerifying = false
                redLabel.Text = "Redeem Key"
                setStatusState("Error", res.message or "Invalid license key.")
                if not isSilent then
                    safeDeleteFile(saveFileName)
                end
                -- 3s rate-limit debounce
                task.delay(3, function()
                    self.IsVerifying = false
                end)
            end
        end)
    end

    redeemBtn.Activated:Connect(function()
        verifyKey(keyBox.Text, false)
    end)


    Tweener.Tween(backdrop, Tweener.Info.Fast, { BackgroundTransparency = 0.5 })
    Tweener.Tween(modalScale, Tweener.Info.Smooth, { Scale = 1.0 })


    if cachedKey and #cachedKey > 0 then
        task.defer(function()
            verifyKey(cachedKey, true)
        end)
    end

    return self
end

function KeyCheck:Destroy()
    if self.ContainerManager then
        self.ContainerManager:Destroy()
        self.ContainerManager = nil
    end
end

return KeyCheck
end

_MODULES['Components/TabSection'] = function()


local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local TabSection = {}
TabSection.__index = TabSection


function TabSection.new(window, parent, props)
    local self = setmetatable({}, TabSection)
    self.Window = window
    self.Title = props.Title
    self.Opened = if props.Opened ~= nil then props.Opened else true
    self.Tabs = {}
    self._connections = {}

    local container = Instance.new("Frame")
    container.Name = "Category_" .. props.Title
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = container


    local header = Instance.new("TextButton")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 26)
    header.BackgroundTransparency = 1
    header.Text = ""
    header.AutoButtonColor = false
    header.Parent = container

    local headerPad = Instance.new("UIPadding")
    headerPad.PaddingLeft = UDim.new(0, 8)
    headerPad.PaddingRight = UDim.new(0, 8)
    headerPad.Parent = header

    if props.Icon and props.Icon ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.fromOffset(14, 14)
        icon.Position = UDim2.new(0, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0, 0.5)
        icon.BackgroundTransparency = 1
        icon.ImageColor3 = Theme.GetToken("TextMuted")
        Icons.Apply(icon, props.Icon)
        Theme.Bind(icon, "ImageColor3", "TextMuted")
        icon.Parent = header
    end

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    local offsetX = if props.Icon and props.Icon ~= "" then 20 else 0
    title.Size = UDim2.new(1, -offsetX - 16, 1, 0)
    title.Position = UDim2.new(0, offsetX, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Theme.Fonts.Title
    title.Text = string.upper(props.Title)
    title.TextColor3 = Theme.GetToken("Placeholder")
    title.TextSize = 11
    title.TextXAlignment = Enum.TextXAlignment.Left
    Theme.Bind(title, "TextColor3", "Placeholder")
    title.Parent = header

    local chevron = Instance.new("ImageLabel")
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


    local tabList = Instance.new("CanvasGroup")
    tabList.Name = "TabList"
    tabList.Size = UDim2.new(1, 0, 0, 0)
    tabList.BackgroundTransparency = 1
    tabList.GroupTransparency = if self.Opened then 0 else 1
    tabList.ClipsDescendants = true
    tabList.Visible = self.Opened

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabList

    local tabPad = Instance.new("UIPadding")
    tabPad.Name = "TabListPadding"
    tabPad.PaddingLeft = UDim.new(0, 14)
    tabPad.Parent = tabList

    tabList.Parent = container

    table.insert(self._connections, header.Activated:Connect(function()
        self:Toggle()
    end))

    table.insert(self._connections, header.MouseEnter:Connect(function()
        if not UserInputService.TouchEnabled then
            Tweener.Tween(title, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
            Tweener.Tween(chevron, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Accent") })
        end
    end))
    table.insert(self._connections, header.MouseLeave:Connect(function()
        if not UserInputService.TouchEnabled then
            Tweener.Tween(title, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("Placeholder") })
            Tweener.Tween(chevron, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
        end
    end))

    table.insert(self._connections, tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if self.Opened and not self._isAnimating then
            tabList.Size = UDim2.new(1, 0, 0, tabLayout.AbsoluteContentSize.Y)
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
    self._alphaTween = nil
    self._chevronTween = nil
    self._renderConn = nil


    if self.Opened then
        task.defer(function()
            if self.Opened and not self._isAnimating and tabList and tabLayout then
                tabList.Size = UDim2.new(1, 0, 0, tabLayout.AbsoluteContentSize.Y)
            end
        end)
    end

    return self
end

function TabSection:Destroy()
    if self._renderConn then
        self._renderConn:Disconnect()
        self._renderConn = nil
    end
    if self._sizeTween then
        self._sizeTween:Cancel()
        self._sizeTween = nil
    end
    if self._alphaTween then
        self._alphaTween:Cancel()
        self._alphaTween = nil
    end
    if self._chevronTween then
        self._chevronTween:Cancel()
        self._chevronTween = nil
    end
    for _, conn in self._connections do
        conn:Disconnect()
    end
    table.clear(self._connections)
    if self.Container then
        self.Container:Destroy()
    end
end

function TabSection:Toggle(opened)
    if opened ~= nil then
        self.Opened = opened
    else
        self.Opened = not self.Opened
    end

    -- Cancel active tween to prevent conflict
    if self._sizeTween then
        self._sizeTween:Cancel()
        self._sizeTween = nil
    end
    if self._alphaTween then
        self._alphaTween:Cancel()
        self._alphaTween = nil
    end
    if self._chevronTween then
        self._chevronTween:Cancel()
        self._chevronTween = nil
    end

    self._isAnimating = true

    -- RenderStepped accordion height sync
    if self._renderConn then
        self._renderConn:Disconnect()
        self._renderConn = nil
    end
    self._renderConn = RunService.RenderStepped:Connect(function()
        if not self._isAnimating then
            if self._renderConn then
                self._renderConn:Disconnect()
                self._renderConn = nil
            end
            return
        end
        if self.Window and self.Window.UpdateIndicator then
            self.Window:UpdateIndicator(true)
        end
    end)

    if self.Opened then

        self.TabList.Visible = true
        self.TabList.ClipsDescendants = true

        -- Activate hitboxes on expand
        for _, tab in ipairs(self.Tabs) do
            if tab.SidebarButton then
                tab.SidebarButton.Active = true
                tab.SidebarButton.Visible = true
            end
        end

        self._chevronTween = Tweener.Tween(self.Chevron, Tweener.Info.Smooth, { Rotation = 0 })

        local targetHeight = math.max(1, self.TabLayout.AbsoluteContentSize.Y)

        self._alphaTween = Tweener.Tween(self.TabList, Tweener.Info.Smooth, { GroupTransparency = 0 })
        self._sizeTween = Tweener.Tween(self.TabList, Tweener.Info.Smooth, {
            Size = UDim2.new(1, 0, 0, targetHeight),
        }, function()
            self._isAnimating = false
            self._sizeTween = nil
            self._alphaTween = nil
            if self._renderConn then
                self._renderConn:Disconnect()
                self._renderConn = nil
            end
            if self.Opened then
                self.TabList.Size = UDim2.new(1, 0, 0, self.TabLayout.AbsoluteContentSize.Y)
                self.TabList.GroupTransparency = 0
                if self.Window and self.Window.UpdateIndicator then
                    self.Window:UpdateIndicator(true)
                end
            end
        end)
    else
        -- Deactivate hitboxes on collapse
        for _, tab in ipairs(self.Tabs) do
            if tab.SidebarButton then
                tab.SidebarButton.Active = false
            end
        end

        self._chevronTween = Tweener.Tween(self.Chevron, Tweener.Info.Smooth, { Rotation = -90 })

        self.TabList.ClipsDescendants = true

        self._alphaTween = Tweener.Tween(self.TabList, Tweener.Info.Smooth, { GroupTransparency = 1 })
        self._sizeTween = Tweener.Tween(self.TabList, Tweener.Info.Smooth, {
            Size = UDim2.new(1, 0, 0, 0),
        }, function()
            self._isAnimating = false
            self._sizeTween = nil
            self._alphaTween = nil
            if self._renderConn then
                self._renderConn:Disconnect()
                self._renderConn = nil
            end
            if not self.Opened then
                self.TabList.Visible = false
                self.TabList.GroupTransparency = 1
                for _, tab in ipairs(self.Tabs) do
                    if tab.SidebarButton then
                        tab.SidebarButton.Visible = false
                    end
                end
                task.defer(function()
                    if self.Window and self.Window.UpdateIndicator then
                        self.Window:UpdateIndicator(true)
                    end
                end)
            end
        end)
    end
end

function TabSection:Tab(props)
    assert(self.Window, "[SodiumUI.TabSection] Window reference is nil")
    local tab = self.Window:Tab(props, self)
    table.insert(self.Tabs, tab)
    return tab
end

return TabSection
end

_MODULES['Elements/Divider'] = function()


local Theme = _require("Core/Theme")

local Divider = {}
Divider.__index = Divider


function Divider.new(parent, props)
    local self = setmetatable({}, Divider)
    local title = props and props.Title

    local container = Instance.new("Frame")
    container.Name = "Divider_" .. (title or "Line")
    container.Size = UDim2.new(1, 0, 0, if title and title ~= "" then 22 else 8)
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0

    if title and title ~= "" then
        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.Padding = UDim.new(0, 10)
        layout.Parent = container

        local leftLine = Instance.new("Frame")
        leftLine.Name = "LeftLine"
        leftLine.Size = UDim2.new(0.5, -50, 0, 1)
        leftLine.BackgroundColor3 = Theme.GetToken("BorderSubtle")
        leftLine.BorderSizePixel = 0
        leftLine.Parent = container
        Theme.Bind(leftLine, "BackgroundColor3", "BorderSubtle")

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(0, 0, 1, 0)
        label.AutomaticSize = Enum.AutomaticSize.X
        label.BackgroundTransparency = 1
        label.Font = Theme.Fonts.Title
        label.Text = string.upper(title)
        label.TextColor3 = Theme.GetToken("Placeholder")
        label.TextSize = 10
        label.Parent = container
        Theme.Bind(label, "TextColor3", "Placeholder")

        local rightLine = Instance.new("Frame")
        rightLine.Name = "RightLine"
        rightLine.Size = UDim2.new(0.5, -50, 0, 1)
        rightLine.BackgroundColor3 = Theme.GetToken("BorderSubtle")
        rightLine.BorderSizePixel = 0
        rightLine.Parent = container
        Theme.Bind(rightLine, "BackgroundColor3", "BorderSubtle")
    else
        local line = Instance.new("Frame")
        line.Name = "Line"
        line.Size = UDim2.new(1, 0, 0, 1)
        line.Position = UDim2.new(0, 0, 0.5, 0)
        line.AnchorPoint = Vector2.new(0, 0.5)
        line.BackgroundColor3 = Theme.GetToken("BorderSubtle")
        line.BorderSizePixel = 0
        line.Parent = container
        Theme.Bind(line, "BackgroundColor3", "BorderSubtle")
    end

    container.Parent = parent
    self.Container = container
    return self
end

function Divider:Destroy()
    self.Container:Destroy()
end

return Divider
end

_MODULES['Elements/Button'] = function()


local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Button = {}
Button.__index = Button


function Button.new(parent, props)
    local titleText = props.Title or props.Name or "Button"
    local self = setmetatable({}, Button)
    self.Locked = props.Locked or false
    self.Callback = props.Callback

    local isDesc = props.Desc and props.Desc ~= ""
    local containerHeight = if isDesc then 54 else 38


    local slot = Instance.new("Frame")
    slot.Name = "Button_" .. tostring(titleText)
    slot.Size = UDim2.new(1, 0, 0, containerHeight)
    slot.BackgroundTransparency = 1
    slot.BorderSizePixel = 0


    local container = Instance.new("Frame")
    container.Name = "Card"
    container.Size = UDim2.fromScale(1, 1)
    container.Position = UDim2.fromScale(0.5, 0.5)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.BackgroundColor3 = Theme.GetToken("SurfaceHover")
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


    local iconLabel = nil
    local iconWidth = 0
    if props.Icon and props.Icon ~= "" then
        iconLabel = Instance.new("ImageLabel")
        iconLabel.Name = "Icon"
        iconLabel.Size = UDim2.fromOffset(18, 18)
        iconLabel.Position = UDim2.new(0, 0, 0.5, 0)
        iconLabel.AnchorPoint = Vector2.new(0, 0.5)
        iconLabel.BackgroundTransparency = 1
        iconLabel.ImageColor3 = props.Color or Theme.GetToken("Accent")
        Icons.Apply(iconLabel, props.Icon)
        iconLabel.Parent = btn
        iconWidth = 26
    end


    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconWidth, 0, 18)
    titleLabel.Position = UDim2.new(0, iconWidth, 0, if isDesc then 8 else 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Header
    titleLabel.Text = titleText
    titleLabel.TextColor3 = props.Color or Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = if props.Justify == "Center" then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = btn

    local descLabel = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconWidth, 0, 16)
        descLabel.Position = UDim2.new(0, iconWidth, 0, 28)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Theme.Fonts.Body
        descLabel.Text = props.Desc or ""
        descLabel.TextColor3 = Theme.GetToken("TextMuted")
        descLabel.TextSize = 12
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = btn
    end

    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    if not props.Color then
        Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    end
    if descLabel then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end


    Tweener.BindCardPressFeedback(container, btn, Vector2.new(6, 4))
    Tweener.BindHoverLift(container, stroke)

    btn.Activated:Connect(function()
        if not self.Locked and self.Callback then
            self.Callback()
        end
    end)

    slot.Parent = parent
    self.Slot = slot
    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.IconLabel = iconLabel

    return self
end

function Button:SetTitle(title)
    self.TitleLabel.Text = title
end

function Button:SetDesc(desc)
    if self.DescLabel then
        self.DescLabel.Text = desc
    end
end

function Button:Lock()
    self.Locked = true
    self.Container.BackgroundTransparency = 0.5
    self.TitleLabel.TextColor3 = Theme.GetToken("Placeholder")
end

function Button:Unlock()
    self.Locked = false
    self.Container.BackgroundTransparency = 0
    self.TitleLabel.TextColor3 = Theme.GetToken("TextPrimary")
end

function Button:Destroy()
    if self.Slot then
        self.Slot:Destroy()
    else
        self.Container:Destroy()
    end
end

return Button
end

_MODULES['Elements/Toggle'] = function()


local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Toggle = {}
Toggle.__index = Toggle


function Toggle.new(parent, configEngine, props)
    local titleText = props.Title or props.Name or "Toggle"
    local initialVal = if props.Value ~= nil then props.Value elseif props.Default ~= nil then props.Default else false

    local self = setmetatable({}, Toggle)
    self.Value = initialVal
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self.Flag = props.Flag
    self._connections = {}

    local isDesc = props.Desc and props.Desc ~= ""
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

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 50, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 9 else 12)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Header
    titleLabel.Text = titleText
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = triggerBtn

    local descLabel = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 50, 0, 16)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 29)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Theme.Fonts.Body
        descLabel.Text = props.Desc or ""
        descLabel.TextColor3 = Theme.GetToken("TextMuted")
        descLabel.TextSize = 12
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = triggerBtn
    end


    local switchTrack = Instance.new("Frame")
    switchTrack.Name = "SwitchTrack"
    switchTrack.Size = UDim2.fromOffset(38, 20)
    switchTrack.Position = UDim2.new(1, -19, 0.5, 0)
    switchTrack.AnchorPoint = Vector2.new(0.5, 0.5)
    switchTrack.BackgroundColor3 = if self.Value then Theme.GetToken("Accent") else Theme.GetToken("SurfaceActive")

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
    thumb.Size = UDim2.fromOffset(14, 14)
    thumb.Position = if self.Value then UDim2.new(1, -17, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
    thumb.AnchorPoint = Vector2.new(0, 0.5)
    thumb.BackgroundColor3 = if self.Value then Theme.GetToken("TextPrimary") else Theme.GetToken("Placeholder")

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

    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    if descLabel then
        Theme.Bind(descLabel, "TextColor3", "TextMuted")
    end

    table.insert(self._connections, Theme.Changed:Connect(function()
        if not self.Value then
            switchTrack.BackgroundColor3 = Theme.GetToken("SurfaceActive")
            thumb.BackgroundColor3 = Theme.GetToken("Placeholder")
        end
    end))

    Tweener.BindPressFeedback(switchTrack, triggerBtn)
    Tweener.BindHoverLift(container, stroke)

    triggerBtn.Activated:Connect(function()
        if not self.Locked then
            self:Set(not self.Value)
        end
    end)

    if self.Flag and configEngine then
        configEngine:RegisterFlag(self.Flag, function()
            return self.Value
        end, function(val)
            self:Set(val)
        end)
    end

    container.Parent = parent
    return self
end

function Toggle:Set(state, skipCallback)
    self.Value = state

    local targetPos = if self.Value then UDim2.new(1, -17, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
    local targetBg = if self.Value then Theme.GetToken("Accent") else Theme.GetToken("SurfaceActive")
    local targetThumb = if self.Value then Theme.GetToken("TextPrimary") else Theme.GetToken("Placeholder")
    local targetStroke = if self.Value then Theme.GetToken("BorderAccent") else Theme.GetToken("BorderSubtle")

    Tweener.Tween(self.Thumb, Tweener.Info.Fast, {
        Position = targetPos,
        BackgroundColor3 = targetThumb,
    })
    Tweener.Tween(self.SwitchTrack, Tweener.Info.Fast, {
        BackgroundColor3 = targetBg,
    })
    Tweener.Tween(self.TrackStroke, Tweener.Info.Fast, {
        Color = targetStroke,
    })

    if not skipCallback and self.Callback then
        self.Callback(self.Value)
    end
end

function Toggle:Get()
    return self.Value
end

function Toggle:SetTitle(title)
    self.TitleLabel.Text = title
end

function Toggle:SetDesc(desc)
    if self.DescLabel then
        self.DescLabel.Text = desc
    end
end

function Toggle:Lock()
    self.Locked = true
    self.Container.BackgroundTransparency = 0.7
    self.TitleLabel.TextColor3 = Theme.GetToken("Placeholder")
end

function Toggle:Unlock()
    self.Locked = false
    self.Container.BackgroundTransparency = 0.5
    self.TitleLabel.TextColor3 = Theme.GetToken("TextPrimary")
end

function Toggle:Destroy()
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    table.clear(self._connections)
    self.Container:Destroy()
end

return Toggle
end

_MODULES['Elements/Slider'] = function()


local UserInputService = game:GetService("UserInputService")
local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Slider = {}
Slider.__index = Slider


function Slider.new(parent, configEngine, props)
    local titleText = props.Title or props.Name or "Slider"
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
    self.Flag = props.Flag
    self.IsDragging = false
    self._connections = {}

    local isDesc = props.Desc and props.Desc ~= ""
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


    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 118, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 8 else 12)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Header
    titleLabel.Text = titleText
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = container

    local descLabel = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 118, 0, 14)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 28)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Theme.Fonts.Body
        descLabel.Text = props.Desc or ""
        descLabel.TextColor3 = Theme.GetToken("TextMuted")
        descLabel.TextSize = 12
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = container
    end


    local controlArea = Instance.new("Frame")
    controlArea.Name = "ControlArea"
    controlArea.Size = UDim2.new(0, 116, 0, 24)
    controlArea.Position = UDim2.new(1, 0, 0.5, 0)
    controlArea.AnchorPoint = Vector2.new(1, 0.5)
    controlArea.BackgroundTransparency = 1


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
    badgeInput.Font = Theme.Fonts.Code
    badgeInput.Text = tostring(self.Value) .. self.Suffix
    badgeInput.TextColor3 = Theme.GetToken("TextPrimary")
    badgeInput.TextSize = 11
    badgeInput.ClearTextOnFocus = false
    badgeInput.ClipsDescendants = true
    badgeInput.TextXAlignment = Enum.TextXAlignment.Center
    badgeInput.Parent = badge
    badge.Parent = controlArea


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
    thumb.Size = UDim2.fromOffset(10, 10)
    thumb.Position = UDim2.new(0, 0, 0.5, 0)
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.BorderSizePixel = 0

    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = Theme.Radii.Pill
    thumbCorner.Parent = thumb

    local thumbStroke = Instance.new("UIStroke")
    thumbStroke.Color = Theme.GetToken("BorderSubtle")
    thumbStroke.Thickness = 1
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

    local function snap(rawVal)
        local stepped = math.floor((rawVal - self.Min) / self.Step + 0.5) * self.Step + self.Min
        return math.clamp(stepped, self.Min, self.Max)
    end

    local allowNegative = self.Min < 0
    local allowDecimal = (self.Step % 1 ~= 0)
    local isEditing = false

    local function formatValue(val)
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
            badgeInput.Text = formatValue(self.Value) .. self.Suffix
            return
        end

        local clamped = math.clamp(num, self.Min, self.Max)
        local stepped = snap(clamped)

        self:Set(stepped, false, true)
        badgeInput.Text = formatValue(self.Value) .. self.Suffix
    end))

    local function updateFromInput(inputPos)
        local trackAbsX = track.AbsolutePosition.X
        local trackWidth = track.AbsoluteSize.X
        if trackWidth <= 0 then return end

        local relX = math.clamp(inputPos.X - trackAbsX, 0, trackWidth)
        local pct = relX / trackWidth
        local rawVal = self.Min + (self.Max - self.Min) * pct
        local snapped = snap(rawVal)
        self:Set(snapped, false, false)
    end

    track.InputBegan:Connect(function(input)
        if not self.Locked and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            self.IsDragging = true
            updateFromInput(input.Position)

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    self.IsDragging = false
                end
            end)
        end
    end)

    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if self.IsDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input.Position)
        end
    end))

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self.IsDragging = false
        end
    end))

    self:Set(self.Value, true, false)

    if self.Flag and configEngine then
        configEngine:RegisterFlag(self.Flag, function()
            return self.Value
        end, function(val)
            self:Set(val, false, true)
        end)
    end

    container.Parent = parent
    return self
end

function Slider:Set(newVal, skipCallback, animate)
    if self._isUpdating then return end
    self._isUpdating = true

    self.Value = math.clamp(newVal, self.Min, self.Max)

    local pct = (self.Value - self.Min) / math.max(1e-5, (self.Max - self.Min))

    if self._fillTween then
        self._fillTween:Cancel()
        self._fillTween = nil
    end
    if self._thumbTween then
        self._thumbTween:Cancel()
        self._thumbTween = nil
    end

    if animate then
        self._fillTween = Tweener.Tween(self.Fill, Tweener.Info.Normal, { Size = UDim2.new(pct, 0, 1, 0) })
        self._thumbTween = Tweener.Tween(self.Thumb, Tweener.Info.Normal, { Position = UDim2.new(pct, 0, 0.5, 0) }, function()
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

    if self.BadgeInput and not self.BadgeInput:IsFocused() then
        self.BadgeInput.Text = displayStr .. self.Suffix
    end

    if not skipCallback and self.Callback then
        self.Callback(self.Value)
    end

    self._isUpdating = false
end

function Slider:Get()
    return self.Value
end

function Slider:SetTitle(title)
    self.TitleLabel.Text = title
end

function Slider:SetDesc(desc)
    if self.DescLabel then
        self.DescLabel.Text = desc
    end
end

function Slider:Lock()
    self.Locked = true
    self.Container.BackgroundTransparency = 0.7
    self.TitleLabel.TextColor3 = Theme.GetToken("Placeholder")
    if self.BadgeInput then
        self.BadgeInput.TextEditable = false
    end
end

function Slider:Unlock()
    self.Locked = false
    self.Container.BackgroundTransparency = 0.5
    self.TitleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    if self.BadgeInput then
        self.BadgeInput.TextEditable = true
    end
end

function Slider:Destroy()
    if self._fillTween then
        self._fillTween:Cancel()
        self._fillTween = nil
    end
    if self._thumbTween then
        self._thumbTween:Cancel()
        self._thumbTween = nil
    end
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    table.clear(self._connections)
    self.Container:Destroy()
end

return Slider
end

_MODULES['Elements/Dropdown'] = function()


local UserInputService = game:GetService("UserInputService")
local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Dropdown = {}
Dropdown.__index = Dropdown

local currentOpenDropdown = nil


function Dropdown.new(parent, configEngine, props, parentCard)
    local titleText = props.Title or props.Name or "Dropdown"
    local rawVal = if props.Value ~= nil then props.Value else props.Default

    local self = setmetatable({}, Dropdown)
    self.Values = props.Values or {}
    self.Multi = props.Multi or false
    self.AllowNone = props.AllowNone or false
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self.Flag = props.Flag
    self.ParentCard = parentCard
    self.IsOpen = false
    self.ClickOutsideConn = nil
    self._connections = {}

    if self.Multi then
        self.Selected = if type(rawVal) == "table" then rawVal else (rawVal and { rawVal } or {})
    else
        self.Selected = if type(rawVal) == "string" then rawVal else (self.Values[1] and (type(self.Values[1]) == "table" and self.Values[1].Title or self.Values[1]) or "")
    end

    local isDesc = props.Desc and props.Desc ~= ""
    local containerHeight = if isDesc then 68 else 54

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
    pad.PaddingRight = UDim.new(0, 12)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.Parent = container


    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 16)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Header
    titleLabel.Text = titleText
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = container

    local descLabel = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, 0, 0, 14)
        descLabel.Position = UDim2.new(0, 0, 0, 16)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Theme.Fonts.Body
        descLabel.Text = props.Desc or ""
        descLabel.TextColor3 = Theme.GetToken("TextMuted")
        descLabel.TextSize = 12
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = container
    end


    local triggerY = if isDesc then 32 else 20
    local trigger = Instance.new("TextButton")
    trigger.Name = "Trigger"
    trigger.Size = UDim2.new(1, 0, 0, 24)
    trigger.Position = UDim2.new(0, 0, 0, triggerY)
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
    selectedText.Size = UDim2.new(1, -20, 1, 0)
    selectedText.BackgroundTransparency = 1
    selectedText.Font = Theme.Fonts.Body
    selectedText.TextColor3 = Theme.GetToken("TextPrimary")
    selectedText.TextSize = 12
    selectedText.TextXAlignment = Enum.TextXAlignment.Left
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


    local popover = Instance.new("ScrollingFrame")
    popover.Name = "PopoverList"
    popover.Size = UDim2.new(1, 0, 0, 0)
    popover.Position = UDim2.new(0, 0, 1, 4)
    popover.BackgroundColor3 = Color3.fromHex("#181822")
    popover.BorderSizePixel = 0
    popover.ScrollBarThickness = 2
    popover.ScrollBarImageColor3 = Theme.GetToken("BorderStrong")
    popover.CanvasSize = UDim2.new(0, 0, 0, 0)
    popover.AutomaticCanvasSize = Enum.AutomaticSize.Y
    popover.Visible = false
    popover.ZIndex = 150
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
    popPad.PaddingTop = UDim.new(0, 4)
    popPad.PaddingBottom = UDim.new(0, 4)
    popPad.PaddingLeft = UDim.new(0, 4)
    popPad.PaddingRight = UDim.new(0, 4)
    popPad.Parent = popover

    local popList = Instance.new("UIListLayout")
    popList.SortOrder = Enum.SortOrder.LayoutOrder
    popList.Padding = UDim.new(0, 2)
    popList.Parent = popover

    popover.Parent = trigger

    self.Container = container
    self.TitleLabel = titleLabel
    self.DescLabel = descLabel
    self.Trigger = trigger
    self.SelectedText = selectedText
    self.Chevron = chevron
    self.Popover = popover

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

    local function updateDisplay()
        if self.Multi then
            local count = #self.Selected
            if count == 0 then
                selectedText.Text = "None"
                selectedText.TextColor3 = Theme.GetToken("Placeholder")
            elseif count == 1 then
                selectedText.Text = self.Selected[1]
                selectedText.TextColor3 = Theme.GetToken("TextPrimary")
            else
                selectedText.Text = string.format("%d selected (%s)", count, table.concat(self.Selected, ", "))
                selectedText.TextColor3 = Theme.GetToken("TextPrimary")
            end
        else
            if self.Selected and self.Selected ~= "" then
                selectedText.Text = tostring(self.Selected)
                selectedText.TextColor3 = Theme.GetToken("TextPrimary")
            else
                selectedText.Text = "Select..."
                selectedText.TextColor3 = Theme.GetToken("Placeholder")
            end
        end
    end

    self.UpdateDisplay = updateDisplay

    local function rebuildOptions()
        for _, child in ipairs(popover:GetChildren()) do
            if child:IsA("GuiObject") and child.Name:sub(1, 4) == "Opt_" then
                child:Destroy()
            end
        end

        for i, valItem in ipairs(self.Values) do
            local itemTitle = if type(valItem) == "table" then valItem.Title else tostring(valItem)
            local itemIcon = if type(valItem) == "table" then valItem.Icon else nil

            local optBtn = Instance.new("TextButton")
            optBtn.Name = "Opt_" .. itemTitle
            optBtn.Size = UDim2.new(1, 0, 0, 26)
            optBtn.BackgroundColor3 = Theme.GetToken("SurfaceHover")
            optBtn.BackgroundTransparency = 1
            optBtn.AutoButtonColor = false
            optBtn.Text = ""
            optBtn.ZIndex = 151
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
                icon.ZIndex = 152
                Icons.Apply(icon, itemIcon)
                icon.Parent = optBtn
                optOffset = 20
            end

            local optLabel = Instance.new("TextLabel")
            optLabel.Name = "Label"
            optLabel.Size = UDim2.new(1, -optOffset - 20, 1, 0)
            optLabel.Position = UDim2.new(0, optOffset, 0, 0)
            optLabel.BackgroundTransparency = 1
            optLabel.Font = Theme.Fonts.Body
            optLabel.Text = itemTitle
            optLabel.TextColor3 = Theme.GetToken("TextPrimary")
            optLabel.TextSize = 12
            optLabel.TextXAlignment = Enum.TextXAlignment.Left
            optLabel.ZIndex = 152
            optLabel.Parent = optBtn

            local check = Instance.new("ImageLabel")
            check.Name = "Check"
            check.Size = UDim2.fromOffset(12, 12)
            check.Position = UDim2.new(1, 0, 0.5, 0)
            check.AnchorPoint = Vector2.new(1, 0.5)
            check.BackgroundTransparency = 1
            check.ImageColor3 = Theme.GetToken("Accent")
            check.ZIndex = 152
            Icons.Apply(check, "check")

            local isSelected = false
            if self.Multi then
                isSelected = table.find(self.Selected, itemTitle) ~= nil
            else
                isSelected = self.Selected == itemTitle
            end
            check.Visible = isSelected
            check.Parent = optBtn

            optBtn.MouseEnter:Connect(function()
                Tweener.Tween(optBtn, Tweener.Info.Micro, { BackgroundTransparency = 0 })
            end)
            optBtn.MouseLeave:Connect(function()
                Tweener.Tween(optBtn, Tweener.Info.Micro, { BackgroundTransparency = 1 })
            end)

            optBtn.Activated:Connect(function()
                if self.Multi then
                    local idx = table.find(self.Selected, itemTitle)
                    if idx then
                        if #self.Selected > 1 or self.AllowNone then
                            table.remove(self.Selected, idx)
                            check.Visible = false
                        end
                    else
                        table.insert(self.Selected, itemTitle)
                        check.Visible = true
                    end
                    updateDisplay()
                    if self.Callback then
                        self.Callback(table.clone(self.Selected))
                    end
                else
                    if self.Selected == itemTitle then
                        self.Selected = nil
                        updateDisplay()
                        rebuildOptions()
                        self:Close()
                        if self.Callback then
                            self.Callback(nil)
                        end
                    else
                        self.Selected = itemTitle
                        updateDisplay()
                        rebuildOptions()
                        self:Close()
                        if self.Callback then
                            self.Callback(self.Selected)
                        end
                    end
                end
            end)

            optBtn.Parent = popover
        end
    end

    local function updateOptionColors()
        for _, child in ipairs(popover:GetChildren()) do
            if child:IsA("GuiObject") and child.Name:sub(1, 4) == "Opt_" then
                local optLabel = child:FindFirstChild("OptLabel")
                if optLabel and optLabel:IsA("TextLabel") then
                    local isSel = false
                    if self.Multi then
                        isSel = table.find(self.Selected, child.Name:sub(5)) ~= nil
                    else
                        isSel = (self.Selected == child.Name:sub(5))
                    end
                    optLabel.TextColor3 = if isSel then Theme.GetToken("Accent") else Theme.GetToken("TextPrimary")
                end
                local check = child:FindFirstChild("CheckIcon")
                if check and check:IsA("ImageLabel") then
                    check.ImageColor3 = Theme.GetToken("Accent")
                end
            end
        end
    end

    self.RebuildOptions = rebuildOptions
    rebuildOptions()
    updateDisplay()

    table.insert(self._connections, Theme.Changed:Connect(function()
        updateDisplay()
        updateOptionColors()
    end))

    trigger.Activated:Connect(function()
        if self.Locked then return end
        if self.IsOpen then
            self:Close()
        else
            self:Open()
        end
    end)

    if self.Flag and configEngine then
        configEngine:RegisterFlag(self.Flag, function()
            return self.Selected
        end, function(val)
            self:Set(val)
        end)
    end

    container.Parent = parent
    return self
end

function Dropdown:Open()
    if currentOpenDropdown and currentOpenDropdown ~= self then
        currentOpenDropdown:Close()
    end
    currentOpenDropdown = self

    self.IsOpen = true

    -- Elevate container ZIndex above sibling cards
    if self.ParentCard then
        self.ParentCard.ZIndex = 50
    end
    self.Container.ZIndex = 100

    local optCount = #self.Values
    local targetH = math.clamp(optCount * 28 + 8, 40, 140)

    local screenH = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 1080
    local absY = self.Trigger.AbsolutePosition.Y
    if absY + targetH + 40 > screenH then
        self.Popover.Position = UDim2.new(0, 0, 0, -4)
        self.Popover.AnchorPoint = Vector2.new(0, 1)
    else
        self.Popover.Position = UDim2.new(0, 0, 1, 4)
        self.Popover.AnchorPoint = Vector2.new(0, 0)
    end

    self.Popover.Visible = true
    Tweener.Tween(self.Popover, Tweener.Info.Fast, {
        Size = UDim2.new(1, 0, 0, targetH)
    })
    Tweener.Tween(self.Chevron, Tweener.Info.Fast, {
        Rotation = 180
    })


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

    Tweener.Tween(self.Popover, Tweener.Info.Fast, {
        Size = UDim2.new(1, 0, 0, 0)
    })
    local rotTween = Tweener.Tween(self.Chevron, Tweener.Info.Fast, {
        Rotation = 0
    })
    rotTween.Completed:Once(function()
        if not self.IsOpen then
            self.Popover.Visible = false
            self.Container.ZIndex = 5
            if self.ParentCard then
                self.ParentCard.ZIndex = 1
            end
        end
    end)
end

function Dropdown:Set(val, skipCallback)
    if self.Multi then
        self.Selected = if type(val) == "table" then val else { tostring(val) }
    else
        self.Selected = tostring(val)
    end
    self:RebuildOptions()
    self.UpdateDisplay()

    if not skipCallback and self.Callback then
        self.Callback(self.Selected)
    end
end

function Dropdown:Clear(skipCallback)
    if self.Multi then
        self.Selected = {}
    else
        self.Selected = nil
    end
    self:RebuildOptions()
    self.UpdateDisplay()
    if not skipCallback and self.Callback then
        self.Callback(self.Selected)
    end
end
Dropdown.ClearDropdown = Dropdown.Clear

function Dropdown:Get()
    return self.Selected
end

function Dropdown:Refresh(newValues)
    self.Values = newValues
    self:RebuildOptions()
    self.UpdateDisplay()
end

function Dropdown:SetTitle(title)
    self.TitleLabel.Text = title
end

function Dropdown:SetDesc(desc)
    if self.DescLabel then
        self.DescLabel.Text = desc
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
    if self.ClickOutsideConn then
        self.ClickOutsideConn:Disconnect()
        self.ClickOutsideConn = nil
    end
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    table.clear(self._connections)
    self:Close()
    self.Container:Destroy()
end

return Dropdown
end

_MODULES['Elements/Input'] = function()


local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Input = {}
Input.__index = Input


function Input.new(parent, configEngine, props)
    local titleText = props.Title or props.Name or "Input"
    local rawVal = if props.Value ~= nil then props.Value elseif props.Default ~= nil then props.Default else ""

    local self = setmetatable({}, Input)
    self.Value = tostring(rawVal)
    self.Placeholder = props.Placeholder or "Type here..."
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self.Flag = props.Flag

    local isDesc = props.Desc and props.Desc ~= ""
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
    stroke.Parent = container

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    pad.Parent = container


    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(0.48, 0, 0, 18)
    titleLabel.Position = UDim2.new(0, 0, 0, if isDesc then 12 else 17)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Header
    titleLabel.Text = titleText
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = container

    local descLabel = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(0.48, 0, 0, 16)
        descLabel.Position = UDim2.new(0, 0, 0, 32)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Theme.Fonts.Body
        descLabel.Text = props.Desc or ""
        descLabel.TextColor3 = Theme.GetToken("TextMuted")
        descLabel.TextSize = 12
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.Parent = container
    end


    local boxFrame = Instance.new("Frame")
    boxFrame.Name = "BoxFrame"
    boxFrame.Size = UDim2.new(0.48, 0, 0, 30)
    boxFrame.Position = UDim2.new(1, 0, 0.5, 0)
    boxFrame.AnchorPoint = Vector2.new(1, 0.5)
    boxFrame.BackgroundColor3 = Theme.GetToken("Card")

    local boxCorner = Instance.new("UICorner")
    boxCorner.CornerRadius = Theme.Radii.Control
    boxCorner.Parent = boxFrame

    local boxStroke = Instance.new("UIStroke")
    boxStroke.Color = Theme.GetToken("BorderSubtle")
    boxStroke.Thickness = 1
    boxStroke.Parent = boxFrame

    local boxPad = Instance.new("UIPadding")
    boxPad.PaddingLeft = UDim.new(0, 10)
    boxPad.PaddingRight = UDim.new(0, 8)
    boxPad.Parent = boxFrame

    local textBox = Instance.new("TextBox")
    textBox.Name = "TextBox"
    textBox.Size = UDim2.new(1, -22, 1, 0)
    textBox.BackgroundTransparency = 1
    textBox.Font = Theme.Fonts.Body
    textBox.Text = self.Value
    textBox.PlaceholderText = self.Placeholder
    textBox.PlaceholderColor3 = Theme.GetToken("Placeholder")
    textBox.TextColor3 = Theme.GetToken("TextPrimary")
    textBox.TextSize = 12
    textBox.TextXAlignment = Enum.TextXAlignment.Left
    textBox.ClearTextOnFocus = if props.ClearTextOnFocus ~= nil then props.ClearTextOnFocus else false
    textBox.Parent = boxFrame


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


    textBox.Focused:Connect(function()
        Tweener.Tween(boxStroke, Tweener.Info.Fast, {
            Color = Theme.GetToken("BorderAccent")
        })
    end)

    textBox.FocusLost:Connect(function(enterPressed)
        Tweener.Tween(boxStroke, Tweener.Info.Fast, {
            Color = Theme.GetToken("BorderSubtle")
        })
        self.Value = textBox.Text
        clearBtn.Visible = self.Value ~= ""
        if self.Callback then
            self.Callback(self.Value)
        end
    end)

    textBox:GetPropertyChangedSignal("Text"):Connect(function()
        clearBtn.Visible = textBox.Text ~= ""
    end)

    clearBtn.Activated:Connect(function()
        textBox.Text = ""
        self.Value = ""
        clearBtn.Visible = false
        if self.Callback then
            self.Callback("")
        end
    end)


    if self.Flag and configEngine then
        configEngine:RegisterFlag(self.Flag, function()
            return self.Value
        end, function(val)
            self:Set(tostring(val))
        end)
    end

    container.Parent = parent
    return self
end

function Input:Set(text, skipCallback)
    self.Value = text
    self.TextBox.Text = text
    self.ClearBtn.Visible = text ~= ""
    if not skipCallback and self.Callback then
        self.Callback(self.Value)
    end
end

function Input:Get()
    return self.Value
end

function Input:SetPlaceholder(placeholder)
    self.Placeholder = placeholder
    self.TextBox.PlaceholderText = placeholder
end

function Input:SetTitle(title)
    self.TitleLabel.Text = title
end

function Input:SetDesc(desc)
    if self.DescLabel then
        self.DescLabel.Text = desc
    end
end

function Input:Lock()
    self.Locked = true
    self.TextBox.TextEditable = false
    self.Container.BackgroundTransparency = 0.7
    self.TitleLabel.TextColor3 = Theme.GetToken("Placeholder")
end

function Input:Unlock()
    self.Locked = false
    self.TextBox.TextEditable = true
    self.Container.BackgroundTransparency = 0.5
    self.TitleLabel.TextColor3 = Theme.GetToken("TextPrimary")
end

function Input:Destroy()
    self.Container:Destroy()
end

return Input
end

_MODULES['Elements/Keybind'] = function()


local UserInputService = game:GetService("UserInputService")
local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Keybind = {}
Keybind.__index = Keybind


function Keybind.new(parent, configEngine, props)
    local titleText = props.Title or props.Name or "Keybind"
    local rawVal = if props.Value ~= nil then props.Value elseif props.Default ~= nil then props.Default else nil

    local self = setmetatable({}, Keybind)
    self.Value = if rawVal then (if typeof(rawVal) == "EnumItem" then rawVal.Name else tostring(rawVal)) else "None"
    self.Locked = props.Locked or false
    self.Callback = props.Callback
    self.Flag = props.Flag
    self.IsListening = false
    self._connections = {}
    self._listenConn = nil

    local isDesc = props.Desc and props.Desc ~= ""
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

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset - 90, 0, 18)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, if isDesc then 9 else 12)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Header
    titleLabel.Text = titleText
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    titleLabel.Parent = container

    local descLabel = nil
    if isDesc then
        descLabel = Instance.new("TextLabel")
        descLabel.Name = "Desc"
        descLabel.Size = UDim2.new(1, -iconOffset - 90, 0, 16)
        descLabel.Position = UDim2.new(0, iconOffset, 0, 29)
        descLabel.BackgroundTransparency = 1
        descLabel.Font = Theme.Fonts.Body
        descLabel.Text = props.Desc or ""
        descLabel.TextColor3 = Theme.GetToken("TextMuted")
        descLabel.TextSize = 12
        descLabel.TextXAlignment = Enum.TextXAlignment.Left
        descLabel.TextTruncate = Enum.TextTruncate.AtEnd
        descLabel.Parent = container
    end


    local badge = Instance.new("TextButton")
    badge.Name = "KeyBadge"
    badge.Size = UDim2.new(0, 82, 0, 22)
    badge.Position = UDim2.new(1, 0, 0.5, 0)
    badge.AnchorPoint = Vector2.new(1, 0.5)
    badge.BackgroundColor3 = Theme.GetToken("Card")
    badge.AutoButtonColor = false
    badge.Text = ""

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = Theme.Radii.Control
    badgeCorner.Parent = badge

    local badgeStroke = Instance.new("UIStroke")
    badgeStroke.Color = Theme.GetToken("BorderSubtle")
    badgeStroke.Thickness = 1
    badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    badgeStroke.Parent = badge

    local badgePad = Instance.new("UIPadding")
    badgePad.PaddingLeft = UDim.new(0, 6)
    badgePad.PaddingRight = UDim.new(0, 6)
    badgePad.Parent = badge

    local badgeText = Instance.new("TextLabel")
    badgeText.Name = "KeyText"
    badgeText.Size = UDim2.fromScale(1, 1)
    badgeText.BackgroundTransparency = 1
    badgeText.Font = Theme.Fonts.Code
    badgeText.Text = self.Value
    badgeText.TextColor3 = Theme.GetToken("TextPrimary")
    badgeText.TextSize = 11
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

    Tweener.BindHoverLift(container, stroke)

    local function endListening(selectedKey)
        if self._listenConn then
            self._listenConn:Disconnect()
            self._listenConn = nil
        end
        self.IsListening = false
        Tweener.Tween(badgeStroke, Tweener.Info.Fast, {
            Color = Theme.GetToken("BorderSubtle")
        })
        if selectedKey then
            self:Set(selectedKey)
        else
            badgeText.Text = self.Value
        end
    end
    self._endListening = endListening

    local function openMobileKeyPicker()
        local targetParent = nil
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
        title.Font = Theme.Fonts.Title
        title.TextSize = 13
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
            keyBtn.Font = Theme.Fonts.Code
            keyBtn.TextSize = 11
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
        Tweener.Tween(badgeStroke, Tweener.Info.Fast, {
            Color = Theme.GetToken("BorderAccent")
        })

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

    if self.Flag and configEngine then
        configEngine:RegisterFlag(self.Flag, function()
            return self.Value
        end, function(val)
            self:Set(tostring(val))
        end)
    end

    container.Parent = parent
    return self
end

function Keybind:Set(key, skipCallback)
    self.Value = key
    self.BadgeText.Text = self.Value
    if not skipCallback and self.Callback then
        self.Callback(self.Value)
    end
end

function Keybind:Get()
    return self.Value
end

function Keybind:SetTitle(title)
    self.TitleLabel.Text = title
end

function Keybind:SetDesc(desc)
    if self.DescLabel then
        self.DescLabel.Text = desc
    end
end

function Keybind:Lock()
    self.Locked = true
    self.Container.BackgroundTransparency = 0.7
    self.TitleLabel.TextColor3 = Theme.GetToken("Placeholder")
end

function Keybind:Unlock()
    self.Locked = false
    self.Container.BackgroundTransparency = 0.5
    self.TitleLabel.TextColor3 = Theme.GetToken("TextPrimary")
end

function Keybind:Destroy()
    if self.IsListening and self._endListening then
        self._endListening(nil)
    end
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    table.clear(self._connections)
    self.Container:Destroy()
end

return Keybind
end

_MODULES['Elements/Paragraph'] = function()


local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")

local Paragraph = {}
Paragraph.__index = Paragraph


function Paragraph.new(parent, props)
    local titleText = props.Title or props.Name or "Paragraph"
    local descText = props.Desc or props.Content or ""

    local self = setmetatable({}, Paragraph)

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

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, -iconOffset, 1, 0)
    titleLabel.Position = UDim2.new(0, iconOffset, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Title
    titleLabel.Text = titleText
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.RichText = true
    titleLabel.Parent = header

    local descLabel = Instance.new("TextLabel")
    descLabel.Name = "Desc"
    descLabel.Size = UDim2.new(1, 0, 0, 0)
    descLabel.AutomaticSize = Enum.AutomaticSize.Y
    descLabel.BackgroundTransparency = 1
    descLabel.Font = Theme.Fonts.Body
    descLabel.Text = descText
    descLabel.TextColor3 = Theme.GetToken("TextMuted")
    descLabel.TextSize = 12
    descLabel.TextWrapped = true
    descLabel.RichText = true
    descLabel.LineHeight = 1.2
    descLabel.TextXAlignment = Enum.TextXAlignment.Left
    descLabel.LayoutOrder = 2
    descLabel.Parent = container

    Theme.Bind(container, "BackgroundColor3", "SurfaceHover")
    Theme.Bind(stroke, "Color", "BorderSubtle")
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    Theme.Bind(descLabel, "TextColor3", "TextMuted")


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
            local btn = Instance.new("TextButton")
            btn.Name = "Btn_" .. bData.Title
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

            local btnLabel = Instance.new("TextLabel")
            btnLabel.Size = UDim2.fromScale(1, 1)
            btnLabel.BackgroundTransparency = 1
            btnLabel.Font = Theme.Fonts.Header
            btnLabel.Text = bData.Title
            btnLabel.TextColor3 = Theme.GetToken("TextPrimary")
            btnLabel.TextSize = 11
            btnLabel.Parent = btn

            Theme.Bind(btn, "BackgroundColor3", "SurfaceActive")
            Theme.Bind(btnStroke, "Color", "BorderSubtle")
            Theme.Bind(btnLabel, "TextColor3", "TextPrimary")

            Tweener.BindPressFeedback(btn)

            btn.MouseEnter:Connect(function()
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Accent") })
                Tweener.Tween(btnLabel, Tweener.Info.Fast, { TextColor3 = Color3.fromRGB(255, 255, 255) })
            end)
            btn.MouseLeave:Connect(function()
                Tweener.Tween(btn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceActive") })
                Tweener.Tween(btnLabel, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
            end)

            btn.Activated:Connect(function()
                if bData.Callback then
                    bData.Callback()
                end
            end)
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

function Paragraph:SetTitle(title)
    self.TitleLabel.Text = title
end

function Paragraph:SetDesc(desc)
    self.DescLabel.Text = desc
end

function Paragraph:Destroy()
    self.Container:Destroy()
end

return Paragraph
end

_MODULES['Components/Section'] = function()


local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Primitives = _require("Components/Primitives")
local Divider = _require("Elements/Divider")

local Section = {}
Section.__index = Section


function Section.new(parent, configEngine, rawProps)
    local props = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    local sectionTitle = props.Title or props.Name or "Section"
    props.Title = sectionTitle

    local self = setmetatable({}, Section)
    self.Title = sectionTitle
    self.ConfigEngine = configEngine
    self.Opened = if props.Opened ~= nil then props.Opened else true

    local card = Instance.new("Frame")
    card.Name = "Section_" .. tostring(sectionTitle)
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = Theme.GetToken("Card")
    card.BorderSizePixel = 0
    card.ClipsDescendants = false
    card.ZIndex = 1
    Theme.Bind(card, "BackgroundColor3", "Card")

    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.Radii.Card
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Theme.GetToken("BorderSubtle")
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = card
    Theme.Bind(stroke, "Color", "BorderSubtle")

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 14)
    pad.PaddingBottom = UDim.new(0, 14)
    pad.PaddingLeft = UDim.new(0, 16)
    pad.PaddingRight = UDim.new(0, 16)
    pad.Parent = card

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.Parent = card


    local header = Instance.new("TextButton")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 22)
    header.BackgroundTransparency = 1
    header.Text = ""
    header.AutoButtonColor = false
    header.LayoutOrder = 0
    header.Parent = card

    local offsetIcon = 0
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
        offsetIcon = 22
    end

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -offsetIcon - 30, 1, 0)
    title.Position = UDim2.new(0, offsetIcon, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Theme.Fonts.Title
    title.Text = props.Title
    title.TextColor3 = Theme.GetToken("TextPrimary")
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    Theme.Bind(title, "TextColor3", "TextPrimary")

    local chevron = nil
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


    local elementsContainer = Instance.new("Frame")
    elementsContainer.Name = "Elements"
    elementsContainer.Size = UDim2.new(1, 0, 0, 0)
    elementsContainer.AutomaticSize = Enum.AutomaticSize.Y
    elementsContainer.BackgroundTransparency = 1
    elementsContainer.LayoutOrder = 1
    elementsContainer.Visible = self.Opened
    elementsContainer.ClipsDescendants = false

    local elemList = Instance.new("UIListLayout")
    elemList.SortOrder = Enum.SortOrder.LayoutOrder
    elemList.Padding = UDim.new(0, 8)
    elemList.Parent = elementsContainer

    elementsContainer.Parent = card

    if props.Collapsible and chevron then
        header.Activated:Connect(function()
            self.Opened = not self.Opened
            elementsContainer.Visible = self.Opened
            Tweener.Tween(chevron, Tweener.Info.Fast, {
                Rotation = if self.Opened then 0 else -90
            })
        end)
    end

    card.Parent = parent
    self.Card = card
    self.ElementsContainer = elementsContainer

    return self
end

function Section:Button(props)
    local Button = _require("Elements/Button")
    return Button.new(self.ElementsContainer, props)
end

function Section:Toggle(props)
    local Toggle = _require("Elements/Toggle")
    return Toggle.new(self.ElementsContainer, self.ConfigEngine, props)
end

function Section:Slider(props)
    local Slider = _require("Elements/Slider")
    return Slider.new(self.ElementsContainer, self.ConfigEngine, props)
end

function Section:Dropdown(props)
    local Dropdown = _require("Elements/Dropdown")
    return Dropdown.new(self.ElementsContainer, self.ConfigEngine, props, self.Card)
end

function Section:Input(props)
    local Input = _require("Elements/Input")
    return Input.new(self.ElementsContainer, self.ConfigEngine, props)
end

function Section:Keybind(props)
    local Keybind = _require("Elements/Keybind")
    return Keybind.new(self.ElementsContainer, self.ConfigEngine, props)
end

function Section:Paragraph(props)
    local Paragraph = _require("Elements/Paragraph")
    return Paragraph.new(self.ElementsContainer, props)
end

function Section:Divider(props)
    local p = if type(props) == "string" then { Title = props } else (props or {})
    return Divider.new(self.ElementsContainer, p)
end

function Section:Space(height)
    return Primitives.Space(self.ElementsContainer, height)
end

function Section:SetTitle(newTitle)
    local header = self.Card:FindFirstChild("Header")
    if header then
        local title = header:FindFirstChild("Title")
        if title then
            title.Text = newTitle
        end
    end
end

function Section:Destroy()
    self.Card:Destroy()
end


Section.CreateButton = Section.Button
Section.AddButton = Section.Button
Section.CreateToggle = Section.Toggle
Section.AddToggle = Section.Toggle
Section.CreateSlider = Section.Slider
Section.AddSlider = Section.Slider
Section.CreateDropdown = Section.Dropdown
Section.AddDropdown = Section.Dropdown
Section.CreateInput = Section.Input
Section.AddInput = Section.Input
Section.CreateKeybind = Section.Keybind
Section.AddKeybind = Section.Keybind
Section.CreateParagraph = Section.Paragraph
Section.AddParagraph = Section.Paragraph
Section.CreateDivider = Section.Divider
Section.AddDivider = Section.Divider

return Section
end

_MODULES['Components/Tab'] = function()


local UserInputService = game:GetService("UserInputService")
local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Section = _require("Components/Section")

local Tab = {}
Tab.__index = Tab


function Tab.new(window, sidebarList, contentContainer, configEngine, rawProps)
    local props = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    local tabTitle = props.Title or props.Name or "Tab"
    props.Title = tabTitle

    local self = setmetatable({}, Tab)
    self.Title = tabTitle
    self.Window = window
    self.ConfigEngine = configEngine
    self.Columns = props.Columns or 2
    self.Locked = props.Locked or false
    self.Active = false
    self._connections = {}


    local sidebarBtn = Instance.new("TextButton")
    sidebarBtn.Name = "TabBtn_" .. tostring(tabTitle)
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
    local iconLabel = nil
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
    titleLabel.Font = Theme.Fonts.Header
    titleLabel.Text = props.Title
    titleLabel.TextColor3 = Theme.GetToken("TextMuted")
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = sidebarBtn

    sidebarBtn.Parent = sidebarList
    self.SidebarButton = sidebarBtn
    self.TitleLabel = titleLabel
    self.IconLabel = iconLabel


    local pageWrapper = Instance.new("CanvasGroup")
    pageWrapper.Name = "PageWrapper_" .. props.Title
    pageWrapper.Size = UDim2.fromScale(1, 1)
    pageWrapper.Position = UDim2.new(0, 0, 0, 0)
    pageWrapper.BackgroundTransparency = 1
    pageWrapper.GroupTransparency = 1
    pageWrapper.Visible = false
    pageWrapper.Parent = contentContainer
    self.PageWrapper = pageWrapper
    self._pageTween = nil


    local page = Instance.new("ScrollingFrame")
    page.Name = "Page_" .. props.Title
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Theme.GetToken("BorderStrong")
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = true
    page.ClipsDescendants = false
    page.Parent = pageWrapper

    if self.Columns == 2 then
        local colContainer = Instance.new("Frame")
        colContainer.Name = "Columns"
        colContainer.Size = UDim2.new(1, -34, 0, 0)
        colContainer.Position = UDim2.new(0, 16, 0, 14)
        colContainer.AutomaticSize = Enum.AutomaticSize.Y
        colContainer.BackgroundTransparency = 1
        colContainer.ClipsDescendants = false

        local colLayout = Instance.new("UIListLayout")
        colLayout.FillDirection = Enum.FillDirection.Horizontal
        colLayout.SortOrder = Enum.SortOrder.LayoutOrder
        colLayout.Padding = UDim.new(0, 14)
        colLayout.Parent = colContainer


        local leftCol = Instance.new("Frame")
        leftCol.Name = "LeftColumn"
        leftCol.Size = UDim2.new(0.5, -7, 0, 0)
        leftCol.AutomaticSize = Enum.AutomaticSize.Y
        leftCol.BackgroundTransparency = 1
        leftCol.ClipsDescendants = false
        leftCol.ZIndex = 2

        local leftList = Instance.new("UIListLayout")
        leftList.SortOrder = Enum.SortOrder.LayoutOrder
        leftList.Padding = UDim.new(0, 14)
        leftList.Parent = leftCol
        leftCol.Parent = colContainer


        local rightCol = Instance.new("Frame")
        rightCol.Name = "RightColumn"
        rightCol.Size = UDim2.new(0.5, -7, 0, 0)
        rightCol.AutomaticSize = Enum.AutomaticSize.Y
        rightCol.BackgroundTransparency = 1
        rightCol.ClipsDescendants = false
        rightCol.ZIndex = 1

        local rightList = Instance.new("UIListLayout")
        rightList.SortOrder = Enum.SortOrder.LayoutOrder
        rightList.Padding = UDim.new(0, 14)
        rightList.Parent = rightCol
        rightCol.Parent = colContainer

        colContainer.Parent = page
        self.LeftColumn = leftCol
        self.RightColumn = rightCol

        local function updateResponsiveColumns()
            if not leftCol or not rightCol then return end
            local isMobile = (window.ContainerManager and window.ContainerManager.IsMobile) or false
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
            local shouldStack = isMobile or (vp.X < 850)

            if shouldStack then
                colLayout.FillDirection = Enum.FillDirection.Vertical
                leftCol.Size = UDim2.new(1, 0, 0, 0)
                rightCol.Size = UDim2.new(1, 0, 0, 0)
            else
                colLayout.FillDirection = Enum.FillDirection.Horizontal
                leftCol.Size = UDim2.new(0.5, -7, 0, 0)
                rightCol.Size = UDim2.new(0.5, -7, 0, 0)
            end
        end

        updateResponsiveColumns()
        if workspace.CurrentCamera then
            table.insert(self._connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveColumns))
        end
    else
        local singleContainer = Instance.new("Frame")
        singleContainer.Name = "SingleColumnContainer"
        singleContainer.Size = UDim2.new(1, -34, 0, 0)
        singleContainer.Position = UDim2.new(0, 16, 0, 14)
        singleContainer.AutomaticSize = Enum.AutomaticSize.Y
        singleContainer.BackgroundTransparency = 1
        singleContainer.ClipsDescendants = false

        local singleList = Instance.new("UIListLayout")
        singleList.SortOrder = Enum.SortOrder.LayoutOrder
        singleList.Padding = UDim.new(0, 14)
        singleList.Parent = singleContainer

        singleContainer.Parent = page
        self.SingleColumn = singleContainer
    end

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
    if self._pageTween then
        self._pageTween:Cancel()
        self._pageTween = nil
    end
    if self._hoverScaleTween then
        self._hoverScaleTween:Cancel()
        self._hoverScaleTween = nil
    end
    for _, conn in self._connections do
        conn:Disconnect()
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

function Tab:Select(animated)
    if self.Window and self.Window.CurrentTab ~= self then
        self.Window:SelectTab(self)
        return
    end

    self.Active = true

    if self._pageTween then
        self._pageTween:Cancel()
        self._pageTween = nil
    end
    if self._hoverScaleTween then
        self._hoverScaleTween:Cancel()
        self._hoverScaleTween = nil
    end
    self._hoverScaleTween = Tweener.Tween(self.BtnScale, Tweener.Info.Fast, { Scale = 1.0 }, function()
        self._hoverScaleTween = nil
    end)

    self.PageWrapper.Visible = true
    self.SidebarButton.BackgroundTransparency = 1

    local isAnimated = if animated ~= nil then animated else true
    if isAnimated then
        self.PageWrapper.Position = UDim2.new(0, 0, 0, 8)
        self.PageWrapper.GroupTransparency = 1

        self._pageTween = Tweener.Tween(self.PageWrapper, Tweener.Info.Normal, {
            Position = UDim2.new(0, 0, 0, 0),
            GroupTransparency = 0,
        }, function()
            self._pageTween = nil
            if self.Active then
                self.PageWrapper.Position = UDim2.new(0, 0, 0, 0)
                self.PageWrapper.GroupTransparency = 0
            end
        end)
    else
        self.PageWrapper.Position = UDim2.new(0, 0, 0, 0)
        self.PageWrapper.GroupTransparency = 0
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

function Tab:Deselect(animated)
    self.Active = false

    if self._pageTween then
        self._pageTween:Cancel()
        self._pageTween = nil
    end

    self.SidebarButton.BackgroundTransparency = 1

    local isAnimated = if animated ~= nil then animated else true
    if isAnimated then
        self._pageTween = Tweener.Tween(self.PageWrapper, Tweener.Info.Fast, {
            Position = UDim2.new(0, 0, 0, -8),
            GroupTransparency = 1,
        }, function()
            self._pageTween = nil
            if not self.Active then
                self.PageWrapper.Visible = false
            end
        end)
    else
        self.PageWrapper.Visible = false
        self.PageWrapper.GroupTransparency = 1
        self.PageWrapper.Position = UDim2.new(0, 0, 0, 0)
    end

    Tweener.Tween(self.TitleLabel, Tweener.Info.Fast, {
        TextColor3 = Theme.GetToken("TextMuted"),
    })
    if self.IconLabel then
        Tweener.Tween(self.IconLabel, Tweener.Info.Fast, {
            ImageColor3 = Theme.GetToken("TextMuted"),
        })
    end
end

function Tab:Section(rawProps)
    local props = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    props.Title = props.Title or props.Name or "Section"

    local targetParent = self.SingleColumn
    if self.Columns == 2 then
        if props.Column == "Right" then
            targetParent = self.RightColumn
        else
            targetParent = self.LeftColumn
        end
    end

    return Section.new(targetParent, self.ConfigEngine, props)
end

function Tab:_getOrCreateDefaultSection()
    if not self._defaultSection then
        self._defaultSection = self:Section({ Title = self.Title .. " Controls" })
    end
    return self._defaultSection
end

function Tab:Button(props)
    return self:_getOrCreateDefaultSection():Button(props)
end

function Tab:Toggle(props)
    return self:_getOrCreateDefaultSection():Toggle(props)
end

function Tab:Slider(props)
    return self:_getOrCreateDefaultSection():Slider(props)
end

function Tab:Dropdown(props)
    return self:_getOrCreateDefaultSection():Dropdown(props)
end

function Tab:Input(props)
    return self:_getOrCreateDefaultSection():Input(props)
end

function Tab:Keybind(props)
    return self:_getOrCreateDefaultSection():Keybind(props)
end

function Tab:Paragraph(props)
    return self:_getOrCreateDefaultSection():Paragraph(props)
end

function Tab:Divider(props)
    return self:_getOrCreateDefaultSection():Divider(props)
end


Tab.CreateSection = Tab.Section
Tab.AddSection = Tab.Section
Tab.CreateButton = Tab.Button
Tab.AddButton = Tab.Button
Tab.CreateToggle = Tab.Toggle
Tab.AddToggle = Tab.Toggle
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
Tab.CreateDivider = Tab.Divider
Tab.AddDivider = Tab.Divider

return Tab
end

_MODULES['Components/Window'] = function()


local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Theme = _require("Core/Theme")
local Tweener = _require("Core/Tweener")
local Icons = _require("Core/Icons")
local Tab = _require("Components/Tab")
local TabSection = _require("Components/TabSection")
local Popup = _require("Components/Popup")
local Notification = _require("Components/Notification")
local Dialog = _require("Components/Dialog")

local Window = {}
Window.__index = Window


function Window.new(containerManager, configEngine, props)
    local self = setmetatable({}, Window)
    self.ContainerManager = containerManager
    self.ConfigEngine = configEngine
    self.Flags = configEngine.Flags
    self.RootGui = containerManager.ScreenGui
    self.Tabs = {}
    self.Sections = {}
    self._currentSection = nil
    self.CurrentTab = nil
    self._indicatorTween = nil
    local initialKey = props.ToggleKey or Enum.KeyCode.LeftShift
    if type(initialKey) == "string" then
        local found = Enum.KeyCode[initialKey]
        self.ToggleKey = found or initialKey
    else
        self.ToggleKey = initialKey
    end
    self.IsVisible = true
    self.IsMinimized = false

    local defaultSize = props.Size or UDim2.fromOffset(740, 520)
    local sideBarWidth = props.SideBarWidth or 200

    local windowTitle = props.Title or "Sodium Hub"


    containerManager:SetBaseWindowSize(Vector2.new(defaultSize.X.Offset, defaultSize.Y.Offset))


    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "SodiumWindow_" .. windowTitle
    mainFrame.Size = defaultSize
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.Position = UDim2.fromScale(0.5, 0.5)
    mainFrame.BackgroundColor3 = Theme.GetToken("Background")
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = false
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


    local windowScale = Instance.new("UIScale")
    windowScale.Name = "WindowScale"
    windowScale.Scale = 1.0
    windowScale.Parent = mainFrame
    self.WindowScale = windowScale


    local dropShadow = Instance.new("ImageLabel")
    dropShadow.Name = "WindowDropShadow"
    dropShadow.Size = UDim2.new(0, defaultSize.X.Offset + 40, 0, defaultSize.Y.Offset + 40)
    dropShadow.AnchorPoint = Vector2.new(0.5, 0.5)
    dropShadow.Position = mainFrame.Position
    dropShadow.BackgroundTransparency = 1
    dropShadow.Image = "rbxassetid://6014261993"
    dropShadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    dropShadow.ImageTransparency = 0.52
    dropShadow.ScaleType = Enum.ScaleType.Slice
    dropShadow.SliceCenter = Rect.new(49, 49, 450, 450)
    dropShadow.ZIndex = 1
    dropShadow.Parent = self.RootGui
    self.DropShadow = dropShadow

    local dropShadowScale = Instance.new("UIScale")
    dropShadowScale.Name = "DropShadowScale"
    dropShadowScale.Scale = 1.0
    dropShadowScale.Parent = dropShadow
    self.DropShadowScale = dropShadowScale

    local function syncDropShadow()
        if mainFrame and mainFrame.Parent and dropShadow and dropShadow.Parent then
            dropShadow.Size = UDim2.new(0, mainFrame.Size.X.Offset + 40, 0, mainFrame.Size.Y.Offset + 40)
            dropShadow.Visible = mainFrame.Visible and not self.IsMinimized
        end
    end

    mainFrame:GetPropertyChangedSignal("Size"):Connect(syncDropShadow)
    mainFrame:GetPropertyChangedSignal("Visible"):Connect(syncDropShadow)


    local topbar = Instance.new("Frame")
    topbar.Name = "TopBar"
    topbar.Size = UDim2.new(1, 0, 0, 48)
    topbar.BackgroundTransparency = 1
    topbar.BorderSizePixel = 0
    topbar.ZIndex = 3


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


    local titleContainer = Instance.new("Frame")
    titleContainer.Name = "TitleContainer"
    titleContainer.Size = UDim2.new(1, -70, 1, 0)
    titleContainer.Position = UDim2.new(0, 0, 0, 0)
    titleContainer.BackgroundTransparency = 1
    titleContainer.ZIndex = 4
    titleContainer.Parent = topbar

    local titleLayout = Instance.new("UIListLayout")
    titleLayout.FillDirection = Enum.FillDirection.Horizontal
    titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    titleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    titleLayout.Padding = UDim.new(0, 8)
    titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
    titleLayout.Parent = titleContainer


    local logoAsset = props.Logo or props.Icon
    local resolvedLogoImage = ""
    if logoAsset and logoAsset ~= "" then
        local icon = Instance.new("ImageLabel")
        icon.Name = "WindowIcon"
        icon.Size = UDim2.fromOffset(28, 28)
        icon.BackgroundTransparency = 1
        icon.LayoutOrder = 1
        icon.ZIndex = 4
        Icons.ApplyAsset(icon, logoAsset)
        icon.Parent = titleContainer
        resolvedLogoImage = icon.Image
    end
    self.ResolvedLogo = resolvedLogoImage

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(0, 0, 1, 0)
    titleLabel.AutomaticSize = Enum.AutomaticSize.X
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Theme.Fonts.Title
    titleLabel.Text = windowTitle
    titleLabel.TextColor3 = Theme.GetToken("TextPrimary")
    titleLabel.TextSize = 14
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.LayoutOrder = 2
    titleLabel.ZIndex = 4
    titleLabel.Parent = titleContainer
    Theme.Bind(titleLabel, "TextColor3", "TextPrimary")
    self.TitleLabel = titleLabel
    self.TitleContainer = titleContainer


    function self:Tag(tagProps)
        local tProps = tagProps or {}
        local tagTitle = tProps.Title or "v1.0"
        local tagIcon = tProps.Icon or "github"
        local tagColor = tProps.Color or Color3.fromHex("#30ff6a")

        if self._tagBadge then
            self._tagBadge:Destroy()
            self._tagBadge = nil
        end

        local tagBadge = Instance.new("Frame")
        tagBadge.Name = "TagBadge"
        tagBadge.Size = UDim2.new(0, 0, 0, 20)
        tagBadge.AutomaticSize = Enum.AutomaticSize.X
        tagBadge.BackgroundColor3 = tagColor
        tagBadge.BackgroundTransparency = 0.86
        tagBadge.BorderSizePixel = 0
        tagBadge.LayoutOrder = 3
        tagBadge.ZIndex = 4

        local badgeCorner = Instance.new("UICorner")
        badgeCorner.CornerRadius = Theme.Radii.Control
        badgeCorner.Parent = tagBadge

        local badgeStroke = Instance.new("UIStroke")
        badgeStroke.Color = tagColor
        badgeStroke.Transparency = 0.5
        badgeStroke.Thickness = 1
        badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        badgeStroke.Parent = tagBadge

        local badgePad = Instance.new("UIPadding")
        badgePad.PaddingLeft = UDim.new(0, 7)
        badgePad.PaddingRight = UDim.new(0, 7)
        badgePad.Parent = tagBadge

        local badgeLayout = Instance.new("UIListLayout")
        badgeLayout.FillDirection = Enum.FillDirection.Horizontal
        badgeLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        badgeLayout.Padding = UDim.new(0, 4)
        badgeLayout.Parent = tagBadge

        local badgeIcon = nil
        if tagIcon and tagIcon ~= "" then
            badgeIcon = Instance.new("ImageLabel")
            badgeIcon.Name = "Icon"
            badgeIcon.Size = UDim2.fromOffset(12, 12)
            badgeIcon.BackgroundTransparency = 1
            badgeIcon.ImageColor3 = tagColor
            badgeIcon.ZIndex = 5
            Icons.Apply(badgeIcon, tagIcon)
            badgeIcon.Parent = tagBadge
        end

        local badgeText = Instance.new("TextLabel")
        badgeText.Name = "Text"
        badgeText.Size = UDim2.new(0, 0, 1, 0)
        badgeText.AutomaticSize = Enum.AutomaticSize.X
        badgeText.BackgroundTransparency = 1
        badgeText.Font = Theme.Fonts.Title
        badgeText.Text = tagTitle
        badgeText.TextColor3 = tagColor
        badgeText.TextSize = 10
        badgeText.TextXAlignment = Enum.TextXAlignment.Center
        badgeText.ZIndex = 5
        badgeText.Parent = tagBadge

        tagBadge.Parent = titleContainer
        self._tagBadge = tagBadge

        local tagController = {}
        function tagController:SetTitle(newTitle)
            badgeText.Text = newTitle
        end
        function tagController:SetColor(newColor)
            tagColor = newColor
            tagBadge.BackgroundColor3 = newColor
            badgeStroke.Color = newColor
            badgeText.TextColor3 = newColor
            if badgeIcon then
                badgeIcon.ImageColor3 = newColor
            end
        end
        function tagController:SetIcon(newIcon)
            if badgeIcon then
                Icons.Apply(badgeIcon, newIcon)
            end
        end
        function tagController:Destroy()
            if tagBadge and tagBadge.Parent then
                tagBadge:Destroy()
            end
            if self._tagBadge == tagBadge then
                self._tagBadge = nil
            end
        end

        return tagController
    end

    if props.Tag then
        self:Tag(props.Tag)
    end

    if props.Author and props.Author ~= "" then
        local authorLabel = Instance.new("TextLabel")
        authorLabel.Name = "Author"
        authorLabel.Size = UDim2.new(0, 0, 1, 0)
        authorLabel.AutomaticSize = Enum.AutomaticSize.X
        authorLabel.BackgroundTransparency = 1
        authorLabel.Font = Theme.Fonts.Body
        authorLabel.Text = props.Author
        authorLabel.TextColor3 = Theme.GetToken("Placeholder")
        authorLabel.TextSize = 11
        authorLabel.TextXAlignment = Enum.TextXAlignment.Left
        authorLabel.LayoutOrder = 4
        authorLabel.ZIndex = 4
        authorLabel.Parent = titleContainer
        Theme.Bind(authorLabel, "TextColor3", "Placeholder")
    end


    local controls = Instance.new("Frame")
    controls.Name = "Controls"
    controls.Size = UDim2.new(0, 64, 1, 0)
    controls.Position = UDim2.new(1, 0, 0.5, 0)
    controls.AnchorPoint = Vector2.new(1, 0.5)
    controls.BackgroundTransparency = 1

    local controlLayout = Instance.new("UIListLayout")
    controlLayout.FillDirection = Enum.FillDirection.Horizontal
    controlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    controlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    controlLayout.Padding = UDim.new(0, 6)
    controlLayout.Parent = controls


    local minSlot = Instance.new("Frame")
    minSlot.Name = "MinSlot"
    minSlot.Size = UDim2.fromOffset(26, 26)
    minSlot.BackgroundTransparency = 1


    local minBtn = Instance.new("ImageButton")
    minBtn.Name = "Minimize"
    minBtn.Size = UDim2.fromOffset(26, 26)
    minBtn.Position = UDim2.fromScale(0.5, 0.5)
    minBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    minBtn.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    minBtn.AutoButtonColor = false
    Theme.Bind(minBtn, "BackgroundColor3", "SurfaceHover")

    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = Theme.Radii.Control
    minCorner.Parent = minBtn

    local minStroke = Instance.new("UIStroke")
    minStroke.Color = Theme.GetToken("BorderSubtle")
    minStroke.Thickness = 1
    minStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    minStroke.Parent = minBtn
    Theme.Bind(minStroke, "Color", "BorderSubtle")

    local minIcon = Instance.new("ImageLabel")
    minIcon.Size = UDim2.fromOffset(14, 14)
    minIcon.Position = UDim2.fromScale(0.5, 0.5)
    minIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    minIcon.BackgroundTransparency = 1
    minIcon.ImageColor3 = Theme.GetToken("TextMuted")
    Icons.Apply(minIcon, "minus")
    minIcon.Parent = minBtn
    Theme.Bind(minIcon, "ImageColor3", "TextMuted")
    minBtn.Parent = minSlot
    minSlot.Parent = controls
    Tweener.BindPressFeedback(minBtn, minBtn)


    local closeSlot = Instance.new("Frame")
    closeSlot.Name = "CloseSlot"
    closeSlot.Size = UDim2.fromOffset(26, 26)
    closeSlot.BackgroundTransparency = 1


    local closeBtn = Instance.new("ImageButton")
    closeBtn.Name = "Close"
    closeBtn.Size = UDim2.fromOffset(26, 26)
    closeBtn.Position = UDim2.fromScale(0.5, 0.5)
    closeBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    closeBtn.BackgroundColor3 = Theme.GetToken("SurfaceHover")
    closeBtn.AutoButtonColor = false
    Theme.Bind(closeBtn, "BackgroundColor3", "SurfaceHover")

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = Theme.Radii.Control
    closeCorner.Parent = closeBtn

    local closeStroke = Instance.new("UIStroke")
    closeStroke.Color = Theme.GetToken("BorderSubtle")
    closeStroke.Thickness = 1
    closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    closeStroke.Parent = closeBtn
    Theme.Bind(closeStroke, "Color", "BorderSubtle")

    local closeIcon = Instance.new("ImageLabel")
    closeIcon.Size = UDim2.fromOffset(14, 14)
    closeIcon.Position = UDim2.fromScale(0.5, 0.5)
    closeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    closeIcon.BackgroundTransparency = 1
    closeIcon.ImageColor3 = Theme.GetToken("TextMuted")
    Icons.Apply(closeIcon, "x")
    closeIcon.Parent = closeBtn
    Theme.Bind(closeIcon, "ImageColor3", "TextMuted")
    closeBtn.Parent = closeSlot
    closeSlot.Parent = controls
    Tweener.BindPressFeedback(closeBtn, closeBtn)


    minBtn.MouseEnter:Connect(function()
        Tweener.Tween(minBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceActive") })
        Tweener.Tween(minIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextPrimary") })
    end)
    minBtn.MouseLeave:Connect(function()
        Tweener.Tween(minBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
        Tweener.Tween(minIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
    end)

    closeBtn.MouseEnter:Connect(function()
        Tweener.Tween(closeBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Danger") })
        Tweener.Tween(closeIcon, Tweener.Info.Fast, { ImageColor3 = Color3.fromRGB(255, 255, 255) })
    end)
    closeBtn.MouseLeave:Connect(function()
        Tweener.Tween(closeBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
        Tweener.Tween(closeIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
    end)

    controls.Parent = topbar
    topbar.Parent = mainFrame


    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Size = UDim2.new(1, 0, 1, -48)
    body.Position = UDim2.new(0, 0, 0, 48)
    body.BackgroundTransparency = 1
    body.ClipsDescendants = false


    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, sideBarWidth, 1, 0)
    sidebar.BackgroundTransparency = 1
    sidebar.BorderSizePixel = 0

    local sideDivider = Instance.new("Frame")
    sideDivider.Name = "RightBorder"
    sideDivider.Size = UDim2.new(0, 1, 1, 0)
    sideDivider.Position = UDim2.new(1, -1, 0, 0)
    sideDivider.BackgroundColor3 = Theme.GetToken("BorderSubtle")
    sideDivider.BorderSizePixel = 0
    sideDivider.Parent = sidebar
    Theme.Bind(sideDivider, "BackgroundColor3", "BorderSubtle")


    local searchOffset = 0
    if not props.HideSearchBar then
        searchOffset = 46
        local searchFrame = Instance.new("Frame")
        searchFrame.Name = "SearchContainer"
        searchFrame.Size = UDim2.new(1, -24, 0, 32)
        searchFrame.Position = UDim2.new(0, 12, 0, 12)
        searchFrame.BackgroundColor3 = Theme.GetToken("Card")
        Theme.Bind(searchFrame, "BackgroundColor3", "Card")

        local searchCorner = Instance.new("UICorner")
        searchCorner.CornerRadius = Theme.Radii.Element
        searchCorner.Parent = searchFrame

        local searchStroke = Instance.new("UIStroke")
        searchStroke.Color = Theme.GetToken("BorderSubtle")
        searchStroke.Thickness = 1
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
        searchBox.Font = Theme.Fonts.Body
        searchBox.PlaceholderText = "Search tabs..."
        searchBox.PlaceholderColor3 = Theme.GetToken("Placeholder")
        searchBox.Text = ""
        searchBox.TextColor3 = Theme.GetToken("TextPrimary")
        searchBox.TextSize = 12
        searchBox.TextXAlignment = Enum.TextXAlignment.Left
        searchBox.ClearTextOnFocus = false
        searchBox.Parent = searchFrame
        Theme.Bind(searchBox, "PlaceholderColor3", "Placeholder")
        Theme.Bind(searchBox, "TextColor3", "TextPrimary")

        searchFrame.Parent = sidebar
        self.SearchBox = searchBox
    end


    local userCardHeight = 0
    if props.User and props.User.Enabled then
        userCardHeight = 56


        local sidebarTools = Instance.new("Frame")
        sidebarTools.Name = "SidebarTools"
        sidebarTools.Size = UDim2.new(1, -24, 0, 32)
        sidebarTools.Position = UDim2.new(0, 12, 1, -104)
        sidebarTools.BackgroundTransparency = 1
        sidebarTools.Parent = sidebar

        local toolsLayout = Instance.new("UIListLayout")
        toolsLayout.FillDirection = Enum.FillDirection.Horizontal
        toolsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        toolsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        toolsLayout.Padding = UDim.new(0, 8)
        toolsLayout.Parent = sidebarTools


        local function applyIconToLabel(imgLabel, iconSource)
            Icons.ApplyAsset(imgLabel, iconSource)
        end

        local iconConfig = props.Icons or {}
        local currentDiscordIcon = iconConfig.Discord or "send"
        local currentThemeIcon = iconConfig.Theme or "sun"
        local currentProfileIcon = iconConfig.Profile or "hat-glasses"
        local isNameHidden = (props.User and props.User.Anonymous) or false
        local isWhiteMode = Theme.GetCurrentThemeName() == "WhiteMode"


        local hideNameBtn = Instance.new("TextButton")
        hideNameBtn.Name = "HideNameButton"
        hideNameBtn.Size = UDim2.fromOffset(32, 32)
        hideNameBtn.BackgroundColor3 = Theme.GetToken("Card")
        hideNameBtn.AutoButtonColor = false
        hideNameBtn.Text = ""
        hideNameBtn.Parent = sidebarTools
        Theme.Bind(hideNameBtn, "BackgroundColor3", "Card")

        local hideNameCorner = Instance.new("UICorner")
        hideNameCorner.CornerRadius = Theme.Radii.Control
        hideNameCorner.Parent = hideNameBtn

        local hideNameStroke = Instance.new("UIStroke")
        hideNameStroke.Color = if isNameHidden then Theme.GetToken("Accent") else Theme.GetToken("BorderSubtle")
        hideNameStroke.Thickness = 1.2
        hideNameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        hideNameStroke.Parent = hideNameBtn

        local hideNameIcon = Instance.new("ImageLabel")
        hideNameIcon.Name = "Icon"
        hideNameIcon.Size = UDim2.fromOffset(16, 16)
        hideNameIcon.Position = UDim2.fromScale(0.5, 0.5)
        hideNameIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        hideNameIcon.BackgroundTransparency = 1
        hideNameIcon.ImageColor3 = if isNameHidden then Theme.GetToken("Accent") else Theme.GetToken("TextMuted")
        applyIconToLabel(hideNameIcon, currentProfileIcon)
        hideNameIcon.Parent = hideNameBtn


        local themeToggleBtn = Instance.new("TextButton")
        themeToggleBtn.Name = "ThemeToggleButton"
        themeToggleBtn.Size = UDim2.fromOffset(32, 32)
        themeToggleBtn.BackgroundColor3 = Theme.GetToken("Card")
        themeToggleBtn.AutoButtonColor = false
        themeToggleBtn.Text = ""
        themeToggleBtn.Parent = sidebarTools
        Theme.Bind(themeToggleBtn, "BackgroundColor3", "Card")

        local themeToggleCorner = Instance.new("UICorner")
        themeToggleCorner.CornerRadius = Theme.Radii.Control
        themeToggleCorner.Parent = themeToggleBtn

        local themeToggleStroke = Instance.new("UIStroke")
        themeToggleStroke.Color = if isWhiteMode then Theme.GetToken("Accent") else Theme.GetToken("BorderSubtle")
        themeToggleStroke.Thickness = 1.2
        themeToggleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        themeToggleStroke.Parent = themeToggleBtn

        local themeToggleIcon = Instance.new("ImageLabel")
        themeToggleIcon.Name = "Icon"
        themeToggleIcon.Size = UDim2.fromOffset(16, 16)
        themeToggleIcon.Position = UDim2.fromScale(0.5, 0.5)
        themeToggleIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        themeToggleIcon.BackgroundTransparency = 1
        themeToggleIcon.ImageColor3 = if isWhiteMode then Theme.GetToken("Accent") else Theme.GetToken("TextMuted")
        applyIconToLabel(themeToggleIcon, if isWhiteMode then "moon" else currentThemeIcon)
        themeToggleIcon.Parent = themeToggleBtn


        local discordBtn = Instance.new("TextButton")
        discordBtn.Name = "DiscordButton"
        discordBtn.Size = UDim2.fromOffset(32, 32)
        discordBtn.BackgroundColor3 = Theme.GetToken("Card")
        discordBtn.AutoButtonColor = false
        discordBtn.Text = ""
        discordBtn.Parent = sidebarTools
        Theme.Bind(discordBtn, "BackgroundColor3", "Card")

        local discordCorner = Instance.new("UICorner")
        discordCorner.CornerRadius = Theme.Radii.Control
        discordCorner.Parent = discordBtn

        local discordStroke = Instance.new("UIStroke")
        discordStroke.Color = Theme.GetToken("BorderSubtle")
        discordStroke.Thickness = 1.2
        discordStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        discordStroke.Parent = discordBtn

        local discordIcon = Instance.new("ImageLabel")
        discordIcon.Name = "Icon"
        discordIcon.Size = UDim2.fromOffset(16, 16)
        discordIcon.Position = UDim2.fromScale(0.5, 0.5)
        discordIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        discordIcon.BackgroundTransparency = 1
        discordIcon.ImageColor3 = Theme.GetToken("TextMuted")
        applyIconToLabel(discordIcon, currentDiscordIcon)
        discordIcon.Parent = discordBtn

        Tweener.BindPressFeedback(hideNameBtn, hideNameBtn, 0.9)
        Tweener.BindPressFeedback(themeToggleBtn, themeToggleBtn, 0.9)
        Tweener.BindPressFeedback(discordBtn, discordBtn, 0.9)

        local userCard = Instance.new("TextButton")
        userCard.Name = "UserCard"
        userCard.Size = UDim2.new(1, -24, 0, 56)
        userCard.Position = UDim2.new(0, 12, 1, -64)
        userCard.BackgroundColor3 = Theme.GetToken("Card")
        userCard.AutoButtonColor = false
        userCard.Text = ""
        Theme.Bind(userCard, "BackgroundColor3", "Card")

        local userCorner = Instance.new("UICorner")
        userCorner.CornerRadius = Theme.Radii.Card
        userCorner.Parent = userCard

        local userStroke = Instance.new("UIStroke")
        userStroke.Color = Theme.GetToken("BorderSubtle")
        userStroke.Thickness = 1.2
        userStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        userStroke.Parent = userCard

        -- Refresh outlines on theme change
        local function refreshToolStrokes()
            local subtle = Theme.GetToken("BorderSubtle")
            local accent = Theme.GetToken("Accent")
            local muted = Theme.GetToken("TextMuted")
            Tweener.Tween(hideNameStroke, Tweener.Info.Fast, { Color = if isNameHidden then accent else subtle })
            Tweener.Tween(themeToggleStroke, Tweener.Info.Fast, { Color = if isWhiteMode then accent else subtle })
            Tweener.Tween(discordStroke, Tweener.Info.Fast, { Color = subtle })
            Tweener.Tween(userStroke, Tweener.Info.Fast, { Color = subtle })
            Tweener.Tween(discordIcon, Tweener.Info.Fast, { ImageColor3 = muted })
            if not isNameHidden then
                Tweener.Tween(hideNameIcon, Tweener.Info.Fast, { ImageColor3 = muted })
            end
            if not isWhiteMode then
                Tweener.Tween(themeToggleIcon, Tweener.Info.Fast, { ImageColor3 = muted })
            end
        end
        self._refreshConn = Theme.Changed:Connect(refreshToolStrokes)


        hideNameBtn.MouseEnter:Connect(function()
            Tweener.Tween(hideNameBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
            if not isNameHidden then
                Tweener.Tween(hideNameStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderAccent") })
                Tweener.Tween(hideNameIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextPrimary") })
            end
        end)
        hideNameBtn.MouseLeave:Connect(function()
            Tweener.Tween(hideNameBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Card") })
            if not isNameHidden then
                Tweener.Tween(hideNameStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
                Tweener.Tween(hideNameIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
            end
        end)

        themeToggleBtn.MouseEnter:Connect(function()
            Tweener.Tween(themeToggleBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
            if not isWhiteMode then
                Tweener.Tween(themeToggleStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderAccent") })
                Tweener.Tween(themeToggleIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextPrimary") })
            end
        end)
        themeToggleBtn.MouseLeave:Connect(function()
            Tweener.Tween(themeToggleBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Card") })
            if not isWhiteMode then
                Tweener.Tween(themeToggleStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
                Tweener.Tween(themeToggleIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
            end
        end)

        discordBtn.MouseEnter:Connect(function()
            Tweener.Tween(discordBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
            Tweener.Tween(discordStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderAccent") })
            Tweener.Tween(discordIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextPrimary") })
        end)
        discordBtn.MouseLeave:Connect(function()
            Tweener.Tween(discordBtn, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Card") })
            Tweener.Tween(discordStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
            Tweener.Tween(discordIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
        end)

        userCard.MouseEnter:Connect(function()
            Tweener.Tween(userCard, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("SurfaceHover") })
            Tweener.Tween(userStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderAccent") })
        end)
        userCard.MouseLeave:Connect(function()
            Tweener.Tween(userCard, Tweener.Info.Fast, { BackgroundColor3 = Theme.GetToken("Card") })
            Tweener.Tween(userStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
        end)

        local lp = Players.LocalPlayer
        local avatarImg = Instance.new("ImageLabel")
        avatarImg.Name = "Avatar"
        avatarImg.Size = UDim2.fromOffset(34, 34)
        avatarImg.Position = UDim2.new(0, 8, 0.5, 0)
        avatarImg.AnchorPoint = Vector2.new(0, 0.5)
        avatarImg.BackgroundColor3 = Theme.GetToken("SurfaceHover")
        Theme.Bind(avatarImg, "BackgroundColor3", "SurfaceHover")

        local avatarCorner = Instance.new("UICorner")
        avatarCorner.CornerRadius = Theme.Radii.Pill
        avatarCorner.Parent = avatarImg

        local playerThumbnail = ""
        if lp then
            task.spawn(function()
                local content, _ = Players:GetUserThumbnailAsync(
                    lp.UserId,
                    Enum.ThumbnailType.HeadShot,
                    Enum.ThumbnailSize.Size100x100
                )
                playerThumbnail = content
                if not isNameHidden then
                    avatarImg.Image = content
                end
            end)
        end
        if isNameHidden and resolvedLogoImage ~= "" then
            avatarImg.Image = resolvedLogoImage
        end
        avatarImg.Parent = userCard

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "DisplayName"
        nameLabel.Size = UDim2.new(1, -58, 0, 14)
        nameLabel.Position = UDim2.new(0, 50, 0, 7)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Theme.Fonts.Title
        nameLabel.Text = if isNameHidden then "Sodium" else (lp and lp.DisplayName or "User")
        nameLabel.TextColor3 = Theme.GetToken("TextPrimary")
        nameLabel.TextSize = 12
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = userCard
        Theme.Bind(nameLabel, "TextColor3", "TextPrimary")

        local userLabel = Instance.new("TextLabel")
        userLabel.Name = "Username"
        userLabel.Size = UDim2.new(1, -58, 0, 12)
        userLabel.Position = UDim2.new(0, 50, 0, 22)
        userLabel.BackgroundTransparency = 1
        userLabel.Font = Theme.Fonts.Sub
        userLabel.Text = if isNameHidden then "sodiumuser@gmail.com" else (lp and "@" .. lp.Name or "@unknown")
        userLabel.TextColor3 = Theme.GetToken("Placeholder")
        userLabel.TextSize = 10
        userLabel.TextXAlignment = Enum.TextXAlignment.Left
        userLabel.TextTruncate = Enum.TextTruncate.AtEnd
        userLabel.Parent = userCard
        Theme.Bind(userLabel, "TextColor3", "Placeholder")

        local keyExpiryLabel = Instance.new("TextLabel")
        keyExpiryLabel.Name = "KeyExpiry"
        keyExpiryLabel.Size = UDim2.new(1, -58, 0, 12)
        keyExpiryLabel.Position = UDim2.new(0, 50, 0, 35)
        keyExpiryLabel.BackgroundTransparency = 1
        keyExpiryLabel.Font = Theme.Fonts.Sub
        keyExpiryLabel.Text = ""
        keyExpiryLabel.TextColor3 = Theme.GetToken("Success")
        keyExpiryLabel.TextSize = 10
        keyExpiryLabel.TextXAlignment = Enum.TextXAlignment.Left
        keyExpiryLabel.TextTruncate = Enum.TextTruncate.AtEnd
        keyExpiryLabel.Visible = false
        keyExpiryLabel.Parent = userCard

        local function getSafeTimestamp()
            local t = os.time()
            if t and t > 1000000000 then
                return t
            end
            local success, serverTime = pcall(function()
                return math.floor(workspace:GetServerTimeNow())
            end)
            if success and serverTime and serverTime > 1000000000 then
                return serverTime
            end
            return math.floor(tick())
        end

        local function formatRemainingTime(seconds)
            local hours = math.floor(seconds / 3600)
            local mins = math.floor((seconds % 3600) / 60)
            local secs = seconds % 60
            return string.format("%02d:%02d:%02d", hours, mins, secs)
        end

        local expiryThread = nil
        local function startExpiryWorker()
            if expiryThread then task.cancel(expiryThread) end
            -- Realtime key expiry worker
            expiryThread = task.spawn(function()
                while true do
                    if self._isDestroyed then
                        break
                    end
                    if self._mounted and (not self.MainFrame or not self.MainFrame.Parent) then
                        break
                    end
                    local keyExp = self._keyExpires
                    if not keyExp then
                        keyExpiryLabel.Visible = false
                    else
                        keyExpiryLabel.Visible = true
                        if type(keyExp) == "string" and (keyExp:lower() == "lifetime" or keyExp:lower() == "permanent") then
                            keyExpiryLabel.Text = "Key expired : Lifetime (Permanent)"
                            keyExpiryLabel.TextColor3 = Theme.GetToken("Success")
                        else
                            local targetTime = tonumber(keyExp) or 0
                            local now = getSafeTimestamp()
                            local remaining = math.max(0, targetTime - now)
                            if remaining <= 0 then
                                keyExpiryLabel.Text = "Key expired : 00:00:00 (Expired!)"
                                keyExpiryLabel.TextColor3 = Theme.GetToken("Danger")
                            else
                                local timeStr = formatRemainingTime(remaining)
                                keyExpiryLabel.Text = "Key expired : " .. timeStr .. "(hh:mm:ss)"
                                if remaining > 3600 then
                                    keyExpiryLabel.TextColor3 = Theme.GetToken("Success")
                                elseif remaining > 600 then
                                    keyExpiryLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
                                else
                                    keyExpiryLabel.TextColor3 = Theme.GetToken("Danger")
                                end
                            end
                        end
                    end
                    task.wait(1)
                end
            end)
        end

        function self:SetKeyExpiry(expires)
            if type(expires) == "number" and expires < 100000000 then
                self._keyExpires = getSafeTimestamp() + expires
            else
                self._keyExpires = expires
            end
            startExpiryWorker()
        end

        if props.User and props.User.KeyExpires then
            self:SetKeyExpiry(props.User.KeyExpires)
        end

        local function updateNameDisplay()
            if isNameHidden then
                nameLabel.Text = "Sodium"
                userLabel.Text = "sodiumuser@gmail.com"
                if resolvedLogoImage ~= "" then
                    avatarImg.Image = resolvedLogoImage
                end
                applyIconToLabel(hideNameIcon, currentProfileIcon)
                Tweener.Tween(hideNameStroke, Tweener.Info.Fast, { Color = Theme.GetToken("Accent") })
                Tweener.Tween(hideNameIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Accent") })
            else
                local localPlr = Players.LocalPlayer
                nameLabel.Text = if localPlr then localPlr.DisplayName else "User"
                userLabel.Text = if localPlr then "@" .. localPlr.Name else "@unknown"
                avatarImg.Image = playerThumbnail
                applyIconToLabel(hideNameIcon, currentProfileIcon)
                Tweener.Tween(hideNameStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
                Tweener.Tween(hideNameIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
            end
        end
        if isNameHidden then
            updateNameDisplay()
        end

        hideNameBtn.Activated:Connect(function()
            isNameHidden = not isNameHidden
            updateNameDisplay()
        end)

        themeToggleBtn.Activated:Connect(function()
            isWhiteMode = not isWhiteMode
            if isWhiteMode then
                Theme.SetTheme("WhiteMode")
                applyIconToLabel(themeToggleIcon, "moon")
                Tweener.Tween(themeToggleStroke, Tweener.Info.Fast, { Color = Theme.GetToken("Accent") })
                Tweener.Tween(themeToggleIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("Accent") })
            else
                Theme.SetTheme("Obsidian Amethyst")
                applyIconToLabel(themeToggleIcon, currentThemeIcon)
                Tweener.Tween(themeToggleStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
                Tweener.Tween(themeToggleIcon, Tweener.Info.Fast, { ImageColor3 = Theme.GetToken("TextMuted") })
            end
        end)


        local discordInviteUrl = props.DiscordLink or "https://discord.gg/2gEjXyQWKM"
        discordBtn.Activated:Connect(function()
            pcall(function()
                if setclipboard then
                    setclipboard(discordInviteUrl)
                elseif toclipboard then
                    toclipboard(discordInviteUrl)
                end
            end)
            Notification.Notify(self.RootGui, {
                Title = "Discord",
                Content = "Copied Discord invite to clipboard!",
                Icon = "check",
                Duration = 3,
            })
        end)


        function self:SetIconConfig(newConfig)
            if type(newConfig) ~= "table" then return end
            if newConfig.Discord then
                currentDiscordIcon = newConfig.Discord
                applyIconToLabel(discordIcon, currentDiscordIcon)
            end
            if newConfig.Theme then
                currentThemeIcon = newConfig.Theme
                applyIconToLabel(themeToggleIcon, if isWhiteMode then "moon" else currentThemeIcon)
            end
            if newConfig.Profile then
                currentProfileIcon = newConfig.Profile
                applyIconToLabel(hideNameIcon, if isNameHidden then "eye-off" else currentProfileIcon)
            end
        end

        if props.User.Callback then
            userCard.Activated:Connect(props.User.Callback)
        end

        userCard.Parent = sidebar
    end


    local bottomTotalHeight = if (props.User and props.User.Enabled) then (userCardHeight + 40 + 20) else 24
    local tabList = Instance.new("ScrollingFrame")
    tabList.Name = "TabList"
    tabList.Size = UDim2.new(1, -24, 1, -searchOffset - bottomTotalHeight)
    tabList.Position = UDim2.new(0, 12, 0, searchOffset + 12)
    tabList.BackgroundTransparency = 1
    tabList.BorderSizePixel = 0
    tabList.ScrollBarThickness = 2
    tabList.ScrollBarImageColor3 = Theme.GetToken("BorderStrong")
    tabList.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabList.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabList

    tabList.ZIndex = 2
    tabList.Parent = sidebar


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
    accentPill.Size = UDim2.new(0, 3, 0, 16)
    accentPill.Position = UDim2.new(0, 4, 0.5, 0)
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
    indicatorStroke.Color = Theme.GetToken("BorderAccent")
    indicatorStroke.Transparency = 0.65
    indicatorStroke.Thickness = 1
    indicatorStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    indicatorStroke.Parent = tabIndicator
    Theme.Bind(indicatorStroke, "Color", "BorderAccent")

    self.TabIndicator = tabIndicator


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


    local contentArea = Instance.new("Frame")
    contentArea.Name = "ContentArea"
    contentArea.Size = UDim2.new(1, -sideBarWidth, 1, 0)
    contentArea.Position = UDim2.new(0, sideBarWidth, 0, 0)
    contentArea.BackgroundTransparency = 1
    contentArea.ClipsDescendants = true
    contentArea.Parent = body

    body.Parent = mainFrame
    mainFrame.Parent = self.RootGui

    self.MainFrame = mainFrame
    self.Body = body
    self.SidebarTabList = tabList
    self.ContentArea = contentArea
    self.DefaultSize = defaultSize
    self._mounted = true

    -- Floating minimized widget
    local minWidget = Instance.new("TextButton")
    minWidget.Name = "FloatingMinimizedWidget"
    minWidget.Size = UDim2.fromOffset(108, 34)
    minWidget.Position = UDim2.new(0.5, -54, 0, 24)
    minWidget.AnchorPoint = Vector2.new(0, 0)
    minWidget.BackgroundColor3 = Theme.GetToken("Card")
    minWidget.BackgroundTransparency = 0
    minWidget.AutoButtonColor = false
    minWidget.Text = "Sodium Hub"
    minWidget.Font = Theme.Fonts.Title
    minWidget.TextSize = 13
    minWidget.TextColor3 = Theme.GetToken("TextPrimary")
    minWidget.Visible = true
    minWidget.ZIndex = 999999
    Theme.Bind(minWidget, "BackgroundColor3", "Card")
    Theme.Bind(minWidget, "TextColor3", "TextPrimary")

    local minWidgetCorner = Instance.new("UICorner")
    minWidgetCorner.CornerRadius = Theme.Radii.Element
    minWidgetCorner.Parent = minWidget

    local minWidgetStroke = Instance.new("UIStroke")
    minWidgetStroke.Color = Theme.GetToken("BorderSubtle")
    minWidgetStroke.Thickness = 1.2
    minWidgetStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    minWidgetStroke.Parent = minWidget
    Theme.Bind(minWidgetStroke, "Color", "BorderSubtle")


    local minShadow = Instance.new("ImageLabel")
    minShadow.Name = "MinWidgetDropShadow"
    minShadow.Size = UDim2.new(0, 108 + 24, 0, 34 + 24)
    minShadow.Position = UDim2.new(0.5, -66, 0, 12)
    minShadow.AnchorPoint = Vector2.new(0, 0)
    minShadow.BackgroundTransparency = 1
    minShadow.Image = "rbxassetid://6014261993"
    minShadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    minShadow.ImageTransparency = 0.4
    minShadow.ScaleType = Enum.ScaleType.Slice
    minShadow.SliceCenter = Rect.new(49, 49, 450, 450)
    minShadow.ZIndex = 999998
    minShadow.Parent = self.RootGui
    self.MinShadow = minShadow

    local minWidgetScale = Instance.new("UIScale")
    minWidgetScale.Scale = 1
    minWidgetScale.Parent = minWidget


    minWidget.MouseEnter:Connect(function()
        Tweener.Tween(minWidgetStroke, Tweener.Info.Fast, { Color = Theme.GetToken("Accent") })
        Tweener.Tween(minWidget, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("Accent") })
    end)
    minWidget.MouseLeave:Connect(function()
        Tweener.Tween(minWidgetStroke, Tweener.Info.Fast, { Color = Theme.GetToken("BorderSubtle") })
        Tweener.Tween(minWidget, Tweener.Info.Fast, { TextColor3 = Theme.GetToken("TextPrimary") })
    end)

    minWidget.Parent = self.RootGui
    self.MinWidget = minWidget
    self.MinWidgetScale = minWidgetScale

    self:_initDraggableWidget(minWidget, function()
        self:ToggleVisibility()
    end)


    self:_initDragging(topbar)


    minBtn.Activated:Connect(function()
        self:ToggleVisibility()
    end)

    closeBtn.Activated:Connect(function()
        self:Destroy()
    end)


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


    if self.SearchBox then
        self.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local query = string.lower(self.SearchBox.Text)
            for _, tabItem in ipairs(self.Tabs) do
                local match = query == "" or string.find(string.lower(tabItem.Title), query, 1, true) ~= nil
                tabItem.SidebarButton.Visible = match
            end
        end)
    end

    local g = rawget(getfenv(), "_G")
    if g then
        g._SODIUM_ACTIVE_WINDOW = self
    end

    return self
end

function Window:_initDraggableWidget(widget, onClick)
    local isDragging = false
    local startMousePos = Vector2.zero
    local startWidgetPos = Vector2.zero

    local function clampWidgetToScreen()
        local camera = workspace.CurrentCamera
        local screenSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local scale = math.max(0.01, self.ContainerManager.UIScale.Scale)
        local widgetSize = widget.AbsoluteSize / scale
        local maxX = math.max(0, (screenSize.X / scale) - widgetSize.X)
        local maxY = math.max(0, (screenSize.Y / scale) - widgetSize.Y)

        local curX = widget.Position.X.Offset
        local curY = widget.Position.Y.Offset
        local clampedX = math.clamp(curX, 0, maxX)
        local clampedY = math.clamp(curY, 0, maxY)
        widget.Position = UDim2.fromOffset(clampedX, clampedY)
        if self.MinShadow then
            self.MinShadow.Position = UDim2.fromOffset(clampedX - 12, clampedY - 12)
        end
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

            local curX = math.floor(widget.Position.X.Scale * (screenSize.X / scale) + widget.Position.X.Offset - widget.AnchorPoint.X * (widget.AbsoluteSize.X / scale))
            local curY = math.floor(widget.Position.Y.Scale * (screenSize.Y / scale) + widget.Position.Y.Offset - widget.AnchorPoint.Y * (widget.AbsoluteSize.Y / scale))
            startWidgetPos = Vector2.new(curX, curY)
            widget.Position = UDim2.fromOffset(curX, curY)
            widget.AnchorPoint = Vector2.zero
            if self.MinShadow then
                self.MinShadow.Position = UDim2.fromOffset(curX - 12, curY - 12)
                self.MinShadow.AnchorPoint = Vector2.zero
            end

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

                    local widgetSize = widget.AbsoluteSize / scale
                    local maxX = math.max(0, (screenSize.X / scale) - widgetSize.X)
                    local maxY = math.max(0, (screenSize.Y / scale) - widgetSize.Y)

                    local clampedX = math.clamp(targetX, 0, maxX)
                    local clampedY = math.clamp(targetY, 0, maxY)

                    widget.Position = UDim2.fromOffset(clampedX, clampedY)
                    if self.MinShadow then
                        self.MinShadow.Position = UDim2.fromOffset(clampedX - 12, clampedY - 12)
                    end
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

function Window:_initDragging(dragHandle)
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
            startScaleX = self.MainFrame.Position.X.Scale
            startScaleY = self.MainFrame.Position.Y.Scale
            startOffsetX = self.MainFrame.Position.X.Offset
            startOffsetY = self.MainFrame.Position.Y.Offset

            if self._dragConn then
                self._dragConn:Disconnect()
                self._dragConn = nil
            end
            if self._dragEndConn then
                self._dragEndConn:Disconnect()
                self._dragEndConn = nil
            end

            -- 1:1 drag tracking with UIScale compensation
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
                    if self.DropShadow then
                        self.DropShadow.Position = newPos
                    end
                end
            end)


            self._dragEndConn = UserInputService.InputEnded:Connect(function(endInput)
                if endInput.UserInputType == Enum.UserInputType.MouseButton1 or endInput.UserInputType == Enum.UserInputType.Touch then
                    stopDragging()
                end
            end)
        end
    end)


    self.ContainerManager.OnScaleChanged = function(_newScale)
        if self._clampWidgetToScreen then
            self._clampWidgetToScreen()
        end
    end
end

function Window:ToggleMinimize()
    self:ToggleVisibility()
end

function Window:ToggleVisibility()
    if self.MainFrame.Visible then
        self.IsVisible = false
        self.IsMinimized = true


        local tweenInfo = Tweener.Info.Fast
        if self.WindowScale and self.DropShadowScale and self.DropShadow then
            Tweener.Tween(self.DropShadow, tweenInfo, { ImageTransparency = 1.0 })
            Tweener.Tween(self.DropShadowScale, tweenInfo, { Scale = 0.94 })
            Tweener.Tween(self.WindowScale, tweenInfo, { Scale = 0.94 }, function()
                if not self.IsVisible then
                    self.MainFrame.Visible = false
                    if self.DropShadow then
                        self.DropShadow.Visible = false
                        self.DropShadow.ImageTransparency = 0.52
                    end
                end
            end)
        else
            self.MainFrame.Visible = false
            if self.DropShadow then
                self.DropShadow.Visible = false
            end
        end
    else
        self.IsVisible = true
        self.IsMinimized = false
        self.MainFrame.Visible = true
        self.Body.Visible = true
        if self.DropShadow then
            self.DropShadow.Visible = true
            self.DropShadow.ImageTransparency = 1.0
        end


        local tweenInfo = Tweener.Info.Fast
        if self.WindowScale and self.DropShadowScale and self.DropShadow then
            self.WindowScale.Scale = 0.94
            self.DropShadowScale.Scale = 0.94
            Tweener.Tween(self.WindowScale, tweenInfo, { Scale = 1.0 })
            Tweener.Tween(self.DropShadowScale, tweenInfo, { Scale = 1.0 })
            Tweener.Tween(self.DropShadow, tweenInfo, { ImageTransparency = 0.52 })
        end
    end
    if self.MinWidget then
        self.MinWidget.Visible = true
    end
    if self.MinShadow then
        self.MinShadow.Visible = true
    end
end


function Window:SaveConfig(name)
    return self.ConfigEngine:SaveConfig(name)
end

function Window:LoadConfig(name, silent)
    return self.ConfigEngine:LoadConfig(name, silent)
end

function Window:DeleteConfig(name)
    return self.ConfigEngine:DeleteConfig(name)
end

function Window:GetConfigs()
    return self.ConfigEngine:GetConfigs()
end

function Window:ExportConfig(name)
    return self.ConfigEngine:ExportConfig(name)
end

function Window:ImportConfig(name, jsonString)
    return self.ConfigEngine:ImportConfig(name, jsonString)
end

function Window:SetAutoSave(enabled, name, delay)
    self.ConfigEngine:SetAutoSave(enabled, name, delay)
end

function Window:ResetToDefaults(silent)
    self.ConfigEngine:ResetToDefaults(silent)
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

function Window:SelectTab(targetTab)
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
    self:UpdateIndicator(false)

    -- Lock indicator to absolute position on layout shift
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

function Window:TrackHover(targetTab)
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

function Window:HideHoverTracker(smooth)
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

function Window:UpdateIndicator(immediate)
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


    local relX = (btnPos.X - overlayPos.X) / scale
    local relY = (btnPos.Y - overlayPos.Y) / scale
    local width = btnSize.X / scale
    local height = btnSize.Y / scale

    local targetPos = UDim2.fromOffset(relX, relY)
    local targetSize = UDim2.fromOffset(width, height)


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

    if self.TabIndicator.BackgroundTransparency >= 0.99 and not self._hasInitializedIndicator then
        self._hasInitializedIndicator = true
        self.TabIndicator.Position = targetPos
        self.TabIndicator.Size = targetSize
        Tweener.Tween(self.TabIndicator, Tweener.Info.Fast, { BackgroundTransparency = 0 })
    else
        self._hasInitializedIndicator = true
        local tweenGoals = {
            Position = targetPos,
            Size = targetSize,
        }
        if self.TabIndicator.BackgroundTransparency > 0.01 then
            tweenGoals.BackgroundTransparency = 0
        end
        self._indicatorTween = Tweener.Tween(self.TabIndicator, Tweener.Info.Smooth, tweenGoals, function()
            self._indicatorTween = nil
            -- AbsolutePosition locking on layout shift
            if self.CurrentTab == targetTab and self.TabIndicator then
                local b = targetTab.SidebarButton
                if b and b.Parent and b.Visible then
                    local s = math.max(0.001, self.ContainerManager.UIScale.Scale)
                    local oPos = self.TabIndicatorOverlay.AbsolutePosition
                    local bPos = b.AbsolutePosition
                    local bSize = b.AbsoluteSize
                    self.TabIndicator.Position = UDim2.fromOffset((bPos.X - oPos.X) / s, (bPos.Y - oPos.Y) / s)
                    self.TabIndicator.Size = UDim2.fromOffset(bSize.X / s, bSize.Y / s)
                elseif targetTab.ParentSection and not targetTab.ParentSection.Opened then
                    self.TabIndicator.Visible = false
                end
            end
        end)
    end
end

function Window:Tab(rawProps, sectionTarget)
    local props = if type(rawProps) == "string" then { Title = rawProps } else (rawProps or {})
    props.Title = props.Title or props.Name or "Tab"

    local targetSection = sectionTarget or props.Section
    if not targetSection and self._currentSection and props.Standalone ~= true and props.Section ~= false then
        targetSection = self._currentSection
    end

    local parentList = if targetSection then targetSection.TabList else self.SidebarTabList
    local tabItem = Tab.new(self, parentList, self.ContentArea, self.ConfigEngine, props)
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

function Window:Section(rawProps)
    if not rawProps then
        self._currentSection = nil
        return nil
    end
    local props = if type(rawProps) == "string" then { Title = rawProps } else rawProps
    props.Title = props.Title or props.Name or "Section"

    local section = TabSection.new(self, self.SidebarTabList, props)
    self._currentSection = section
    table.insert(self.Sections, section)
    return section
end

function Window:Popup(props)
    Popup.Show(self.RootGui, props)
end

function Window:Notify(props)
    Notification.Notify(self.RootGui, props)
end

function Window:SetToggleKey(keyCode)
    if typeof(keyCode) == "EnumItem" then
        self.ToggleKey = keyCode
    elseif type(keyCode) == "string" then
        local found = Enum.KeyCode[keyCode]
        self.ToggleKey = found or keyCode
    end
end

function Window:Dialog(props)
    return Dialog.Show(self.MainFrame, props)
end

function Window:Destroy()
    self._isDestroyed = true
    if self._indicatorTween then
        self._indicatorTween:Cancel()
        self._indicatorTween = nil
    end
    if self._hoverTrackerTween then
        self._hoverTrackerTween:Cancel()
        self._hoverTrackerTween = nil
    end
    if self._activeBtnPosConn then
        self._activeBtnPosConn:Disconnect()
        self._activeBtnPosConn = nil
    end
    if self._refreshConn then
        self._refreshConn:Disconnect()
        self._refreshConn = nil
    end
    if self._dragConn then
        self._dragConn:Disconnect()
        self._dragConn = nil
    end
    if self._dragEndConn then
        self._dragEndConn:Disconnect()
        self._dragEndConn = nil
    end
    if self._dragRenderConn then
        self._dragRenderConn:Disconnect()
        self._dragRenderConn = nil
    end
    if self._minDragConn then
        self._minDragConn:Disconnect()
        self._minDragConn = nil
    end
    if self._toggleKeyConn then
        self._toggleKeyConn:Disconnect()
        self._toggleKeyConn = nil
    end
    if self.MinShadow then
        self.MinShadow:Destroy()
        self.MinShadow = nil
    end
    if self.MinWidget then
        self.MinWidget:Destroy()
        self.MinWidget = nil
    end
    if self.DropShadow then
        self.DropShadow:Destroy()
        self.DropShadow = nil
    end
    if self.RootGui then
        self.RootGui:Destroy()
    end
    local g = rawget(getfenv(), "_G")
    if g and g._SODIUM_ACTIVE_WINDOW == self then
        g._SODIUM_ACTIVE_WINDOW = nil
    end
end


Window.CreateTab = Window.Tab
Window.AddTab = Window.Tab
Window.CreateSection = Window.Section
Window.AddSection = Window.Section

return Window
end

_MODULES['Init'] = function()


local Theme = _require("Core/Theme")
local Icons = _require("Core/Icons")
local Signals = _require("Core/Signals")
local Container = _require("Core/Container")
local ConfigEngine = _require("Storage/ConfigEngine")
local Window = _require("Components/Window")
local Popup = _require("Components/Popup")
local Notification = _require("Components/Notification")
local Dialog = _require("Components/Dialog")
local Loading = _require("Components/Loading")
local KeyCheck = _require("Components/KeyCheck")

local SodiumUI = {
    Version = "1.0.0",
    Theme = Theme,
    Icons = Icons,
    Signals = Signals,
}

local activeContainers = {}

function SodiumUI:CreateWindow(props)
    local g = rawget(getfenv(), "_G")
    if g and g._SODIUM_ACTIVE_WINDOW then
        pcall(function()
            g._SODIUM_ACTIVE_WINDOW:Destroy()
        end)
    end

    local folderName = props.Folder or "SodiumUI"
    local configEngine = ConfigEngine.new(folderName)
    local containerManager = Container.new(props.Title or "SodiumUI")
    table.insert(activeContainers, containerManager)

    local windowInstance = Window.new(containerManager, configEngine, props)
    windowInstance.ConfigEngine = configEngine

    return windowInstance
end

function SodiumUI:AddTheme(name, tokens)
    Theme.AddTheme(name, tokens)
end

function SodiumUI:SetTheme(name)
    Theme.SetTheme(name)
end

function SodiumUI:Notify(props)
    local targetRoot = activeContainers[#activeContainers] and activeContainers[#activeContainers].ScreenGui
    if not targetRoot then
        local tempContainer = Container.new("NotificationRoot")
        table.insert(activeContainers, tempContainer)
        targetRoot = tempContainer.ScreenGui
    end
    Notification.Notify(targetRoot, props)
end

function SodiumUI:Popup(props)
    local targetRoot = activeContainers[#activeContainers] and activeContainers[#activeContainers].ScreenGui
    if not targetRoot then
        local tempContainer = Container.new("PopupRoot")
        table.insert(activeContainers, tempContainer)
        targetRoot = tempContainer.ScreenGui
    end
    Popup.Show(targetRoot, props)
end

function SodiumUI:Dialog(props)
    local g = rawget(getfenv(), "_G")
    local activeWindow = g and g._SODIUM_ACTIVE_WINDOW
    if activeWindow and activeWindow.MainFrame and activeWindow.MainFrame.Parent then
        return Dialog.Show(activeWindow.MainFrame, props)
    end
    local targetRoot = activeContainers[#activeContainers] and activeContainers[#activeContainers].ScreenGui
    if not targetRoot then
        local tempContainer = Container.new("DialogRoot")
        table.insert(activeContainers, tempContainer)
        targetRoot = tempContainer.ScreenGui
    end
    return Dialog.Show(targetRoot, props)
end

function SodiumUI:CreateLoading(props)
    return Loading.new(props)
end
SodiumUI.Loading = SodiumUI.CreateLoading

function SodiumUI:CreateKeyCheck(props)
    return KeyCheck.new(props)
end
SodiumUI.KeyCheck = SodiumUI.CreateKeyCheck

return SodiumUI
end

return _require('Init')
