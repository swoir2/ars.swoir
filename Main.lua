-- ui.lua
-- ars.swoir
-- UI:      xsx / Consistt library  (https://raw.githubusercontent.com/Consistt/Ui/main/UnLeaked)
-- ESP:     Shenanigans v2.3.0 engine  (env-stripped, key-check removed)
-- Aimbot:  Shenanigans v2.3.0 aimbot  (getSilentAimTarget, installBulletHook, installWallbang, main render)
-- GunMods: AR2/DROIDWARE weapon layer (allFireModes, instantReload, autoReload, alwaysSuppressed,
--          vehicleEquip, hbeSetEnabled, rageBotSetEnabled, shotLogStart, wallbangTagging)
-- Game:    UGC placeId 90014710188160
-- Patch 13: gun mods rewritten — ItemData direct-write (Vora approach) replaces broken upvalue surgery

-- ── 0. duplicate-instance guard ──────────────────────────────────────────────
if getgenv then
    local g = getgenv()
    if g.ORIGIN_HUB_ACTIVE then
        warn("[OriginHUB] previous instance detected, unloading it first")
        pcall(function()
            if type(g.OriginHUB_Unload) == "function" then g.OriginHUB_Unload() end
        end)
        task.wait(0.15)
    end
    g.ORIGIN_HUB_ACTIVE = true
end

-- ── 1. services ───────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local camera      = workspace.CurrentCamera

-- ── 2. capability flags ───────────────────────────────────────────────────────
local CAP = {
    getupvalue       = debug and typeof(debug.getupvalue)  == "function",
    setupvalue       = debug and typeof(debug.setupvalue)  == "function",
    getinfo          = debug and typeof(debug.getinfo)     == "function",
    getrawmetatable  = typeof(getrawmetatable)   == "function",
    setreadonly      = typeof(setreadonly)        == "function",
    newcclosure      = typeof(newcclosure)        == "function",
    hookfunction     = typeof(hookfunction)       == "function",
    isreadonly       = typeof(isreadonly)         == "function",
    getconnections   = typeof(getconnections)     == "function",
    mousemoverel     = typeof(mousemoverel)       == "function",
    fireproximityprompt = typeof(fireproximityprompt) == "function",
}

-- ── 3. shared state ───────────────────────────────────────────────────────────
local Characters = workspace:FindFirstChild("Characters")
local Zombies    = workspace:FindFirstChild("Zombies")
local Vehicles   = workspace:FindFirstChild("Vehicles")
local Corpses    = workspace:FindFirstChild("Corpses")
workspace.ChildAdded:Connect(function(c)
    if     c.Name == "Characters" then Characters = c
    elseif c.Name == "Zombies"    then Zombies    = c
    elseif c.Name == "Vehicles"   then Vehicles   = c
    elseif c.Name == "Corpses"    then Corpses    = c
    end
end)

-- ── 4. fullbright ─────────────────────────────────────────────────────────────
local FB = { enabled = false, conn = nil }
task.spawn(function()
    task.wait(0.1)
    FB.origBrightness     = Lighting.Brightness
    FB.origClockTime      = Lighting.ClockTime
    FB.origFogEnd         = Lighting.FogEnd
    FB.origAmbient        = Lighting.Ambient
    FB.origOutdoorAmbient = Lighting.OutdoorAmbient
    FB.origAtmoDensity    = Lighting.Atmosphere and Lighting.Atmosphere.Density
end)
local function toggleFullbright(enabled)
    FB.enabled = enabled
    if FB.conn then FB.conn:Disconnect(); FB.conn = nil end
    if enabled then
        FB.conn = RunService.RenderStepped:Connect(function()
            if Lighting.Brightness    ~= 2       then Lighting.Brightness    = 2 end
            if Lighting.ClockTime     ~= 14      then Lighting.ClockTime     = 14 end
            if Lighting.FogEnd        ~= 1000000 then Lighting.FogEnd        = 1000000 end
            if Lighting.GlobalShadows ~= false   then Lighting.GlobalShadows = false end
            local atmo = Lighting.Atmosphere
            if atmo and atmo.Density ~= 0 then atmo.Density = 0 end
            Lighting.Ambient        = Color3.fromRGB(178,178,178)
            Lighting.OutdoorAmbient = Color3.fromRGB(178,178,178)
        end)
    else
        if FB.origBrightness     ~= nil then Lighting.Brightness     = FB.origBrightness     end
        if FB.origClockTime      ~= nil then Lighting.ClockTime      = FB.origClockTime      end
        if FB.origFogEnd         ~= nil then Lighting.FogEnd         = FB.origFogEnd         end
        if FB.origAmbient        ~= nil then Lighting.Ambient        = FB.origAmbient        end
        if FB.origOutdoorAmbient ~= nil then Lighting.OutdoorAmbient = FB.origOutdoorAmbient end
        if FB.origAtmoDensity    ~= nil then
            local atmo = Lighting.Atmosphere
            if atmo then atmo.Density = FB.origAtmoDensity end
        end
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- 5. ESP + AIMBOT ENGINE
-- ═════════════════════════════════════════════════════════════════════════════

local camCFrame     = camera and camera.CFrame or CFrame.identity
local camCFrameConn = nil
local viewportW     = 1920
local viewportH     = 1080
local tanHalfFov    = 0.7
local aspectRatio   = 16/9

local function trackCamera(cam)
    if camCFrameConn then pcall(function() camCFrameConn:Disconnect() end); camCFrameConn = nil end
    if not cam then return end
    camCFrame = cam.CFrame
    camCFrameConn = cam:GetPropertyChangedSignal("CFrame"):Connect(function()
        camCFrame = cam.CFrame
    end)
end
trackCamera(camera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    camera = workspace.CurrentCamera
    trackCamera(camera)
end)

local function worldToScreen(worldPos)
    local v = camCFrame:PointToObjectSpace(worldPos)
    if v.Z >= 0 then return Vector3.new(0, 0, -v.Z), false end
    local n  = -v.Z
    local nx = v.X / n / (tanHalfFov * aspectRatio)
    local ny = v.Y / n / tanHalfFov
    return Vector3.new((nx+1)*0.5*viewportW, (1-ny)*0.5*viewportH, n), true
end
local function cameraPosition() return camCFrame.Position end
local function screenCenter()   return Vector2.new(viewportW*0.5, viewportH*0.5) end
local function worldToFovOffset(worldPos)
    local v, ok = worldToScreen(worldPos)
    if not ok then return nil, nil end
    return Vector2.new(v.X - viewportW*0.5, v.Y - viewportH*0.5), v
end

local myCharacter = LocalPlayer.Character
local myRoot      = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
LocalPlayer.CharacterAdded:Connect(function(c)
    myCharacter = c
    myRoot      = c:WaitForChild("HumanoidRootPart")
end)

local otherPlayers = {}
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then otherPlayers[#otherPlayers+1] = p end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then otherPlayers[#otherPlayers+1] = p end
end)
Players.PlayerRemoving:Connect(function(p)
    for i, v in ipairs(otherPlayers) do
        if v == p then table.remove(otherPlayers, i); break end
    end
end)

local aimRaycastParams = RaycastParams.new()
aimRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
aimRaycastParams.IgnoreWater = true
aimRaycastParams.FilterDescendantsInstances = { myCharacter }
LocalPlayer.CharacterAdded:Connect(function(c)
    aimRaycastParams.FilterDescendantsInstances = { c }
end)

local partyMembers   = {}
local partyDirty     = true
local squadListFrame = nil
pcall(function()
    local pg = LocalPlayer:WaitForChild("PlayerGui", 10)
    local pl = pg:WaitForChild("PlayerList", 10)
    local ml = pl:WaitForChild("MainList", 10)
    local sl = ml:WaitForChild("SquadList", 10)
    squadListFrame = sl:WaitForChild("ScrollingFrame", 10)
    squadListFrame.ChildAdded:Connect(function()   partyDirty = true end)
    squadListFrame.ChildRemoved:Connect(function() partyDirty = true end)
end)
local function rebuildParty()
    partyDirty   = false
    partyMembers = {}
    if not squadListFrame then return end
    for _, v in ipairs(squadListFrame:GetChildren()) do
        if v:IsA("Frame") and v.Name == "Frame" then
            local nb = v:FindFirstChild("NameButton")
            local ll = nb and nb:FindFirstChild("NameLabelBin") and nb.NameLabelBin:FindFirstChild("NameLabel")
            if ll then
                local pl = Players:FindFirstChild(ll.Text)
                if pl then partyMembers[pl] = true end
            end
        end
    end
end
local function isPartyMember(player)
    if partyDirty then rebuildParty() end
    return partyMembers[player] == true
end

local equippedItemCache = {}
local equippedNameCache = {}
local function getEquippedName(char)
    if not char then return nil end
    local ei = equippedItemCache[char]
    if not ei or not ei.Parent then
        ei = char:FindFirstChild("EquippedItem", true)
        equippedItemCache[char] = ei
        equippedNameCache[char] = nil
        if not ei then return nil end
    end
    local cached = equippedNameCache[char]
    local val    = ei.Value
    if not cached or val ~= cached.val then
        local ok, t = pcall(HttpService.JSONDecode, HttpService, val)
        local name  = ok and type(t) == "table" and type(t.ItemName) == "string" and t.ItemName ~= "" and t.ItemName or nil
        equippedNameCache[char] = { val = val, name = name }
        return name
    end
    return cached.name
end

local visibleCache         = {}
local visIndex             = 1
local visLastClean         = 0
local randomAimPartByModel = {}
local function updateVisibilityCache()
    local camPos = cameraPosition()
    local n      = #otherPlayers
    if n == 0 then return end
    if n < visIndex then visIndex = 1 end
    for _ = 128, math.min(4, n) + 127 do
        local p = otherPlayers[visIndex]
        if p then
            local char = p.Character
            local head = char and char:FindFirstChild("Head")
            if not head then
                visibleCache[p] = nil
            else
                local dir = head.Position - camPos
                local hit = workspace:Raycast(camPos, dir, aimRaycastParams)
                visibleCache[p] = hit ~= nil and hit.Instance ~= nil
                    and hit.Instance:IsDescendantOf(char)
            end
        end
        visIndex += 1
        if n < visIndex then visIndex = 1 end
    end
    local now = os.clock()
    if now - visLastClean > 1 then
        visLastClean = now
        local live = {}
        for _, p in ipairs(otherPlayers) do live[p] = true end
        for k in pairs(visibleCache) do
            if not live[k] then visibleCache[k] = nil end
        end
        for k in pairs(randomAimPartByModel) do
            if not k.Parent then randomAimPartByModel[k] = nil end
        end
    end
end

local espFlags = {
    AimPart          = "Head",
    FOV              = 150,
    AimDist          = 1200,
    WallCheck        = false,
    Prediction       = true,
    Aim              = false,
    SilentAim        = false,
    HideFOV          = false,
    SilentHitChance  = 100,
    NormalAimKey     = Enum.KeyCode.Unknown,
    NoRecoil         = false,
    NoSpread         = false,
    Wallbang         = false,
    Tracers          = false,
    ESP              = false,
    Box              = true,
    Name             = true,
    Dist             = true,
    Equip            = true,
    Charms           = false,
    ShowSkeleton     = false,
    ShowTracers      = false,
    PartyTag         = true,
    LookLine         = false,
    BoxScale         = 1.15,
    MaxDist          = 2000,
    BoxThickness     = 1,
    TracerLineColor  = Color3.fromRGB(255,130,130),
    TracerThickness  = 1,
    NameSize         = 1.15,
    DistSize         = 1.15,
    EquipSize        = 1.15,
    DistDynamicColor = true,
    DistColor        = Color3.new(1,1,1),
    NameStandard     = Color3.new(1,1,1),
    BoxStandard      = Color3.new(1,1,1),
    SkeletonColor    = Color3.new(1,1,1),
    SkeletonThickness       = 1,
    PartyColor              = Color3.new(1,1,1),
    CharmsFill              = Color3.new(1,1,1),
    CharmsFillTransparency  = 0.5,
    CharmsOutline           = Color3.new(0,0,0),
    CharmsOutlineTransparency = 0,
    CharmsAlwaysOnTop       = false,
    VisCheck         = false,
    VisibleColor     = Color3.fromRGB(80,220,120),
    HiddenColor      = Color3.fromRGB(220,80,80),
    HealthBar        = false,
    HealthBarWidth   = 4,
    CornerBox        = false,
    CornerLen        = 6,
    OffscreenArrows  = false,
    ArrowDist        = 120,
    AlwaysSuppressed = false,
    WallbangTag      = false,
}

local function getAimPart(char)
    local part = espFlags.AimPart or "Head"
    if part == "Random" then
        part = randomAimPartByModel[char]
        if not part then
            local opts = {"Head","UpperTorso","Legs"}
            part = opts[math.random(1,3)]
            randomAimPartByModel[char] = part
        end
    end
    if part == "UpperTorso" then
        local ut = char:FindFirstChild("UpperTorso")
        return ut, ut and ut.Position
    elseif part == "Legs" then
        local ll = char:FindFirstChild("LeftUpperLeg")  or char:FindFirstChild("LeftLeg")
        local rl = char:FindFirstChild("RightUpperLeg") or char:FindFirstChild("RightLeg")
        local lt = char:FindFirstChild("LowerTorso")    or char:FindFirstChild("HumanoidRootPart")
        if ll and rl then return lt, (ll.Position + rl.Position)*0.5 end
        if ll then return lt, ll.Position end
        if rl then return lt, rl.Position end
        return lt, lt and lt.Position
    else
        local h = char:FindFirstChild("Head")
        return h, h and h.Position
    end
end

local function isLivingCharacter(char)
    if not char then return false end
    local pl = Players:GetPlayerFromCharacter(char)
    if not pl then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char:FindFirstChild("HumanoidRootPart") ~= nil
        and char:FindFirstChild("Head") ~= nil
        and (hum == nil or hum.Health > 0)
end

local function wallCheckClear(_, char, targetPos)
    if not espFlags.WallCheck then return true end
    local origin = camera.CFrame.Position
    local hit    = workspace:Raycast(origin, targetPos - origin, aimRaycastParams)
    return hit ~= nil and hit.Instance ~= nil and hit.Instance:IsDescendantOf(char)
end

local _framework = nil
local function getFramework()
    if _framework then return _framework end
    local ok, fw = pcall(function()
        local f = require(ReplicatedFirst:WaitForChild("Framework", 10))
        if f and f.WaitForLoaded then pcall(function() f:WaitForLoaded() end) end
        return f
    end)
    if ok and fw then _framework = fw end
    return _framework
end

local weaponVelocities = {
    ["AC-556"]=4630,["AK-47"]=3800,["AK-74"]=4610,AKM=3900,["AKS-74U"]=4000,
    ["AO-46"]=3580,["AS Val"]=2090,AUG=4670,["Auto-5"]=2450,
    ["Camp Carbine"]=2850,["Coach Gun"]=2530,["Desert Eagle"]=2550,
    ["Dragunov SVD"]=4400,FAL=4370,G17=2475,G3=4270,["Hi-Power"]=2520,
    L96A1=4650,Lupara=2180,["M1 Carbine"]=3475,["M1 Garand"]=4370,
    ["M1 Thompson"]=2215,M14=4370,M16=4625,M16A2=4650,M1903=4425,
    M1911=2040,M1911Mod1=2040,["M1918 BAR"]=4380,M1919A6=4360,
    ["M2 Carbine"]=3475,M21=4425,M249=4575,M3A1=2140,M40A1=4575,
    M4A1=4415,M60=4370,M9=2600,M93R=2600,["MAC-10"]=2000,
    ["MAT-49"]=2740,["MK23 SOCOM"]=2200,["MP 40"]=2765,MP5=2700,
    MP5K=2600,["MSG-90"]=4425,Makarov=2260,["Maverick 88"]=2600,
    ["Medic Dart Gun"]=850,["Mini-14"]=4670,["Model 29"]=2475,
    ["Model 459"]=2490,["Mosin M44 Carbine"]=3960,["Mosin Obrez"]=3280,
    ["Mosin PU"]=4400,["OTS-14 Groza"]=1975,["P220 SIG"]=2100,
    PKM=4240,["PP-19 Bizon"]=2340,["PSG-1"]=4450,Patriot=4075,
    Python=2735,RPK=3970,["RPK-74M"]=4700,["Remington 788"]=3600,
    ["Ruger Model 44 Carbine"]=3380,SKS=3960,["SPAS-12"]=2410,
    ["SVT-40"]=4270,["Skorpion vz.65"]=2290,["TEC-9"]=2500,
    UMP45=2180,Uzi=2665,UziMod1=2720,["VSS Vintorez"]=2275,
    ["Walther P38"]=2430,["Winchester 1894"]=3130,XM177=4415,
}
local function getEquippedModel()
    local char  = myCharacter
    local equip = char and char:FindFirstChild("Equipped")
    return equip and equip:GetChildren()[1] or nil
end
local function getPredictionVelocity()
    local gun = getEquippedModel()
    if gun then
        local v = weaponVelocities[gun.Name]
        if type(v) == "number" and v > 0 then return v end
    end
    return 1800
end
local function hasWeaponEquipped() return getEquippedModel() ~= nil end

local aimTarget       = nil
local aimTargetPos    = nil
local silentTarget    = nil
local silentTargetRoot = nil
local silentTargetPos = nil

local aimCfg = {
    LOCK_BASE_MOUSE_DELTA      = 0.52,
    LOCK_REFERENCE_ROBLOX_SENS = 1,
    MIN_LOCK_PIXEL_STEP        = 1,
    BASE_CENTER_EPSILON        = 0.35,
    MAX_MOUSE_STEP             = 50,
    SCOPED_FOV_THRESHOLD       = 33,
    SCOPED_SLOWDOWN_MULT       = 1.3,
    THIRD_PERSON_SLOWDOWN_MULT = 1.5,
}
local GameSettings      = UserSettings():GetService("UserGameSettings")
local mouseSaved        = nil
local mouseSavedApplied = false
local function applyAimSensitivity()
    if not mouseSavedApplied then
        mouseSaved = UserInputService.MouseDeltaSensitivity
        mouseSavedApplied = true
    end
    local target = aimCfg.LOCK_BASE_MOUSE_DELTA * (aimCfg.LOCK_REFERENCE_ROBLOX_SENS / math.max(GameSettings.MouseSensitivity, 0.001))
    if UserInputService.MouseDeltaSensitivity ~= target then
        UserInputService.MouseDeltaSensitivity = target
    end
end
local function restoreMouseSensitivity()
    if not mouseSavedApplied then return end
    if mouseSaved ~= nil then UserInputService.MouseDeltaSensitivity = mouseSaved end
    mouseSaved = nil; mouseSavedApplied = false
end
local function resetAimState()
    aimTarget = nil; aimTargetPos = nil
    restoreMouseSensitivity()
end
local function centerEpsilon()
    local fov = camera.FieldOfView
    return aimCfg.BASE_CENTER_EPSILON + (fov > 33 and (fov - 33)*0.02 or 0)
end
local function clampMouseStep(rawStep, errorVec, deadzone)
    local x, y = rawStep.X, rawStep.Y
    if math.abs(errorVec.X) > deadzone and math.abs(x) < aimCfg.MIN_LOCK_PIXEL_STEP then
        x = errorVec.X > 0 and aimCfg.MIN_LOCK_PIXEL_STEP or -aimCfg.MIN_LOCK_PIXEL_STEP
    end
    if math.abs(errorVec.Y) > deadzone and math.abs(y) < aimCfg.MIN_LOCK_PIXEL_STEP then
        y = errorVec.Y > 0 and aimCfg.MIN_LOCK_PIXEL_STEP or -aimCfg.MIN_LOCK_PIXEL_STEP
    end
    local nx, ny = math.round(x), math.round(y)
    if nx == 0 and math.abs(errorVec.X) > deadzone then nx = errorVec.X > 0 and 1 or -1 end
    if ny == 0 and math.abs(errorVec.Y) > deadzone then ny = errorVec.Y > 0 and 1 or -1 end
    local v = Vector2.new(nx, ny)
    if v.Magnitude > aimCfg.MAX_MOUSE_STEP then
        local u = v.Unit * aimCfg.MAX_MOUSE_STEP
        return Vector2.new(math.round(u.X), math.round(u.Y))
    end
    return v
end

local function isAimTargetValid(part)
    if not (part and part.Parent) then return false end
    local char = part.Parent
    if not isLivingCharacter(char) then return false end
    local pl = Players:GetPlayerFromCharacter(char)
    if pl and isPartyMember(pl) then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root or not myRoot then return false end
    if (root.Position - myRoot.Position).Magnitude > (espFlags.AimDist or 1200) then return false end
    local _, pos = getAimPart(char)
    if not pos then return false end
    if not wallCheckClear(part, char, pos) then return false end
    if not worldToFovOffset(pos) then return false end
    return true
end
local function findTargetInFov()
    local best, bestDist = nil, espFlags.FOV or 150
    aimTargetPos = nil
    if not myRoot then return nil end
    for _, pl in ipairs(otherPlayers) do
        if pl ~= LocalPlayer then
            local char = pl.Character
            if isLivingCharacter(char) and not isPartyMember(pl) then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root and (root.Position - myRoot.Position).Magnitude <= (espFlags.AimDist or 1200) then
                    local part, pos = getAimPart(char)
                    if part and pos then
                        local off = worldToFovOffset(pos)
                        if off then
                            local d = off.Magnitude
                            if d < bestDist and wallCheckClear(part, char, pos) then
                                best = part; bestDist = d; aimTargetPos = pos
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end
local function getOrPickAimTarget()
    if isAimTargetValid(aimTarget) then return aimTarget end
    aimTarget = findTargetInFov()
    return aimTarget
end
local function getSilentAimTarget()
    local bestPart, bestRoot, bestPos = nil, nil, nil
    local bestScore = math.huge
    local mousePos  = UserInputService:GetMouseLocation()
    local fov       = espFlags.FOV or 150
    local maxDist   = espFlags.AimDist or 1200
    local camPos    = camCFrame.Position
    for _, pl in ipairs(otherPlayers) do
        if pl ~= LocalPlayer then
            local char = pl.Character
            if isLivingCharacter(char) and not isPartyMember(pl) then
                local part, pos = getAimPart(char)
                local root      = char:FindFirstChild("HumanoidRootPart")
                local hum       = char:FindFirstChild("Humanoid")
                if part and root and hum and hum.Health > 0 then
                    local screenP, onScreen = worldToScreen(pos or part.Position)
                    if onScreen then
                        local pixelDist = (Vector2.new(screenP.X, screenP.Y) - mousePos).Magnitude
                        if pixelDist <= fov then
                            local worldDist = (root.Position - camPos).Magnitude
                            if worldDist <= maxDist then
                                local score = worldDist/1000*0.7 + pixelDist/fov*0.3
                                if score < bestScore then
                                    bestScore = score
                                    bestPart  = part
                                    bestRoot  = root
                                    bestPos   = pos or part.Position
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return bestPart, bestRoot, bestPos
end

-- ── ItemData gun mods (Patch 13 — replaces broken upvalue surgery) ────────────
-- Writes directly to RS.Client.Configs.ItemData — the shared weapon config tables
-- that Bullets.Fire reads every shot. Same approach as AR2's own DROIDWARE hub.
local _itemData       = nil
local _itemBackups    = {}
local _itemDataLoaded = false

local function loadItemData()
    if _itemDataLoaded then return _itemData end
    _itemDataLoaded = true
    local ok, id = pcall(function()
        return require(ReplicatedStorage
            :WaitForChild("Client", 10)
            :WaitForChild("Configs", 10)
            :WaitForChild("ItemData", 10))
    end)
    if ok and type(id) == "table" then
        _itemData = id
    else
        warn("[OriginHUB] ItemData not found:", tostring(id))
    end
    return _itemData
end

local function ensureBackup(name, entry)
    if _itemBackups[name] then return end
    local b = { recoil = {} }
    if entry.RecoilData and type(entry.RecoilData) == "table" then
        local rd = entry.RecoilData
        b.recoil = {
            KickUpForce           = rd.KickUpForce,
            RaiseForce            = rd.RaiseForce,
            ShiftForce            = rd.ShiftForce,
            SlideForce            = rd.SlideForce,
            KickUpCameraInfluence = rd.KickUpCameraInfluence,
            ShiftCameraInfluence  = rd.ShiftCameraInfluence,
            RaiseInfluence        = rd.RaiseInfluence,
            SlideInfluence        = rd.SlideInfluence,
            SpreadBase            = rd.SpreadBase,
            SpreadAddFPSHip       = rd.SpreadAddFPSHip,
            SpreadAddFPSZoom      = rd.SpreadAddFPSZoom,
            SpreadAddTPSHip       = rd.SpreadAddTPSHip,
            SpreadAddTPSZoom      = rd.SpreadAddTPSZoom,
        }
    end
    _itemBackups[name] = b
end

local function applyGunMods()
    local id = loadItemData()
    if not id then return end
    for name, entry in pairs(id) do
        if type(entry) == "table" and entry.RecoilData and type(entry.RecoilData) == "table" then
            ensureBackup(name, entry)
            local rd = entry.RecoilData
            local b  = _itemBackups[name].recoil

            -- unlock the table before writing
            pcall(setreadonly, rd, false)
            pcall(setreadonly, entry, false)

            if espFlags.NoRecoil then
                rd.KickUpForce           = 0
                rd.RaiseForce            = 0
                rd.ShiftForce            = 0
                rd.SlideForce            = 0
                rd.KickUpCameraInfluence = 0
                rd.ShiftCameraInfluence  = 0
                rd.RaiseInfluence        = 0
                rd.SlideInfluence        = 0
            else
                rd.KickUpForce           = b.KickUpForce
                rd.RaiseForce            = b.RaiseForce
                rd.ShiftForce            = b.ShiftForce
                rd.SlideForce            = b.SlideForce
                rd.KickUpCameraInfluence = b.KickUpCameraInfluence
                rd.ShiftCameraInfluence  = b.ShiftCameraInfluence
                rd.RaiseInfluence        = b.RaiseInfluence
                rd.SlideInfluence        = b.SlideInfluence
            end

            if espFlags.NoSpread then
                rd.SpreadBase        = 0
                rd.SpreadAddFPSHip   = 0
                rd.SpreadAddFPSZoom  = 0
                rd.SpreadAddTPSHip   = 0
                rd.SpreadAddTPSZoom  = 0
            else
                rd.SpreadBase        = b.SpreadBase
                rd.SpreadAddFPSHip   = b.SpreadAddFPSHip
                rd.SpreadAddFPSZoom  = b.SpreadAddFPSZoom
                rd.SpreadAddTPSHip   = b.SpreadAddTPSHip
                rd.SpreadAddTPSZoom  = b.SpreadAddTPSZoom
            end
        end
    end
end

local function restoreGunMods()
    local id = loadItemData()
    if not id then return end
    for name, b in pairs(_itemBackups) do
        local entry = id[name]
        if entry and entry.RecoilData and type(entry.RecoilData) == "table" then
            local rd = entry.RecoilData
            local r  = b.recoil

            pcall(setreadonly, rd, false)
            pcall(setreadonly, entry, false)

            rd.KickUpForce           = r.KickUpForce
            rd.RaiseForce            = r.RaiseForce
            rd.ShiftForce            = r.ShiftForce
            rd.SlideForce            = r.SlideForce
            rd.KickUpCameraInfluence = r.KickUpCameraInfluence
            rd.ShiftCameraInfluence  = r.ShiftCameraInfluence
            rd.RaiseInfluence        = r.RaiseInfluence
            rd.SlideInfluence        = r.SlideInfluence
            rd.SpreadBase            = r.SpreadBase
            rd.SpreadAddFPSHip       = r.SpreadAddFPSHip
            rd.SpreadAddFPSZoom      = r.SpreadAddFPSZoom
            rd.SpreadAddTPSHip       = r.SpreadAddTPSHip
            rd.SpreadAddTPSZoom      = r.SpreadAddTPSZoom
        end
    end
end


-- ── bullet hook (silent aim + tracers only; recoil/spread via ItemData above) ──
local bulletHookOn      = false
local origFireFn        = nil
local origSpreadAngleFn = nil
local silentAimDir      = nil

local beamHolder = Instance.new("Part")
beamHolder.Anchored = true; beamHolder.CanCollide = false
beamHolder.Transparency = 1; beamHolder.Size = Vector3.new(0.1,0.1,0.1)
beamHolder.CFrame = CFrame.new(0,0,0); beamHolder.Parent = workspace

local function drawTracerBeam(p0, p1)
    local a0 = Instance.new("Attachment"); a0.WorldPosition = p0; a0.Parent = beamHolder
    local a1 = Instance.new("Attachment"); a1.WorldPosition = p1; a1.Parent = beamHolder
    local beam = Instance.new("Beam")
    beam.Attachment0 = a0; beam.Attachment1 = a1
    beam.Color = ColorSequence.new(Color3.new(1,1,1))
    beam.Width0 = 0.25; beam.Width1 = 0.25
    beam.Transparency = NumberSequence.new(0.5)
    beam.LightEmission = 1; beam.FaceCamera = true; beam.Parent = beamHolder
    task.delay(0.6, function()
        pcall(function() beam:Destroy(); a0:Destroy(); a1:Destroy() end)
    end)
end

local function installBulletHook()
    if bulletHookOn then return end
    local fw = getFramework()
    if not fw then
        warn("[OriginHUB] installBulletHook: Framework not loaded")
        return
    end
    local bullets = fw.Libraries and fw.Libraries.Bullets
    if not (bullets and bullets.Fire) then
        warn("[OriginHUB] installBulletHook: Bullets.Fire not found")
        return
    end
    local Fire = bullets.Fire
    origFireFn = Fire

    -- belt-and-suspenders: also zero the GetSpreadAngle return when NoSpread is on
    if bullets.GetSpreadAngle then
        origSpreadAngleFn = bullets.GetSpreadAngle
        bullets.GetSpreadAngle = function(...)
            if espFlags.NoSpread or espFlags.SilentAim then return 0 end
            return origSpreadAngleFn(...)
        end
    end

    -- wrap Fire for silent aim and tracers only
    function bullets.Fire(self, ...)
        local args = { ... }
        local doSilent = espFlags.SilentAim
            and silentTargetPos and silentTargetRoot and silentTarget
            and not ((espFlags.SilentHitChance or 100) < math.random(1, 100))
        local origin = type(args[4]) == "userdata" and args[4] or camera.CFrame.Position
        local dest   = nil
        if not doSilent then
            local d5 = args[5]
            if type(d5) == "userdata" then dest = origin + d5.Unit * 2000 end
        else
            dest = silentTargetPos
            if espFlags.Prediction then
                local spd  = getPredictionVelocity()
                local mag  = (silentTargetPos - origin).Magnitude
                local lead = mag / spd
                if mag > 35 then
                    dest = silentTargetPos + silentTargetRoot.AssemblyLinearVelocity * lead * 1.05
                end
            end
            local unit = (dest - origin).Unit
            args[5] = unit
            silentAimDir = unit
        end
        if espFlags.Tracers and dest then drawTracerBeam(origin, dest) end
        if espFlags.AimPart == "Random" then
            if aimTarget    and aimTarget.Parent    then randomAimPartByModel[aimTarget.Parent]    = nil end
            if silentTarget and silentTarget.Parent then randomAimPartByModel[silentTarget.Parent] = nil end
        end
        return Fire(self, table.unpack(args))
    end

    -- load ItemData and apply current state immediately
    task.spawn(function()
        loadItemData()
        applyGunMods()
    end)

    bulletHookOn = true
end

local function removeBulletHook()
    if not bulletHookOn then return end
    silentAimDir = nil
    local fw = getFramework()
    if fw then
        local bullets = fw.Libraries and fw.Libraries.Bullets
        if bullets then
            if origFireFn        then bullets.Fire           = origFireFn        end
            if origSpreadAngleFn then bullets.GetSpreadAngle = origSpreadAngleFn end
        end
    end
    restoreGunMods()
    bulletHookOn = false
end

-- ── wallbang ──────────────────────────────────────────────────────────────────
local wallbangHookOn    = false
local origBulletCast    = nil
local origCastWhitelist = nil

local function installWallbang()
    if wallbangHookOn then return end
    local fw = getFramework()
    if not fw then return end
    local raycasting = fw.Libraries and fw.Libraries.Raycasting
    if not (raycasting and raycasting.BulletCastLight and raycasting.CastWithIgnoreList) then return end
    origBulletCast    = raycasting.BulletCastLight
    origCastWhitelist = raycasting.CastWithIgnoreList

    local wbParams   = RaycastParams.new()
    wbParams.FilterType  = Enum.RaycastFilterType.Include
    wbParams.IgnoreWater = true
    local wbParts    = {}
    local wbDirty    = true
    local wbConns    = {}
    local wbCharParts = {}

    local function trackChar(char)
        if not char then return end
        local parts = {}
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then parts[d] = true end
        end
        wbCharParts[char] = parts; wbDirty = true
        local conns = {
            char.DescendantAdded:Connect(function(d)
                if d:IsA("BasePart") and wbCharParts[char] then wbCharParts[char][d]=true; wbDirty=true end
            end),
            char.DescendantRemoving:Connect(function(d)
                if wbCharParts[char] then wbCharParts[char][d]=nil; wbDirty=true end
            end),
        }
        wbConns[char] = conns
    end
    local function untrackChar(char)
        for _, c in ipairs(wbConns[char] or {}) do pcall(function() c:Disconnect() end) end
        wbConns[char] = nil; wbCharParts[char] = nil; wbDirty = true
    end
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then
            table.insert(wbConns, pl.CharacterAdded:Connect(trackChar))
            table.insert(wbConns, pl.CharacterRemoving:Connect(untrackChar))
            if pl.Character then trackChar(pl.Character) end
        end
    end
    Players.PlayerAdded:Connect(function(pl)
        if pl == LocalPlayer then return end
        table.insert(wbConns, pl.CharacterAdded:Connect(trackChar))
        table.insert(wbConns, pl.CharacterRemoving:Connect(untrackChar))
    end)

    local function rebuildWbList()
        if not wbDirty then return end
        wbDirty = false
        wbParts = {}
        for char, parts in pairs(wbCharParts) do
            if char.Parent then
                for part in pairs(parts) do
                    if part.Parent then wbParts[#wbParts+1] = part end
                end
            else
                wbCharParts[char] = nil
            end
        end
        wbParams.FilterDescendantsInstances = wbParts
    end
    local bodyNames = { Head=true, UpperTorso=true, LowerTorso=true }
    local function wbRaycast(ray)
        if not ray then return end
        rebuildWbList()
        if #wbParts == 0 then return end
        local hit = workspace:Raycast(ray.Origin, ray.Direction, wbParams)
        if not hit then return end
        local inst = hit.Instance
        if myCharacter and inst:IsDescendantOf(myCharacter) then return end
        local penetrateList = {}
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer and pl.Character and inst:IsDescendantOf(pl.Character) then
                for partName in pairs(bodyNames) do
                    local bp = pl.Character:FindFirstChild(partName)
                    if bp then penetrateList[#penetrateList+1] = bp end
                end
                break
            end
        end
        if #penetrateList == 0 then
            return inst, hit.Position, hit.Normal
        end
        local pp = RaycastParams.new()
        pp.FilterType = Enum.RaycastFilterType.Include
        pp.FilterDescendantsInstances = penetrateList
        pp.IgnoreWater = true
        local backHit = workspace:Raycast(hit.Position + ray.Direction.Unit*0.1, -ray.Direction.Unit*10, pp)
        if backHit then return backHit.Instance, backHit.Position, backHit.Normal end
        local best, bestDist = nil, math.huge
        for _, p in ipairs(penetrateList) do
            local d = (p.Position - hit.Position).Magnitude
            if d < bestDist then bestDist = d; best = p end
        end
        if best then return best, best.Position, best.CFrame.LookVector end
    end

    function raycasting.BulletCastLight(...)
        if not espFlags.Wallbang then return origBulletCast(...) end
        local args = { ... }
        local ray  = type(args[1]) == "userdata" and args[1] or args[2]
        if not ray then return origBulletCast(...) end
        local origReturns = table.pack(origBulletCast(...))
        local ok, a, b, c = pcall(wbRaycast, ray)
        if ok and a then
            origReturns[1] = a
            origReturns[2] = b
            origReturns[3] = c
            origReturns.n = math.max(origReturns.n or 0, 3)
        end
        return table.unpack(origReturns, 1, origReturns.n)
    end
    function raycasting.CastWithIgnoreList(...)
        if not espFlags.Wallbang then return origCastWhitelist(...) end
        return origCastWhitelist(...)
    end
    wallbangHookOn = true
end
local function removeWallbang()
    if not wallbangHookOn then return end
    local fw = getFramework()
    if fw then
        local raycasting = fw.Libraries and fw.Libraries.Raycasting
        if raycasting then
            if origBulletCast    then raycasting.BulletCastLight    = origBulletCast    end
            if origCastWhitelist then raycasting.CastWithIgnoreList = origCastWhitelist end
        end
    end
    wallbangHookOn = false
end

local function destroyDrawing(d)
    if d then pcall(function() d.Visible = false end); pcall(function() d:Remove() end) end
end

local skeletonBones = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}

local function createEspDrawings(player)
    local box   = Drawing.new("Square"); box.Thickness=2;   box.Transparency=1; box.Filled=false; box.Visible=false; box.Color=Color3.new(0,0,0)
    local boxOL = Drawing.new("Square"); boxOL.Thickness=1; boxOL.Transparency=1; boxOL.Filled=false; boxOL.Visible=false
    local name  = Drawing.new("Text");  name.Font=2;  name.Center=true; name.Outline=true; name.Visible=false
    local dist  = Drawing.new("Text");  dist.Font=2;  dist.Center=true; dist.Outline=true; dist.Visible=false
    local equip = Drawing.new("Text");  equip.Font=2; equip.Center=true; equip.Outline=false; equip.Visible=false; equip.Transparency=0.6
    local party = Drawing.new("Text");  party.Font=2; party.Center=true; party.Outline=true; party.Visible=false; party.Text="[Party]"
    local look  = Drawing.new("Line");  look.Thickness=1;  look.Transparency=1; look.Visible=false
    local trace = Drawing.new("Line");  trace.Thickness=1; trace.Transparency=1; trace.Visible=false; trace.Color=Color3.fromRGB(255,0,0)
    local skel  = {}
    for _, bp in ipairs(skeletonBones) do
        local l = Drawing.new("Line"); l.Thickness=1; l.Transparency=0.5; l.Visible=false; l.Color=Color3.new(1,1,1)
        skel[#skel+1] = { line=l, from=bp[1], to=bp[2] }
    end
    local hpBarBg = Drawing.new("Square"); hpBarBg.Thickness=1; hpBarBg.Filled=true;  hpBarBg.Visible=false; hpBarBg.Color=Color3.new(0,0,0); hpBarBg.Transparency=0.6
    local hpBar   = Drawing.new("Square"); hpBar.Thickness=1;   hpBar.Filled=true;    hpBar.Visible=false
    local corners = {}
    for i = 1, 4 do
        local l1 = Drawing.new("Line"); l1.Thickness=2; l1.Visible=false
        local l2 = Drawing.new("Line"); l2.Thickness=2; l2.Visible=false
        corners[i] = { l1, l2 }
    end
    local arrow = Drawing.new("Triangle"); arrow.Filled=true; arrow.Visible=false
    return { box=box, boxOutline=boxOL, name=name, dist=dist, equipped=equip,
             party=party, lookLine=look, tracer=trace, skeleton=skel, highlight=nil,
             hpBarBg=hpBarBg, hpBar=hpBar, corners=corners, arrow=arrow }
end

local charInfoCache = {}
local function getCharInfo(player, char, wantSkeleton)
    local ci = charInfoCache[player]
    if not ci or ci.character ~= char then
        local root = char:FindFirstChild("HumanoidRootPart")
        local head = char:FindFirstChild("Head")
        if not root or not head then charInfoCache[player] = nil; return nil end
        local skel = nil
        if wantSkeleton then
            skel = {}
            for _, bp in ipairs(skeletonBones) do
                skel[bp[1]] = char:FindFirstChild(bp[1])
                skel[bp[2]] = char:FindFirstChild(bp[2])
            end
        end
        ci = { character=char, root=root, head=head,
               leftFoot=char:FindFirstChild("LeftFoot"),
               equipped=char:FindFirstChild("Equipped"),
               skeleton=skel }
        charInfoCache[player] = ci
        return ci
    end
    if wantSkeleton and not ci.skeleton then
        local skel = {}
        for _, bp in ipairs(skeletonBones) do
            skel[bp[1]] = char:FindFirstChild(bp[1])
            skel[bp[2]] = char:FindFirstChild(bp[2])
        end
        ci.skeleton = skel
    end
    return ci
end

local espObjects = {}
local upOffset   = Vector3.new(0,1,0)
local function distanceColor(d)
    local t  = math.clamp(d/2000, 0, 1)
    local c0 = Color3.fromRGB(255,130,130)
    local c1 = Color3.fromRGB(255,225,140)
    local c2 = Color3.fromRGB(140,235,160)
    if t < 0.5 then return c0:Lerp(c1, t*2) end
    return c1:Lerp(c2, (t-0.5)*2)
end

local function hidePlayerEsp(player)
    local esp = espObjects[player]
    if not esp then return end
    esp.box.Visible      = false
    esp.name.Visible     = false
    esp.dist.Visible     = false
    esp.equipped.Visible = false
    esp.party.Visible    = false
    esp.lookLine.Visible = false
    if esp.boxOutline then esp.boxOutline.Visible = false end
    if esp.highlight  then esp.highlight.Enabled  = false end
    if esp.tracer     then esp.tracer.Visible      = false end
    if esp.skeleton   then for _, b in ipairs(esp.skeleton) do b.line.Visible = false end end
    if esp.hpBarBg    then esp.hpBarBg.Visible = false end
    if esp.hpBar      then esp.hpBar.Visible   = false end
    if esp.corners    then for _, c in ipairs(esp.corners) do c[1].Visible=false; c[2].Visible=false end end
    if esp.arrow      then esp.arrow.Visible   = false end
end

local espCfg          = nil
local espCfgTime      = 0
local espTextTime     = 0
local lastLookLineTick = 0
local lastSkeletonTick = 0

local function rebuildEspConfig()
    espCfg = {
        boxScale    = espFlags.BoxScale or 1.15,
        maxDist     = espFlags.MaxDist or 2000,
        box         = espFlags.Box,
        boxThick    = espFlags.BoxThickness or 1,
        name        = espFlags.Name,
        dist        = espFlags.Dist,
        distDyn     = espFlags.DistDynamicColor,
        distColor   = espFlags.DistColor or Color3.new(1,1,1),
        equip       = espFlags.Equip,
        charms      = espFlags.Charms,
        skel        = espFlags.ShowSkeleton,
        skelColor   = espFlags.SkeletonColor or Color3.new(1,1,1),
        skelThick   = espFlags.SkeletonThickness or 1,
        tracers     = espFlags.ShowTracers,
        tracerColor = espFlags.TracerLineColor or Color3.fromRGB(255,130,130),
        tracerThick = espFlags.TracerThickness or 1,
        lookLine    = espFlags.LookLine,
        partyTag    = espFlags.PartyTag,
        nameStandard = espFlags.NameStandard or Color3.new(1,1,1),
        boxStandard  = espFlags.BoxStandard  or Color3.new(1,1,1),
        partyColor   = espFlags.PartyColor   or Color3.new(1,1,1),
        charmsFill        = espFlags.CharmsFill or Color3.new(1,1,1),
        charmsFillTransp  = espFlags.CharmsFillTransparency or 0.5,
        charmsOutline     = espFlags.CharmsOutline or Color3.new(0,0,0),
        charmsOutlineTransp = espFlags.CharmsOutlineTransparency or 0,
        charmsAlwaysOnTop = espFlags.CharmsAlwaysOnTop,
        visCheck     = espFlags.VisCheck,
        visibleColor = espFlags.VisibleColor or Color3.fromRGB(80,220,120),
        hiddenColor  = espFlags.HiddenColor  or Color3.fromRGB(220,80,80),
        healthBar    = espFlags.HealthBar,
        healthBarW   = espFlags.HealthBarWidth or 4,
        cornerBox    = espFlags.CornerBox,
        cornerLen    = espFlags.CornerLen or 6,
        offArrows    = espFlags.OffscreenArrows,
        arrowDist    = espFlags.ArrowDist or 120,
    }
end

local colorRed    = Color3.fromRGB(255,0,0)
local colorYellow = Color3.fromRGB(255,255,0)
local colorGreen  = Color3.fromRGB(0,255,0)

local function renderPlayerEsp(tracerOrigin, lookRefPart)
    if not espFlags.ESP then
        for _, esp in pairs(espObjects) do
            esp.box.Visible=false; esp.name.Visible=false; esp.dist.Visible=false
            esp.equipped.Visible=false; esp.party.Visible=false; esp.lookLine.Visible=false
            if esp.boxOutline then esp.boxOutline.Visible=false end
            if esp.highlight  then esp.highlight.Enabled=false  end
            if esp.tracer     then esp.tracer.Visible=false      end
            if esp.skeleton   then for _, b in ipairs(esp.skeleton) do b.line.Visible=false end end
            if esp.hpBarBg    then esp.hpBarBg.Visible=false end
            if esp.hpBar      then esp.hpBar.Visible=false   end
            if esp.corners    then for _, c in ipairs(esp.corners) do c[1].Visible=false; c[2].Visible=false end end
            if esp.arrow      then esp.arrow.Visible=false   end
        end
        return
    end
    local now = os.clock()
    if not espCfg or now - espCfgTime >= 0.1 then
        espCfgTime = now; rebuildEspConfig()
    end
    local cfg    = espCfg
    local camPos = cameraPosition()
    local doLook = cfg.lookLine and (now - lastLookLineTick >= 0.04)
    local doSkel = cfg.skel     and (now - lastSkeletonTick >= 0.04)
    local doText = now - (espTextTime or 0) >= 0.0333

    for _, pl in ipairs(otherPlayers) do
        local char = pl.Character
        local esp  = espObjects[pl]
        if not isLivingCharacter(char) then hidePlayerEsp(pl); continue end
        local ci = getCharInfo(pl, char, cfg.skel)
        if not ci then hidePlayerEsp(pl); continue end

        local root    = ci.root
        local head    = ci.head
        local rootPos = root.Position
        local sv, onscreen = worldToScreen(rootPos)
        if not onscreen then
            hidePlayerEsp(pl)
            if not esp then esp = createEspDrawings(pl); espObjects[pl] = esp end
            if cfg.offArrows then
                local magOff = (rootPos - camPos).Magnitude
                if magOff <= (cfg.arrowDist or 120) then
                    local dirFlat = Vector3.new((rootPos-camPos).X, 0, (rootPos-camPos).Z)
                    if dirFlat.Magnitude > 0.01 then
                        local fx  = dirFlat.Unit:Dot(camCFrame.RightVector)
                        local fy  = -dirFlat.Unit:Dot(camCFrame.LookVector)
                        local ang = math.atan2(fx, fy)
                        local edge = math.min(viewportW, viewportH) * 0.4
                        local cx, cy = viewportW*0.5, viewportH*0.5
                        local px, py = cx + math.sin(ang)*edge, cy - math.cos(ang)*edge
                        local size = 10
                        esp.arrow.PointA = Vector2.new(px + math.sin(ang)*size, py - math.cos(ang)*size)
                        esp.arrow.PointB = Vector2.new(px + math.sin(ang+2.5)*size*0.6, py - math.cos(ang+2.5)*size*0.6)
                        esp.arrow.PointC = Vector2.new(px + math.sin(ang-2.5)*size*0.6, py - math.cos(ang-2.5)*size*0.6)
                        esp.arrow.Color  = Color3.fromRGB(255,255,255)
                        esp.arrow.Visible = true
                    end
                else
                    esp.arrow.Visible = false
                end
            end
            continue
        end
        if esp and esp.arrow then esp.arrow.Visible = false end

        local mag = (rootPos - camPos).Magnitude
        if mag > cfg.maxDist then hidePlayerEsp(pl); continue end

        if not esp then esp = createEspDrawings(pl); espObjects[pl] = esp end

        local headPos = head.Position
        local sv5     = worldToScreen(headPos + upOffset)
        local footY   = ci.leftFoot and (ci.leftFoot.CFrame.Y - 1) or (rootPos.Y - 3)
        local sv6     = worldToScreen(Vector3.new(root.CFrame.X, footY, root.CFrame.Z))
        local hBase   = math.max(math.abs(sv5.Y - sv6.Y), 12)
        local h       = hBase * (cfg.boxScale or 1.15)
        local w       = h / 1.6
        local bx      = sv.X - w/2
        local by      = sv5.Y - (h - hBase) * 0.5

        local party = cfg.partyTag and isPartyMember(pl)

        esp.box.Size      = Vector2.new(w, h)
        esp.box.Position  = Vector2.new(bx, by)
        esp.box.Visible   = cfg.box
        esp.box.Color     = cfg.boxStandard
        esp.box.Thickness = 1
        if esp.boxOutline then
            esp.boxOutline.Size      = Vector2.new(w+2, h+2)
            esp.boxOutline.Position  = Vector2.new(bx-1, by-1)
            esp.boxOutline.Visible   = cfg.box
            esp.boxOutline.Color     = Color3.new(0,0,0)
            esp.boxOutline.Thickness = 1
        end

        if cfg.visCheck then
            local isVis = visibleCache[pl] == true
            esp.box.Color = isVis and cfg.visibleColor or cfg.hiddenColor
        end

        if cfg.cornerBox and cfg.box then
            local cl = math.min(cfg.cornerLen or 6, w/2, h/2)
            local corners = esp.corners
            local function setCorner(i, px, py, dx1, dy1, dx2, dy2, color)
                corners[i][1].From = Vector2.new(px,py); corners[i][1].To = Vector2.new(px+dx1,py+dy1)
                corners[i][2].From = Vector2.new(px,py); corners[i][2].To = Vector2.new(px+dx2,py+dy2)
                corners[i][1].Color = color; corners[i][2].Color = color
                corners[i][1].Thickness = 2; corners[i][2].Thickness = 2
                corners[i][1].Visible = true; corners[i][2].Visible = true
            end
            local cColor = cfg.visCheck and esp.box.Color or cfg.boxStandard
            setCorner(1, bx,   by,    cl, 0,  0, cl,  cColor)
            setCorner(2, bx+w, by,   -cl, 0,  0, cl,  cColor)
            setCorner(3, bx,   by+h,  cl, 0,  0, -cl, cColor)
            setCorner(4, bx+w, by+h, -cl, 0,  0, -cl, cColor)
            esp.box.Visible = false
            if esp.boxOutline then esp.boxOutline.Visible = false end
        elseif esp.corners then
            for _, c in ipairs(esp.corners) do c[1].Visible=false; c[2].Visible=false end
        end

        if cfg.healthBar then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.MaxHealth > 0 then
                local pct  = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                local barX = bx - (cfg.healthBarW or 4) - 2
                esp.hpBarBg.Position = Vector2.new(barX, by)
                esp.hpBarBg.Size     = Vector2.new(cfg.healthBarW or 4, h)
                esp.hpBarBg.Visible  = true
                local fillH = h * pct
                esp.hpBar.Position = Vector2.new(barX, by + (h - fillH))
                esp.hpBar.Size     = Vector2.new(cfg.healthBarW or 4, fillH)
                esp.hpBar.Color    = Color3.fromRGB(255*(1-pct), 255*pct, 0)
                esp.hpBar.Visible  = true
            else
                esp.hpBarBg.Visible = false; esp.hpBar.Visible = false
            end
        else
            esp.hpBarBg.Visible = false; esp.hpBar.Visible = false
        end

        esp.name.Position = Vector2.new(sv.X, by - 15)
        esp.name.Visible  = cfg.name
        if doText then
            esp.name.Size  = 14
            esp.name.Color = cfg.nameStandard
            esp.name.Text  = pl.Name
        end

        if party then
            esp.party.Position = Vector2.new(sv.X, by - 29)
            esp.party.Visible  = true
            if doText then esp.party.Size = 13; esp.party.Color = cfg.partyColor end
        else
            esp.party.Visible = false
        end

        if cfg.dist or cfg.equip then
            esp.dist.Position = Vector2.new(sv.X, by + h + 2)
            esp.dist.Visible  = true
            if doText then
                local parts = {}
                if cfg.dist  then parts[#parts+1] = math.floor(mag) .. " Studs" end
                if cfg.equip then parts[#parts+1] = getEquippedName(char) or "Unarmed" end
                local label = table.concat(parts, " | ")
                if label ~= esp.lastDistFloor then esp.dist.Text = label; esp.lastDistFloor = label end
                esp.dist.Size  = 13
                esp.dist.Color = cfg.distDyn and distanceColor(mag) or cfg.distColor
            end
        else
            esp.dist.Visible = false
        end
        esp.equipped.Visible = false

        if cfg.charms then
            local hl = esp.highlight
            if not (hl and hl.Parent) then
                hl = Instance.new("Highlight"); hl.Adornee = char; hl.Parent = char; esp.highlight = hl
            elseif hl.Adornee ~= char then hl.Adornee = char; hl.Parent = char end
            hl.FillColor           = cfg.charmsFill
            hl.FillTransparency    = cfg.charmsFillTransp
            hl.OutlineColor        = cfg.charmsOutline
            hl.OutlineTransparency = cfg.charmsOutlineTransp
            hl.DepthMode = cfg.charmsAlwaysOnTop
                and Enum.HighlightDepthMode.AlwaysOnTop
                or  Enum.HighlightDepthMode.Occluded
            hl.Enabled = true
        else
            if esp.highlight then esp.highlight.Enabled = false end
        end

        if not cfg.lookLine then
            esp.lookLine.Visible = false
        elseif doLook then
            local hv, hs = worldToScreen(headPos)
            local lv, ls = worldToScreen(headPos + head.CFrame.LookVector*15)
            if hs and ls then
                esp.lookLine.From = Vector2.new(hv.X, hv.Y)
                esp.lookLine.To   = Vector2.new(lv.X, lv.Y)
                if lookRefPart then
                    local dot = head.CFrame.LookVector:Dot((lookRefPart.Position - headPos).Unit)
                    esp.lookLine.Color = dot>0.9 and colorRed or (dot>-0.3 and colorYellow or colorGreen)
                end
                esp.lookLine.Visible = true
            else esp.lookLine.Visible = false end
        end

        if cfg.skel and doSkel and ci.skeleton then
            for _, b in ipairs(esp.skeleton) do
                local pa = ci.skeleton[b.from]; local pb = ci.skeleton[b.to]
                if pa and pb then
                    local va, oa = worldToScreen(pa.Position)
                    local vb, ob = worldToScreen(pb.Position)
                    if oa and ob then
                        b.line.From=Vector2.new(va.X,va.Y); b.line.To=Vector2.new(vb.X,vb.Y)
                        b.line.Color=cfg.skelColor; b.line.Thickness=cfg.skelThick; b.line.Visible=true
                    else b.line.Visible=false end
                else b.line.Visible=false end
            end
        elseif esp.skeleton then
            for _, b in ipairs(esp.skeleton) do b.line.Visible=false end
        end

        if cfg.tracers then
            esp.tracer.From    = tracerOrigin or screenCenter()
            esp.tracer.To      = Vector2.new(sv.X, sv.Y)
            esp.tracer.Color   = cfg.tracerColor
            esp.tracer.Thickness = cfg.tracerThick
            esp.tracer.Visible = true
        else if esp.tracer then esp.tracer.Visible=false end end
    end
    if doLook then lastLookLineTick = now end
    if doSkel then lastSkeletonTick = now end
    if doText then espTextTime      = now end
end

local function watchPlayerEsp(player)
    if player == LocalPlayer then return end
    player.CharacterRemoving:Connect(function()
        charInfoCache[player] = nil
        hidePlayerEsp(player)
        if espObjects[player] then
            local esp = espObjects[player]
            for k, v in pairs(esp) do
                if     k == "skeleton"  then for _, b in ipairs(v) do destroyDrawing(b.line) end
                elseif k == "corners"   then for _, c in ipairs(v) do destroyDrawing(c[1]); destroyDrawing(c[2]) end
                elseif k == "highlight" then if v then pcall(function() v:Destroy() end) end
                else destroyDrawing(v) end
            end
            espObjects[player] = nil
        end
    end)
end
for _, pl in ipairs(otherPlayers) do watchPlayerEsp(pl) end
Players.PlayerAdded:Connect(function(pl) watchPlayerEsp(pl) end)

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness=2; fovCircle.Filled=false; fovCircle.Transparency=0.7
fovCircle.Color=Color3.new(1,1,1); fovCircle.Visible=false

local function isMenuOrDeathOpen()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    local mm = pg:FindFirstChild("MainMenu")
    local ds = pg:FindFirstChild("DeathScreen")
    return (mm and mm.Enabled) or (ds and ds.Enabled)
end

local renderConn = RunService.RenderStepped:Connect(function()
    if not camera then return end
    local vp    = camera.ViewportSize
    viewportW   = vp.X; viewportH = vp.Y
    aspectRatio = viewportW / viewportH
    tanHalfFov  = math.tan(math.rad(camera.FieldOfView) * 0.5)
    local center = screenCenter()

    if fovCircle then
        fovCircle.Position = center
        fovCircle.Radius   = espFlags.FOV or 150
        fovCircle.Color    = Color3.new(1,1,1)
        fovCircle.Visible  = not espFlags.HideFOV
            and ((espFlags.Aim or espFlags.SilentAim) and not isMenuOrDeathOpen())
    end

    if espFlags.SilentAim and not isMenuOrDeathOpen() then
        silentTarget, silentTargetRoot, silentTargetPos = getSilentAimTarget()
    else
        silentTarget=nil; silentTargetRoot=nil; silentTargetPos=nil
    end

    local holdKey  = espFlags.NormalAimKey
    local pressing = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    if holdKey and holdKey ~= Enum.KeyCode.Unknown then
        pressing = pressing or UserInputService:IsKeyDown(holdKey)
    end
    local wantAim = espFlags.Aim and not espFlags.SilentAim
        and not isMenuOrDeathOpen() and hasWeaponEquipped() and pressing
    if not hasWeaponEquipped() and aimTarget then resetAimState() end
    if not wantAim then
        resetAimState()
    else
        local tgt = getOrPickAimTarget()
        if tgt and tgt.Parent then
            local par   = tgt.Parent
            local root2 = par:FindFirstChild("HumanoidRootPart")
            if root2 then
                local _, pos = getAimPart(par)
                local p = pos or tgt.Position
                if (espFlags.AimPart or "Head") == "Head" then p = p - Vector3.new(0, 0.6, 0) end
                if espFlags.Prediction then
                    p = p + tgt.AssemblyLinearVelocity
                        * ((p - camera.CFrame.Position).Magnitude / math.max(getPredictionVelocity(), 1))
                end
                local off = worldToFovOffset(p)
                if not off then
                    resetAimState()
                else
                    local eps = centerEpsilon()
                    if off.Magnitude > eps then
                        local slowdown = 1
                        if camera.FieldOfView < aimCfg.SCOPED_FOV_THRESHOLD then
                            slowdown = slowdown * aimCfg.SCOPED_SLOWDOWN_MULT
                        end
                        local step = clampMouseStep(off / slowdown, off, eps)
                        applyAimSensitivity()
                        if CAP.mousemoverel then pcall(mousemoverel, step.X, step.Y) end
                    else
                        applyAimSensitivity()
                    end
                end
            else resetAimState() end
        else resetAimState() end
    end

    updateVisibilityCache()
    renderPlayerEsp(center, myRoot)
end)

local function resetOnEvent()
    resetAimState()
    UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true
end
pcall(function()
    LocalPlayer:FindFirstChild("PlayerGui").DeathScreen
        :GetPropertyChangedSignal("Enabled"):Connect(function() resetOnEvent() end)
end)
LocalPlayer.CharacterRemoving:Connect(resetOnEvent)
LocalPlayer.CharacterAdded:Connect(function(c)
    myCharacter = c; myRoot = c:WaitForChild("HumanoidRootPart")
    resetOnEvent()
end)

installBulletHook()
installWallbang()

-- ═════════════════════════════════════════════════════════════════════════════
-- 6. AR2 / DROIDWARE WEAPON MODS
-- ═════════════════════════════════════════════════════════════════════════════
local warnLast = {}
local function warnOnce(key, msg, gap)
    local now = os.clock()
    if warnLast[key] and now - warnLast[key] < (gap or 3) then return end
    warnLast[key] = now; warn(msg)
end

local function AR2call(path, ...)
    local cur = getgenv()
    for seg in string.gmatch(path, "[^%.]+") do
        if type(cur) ~= "table" then cur = nil; break end
        cur = rawget(cur, seg)
    end
    if type(cur) ~= "function" then
        warnOnce("missing:"..path, "[OriginHUB] "..path.." not found in getgenv (DROIDWARE layer not loaded?)")
        return false
    end
    return pcall(cur, ...)
end

local originalFireModesCache = {}
local allFireModesConn       = nil
local allFireModes_table     = {"Automatic","Semiautomatic","Burst"}
local function AR2_getEquippedInner()
    local ok, pc = pcall(function()
        return require(ReplicatedFirst:WaitForChild("Framework",30)).Classes.Players.get()
    end)
    if not ok or not pc or not pc.Character then return nil end
    local item = pc.Character.EquippedItem
    if not item then return nil end
    return rawget(item,"__item") or item
end
local function applyToInner(inner)
    if not inner then return nil end
    local id = tostring(inner.Id or inner.ItemName or inner.Name or "unknown")
    if not originalFireModesCache[id] then
        originalFireModesCache[id] = inner.FireModes
    end
    inner.FireModes = allFireModes_table
    return inner
end
local function AR2_applyAllFireModes(enabled)
    if allFireModesConn then allFireModesConn:Disconnect(); allFireModesConn=nil end
    if not enabled then
        local inner = AR2_getEquippedInner()
        if inner then
            local id = tostring(inner.Id or inner.ItemName or inner.Name or "unknown")
            inner.FireModes = originalFireModesCache[id] or inner.FireModes
        end
        return
    end
    local last = applyToInner(AR2_getEquippedInner())
    allFireModesConn = RunService.Heartbeat:Connect(function()
        local inner = AR2_getEquippedInner()
        if inner and inner ~= last then last = applyToInner(inner) end
    end)
end

local instantReloadEnabled   = false
local instantReloadOrigMap   = {}
local instantReloadEquipConn = nil
local reloadWatchConn        = nil
local reloadWatchLast        = 0

local function getPlayerClass()
    local ok, pc = pcall(function()
        return require(ReplicatedFirst:WaitForChild("Framework",30)).Classes.Players.get()
    end)
    return ok and pc or nil
end

local function AR2_instantReloadHook()
    if not instantReloadEnabled then return end
    if not CAP.getupvalue then return end
    local pc = getPlayerClass()
    if not pc or not pc.Character then return end
    local item  = pc.Character.EquippedItem
    if not item then return end
    local inner = rawget(item,"__item") or item
    if not inner or type(inner.OnReload) ~= "function" then return end
    if inner.__reloadHooked then return end
    local findReloadAmmo = nil
    for i = 1, 20 do
        local ok2, val = pcall(debug.getupvalue, inner.OnReload, i)
        if not ok2 then break end
        if type(val) == "function" then
            local ok3, info = pcall(debug.getinfo, val)
            if ok3 and info and info.name == "findReloadAmmo" then
                findReloadAmmo = val; break
            end
        end
    end
    if not findReloadAmmo then return end
    local origOnReload = inner.OnReload
    instantReloadOrigMap[inner] = origOnReload
    local Network = nil
    local ok4, nr = pcall(function()
        return require(ReplicatedFirst:WaitForChild("Framework",30)).Libraries.Network
    end)
    if ok4 then Network = nr end
    inner.OnReload = function(gun, charClass, itemData, ...)
        if instantReloadEnabled then
            local ammoSel = findReloadAmmo(gun, charClass, itemData)
            if ammoSel and Network then
                Network:Send("Character Reload Firearm Initiated", gun.Id, ammoSel.Id)
                if gun.FireConfig and gun.FireConfig.InternalMag then
                    for _ = 1, gun.FireConfig.InternalMagSize do
                        Network:Send("Character Reload Firearm Committed", gun.Id, ammoSel.Id)
                    end
                else
                    Network:Send("Character Reload Firearm Committed", gun.Id, ammoSel.Id)
                end
                Network:Send("Character Reload Firearm Clear", gun.Id, ammoSel.Id)
            end
            return true
        end
        return origOnReload(gun, charClass, itemData, ...)
    end
    inner.__reloadHooked = true
end
local function AR2_instantReloadOnEquip()
    if instantReloadEquipConn then instantReloadEquipConn:Disconnect(); instantReloadEquipConn=nil end
    local pc = getPlayerClass()
    if not pc or not pc.Character then return end
    instantReloadEquipConn = pc.Character.EquipmentChanged:Connect(function()
        task.wait(0.1)
        if instantReloadEnabled then AR2_instantReloadHook() end
    end)
end
local function setInstantReloadEnabled(enabled)
    instantReloadEnabled = enabled
    if enabled then
        AR2_instantReloadHook(); AR2_instantReloadOnEquip()
        if not reloadWatchConn then
            reloadWatchConn = RunService.Heartbeat:Connect(function()
                if not instantReloadEnabled then
                    reloadWatchConn:Disconnect(); reloadWatchConn=nil; return
                end
                local now = os.clock()
                if now - reloadWatchLast < 4 then return end
                reloadWatchLast = now
                local inner = AR2_getEquippedInner()
                if inner and not inner.__reloadHooked then AR2_instantReloadHook() end
            end)
        end
    else
        if reloadWatchConn then reloadWatchConn:Disconnect(); reloadWatchConn=nil end
        reloadWatchLast = 0
        for inner, orig in pairs(instantReloadOrigMap) do
            if inner and type(inner.OnReload) == "function" then
                inner.OnReload = orig; inner.__reloadHooked = nil
            end
        end
        table.clear(instantReloadOrigMap)
        if instantReloadEquipConn then
            instantReloadEquipConn:Disconnect(); instantReloadEquipConn=nil
        end
    end
end

local autoReloadEnabled = false
local autoReloadConn    = nil
local autoReloadLast    = 0
local function AR2_setAutoReload(enabled)
    autoReloadEnabled = enabled
    if autoReloadConn then autoReloadConn:Disconnect(); autoReloadConn=nil end
    if not enabled then return end
    autoReloadConn = RunService.Heartbeat:Connect(function()
        if not autoReloadEnabled then return end
        local now = os.clock()
        if now - autoReloadLast < 1 then return end
        autoReloadLast = now
        pcall(function()
            local inner = AR2_getEquippedInner()
            if inner and inner.Attachments and inner.Attachments.Ammo then
                local ammo = inner.Attachments.Ammo.__item.WorkingAmount
                if ammo == 0 then
                    local VIM = game:GetService("VirtualInputManager")
                    VIM:SendKeyEvent(true,  Enum.KeyCode.R, false, game)
                    task.wait(0.05)
                    VIM:SendKeyEvent(false, Enum.KeyCode.R, false, game)
                end
            end
        end)
    end)
end

local alwaysSuppressedOrig = nil
local function applyAlwaysSuppressedHook()
    if alwaysSuppressedOrig then return end
    local ok, fw = pcall(function()
        return require(ReplicatedFirst:WaitForChild("Framework",30))
    end)
    if not ok or not fw then return end
    local bullets = fw.Libraries and fw.Libraries.Bullets
    if not (bullets and type(bullets.Fire)=="function") then return end
    alwaysSuppressedOrig = bullets.Fire
    if CAP.setreadonly then pcall(setreadonly, bullets, false) end
    pcall(rawset, bullets, "Fire", function(...)
        local args = {...}
        if espFlags.AlwaysSuppressed and args[4] then
            pcall(function() args[4].SuppressedByDefault = true end)
        end
        return alwaysSuppressedOrig(table.unpack(args))
    end)
    if CAP.setreadonly then pcall(setreadonly, bullets, true) end
end
local function AR2_setAlwaysSuppressed(enabled)
    espFlags.AlwaysSuppressed = enabled
    pcall(applyAlwaysSuppressedHook)
end
task.spawn(function()
    ReplicatedFirst:WaitForChild("Framework",30)
    pcall(applyAlwaysSuppressedHook)
end)

local vehEquipEnabled      = false
local vehEquipInVeh        = false
local vehEquipOrig         = nil
local vehEquipBulletHooked = false
local vehEquipOrigFire     = nil
do
    local RS = ReplicatedStorage
    local function withWritable(t, fn)
        if type(t) ~= "table" then return end
        local wasRO = false
        pcall(function() if isreadonly then wasRO = isreadonly(t) end end)
        pcall(function() if setreadonly then setreadonly(t, false) end end)
        pcall(fn)
        if wasRO then pcall(function() if setreadonly then setreadonly(t, true) end end) end
    end
    local TIMING   = {"NextEquipTime","LastEquipTime","EquipDelay","NextHotbarSwitchTime",
                      "UseDelay","CooldownTime","EquipCooldown","NextEquipValid","EquipReadyAt",
                      "SwitchTime","NextSwitchTime","HotbarSwitchTime","EquipTime","SelectTime"}
    local VEH_KEYS = {"IsVehicleDriver","Sitting","Mounting","Dismounting"}
    local function zeroTiming(item)
        if not item then return end
        withWritable(item, function()
            for _, f in ipairs(TIMING) do rawset(item,f,0) end
        end)
        local inner = rawget(item,"__item")
        if type(inner)=="table" then
            withWritable(inner, function()
                for _, f in ipairs(TIMING) do rawset(inner,f,0) end
            end)
        end
    end
    local function customVehEquip(self, item, ...)
        zeroTiming(item)
        if not vehEquipOrig then return end
        if not (vehEquipEnabled and vehEquipInVeh) then return vehEquipOrig(self, item, ...) end
        local saved = {}
        withWritable(self, function()
            for _, k in ipairs(VEH_KEYS) do saved[k]=rawget(self,k); rawset(self,k,false) end
            saved.isItemUsable = rawget(self,"isItemUsable")
            rawset(self,"isItemUsable", function() return true end)
        end)
        local ok2, res = pcall(vehEquipOrig, self, item, ...)
        withWritable(self, function()
            for _, k in ipairs(VEH_KEYS) do rawset(self,k,saved[k]) end
            rawset(self,"isItemUsable", saved.isItemUsable)
        end)
        return ok2 and res or nil
    end
    local function getPC()
        local ok2, pc = pcall(function() return require(RS.Client.Classes.Players).get() end)
        return ok2 and pc or nil
    end
    RunService.Heartbeat:Connect(function()
        pcall(function()
            local pc = getPC()
            if pc and pc.Character then
                vehEquipInVeh = pc.Character.IsVehicleDriver == true
            end
        end)
    end)
    local okC, Chars = pcall(function() return require(RS.Client.Classes.Characters) end)
    if okC and Chars then vehEquipOrig = Chars.Equip end
    local function patchChar(char)
        if not char or not vehEquipOrig then return end
        if not CAP.getrawmetatable then return end
        pcall(function()
            local mt = getrawmetatable(char)
            if not mt then return end
            local oldIdx = rawget(mt,"__index")
            withWritable(mt, function()
                rawset(mt,"__index", function(self, key)
                    if vehEquipEnabled and key=="Equip" then return customVehEquip end
                    if type(oldIdx)=="function" then return oldIdx(self,key)
                    elseif oldIdx ~= nil         then return oldIdx[key] end
                end)
            end)
        end)
    end
    local function hookVehBullets()
        if vehEquipBulletHooked then return end
        local ok3, Bullets = pcall(function() return require(RS.Client.Libraries.Bullets) end)
        if not ok3 or not Bullets or not Bullets.Fire then return end
        vehEquipOrigFire = Bullets.Fire
        withWritable(Bullets, function()
            rawset(Bullets, "Fire", function(self, ...)
                local args = { ... }
                local wd = args[3]
                if vehEquipEnabled and wd then
                    withWritable(wd, function()
                        wd.CanFire=true; wd.CanFireInVehicles=true
                        wd.InVehicle=false; wd.VehicleFireLocked=false
                    end)
                    local inner = rawget(wd,"__item")
                    if type(inner)=="table" then
                        withWritable(inner, function()
                            inner.CanFire=true; inner.CanFireInVehicles=true
                            inner.InVehicle=false; inner.VehicleFireLocked=false
                        end)
                    end
                end
                return vehEquipOrigFire(self, table.unpack(args))
            end)
        end)
        vehEquipBulletHooked = true
    end
    local pc0 = getPC()
    if pc0 and pc0.Character then patchChar(pc0.Character) end
    hookVehBullets()
    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(1)
        local pc2 = getPC()
        if pc2 then
            local ok5, C = pcall(function() return require(RS.Client.Classes.Characters) end)
            if ok5 and C and C.Equip then vehEquipOrig = C.Equip end
            if pc2.Character then patchChar(pc2.Character) end
        end
    end)
end
local function AR2_setVehicleEquip(enabled) vehEquipEnabled = enabled end

local function AR2_hbeSetEnabled(enabled)
    if type(rawget(getgenv(),"AR2_hbeSetEnabled")) == "function" then
        pcall(getgenv().AR2_hbeSetEnabled, enabled)
    end
end
local function AR2_rageBotSetEnabled(enabled)
    if type(rawget(getgenv(),"AR2_rageBotSetEnabled")) == "function" then
        pcall(getgenv().AR2_rageBotSetEnabled, enabled)
    end
end
local function AR2_shotLogStart()
    if type(rawget(getgenv(),"AR2_shotLogStart")) == "function" then
        pcall(getgenv().AR2_shotLogStart)
    end
end

local wallbangTagConn = nil
local wallbangSaved   = {}
local WALLBANG_GROUPS = {[7]=true,[8]=true,[9]=true,[11]=true,[17]=true}
local function isCharPart(part)
    local p = part.Parent
    while p do
        local hum = p:FindFirstChildOfClass("Humanoid")
        if hum and Players:GetPlayerFromCharacter(p) then return true end
        p = p.Parent
    end
    return false
end
local function tagPart(part)
    if not espFlags.WallbangTag then return end
    if part.Name=="ar2_hbe_head" or part:GetAttribute("ar2_hbe") then return end
    if part:IsA("BasePart") and not isCharPart(part)
       and not CollectionService:HasTag(part,"Bullets Penetrate") then
        CollectionService:AddTag(part,"Bullets Penetrate")
        pcall(function() part:SetAttribute("ar2_tagged",true) end)
    end
end
local function AR2_wallbangForcePart(part)
    if not part:IsA("BasePart") then return end
    if part.Name=="ar2_hbe_head" or part:GetAttribute("ar2_hbe") then return end
    if isCharPart(part) then return end
    if Characters and part:IsDescendantOf(Characters) then return end
    if Zombies    and part:IsDescendantOf(Zombies)    then return end
    if Vehicles   and part:IsDescendantOf(Vehicles)   then return end
    if part:IsA("VehicleSeat") or part:IsA("Seat") then return end
    local gid = part.CollisionGroupId
    if WALLBANG_GROUPS[gid] then
        wallbangSaved[part] = gid
        pcall(function() part.CollisionGroupId = 0 end)
    end
    tagPart(part)
end
local function AR2_untagEverything()
    pcall(function()
        for _, p in ipairs(CollectionService:GetTagged("Bullets Penetrate")) do
            if p:IsA("BasePart") and p:GetAttribute("ar2_tagged") then
                CollectionService:RemoveTag(p,"Bullets Penetrate")
                pcall(function() p:SetAttribute("ar2_tagged",nil) end)
            end
        end
    end)
end
local function startWallbangTagging()
    espFlags.WallbangTag = true
    if wallbangTagConn then return end
    for _, p in ipairs(workspace:GetDescendants()) do AR2_wallbangForcePart(p) end
    local mapF = workspace:FindFirstChild("Map")
    if mapF then for _, d in ipairs(mapF:GetDescendants()) do AR2_wallbangForcePart(d) end end
    wallbangTagConn = workspace.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then AR2_wallbangForcePart(d)
        elseif d:IsA("Humanoid") then
            local m = d.Parent
            if m and m:IsA("Model") then
                for _, p in ipairs(m:GetDescendants()) do
                    if p:IsA("BasePart") then
                        if CollectionService:HasTag(p,"Bullets Penetrate") then
                            CollectionService:RemoveTag(p,"Bullets Penetrate")
                        end
                        wallbangSaved[p] = nil
                    end
                end
            end
        end
    end)
end
local function stopWallbangTagging()
    espFlags.WallbangTag = false
    if wallbangTagConn then wallbangTagConn:Disconnect(); wallbangTagConn=nil end
    AR2_untagEverything()
    for part, gid in pairs(wallbangSaved) do
        pcall(function() if part and part.Parent then part.CollisionGroupId = gid end end)
    end
    wallbangSaved = {}
end

local function AR2_toggleHitmarker(enabled)
    if type(rawget(getgenv(),"AR2_toggleHitmarker")) == "function" then
        pcall(getgenv().AR2_toggleHitmarker, enabled)
    end
end
local function AR2_toggleCrosshair(enabled)
    if type(rawget(getgenv(),"AR2_toggleCrosshair")) == "function" then
        pcall(getgenv().AR2_toggleCrosshair, enabled)
    end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- 7. xsx / Consistt UI
-- ═════════════════════════════════════════════════════════════════════════════
local library = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Consistt/Ui/main/UnLeaked"
))()

library.rank  = "developer"
library.title = "ars.swoir"

local Wm    = library:Watermark(
    "ars.swoir | v"..library.version
    .." | "..library:GetUsername()
    .." | rank: "..library.rank
)
local FpsWm = Wm:AddWatermark("fps: "..library.fps)
coroutine.wrap(function()
    while task.wait(0.75) do FpsWm:Text("fps: "..library.fps) end
end)()

local Notif = library:InitNotifications()
Notif:Notify("Loading ars.swoir, please wait.", 5, "information")
library:Introduction()
task.wait(1)
local Init = library:Init()

local function safeBlock(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        warn("[OriginHUB] tab '"..name.."' failed: "..tostring(err))
        pcall(function() Notif:Notify("Tab '"..name.."' failed, see console", 6, "error") end)
    end
end
local function tryWidget(label, fn)
    local ok, err = pcall(fn)
    if not ok then warn("[OriginHUB] widget '"..label.."' failed: "..tostring(err)) end
end
local function ar2Single(tab, label, fn)
    tab:NewToggle(label, false, function(v) AR2call(fn, v) end)
end
local function ar2Pair(tab, label, on, off)
    tab:NewToggle(label, false, function(v) AR2call(v and on or off) end)
end

local unloadHotkeyConn = nil
local function unloadAll()
    if renderConn        then renderConn:Disconnect();        renderConn        = nil end
    if unloadHotkeyConn  then unloadHotkeyConn:Disconnect();  unloadHotkeyConn  = nil end
    toggleFullbright(false)
    restoreGunMods()
    removeBulletHook(); removeWallbang(); stopWallbangTagging()
    AR2_applyAllFireModes(false); setInstantReloadEnabled(false); AR2_setAutoReload(false)
    resetAimState()
    AR2call("AR2_unload")
    for _, esp in pairs(espObjects) do
        for k, v2 in pairs(esp) do
            if     k == "skeleton"  then for _, b in ipairs(v2) do destroyDrawing(b.line) end
            elseif k == "corners"   then for _, c in ipairs(v2) do destroyDrawing(c[1]); destroyDrawing(c[2]) end
            elseif k == "highlight" then if v2 then pcall(function() v2:Destroy() end) end
            else destroyDrawing(v2) end
        end
    end
    espObjects = {}
    if fovCircle  then destroyDrawing(fovCircle) end
    if beamHolder then pcall(function() beamHolder:Destroy() end) end
    pcall(function() Init:Remove() end); pcall(function() Wm:Remove() end)
    getgenv().ORIGIN_HUB_ACTIVE = nil
end
getgenv().OriginHUB_Unload = unloadAll

unloadHotkeyConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightAlt then
        warn("[OriginHUB] fallback unload hotkey (RightAlt) pressed")
        unloadAll()
    end
end)

-- ── TAB: Aimbot ───────────────────────────────────────────────────────────────
safeBlock("Aimbot", function()
    local TabAim = Init:NewTab("Aimbot")
    TabAim:NewSection("Aimbot")
    local tAim = TabAim:NewToggle("Enabled", false, function(v) espFlags.Aim = v end)
    tryWidget("Aimbot keybind J", function() tAim:AddKeybind(Enum.KeyCode.J) end)
    TabAim:NewSlider("FOV", "", true, "px",
        { min=1, max=400, default=150 }, function(v) espFlags.FOV = v end)
    TabAim:NewSlider("Max Distance", "", true, "m",
        { min=100, max=10000, default=1200 }, function(v) espFlags.AimDist = v end)
    tryWidget("Aim Part selector", function()
        TabAim:NewSelector("Aim Part", "Head",
            {"Head","UpperTorso","Legs","Random"}, function(v) espFlags.AimPart = v end)
    end)
    TabAim:NewToggle("Wall Check",        false, function(v) espFlags.WallCheck  = v end)
    TabAim:NewToggle("Prediction",        true,  function(v) espFlags.Prediction = v end)
    TabAim:NewToggle("Hide FOV Circle",   false, function(v) espFlags.HideFOV    = v end)
    TabAim:NewSection("Silent Aimbot")
    local tSilent = TabAim:NewToggle("Enabled", false, function(v) espFlags.SilentAim = v end)
    tryWidget("Silent aim keybind K", function() tSilent:AddKeybind(Enum.KeyCode.K) end)
    TabAim:NewSlider("Hit Chance", "", false, "%",
        { min=0, max=100, default=100 }, function(v) espFlags.SilentHitChance = v end)
    TabAim:NewToggle("Prediction (Silent)", true, function(v) espFlags.Prediction = v end)
end)

-- ── TAB: ESP ──────────────────────────────────────────────────────────────────
safeBlock("ESP", function()
    local TabESP = Init:NewTab("ESP")
    TabESP:NewSection("Players")
    TabESP:NewToggle("Enabled",          true,  function(v) espFlags.ESP          = v end)
    TabESP:NewToggle("Box",              true,  function(v) espFlags.Box          = v end)
    TabESP:NewToggle("Names",            true,  function(v) espFlags.Name         = v end)
    TabESP:NewToggle("Distance",         true,  function(v) espFlags.Dist         = v end)
    TabESP:NewToggle("Equipped",         true,  function(v) espFlags.Equip        = v end)
    TabESP:NewToggle("Charms",           false, function(v) espFlags.Charms       = v end)
    TabESP:NewToggle("Skeleton",         false, function(v) espFlags.ShowSkeleton = v end)
    TabESP:NewToggle("Show Tracers",     false, function(v) espFlags.ShowTracers  = v end)
    TabESP:NewToggle("Party Tag",        true,  function(v) espFlags.PartyTag     = v end)
    TabESP:NewToggle("Look Direction",   false, function(v) espFlags.LookLine     = v end)
    TabESP:NewSlider("Max Distance", "", true, "m",
        { min=500, max=10000, default=2000 }, function(v) espFlags.MaxDist = v end)
    TabESP:NewSection("Style")
    TabESP:NewToggle("Dynamic Distance Color", true,  function(v) espFlags.DistDynamicColor  = v end)
    TabESP:NewToggle("Charms Always On Top",   false, function(v) espFlags.CharmsAlwaysOnTop = v end)
    TabESP:NewSection("Advanced")
    TabESP:NewToggle("Visibility Check",  false, function(v) espFlags.VisCheck        = v end)
    TabESP:NewToggle("Health Bar",        false, function(v) espFlags.HealthBar        = v end)
    TabESP:NewToggle("Corner Box Style",  false, function(v) espFlags.CornerBox        = v end)
    TabESP:NewSlider("Corner Length", "", false, "px",
        { min=2, max=20, default=6 }, function(v) espFlags.CornerLen = v end)
    TabESP:NewToggle("Off-Screen Arrows", false, function(v) espFlags.OffscreenArrows = v end)
    TabESP:NewSlider("Arrow Max Distance", "", true, "m",
        { min=20, max=1000, default=120 }, function(v) espFlags.ArrowDist = v end)
end)

-- ── TAB: Weapon ───────────────────────────────────────────────────────────────
safeBlock("Weapon", function()
    local TabWeapon = Init:NewTab("Weapon")
    TabWeapon:NewSection("Mods")
    TabWeapon:NewToggle("No Recoil", false, function(v)
        espFlags.NoRecoil = v
        pcall(applyGunMods)
    end)
    TabWeapon:NewToggle("No Spread", false, function(v)
        espFlags.NoSpread = v
        pcall(applyGunMods)
    end)
    TabWeapon:NewToggle("Wallbang (resolver)", false, function(v) espFlags.Wallbang = v end)
    TabWeapon:NewToggle("Shot Tracers",        false, function(v) espFlags.Tracers  = v end)
    TabWeapon:NewSection("Combat")
    TabWeapon:NewToggle("Rage Bot", false, function(v)
        AR2_rageBotSetEnabled(v)
    end)
    TabWeapon:NewToggle("Shot Logger", false, function(v)
        if v then AR2_shotLogStart() end
    end)
    TabWeapon:NewToggle("Hitmarker", false, function(v)
        AR2_toggleHitmarker(v)
    end)
    TabWeapon:NewToggle("Crosshair", false, function(v)
        AR2_toggleCrosshair(v)
    end)
end)

-- ── TAB: Visuals ──────────────────────────────────────────────────────────────
safeBlock("Visuals", function()
    local TabVisuals = Init:NewTab("Visuals")
    TabVisuals:NewSection("Effects")
    TabVisuals:NewToggle("Fullbright", false, function(v) toggleFullbright(v) end)
    ar2Single(TabVisuals, "FOV Zoom",    "AR2_toggleFOVZoom")
    ar2Single(TabVisuals, "Dist Zoom",   "AR2_toggleDistZoomEnabled")
    ar2Single(TabVisuals, "3P ADS",      "AR2_set3pAds")
    ar2Single(TabVisuals, "Hide Player", "AR2_toggleHidePlayer")
    ar2Single(TabVisuals, "Hide Gun",    "AR2_toggleHideGun")
    ar2Pair  (TabVisuals, "Radar",       "AR2_radar.start", "AR2_radar.destroy")
    TabVisuals:NewToggle("Minimap", false, function(v)
        if v then getgenv().AR2_minimapEnabled = true; AR2call("AR2_updateMinimap") end
    end)
    TabVisuals:NewSection("Cleanup")
    ar2Single(TabVisuals, "Remove Shadows",  "AR2_setRemoveShadows")
    ar2Single(TabVisuals, "Remove Doors",    "AR2_setRemoveDoors")
    ar2Single(TabVisuals, "Remove Sun Rays", "AR2_setRemoveSunRays")
    ar2Single(TabVisuals, "Remove Textures", "AR2_toggleRemoveTextures")
    ar2Single(TabVisuals, "Remove Leaves",   "AR2_toggleRemoveLeaves")
    ar2Single(TabVisuals, "Remove Bushes",   "AR2_toggleRemoveBushes")
    TabVisuals:NewLabel("Color Correction", "left")
    TabVisuals:NewToggle("CC Enabled", false, function(v)
        AR2call("AR2_setColorCorrection", v, nil, nil, nil)
    end)
    TabVisuals:NewSlider("Saturation", "", false, "",
        { min=-100, max=100, default=0 }, function(v)
            AR2call("AR2_setColorCorrection", nil, v, nil, nil)
        end)
    TabVisuals:NewSlider("Contrast", "", false, "",
        { min=-100, max=100, default=0 }, function(v)
            AR2call("AR2_setColorCorrection", nil, nil, v, nil)
        end)
    TabVisuals:NewSlider("Brightness", "", false, "",
        { min=-100, max=100, default=0 }, function(v)
            AR2call("AR2_setColorCorrection", nil, nil, nil, v)
        end)
end)

-- ── TAB: Misc ─────────────────────────────────────────────────────────────────
safeBlock("Misc", function()
    local TabMisc = Init:NewTab("Misc")
    TabMisc:NewSection("Player")
    ar2Pair  (TabMisc, "Freeze Players", "AR2_freeze.start", "AR2_freeze.destroy")
    ar2Single(TabMisc, "Self Backtrack", "AR2_setSelfBacktrack")
    ar2Single(TabMisc, "Jump Circle",    "AR2_setJumpCircle")
    ar2Single(TabMisc, "Zombie Circle",  "AR2_setZombieCircle")
    ar2Single(TabMisc, "Charm",          "AR2_toggleCharm")
    ar2Single(TabMisc, "Cos Unlock",     "AR2_cosSetEnabled")
    ar2Single(TabMisc, "Respawn TP",     "AR2_toggleRespawnTP")
    TabMisc:NewToggle("AR2 Tracers", false, function(v)
        getgenv().AR2_tracersEnabled = v
        AR2call("AR2_tracersUpdate")
    end)
    TabMisc:NewSection("Session")
    TabMisc:NewButton("Unload All", function()
        local ok, err = pcall(unloadAll)
        if not ok then warn("[OriginHUB] Unload All button error: "..tostring(err)) end
    end)
    TabMisc:NewButton("Reload UI", function()
        local ok, err = pcall(function()
            unloadAll()
            loadstring(readfile("ui.lua"))()
        end)
        if not ok then warn("[OriginHUB] Reload UI button error: "..tostring(err)) end
    end)
    TabMisc:NewLabel("RightShift = hide / show UI, RightAlt = force unload", "left")
end)

-- ── keybind / done ────────────────────────────────────────────────────────────
pcall(function() Init:UpdateKeybind(Enum.KeyCode.RightShift) end)
Notif:Notify("ars.swoir loaded~", 4, "success")
getgenv().OriginHUB_Window = Init
