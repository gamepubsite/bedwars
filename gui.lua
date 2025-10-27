repeat task.wait() until game:IsLoaded()

local run = function(func) func() end
local cloneref = cloneref or function(obj) return obj end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local inputService = cloneref(game:GetService('UserInputService'))
local contextActionService = cloneref(game:GetService('ContextActionService'))
local lplr = playersService.LocalPlayer
local playerGui = lplr:WaitForChild("PlayerGui")

-- Load saved statuses
local sprintEnabled = false
local success, saved = pcall(function()
    return readfile('sprint_status.txt')
end)
if success and saved == 'true' then
    sprintEnabled = true
end

local noslowEnabled = false
local success2, saved2 = pcall(function()
    return readfile('noslow_status.txt')
end)
if success2 and saved2 == 'true' then
    noslowEnabled = true
end

local hitboxesEnabled = false
local success3, saved3 = pcall(function()
    return readfile('hitboxes_status.txt')
end)
if success3 and saved3 == 'true' then
    hitboxesEnabled = true
end


-- Bedwars and entitylib setup
local bedwars, entitylib = {}, {List = {}, Running = false, Events = {}, character = {}, isAlive = false, PlayerConnections = {}, EntityThreads = {}, EntityConnections = {}}
local store = {
    attackReach = 0,
    attackReachUpdate = tick(),
    damageBlockFail = tick(),
    hand = {},
    inventory = {
        inventory = {
            items = {},
            armor = {}
        },
        hotbar = {}
    },
    inventories = {},
    matchState = 0,
    queueType = 'bedwars_test',
    tools = {}
}

local function waitForChildOfType(obj, name, timeout, prop)
    timeout = timeout or 10
    local check, returned = tick() + timeout
    repeat
        returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
        if returned or check < tick() then
            break
        end
        task.wait()
    until false
    return returned
end

local function getShieldAttribute(char)
    local returned = 0
    for name, val in char:GetAttributes() do
        if name:find('Shield') and type(val) == 'number' and val > 0 then
            returned += val
        end
    end
    return returned
end

local function isFriend(plr, recolor)
    return false  -- Simplified for this script
end

local function isTarget(plr)
    return false  -- Simplified for this script
end

local function collection(tags, module, customadd, customremove)
    tags = typeof(tags) ~= 'table' and {tags} or tags
    local objs, connections = {}, {}

    for _, tag in tags do
        table.insert(connections, collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
            if customadd then
                customadd(objs, v, tag)
                return
            end
            table.insert(objs, v)
        end))
        table.insert(connections, collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
            if customremove then
                customremove(objs, v, tag)
                return
            end
            v = table.find(objs, v)
            if v then
                table.remove(objs, v)
            end
        end))

        for _, v in collectionService:GetTagged(tag) do
            if customadd then
                customadd(objs, v, tag)
                continue
            end
            table.insert(objs, v)
        end
    end

    local cleanFunc = function(self)
        for _, v in connections do
            v:Disconnect()
        end
        table.clear(connections)
        table.clear(objs)
        table.clear(self)
    end
    if module then
        module:Clean(cleanFunc)
    end
    return objs, cleanFunc
end

local collectionService = cloneref(game:GetService('CollectionService'))
local vapeEvents = setmetatable({}, {
    __index = function(self, index)
        self[index] = Instance.new('BindableEvent')
        return self[index]
    end
})

run(function()
    local function dumpRemote(tab)
        local ind = table.find(tab, 'Client')
        return ind and tab[ind + 1] or ''
    end
    local KnitInit, Knit
    repeat
        KnitInit, Knit = pcall(function() return debug.getupvalue(require(lplr.PlayerScripts.TS.knit).setup, 9) end)
        if KnitInit then break end
        task.wait()
    until KnitInit
    if not debug.getupvalue(Knit.Start, 1) then
        repeat task.wait() until debug.getupvalue(Knit.Start, 1)
    end
    local Flamework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
    local Client = require(replicatedStorage.TS.remotes).default.Client
    bedwars = setmetatable({
        Client = Client,
        CrateItemMeta = debug.getupvalue(Flamework.resolveDependency('client/controllers/global/reward-crate/crate-controller@CrateController').onStart, 3),
        Store = require(lplr.PlayerScripts.TS.ui.store).ClientStore
    }, {
        __index = function(self, ind)
            rawset(self, ind, Knit.Controllers[ind])
            return rawget(self, ind)
        end
    })
end)

run(function()
    local oldstart = entitylib.start
    local function customEntity(ent)
        if ent:HasTag('inventory-entity') and not ent:HasTag('Monster') then
            return
        end

        entitylib.addEntity(ent, nil, ent:HasTag('Drone') and function(self)
            local droneplr = playersService:GetPlayerByUserId(self.Character:GetAttribute('PlayerUserId'))
            return not droneplr or lplr:GetAttribute('Team') ~= droneplr:GetAttribute('Team')
        end or function(self)
            return lplr:GetAttribute('Team') ~= self.Character:GetAttribute('Team')
        end)
    end

    entitylib.start = function()
        if oldstart then oldstart() end
        if entitylib.Running then
            for _, ent in collectionService:GetTagged('entity') do
                customEntity(ent)
            end
            table.insert(entitylib.Connections, collectionService:GetInstanceAddedSignal('entity'):Connect(customEntity))
            table.insert(entitylib.Connections, collectionService:GetInstanceRemovedSignal('entity'):Connect(function(ent)
                entitylib.removeEntity(ent)
            end))
        end
    end

    entitylib.addPlayer = function(plr)
        if plr.Character then
            entitylib.refreshEntity(plr.Character, plr)
        end
        entitylib.PlayerConnections[plr] = {
            plr.CharacterAdded:Connect(function(char)
                entitylib.refreshEntity(char, plr)
            end),
            plr.CharacterRemoving:Connect(function(char)
                entitylib.removeEntity(char, plr == lplr)
            end),
            plr:GetAttributeChangedSignal('Team'):Connect(function()
                for _, v in entitylib.List do
                    if v.Targetable ~= entitylib.targetCheck(v) then
                        entitylib.refreshEntity(v.Character, v.Player)
                    end
                end

                if plr == lplr then
                    entitylib.start()
                else
                    entitylib.refreshEntity(plr.Character, plr)
                end
            end)
        }
    end

    entitylib.addEntity = function(char, plr, teamfunc)
        if not char then return end
        entitylib.EntityThreads[char] = task.spawn(function()
            local hum, humrootpart, head
            if plr then
                hum = waitForChildOfType(char, 'Humanoid', 10)
                humrootpart = hum and waitForChildOfType(hum, 'RootPart', workspace.StreamingEnabled and 9e9 or 10, true)
                head = char:WaitForChild('Head', 10) or humrootpart
            else
                hum = {HipHeight = 0.5}
                humrootpart = waitForChildOfType(char, 'PrimaryPart', 10, true)
                head = humrootpart
            end
            local updateobjects = plr and plr ~= lplr and {
                char:WaitForChild('ArmorInvItem_0', 5),
                char:WaitForChild('ArmorInvItem_1', 5),
                char:WaitForChild('ArmorInvItem_2', 5),
                char:WaitForChild('HandInvItem', 5)
            } or {}

            if hum and humrootpart then
                local entity = {
                    Connections = {},
                    Character = char,
                    Health = (char:GetAttribute('Health') or 100) + getShieldAttribute(char),
                    Head = head,
                    Humanoid = hum,
                    HumanoidRootPart = humrootpart,
                    HipHeight = hum.HipHeight + (humrootpart.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
                    Jumps = 0,
                    JumpTick = tick(),
                    Jumping = false,
                    LandTick = tick(),
                    MaxHealth = char:GetAttribute('MaxHealth') or 100,
                    NPC = plr == nil,
                    Player = plr,
                    RootPart = humrootpart,
                    TeamCheck = teamfunc
                }

                if plr == lplr then
                    entity.AirTime = tick()
                    entitylib.character = entity
                    entitylib.isAlive = true
                    entitylib.Events.LocalAdded:Fire(entity)
                    table.insert(entitylib.Connections, char.AttributeChanged:Connect(function(attr)
                        vapeEvents.AttributeChanged:Fire(attr)
                    end))
                else
                    entity.Targetable = entitylib.targetCheck(entity)

                    for _, v in entitylib.getUpdateConnections(entity) do
                        table.insert(entity.Connections, v:Connect(function()
                            entity.Health = (char:GetAttribute('Health') or 100) + getShieldAttribute(char)
                            entity.MaxHealth = char:GetAttribute('MaxHealth') or 100
                            entitylib.Events.EntityUpdated:Fire(entity)
                        end))
                    end

                    for _, v in updateobjects do
                        table.insert(entity.Connections, v:GetPropertyChangedSignal('Value'):Connect(function()
                            task.delay(0.1, function()
                                if bedwars.getInventory then
                                    store.inventories[plr] = bedwars.getInventory(plr)
                                    entitylib.Events.EntityUpdated:Fire(entity)
                                end
                            end)
                        end))
                    end

                    if plr then
                        local anim = char:FindFirstChild('Animate')
                        if anim then
                            pcall(function()
                                anim = anim.jump:FindFirstChildWhichIsA('Animation').AnimationId
                                table.insert(entity.Connections, hum.Animator.AnimationPlayed:Connect(function(playedanim)
                                    if playedanim.Animation.AnimationId == anim then
                                        entity.JumpTick = tick()
                                        entity.Jumps += 1
                                        entity.LandTick = tick() + 1
                                        entity.Jumping = entity.Jumps > 1
                                    end
                                end))
                            end)
                        end

                        task.delay(0.1, function()
                            if bedwars.getInventory then
                                store.inventories[plr] = bedwars.getInventory(plr)
                            end
                        end)
                    end
                    table.insert(entitylib.List, entity)
                    entitylib.Events.EntityAdded:Fire(entity)
                end

                table.insert(entity.Connections, char.ChildRemoved:Connect(function(part)
                    if part == humrootpart or part == hum or part == head then
                        if part == humrootpart and hum.RootPart then
                            humrootpart = hum.RootPart
                            entity.RootPart = hum.RootPart
                            entity.HumanoidRootPart = hum.RootPart
                            return
                        end
                        entitylib.removeEntity(char, plr == lplr)
                    end
                end))
            end
            entitylib.EntityThreads[char] = nil
        end)
    end

    entitylib.getUpdateConnections = function(ent)
        local char = ent.Character
        local tab = {
            char:GetAttributeChangedSignal('Health'),
            char:GetAttributeChangedSignal('MaxHealth'),
            {
                Connect = function()
                    ent.Friend = ent.Player and isFriend(ent.Player) or nil
                    ent.Target = ent.Player and isTarget(ent.Player) or nil
                    return {Disconnect = function() end}
                end
            }
        }

        if ent.Player then
            table.insert(tab, ent.Player:GetAttributeChangedSignal('PlayingAsKit'))
        end

        for name, val in char:GetAttributes() do
            if name:find('Shield') and type(val) == 'number' then
                table.insert(tab, char:GetAttributeChangedSignal(name))
            end
        end

        return tab
    end

    entitylib.targetCheck = function(ent)
        if ent.TeamCheck then
            return ent:TeamCheck()
        end
        if ent.NPC then return true end
        if isFriend(ent.Player) then return false end
        if not select(2, whitelist:get(ent.Player)) then return false end
        return lplr:GetAttribute('Team') ~= ent.Player:GetAttribute('Team')
    end
end)
entitylib.start()

-- Sprint hooking
local oldStopSprinting
local function enableSprint()
    if inputService.TouchEnabled then pcall(function() lplr.PlayerGui.MobileUI['2'].Visible = false end) end
    oldStopSprinting = bedwars.SprintController.stopSprinting
    bedwars.SprintController.stopSprinting = function(...)
        local call = oldStopSprinting(...)
        bedwars.SprintController:startSprinting()
        return call
    end
    bedwars.SprintController:stopSprinting()
end

local function disableSprint()
    if inputService.TouchEnabled then pcall(function() lplr.PlayerGui.MobileUI['2'].Visible = true end) end
    bedwars.SprintController.stopSprinting = oldStopSprinting
    bedwars.SprintController:stopSprinting()
end

-- NoSlowdown functionality
local oldNoSlow
local function enableNoSlowdown()
    local modifier = bedwars.SprintController:getMovementStatusModifier()
    oldNoSlow = modifier.addModifier
    modifier.addModifier = function(self, tab)
        if tab.moveSpeedMultiplier then
            tab.moveSpeedMultiplier = math.max(tab.moveSpeedMultiplier, 1)
        end
        return oldNoSlow(self, tab)
    end

    for i in modifier.modifiers do
        if (i.moveSpeedMultiplier or 1) < 1 then
            modifier:removeModifier(i)
        end
    end
end

local function disableNoSlowdown()
    if oldNoSlow then
        bedwars.SprintController:getMovementStatusModifier().addModifier = oldNoSlow
        oldNoSlow = nil
    end
end

-- HitBoxes functionality
local hitboxesObjects = {}
local hitboxesSet = false
local function createHitbox(ent)
    if ent.Targetable and ent.Player then
        local hitbox = Instance.new('Part')
        hitbox.Size = Vector3.new(3, 6, 3) + Vector3.one * (14.4 / 5)  -- Expand to 14.4 studs
        hitbox.Position = ent.RootPart.Position
        hitbox.CanCollide = false
        hitbox.Massless = true
        hitbox.Transparency = 1
        hitbox.Parent = ent.Character
        local weld = Instance.new('Motor6D')
        weld.Part0 = hitbox
        weld.Part1 = ent.RootPart
        weld.Parent = hitbox
        hitboxesObjects[ent] = hitbox
    end
end

local function enableHitBoxes()
    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, 14.4 / 3)
    hitboxesSet = true
    -- Also create player hitboxes
    for _, ent in entitylib.List do
        createHitbox(ent)
    end
end

local function disableHitBoxes()
    if hitboxesSet then
        debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, 3.8)
        hitboxesSet = false
    end
    for _, part in hitboxesObjects do
        part:Destroy()
    end
    table.clear(hitboxesObjects)
end



-- Apply initial states after bedwars loads
task.spawn(function()
    repeat task.wait() until bedwars.SprintController
    task.wait(2)  -- Extra wait to ensure everything is loaded
    if sprintEnabled then
        enableSprint()
    end
    if noslowEnabled then
        enableNoSlowdown()
    end
    if hitboxesEnabled then
        enableHitBoxes()
    end
end)

-- GUI Setup
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainMenuGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Welcome notification
task.spawn(function()
    task.wait(2)  -- Wait 2 seconds after load
    local notification = Instance.new("TextLabel")
    notification.Size = UDim2.new(0, 300, 0, 50)
    notification.Position = UDim2.new(0.5, -150, 0.8, -25)
    notification.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    notification.BackgroundTransparency = 0.5
    notification.Text = "Press RightShift to open UI"
    notification.TextColor3 = Color3.new(1, 1, 1)
    notification.Font = Enum.Font.SourceSansBold
    notification.TextSize = 20
    notification.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = notification

    task.wait(5)  -- Show for 5 seconds
    notification:Destroy()
end)

-- Main Menu Frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 160, 0, 300)
mainFrame.Position = UDim2.new(0.5, -80, 0.5, -150)
mainFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
mainFrame.BackgroundTransparency = 0.3
mainFrame.Visible = false
mainFrame.Parent = screenGui

-- Sprint Button
local sprintButton = Instance.new("TextButton")
sprintButton.Size = UDim2.new(0, 140, 0, 40)
sprintButton.Position = UDim2.new(0, 10, 0, 10)
sprintButton.Text = "Sprint: OFF"
sprintButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
sprintButton.TextColor3 = Color3.new(1, 1, 1)
sprintButton.Font = Enum.Font.SourceSansBold
sprintButton.TextSize = 18
sprintButton.Parent = mainFrame

-- NoSlow Button
local noslowButton = Instance.new("TextButton")
noslowButton.Size = UDim2.new(0, 140, 0, 40)
noslowButton.Position = UDim2.new(0, 10, 0, 60)
noslowButton.Text = "NoSlow: OFF"
noslowButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
noslowButton.TextColor3 = Color3.new(1, 1, 1)
noslowButton.Font = Enum.Font.SourceSansBold
noslowButton.TextSize = 18
noslowButton.Parent = mainFrame

-- HitBoxes Button
local hitboxesButton = Instance.new("TextButton")
hitboxesButton.Size = UDim2.new(0, 140, 0, 40)
hitboxesButton.Position = UDim2.new(0, 10, 0, 110)
hitboxesButton.Text = "HitBoxes: OFF"
hitboxesButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
hitboxesButton.TextColor3 = Color3.new(1, 1, 1)
hitboxesButton.Font = Enum.Font.SourceSansBold
hitboxesButton.TextSize = 18
hitboxesButton.Parent = mainFrame

-- AirJump Frame
local airjumpFrame = Instance.new("Frame")
airjumpFrame.Size = UDim2.new(0, 140, 0, 40)
airjumpFrame.Position = UDim2.new(0, 10, 0, 160)
airjumpFrame.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
airjumpFrame.BackgroundTransparency = 0.5
airjumpFrame.Parent = mainFrame

local airjumpLabel = Instance.new("TextLabel")
airjumpLabel.Size = UDim2.new(1, 0, 1, 0)
airjumpLabel.BackgroundTransparency = 1
airjumpLabel.Text = "AirJump: Z"
airjumpLabel.TextColor3 = Color3.new(1, 1, 1)
airjumpLabel.Font = Enum.Font.SourceSansBold
airjumpLabel.TextSize = 18
airjumpLabel.Parent = airjumpFrame



-- Menu Toggle
local menuVisible = false
inputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
        menuVisible = not menuVisible
        mainFrame.Visible = menuVisible
    end
end)

-- AirJump functionality
local function airJump()
    if lplr.Character and lplr.Character:FindFirstChild("Humanoid") then
        lplr.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        print("Keybind: AirJump used!")
    end
end

-- Update buttons in real-time
task.spawn(function()
    while true do
        sprintButton.Text = sprintEnabled and "Sprint: ON" or "Sprint: OFF"
        sprintButton.BackgroundColor3 = sprintEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        noslowButton.Text = noslowEnabled and "NoSlow: ON" or "NoSlow: OFF"
        noslowButton.BackgroundColor3 = noslowEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        hitboxesButton.Text = hitboxesEnabled and "HitBoxes: ON" or "HitBoxes: OFF"
        hitboxesButton.BackgroundColor3 = hitboxesEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        task.wait(0.1)
    end
end)

-- Menu Toggle
local menuVisible = false
contextActionService:BindAction("ToggleMenu", function(actionName, inputState, inputObject)
    if inputState == Enum.UserInputState.Begin then
        menuVisible = not menuVisible
        mainFrame.Visible = menuVisible
        print("Keybind: Menu Toggle used!")
    end
end, false, Enum.KeyCode.RightShift)

contextActionService:BindAction("AirJump", function(actionName, inputState, inputObject)
    if inputState == Enum.UserInputState.Begin then
        airJump()
    end
end, false, Enum.KeyCode.Z)

-- Button Behaviors
sprintButton.MouseButton1Click:Connect(function()
    sprintEnabled = not sprintEnabled
    if sprintEnabled then
        enableSprint()
    else
        disableSprint()
    end
    -- Save status
    pcall(function()
        writefile('sprint_status.txt', tostring(sprintEnabled))
    end)
end)

noslowButton.MouseButton1Click:Connect(function()
    noslowEnabled = not noslowEnabled
    if noslowEnabled then
        enableNoSlowdown()
    else
        disableNoSlowdown()
    end
    -- Save status
    pcall(function()
        writefile('noslow_status.txt', tostring(noslowEnabled))
    end)
end)

hitboxesButton.MouseButton1Click:Connect(function()
    hitboxesEnabled = not hitboxesEnabled
    if hitboxesEnabled then
        enableHitBoxes()
    else
        disableHitBoxes()
    end
    -- Save status
    pcall(function()
        writefile('hitboxes_status.txt', tostring(hitboxesEnabled))
    end)
end)




-- Queue on teleport
local queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(file)
    local suc, res = pcall(function()
        return readfile(file)
    end)
    return suc and res ~= nil and res ~= ''
end
local readfile = readfile or function(file)
    error("readfile not available")
end
local writefile = writefile or function(file, content)
    error("writefile not available")
end

local teleportedServers
playersService.LocalPlayer.OnTeleport:Connect(function()
    if not teleportedServers then
        teleportedServers = true
        pcall(function()
            writefile('sprint_status.txt', tostring(sprintEnabled))
            writefile('noslow_status.txt', tostring(noslowEnabled))
            writefile('hitboxes_status.txt', tostring(hitboxesEnabled))
        end)
        queue_on_teleport('loadstring(game:HttpGet("https://raw.githubusercontent.com/your-repo/gui.lua/main/gui.lua"))()')
    end
end)
