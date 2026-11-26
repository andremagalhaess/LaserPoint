-- WeaponController (ModuleScript)
-- Local no Studio: StarterPlayer > StarterPlayerScripts > Controllers > WeaponController
-- Roda em: cliente
-- Depende de: WeaponConfig, WeaponState (ReplicatedStorage > Modules),
--             RemoteEvents em ReplicatedStorage > Remotes,
--             CameraController e UIController (recebidos no Init)
-- Usado por: ClientMain
--
-- O que este controller faz:
--   1. Enquanto o gatilho está apertado, atira no ritmo da arma.
--   2. Antes de cada tiro, consulta a CÓPIA LOCAL do WeaponState (previsão).
--      Assim o tiro sai na hora, sem esperar o servidor.
--   3. Faz o Raycast a partir do centro da câmera e desenha o laser.
--   4. Envia ao servidor: origem, direção e o que achou que acertou.
--      O servidor é quem decide se valeu (WeaponService).
--   5. Desenha os lasers dos outros jogadores (ShotFired).
--   6. Mostra o viewmodel: a arma presa à sua câmera.
--
-- O hitmarker só aparece quando o servidor confirma (HitConfirmed), para
-- nunca mostrar um acerto que não contou.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local WeaponState = require(Modules:WaitForChild("WeaponState"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FireWeapon = Remotes:WaitForChild("FireWeapon")
local ShotFired = Remotes:WaitForChild("ShotFired")
local HitConfirmed = Remotes:WaitForChild("HitConfirmed")
local WeaponStateSync = Remotes:WaitForChild("WeaponStateSync")
local PlayerEliminated = Remotes:WaitForChild("PlayerEliminated")

local player = Players.LocalPlayer
local config = WeaponConfig[WeaponConfig.Default]
local state = WeaponState.new(config)

local TRACER_WIDTH = 0.08
local TRACER_FADE_TIME = 0.08
-- Posição do viewmodel em relação à câmera (direita, baixo, frente).
local VIEWMODEL_OFFSET = CFrame.new(0.9, -0.75, -1.6)
local VIEWMODEL_KICK = 0.12 -- quanto a arma "volta" a cada tiro (studs)

local WeaponController = {}

local Camera -- CameraController
local UI -- UIController

local triggerHeld = false
local humanoid = nil
local effectsFolder = nil -- lasers e efeitos locais (só existem na sua tela)
local viewmodel = nil -- { Body = Part, Strip = Part, Muzzle = Attachment, Flash = PointLight }
local viewmodelKick = 0

-- ===================================================================
-- Efeitos visuais
-- ===================================================================

-- Desenha um laser de "from" até "to" que some rapidamente.
local function drawTracer(from, to)
	local distance = (to - from).Magnitude
	if distance < 0.1 then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = config.TracerColor
	beam.Size = Vector3.new(TRACER_WIDTH, TRACER_WIDTH, distance)
	-- lookAt aponta o -Z da peça para "to"; andamos metade do caminho.
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -distance / 2)
	beam.Parent = effectsFolder

	local tween = TweenService:Create(beam, TweenInfo.new(TRACER_FADE_TIME), { Transparency = 1 })
	tween.Completed:Connect(function()
		beam:Destroy()
	end)
	tween:Play()
end

local function createViewmodel(camera)
	local body = Instance.new("Part")
	body.Name = "ViewmodelBody"
	body.Size = Vector3.new(0.3, 0.38, 1.9)
	body.Color = Color3.fromRGB(30, 32, 45)
	body.Material = Enum.Material.SmoothPlastic

	local strip = Instance.new("Part")
	strip.Name = "ViewmodelStrip"
	strip.Size = Vector3.new(0.1, 0.1, 1.6)
	strip.Color = config.TracerColor
	strip.Material = Enum.Material.Neon

	for _, part in ipairs({ body, strip }) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = camera -- peças dentro da câmera só existem na sua tela
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.05, -1)
	muzzle.Parent = body

	local flash = Instance.new("PointLight")
	flash.Color = config.TracerColor
	flash.Range = 8
	flash.Brightness = 3
	flash.Enabled = false
	flash.Parent = muzzle

	return { Body = body, Strip = strip, Muzzle = muzzle, Flash = flash }
end

local function muzzleFlash()
	if not viewmodel then
		return
	end
	viewmodel.Flash.Enabled = true
	task.delay(0.04, function()
		if viewmodel then
			viewmodel.Flash.Enabled = false
		end
	end)
end

-- Posiciona o viewmodel na frente da câmera a cada frame.
local function updateViewmodel(dt)
	if not viewmodel then
		return
	end
	local camera = Workspace.CurrentCamera
	local alive = humanoid ~= nil and humanoid.Health > 0
	viewmodel.Body.Transparency = alive and 0 or 1
	viewmodel.Strip.Transparency = alive and 0 or 1

	viewmodelKick = viewmodelKick * math.exp(-15 * dt)
	local cf = camera.CFrame * VIEWMODEL_OFFSET * CFrame.new(0, 0, viewmodelKick)
	viewmodel.Body.CFrame = cf
	viewmodel.Strip.CFrame = cf * CFrame.new(0, 0.22, 0)
end

-- ===================================================================
-- O tiro
-- ===================================================================

-- Sobe na hierarquia a partir da parte atingida procurando um personagem
-- (um Model com Humanoid). Só mandamos hitPart ao servidor se for um.
local function isCharacterPart(part)
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function fire(now)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	if not camera or not character then
		return
	end

	-- Previsão local: gasta energia e calor na cópia do cliente.
	state:RegisterShot(now)

	-- O tiro sai do centro da câmera, na direção para onde ela olha.
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, effectsFolder, camera }
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, direction * config.Range, params)

	local hitPart = nil
	local hitPosition = nil
	local endPoint = origin + direction * config.Range
	if result then
		hitPosition = result.Position
		endPoint = result.Position
		if isCharacterPart(result.Instance) then
			hitPart = result.Instance
		end
	end

	-- Visual imediato.
	local tracerStart = viewmodel and viewmodel.Muzzle.WorldPosition or origin
	drawTracer(tracerStart, endPoint)
	muzzleFlash()
	viewmodelKick = VIEWMODEL_KICK
	Camera.Kick()

	-- Pedido ao servidor. Repare: nada de dano aqui.
	FireWeapon:FireServer(origin, direction, hitPart, hitPosition)
end

local function onHeartbeat()
	local now = os.clock()
	local alive = humanoid ~= nil and humanoid.Health > 0

	if triggerHeld and alive and state:CanFire(now) then
		fire(now)
	end

	UI.UpdateWeapon(state:GetSnapshot(now), config)
end

-- ===================================================================
-- Eventos do servidor
-- ===================================================================

-- Outro jogador atirou: desenha o laser saindo da arma dele.
local function onShotFired(shooter, origin, endPoint)
	local from = origin
	local shooterCharacter = shooter and shooter.Character
	local gun = shooterCharacter and shooterCharacter:FindFirstChild("PulseRifle")
	local muzzle = gun and gun:FindFirstChild("Muzzle")
	if muzzle then
		from = muzzle.WorldPosition
	end
	drawTracer(from, endPoint)
end

local function onCharacterAdded(character)
	humanoid = character:WaitForChild("Humanoid")
	-- Respawn: a cópia local volta cheia e fria, igual ao servidor.
	state:Reset(os.clock())
	humanoid.Died:Connect(function()
		triggerHeld = false
	end)
end

-- ===================================================================
-- API usada pelo ClientMain
-- ===================================================================

function WeaponController.Init(deps)
	Camera = deps.Camera
	UI = deps.UI

	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "LaserPointEffects"
	effectsFolder.Parent = Workspace -- criado pelo cliente: só existe na tela dele

	viewmodel = createViewmodel(Workspace.CurrentCamera)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	WeaponStateSync.OnClientEvent:Connect(function(snapshot)
		state:ApplySnapshot(snapshot, os.clock())
	end)
	ShotFired.OnClientEvent:Connect(onShotFired)
	HitConfirmed.OnClientEvent:Connect(function(_damage, eliminated)
		UI.ShowHitmarker(eliminated)
	end)
	PlayerEliminated.OnClientEvent:Connect(function(killer, victim)
		UI.ShowElimination(killer, victim)
	end)

	RunService.Heartbeat:Connect(onHeartbeat)
	-- O viewmodel roda depois do CameraController (Camera + 2).
	RunService:BindToRenderStep("LaserPointViewmodel", Enum.RenderPriority.Camera.Value + 2, updateViewmodel)
end

function WeaponController.SetTrigger(isHeld)
	triggerHeld = isHeld
end

return WeaponController
