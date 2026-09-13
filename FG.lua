-- =================================================================
-- 1. แกนหลักและระบบตรวจสอบบทบาท (MM2 Core Logic)
-- =================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local function GetCharacter() return LocalPlayer.Character end
local function GetHRP()
    local c = GetCharacter()
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ฟังก์ชันตรวจสอบบทบาท
local function GetRole(plr)
    plr = plr or LocalPlayer
    local char = plr.Character
    if not char then return "Unknown" end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return "Dead" end

    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then
            local n = t.Name:lower()
            if n:find("knife") then return "Murderer" end
            if n:find("gun") then return "Sheriff" end
        end
    end

    local bp = plr:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then
                local n = t.Name:lower()
                if n:find("knife") then return "Murderer?" end
                if n:find("gun") then return "Sheriff?" end
            end
        end
    end
    return "Innocent"
end

local function RoleColor(role)
    if role == "Murderer" or role == "Murderer?" then return Color3.fromRGB(220,50,50)
    elseif role == "Sheriff" or role == "Sheriff?" then return Color3.fromRGB(50,120,255)
    elseif role == "Dead" then return Color3.fromRGB(120,120,120)
    else return Color3.fromRGB(80,220,120) end
end

-- Variables ควบคุมสถานะการทำงานอัตโนมัติ
local autoKillEnabled = true
local silentAimEnabled = true
local sheriffSettings = { fov = 150, hitPart = "Head", hitChance = 100 }

-- =================================================================
-- 2. ระบบนายอำเภอ ล็อกเป้าอัตโนมัติ (Auto Sheriff Silent Aim)
-- =================================================================
local function getAimTarget()
    if not silentAimEnabled then return nil end
    local role = GetRole(LocalPlayer)
    if role ~= "Sheriff" and role ~= "Sheriff?" then return nil end -- ทำงานเฉพาะตอนเป็นนายอำเภอ
    
    if math.random(1,100) > sheriffSettings.hitChance then return nil end
    
    local camPos = Camera.CFrame.Position
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local mPos = UserInputService:GetMouseLocation()
    local ref = (mPos.Magnitude < 5) and center or mPos
    local bestPart, bestScore = nil, math.huge
    
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if char and hum and hum.Health > 0 then
                -- ล็อกเฉพาะฆาตกรเท่านั้น
                local tRole = GetRole(plr)
                if tRole == "Murderer" or tRole == "Murderer?" then
                    local part = char:FindFirstChild(sheriffSettings.hitPart) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
                    if part and part:IsA("BasePart") then
                        local sp, on = Camera:WorldToViewportPoint(part.Position)
                        if on and sp.Z > 0 then
                            local d = (Vector2.new(sp.X, sp.Y) - ref).Magnitude
                            if d <= sheriffSettings.fov and d < bestScore then
                                bestScore = d
                                bestPart = part
                            end
                        end
                    end
                end
            end
        end
    end
    return bestPart
end

-- Hook กระสุนปืน
do
    local G = getgenv and getgenv() or _G
    if not G.OxideSheriffHooked then
        G.OxideSheriffHooked = true
        local mod
        pcall(function() mod = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GunHandler")) end)
        local HookFn = hookfunction or replaceclosure
        
        if mod and type(mod.shoot) == "function" and HookFn then
            local orig
            orig = HookFn(mod.shoot, function(p26)
                if silentAimEnabled and p26 and p26.Shooter == LocalPlayer.Character and p26.AimPosition then
                    local tgt = getAimTarget()
                    if tgt then p26.AimPosition = tgt.Position + (tgt.AssemblyLinearVelocity or Vector3.zero) * 0.13 end
                end
                return orig(p26) end)
        elseif mod and type(mod.getAim) == "function" and HookFn then
            local orig
            orig = HookFn(mod.getAim, function(origin, range)
                if silentAimEnabled then
                    local t = getAimTarget()
                    if t then return (t.Position - origin).Unit, (t.Position - origin).Magnitude end
                end
                return orig(origin, range) end)
        else
            local origRay = Workspace.Raycast
            Workspace.Raycast = function(self, origin, direction, params)
                if silentAimEnabled and self == Workspace and direction and direction.Magnitude > 30 then
                    local t = getAimTarget()
                    if t then
                        local newDir = (t.Position - origin).Unit * direction.Magnitude
                        return origRay(self, origin, newDir, params)
                    end
                end
                return origRay(self, origin, direction, params)
            end
        end
    end
end

-- =================================================================
-- 3. ระบบมองทะลุกำแพงอัตโนมัติแยกสีบทบาท (Auto Chams ESP)
-- =================================================================
local function ApplyChams(p)
    if p == LocalPlayer then return end
    local function setupCharacter(char)
        char:WaitForChild("HumanoidRootPart")
        local highlight = char:FindFirstChild("OxideMm2ESP")
        if not highlight then
            highlight = Instance.new("Highlight")
            highlight.Name = "OxideMm2ESP"
            highlight.FillTransparency = 0.55
            highlight.OutlineTransparency = 0
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = char
        end
        
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if char and char.Parent and highlight then
                local currentRole = GetRole(p)
                local color = RoleColor(currentRole)
                highlight.FillColor = color
                highlight.OutlineColor = color
            else
                conn:Disconnect()
            end
        end)
    end
    if p.Character then setupCharacter(p.Character) end
    p.CharacterAdded:Connect(setupCharacter)
end

for _, p in ipairs(Players:GetPlayers()) do ApplyChams(p) end
Players.PlayerAdded:Connect(ApplyChams)

-- =================================================================
-- 4. ระบบฆาตกรดึงมาฟันอัตโนมัติทันทีแบบวนลูป (Loop Auto Kill)
-- =================================================================
task.spawn(function()
    while true do
        task.wait(0.5) -- ตรวจสอบทุกๆ 0.5 วินาที
        if autoKillEnabled then
            local role = GetRole(LocalPlayer)
            if role == "Murderer" or role == "Murderer?" then
                local character = LocalPlayer.Character
                if character then
                    local knife = character:FindFirstChild("Knife") or LocalPlayer.Backpack:FindFirstChild("Knife")
                    if knife then
                        -- ถือมีดอัตโนมัติ
                        if knife.Parent == LocalPlayer.Backpack then knife.Parent = character end
                        
                        -- ดึงคนมาสับโจมตี
                        for _, target in ipairs(Players:GetPlayers()) do
                            if target ~= LocalPlayer and target.Character and target.Character:FindFirstChild("HumanoidRootPart") and target.Character:FindFirstChild("Humanoid").Health > 0 then
                                target.Character.HumanoidRootPart.Anchored = true 
                                target.Character.HumanoidRootPart.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -2)
                                
                                task.spawn(function()
                                    if knife:FindFirstChild("Stab") then knife.Stab:FireServer()
                                    elseif knife:FindFirstChild("Slash") then knife.Slash:FireServer() end
                                end)
                                
                                task.wait(0.1)
                                target.Character.HumanoidRootPart.Anchored = false
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- =================================================================
-- 5. GUI ปุ่มลอยบอกสถานะ (ขยับดุ๊กดิ๊ก/เปิด-ปิดสวิตช์ได้)
-- =================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MM2_AutoRun_Gui"
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.ResetOnSpawn = false

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 80, 0, 170)
MainFrame.Position = UDim2.new(0.85, 0, 0.4, 0)
MainFrame.BackgroundTransparency = 1
MainFrame.Parent = ScreenGui

-- ปุ่มมีด (Auto Kill Status)
local KnifeButton = Instance.new("ImageButton")
KnifeButton.Size = UDim2.new(0, 70, 0, 70)
KnifeButton.Position = UDim2.new(0, 5, 0, 5)
KnifeButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0) -- เปิดอัตโนมัติตั้งแต่เริ่ม
KnifeButton.BackgroundTransparency = 0.3
KnifeButton.Image = "rbxassetid://13589574488"
KnifeButton.Parent = MainFrame
Instance.new("UICorner", KnifeButton).CornerRadius = UDim.new(0, 15)

local KnifeText = Instance.new("TextLabel")
KnifeText.Size = UDim2.new(1, 0, 0, 15)
KnifeText.Position = UDim2.new(0, 0, 1, 1)
KnifeText.BackgroundTransparency = 1
KnifeText.Text = "AUTO KILL: ON"
KnifeText.TextColor3 = Color3.fromRGB(85, 255, 85)
KnifeText.TextSize = 9
KnifeText.Font = Enum.Font.SourceSansBold
KnifeText.Parent = KnifeButton

-- ปุ่มกระสุน (Auto Aim Status)
local BulletButton = Instance.new("ImageButton")
BulletButton.Size = UDim2.new(0, 70, 0, 70)
BulletButton.Position = UDim2.new(0, 5, 0, 90)
BulletButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0) -- เปิดอัตโนมัติตั้งแต่เริ่ม
BulletButton.BackgroundTransparency = 0.3
BulletButton.Image = "rbxassetid://13846663276"
BulletButton.Parent = MainFrame
Instance.new("UICorner", BulletButton).CornerRadius = UDim.new(0, 15)

local BulletText = Instance.new("TextLabel")
BulletText.Size = UDim2.new(1, 0, 0, 15)
BulletText.Position = UDim2.new(0, 0, 1, 1)
BulletText.BackgroundTransparency = 1
BulletText.Text = "AUTO AIM: ON"
BulletText.TextColor3 = Color3.fromRGB(85, 255, 85)
BulletText.TextSize = 9
BulletText.Font = Enum.Font.SourceSansBold
BulletText.Parent = BulletButton

-- แอนิเมชันขยับดุ๊กดิ๊กหมุนวนลูป
task.spawn(function()
while true do
local info = TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
TweenService:Create(KnifeButton, info, {Rotation = 15, Size = UDim2.new(0, 74, 0, 74)}):Play()
TweenService:Create(BulletButton, info, {Rotation = -15, Size = UDim2.new(0, 74, 0, 74)}):Play()
task.wait(1.3)
end
end)

-- ระบบลากหน้าต่างย้ายตำแหน่งบนหน้าจอ
local dragging, dragInput, dragStart, startPos
MainFrame.InputBegan:Connect(function(input)
if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
dragging = true
dragStart = input.Position
startPos = MainFrame.Position
end
end)

MainFrame.InputChanged:Connect(function(input)
if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
dragInput = input
end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
if input == dragInput and dragging then
local delta = input.Position - dragStart
MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end
end)

-- สามารถกดที่ปุ่มเพื่อปิด/เปิดระบบชั่วคราวได้หากต้องการ
KnifeButton.MouseButton1Click:Connect(function()
autoKillEnabled = not autoKillEnabled
if autoKillEnabled then
KnifeButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
KnifeText.Text = "AUTO KILL: ON"
KnifeText.TextColor3 = Color3.fromRGB(85, 255, 85)
else
KnifeButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
KnifeText.Text = "AUTO KILL: OFF"
KnifeText.TextColor3 = Color3.fromRGB(255, 85, 85)
end
end)

BulletButton.MouseButton1Click:Connect(function()
silentAimEnabled = not silentAimEnabled
if silentAimEnabled then
BulletButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
BulletText.Text = "AUTO AIM: ON"
BulletText.TextColor3 = Color3.fromRGB(85, 255, 85)
else
BulletButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
BulletText.Text = "AUTO AIM: OFF"
BulletText.TextColor3 = Color3.fromRGB(255, 85, 85)
end
end)

-- ส่งแจ้งเตือนเมื่อสคริปต์เริ่มทำงาน
game:GetService("StarterGui"):SetCore("SendNotification", {
Title = "MM2 Experia Active",
Text = "ระบบ Auto All เริ่มทำงานแล้ว!",
Duration = 4
})

