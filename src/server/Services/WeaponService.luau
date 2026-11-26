-- WeaponService (ModuleScript)
-- Local no Studio: ServerScriptService > Services > WeaponService
-- Roda em: servidor
-- Depende de: WeaponConfig, WeaponState (ReplicatedStorage > Modules),
--             CombatService (recebido no Init), RemoteEvents em ReplicatedStorage > Remotes
-- Usado por: Main (chama Init)
--
-- Este é o "juiz" dos tiros. O cliente diz "atirei daqui, nesta direção, e acho
-- que acertei esta parte". O WeaponService confere tudo e só então pede ao
-- CombatService para aplicar o dano, com o valor da WeaponConfig do servidor.
--
-- O cliente NUNCA envia dano, vida ou "matei alguém".
--
-- Ordem das checagens de cada tiro (FireWeapon):
--   1. Tipos dos dados (um cliente trapaceiro pode mandar qualquer coisa).
--   2. Atirador vivo.
--   3. Cadência (limite de tiros por segundo, com folga para a internet).
--   4. Energia e superaquecimento (WeaponState do servidor).
--   5. Origem do tiro perto da cabeça do atirador.
--   6. Se alegou acerto: alvo é outro jogador vivo, ponto do acerto está na
--      linha do tiro, dentro do alcance, perto do alvo no servidor, e não há
--      parede no meio.
-- Se 1 a 5 falham, o tiro é ignorado e o cliente recebe o estado real da arma.
-- Se só a 6 falha, o tiro conta (gasta energia e calor) mas não causa dano.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local WeaponState = require(Modules:WaitForChild("WeaponState"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FireWeapon = Remotes:WaitForChild("FireWeapon")
local ShotFired = Remotes:WaitForChild("ShotFired")
local HitConfirmed = Remotes:WaitForChild("HitConfirmed")
local WeaponStateSync = Remotes:WaitForChild("WeaponStateSync")

-- Tolerâncias da validação. Valores maiores = mais tolerante a lag,
-- mas também mais espaço para trapaça. Ajuste testando com lag simulado.
local MAX_ORIGIN_OFFSET = 6 -- studs entre a origem enviada e a cabeça no servidor
local MAX_TARGET_OFFSET = 5 -- studs extras entre o ponto do acerto e a parte atingida
local MAX_RAY_DEVIATION = 1 -- studs entre o ponto do acerto e a linha do tiro
local FIRE_RATE_TOLERANCE = 1.15 -- aceita até 15% acima da cadência...
local RATE_WINDOW = 1 -- ...medida numa janela de 1 segundo

local LOG_REJECTIONS = true -- mostra no Output os tiros recusados (útil nos testes)

local WeaponService = {}

local CombatService -- recebido no Init
local defaultConfig = WeaponConfig[WeaponConfig.Default]
local maxShotsPerWindow = math.floor(defaultConfig.FireRate / 60 * RATE_WINDOW * FIRE_RATE_TOLERANCE) + 1

-- Dados de cada jogador: [Player] = { State = WeaponState, ShotTimes = {números} }
local playerData = {}

-- ===================================================================
-- Funções auxiliares
-- ===================================================================

local function reject(player, data, reason)
	if LOG_REJECTIONS then
		warn(string.format("[WeaponService] Tiro de %s recusado: %s", player.Name, reason))
	end
	if data then
		-- Corrige a previsão do cliente com os valores reais do servidor.
		WeaponStateSync:FireClient(player, data.State:GetSnapshot(os.clock()))
	end
end

-- Um Vector3 com NaN ou infinito quebraria as contas. x ~= x só é verdade para NaN.
local function isValidVector(v)
	if typeof(v) ~= "Vector3" then
		return false
	end
	local m = v.Magnitude
	return m == m and m < math.huge
end

local function getAliveHumanoid(character)
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Limite de tiros por segundo. Guardamos o horário dos tiros recentes e
-- recusamos se já houver tiros demais na última janela.
local function passesRateLimit(data, now)
	local times = data.ShotTimes
	-- Remove tiros mais antigos que a janela (de trás para frente para não pular itens).
	for i = #times, 1, -1 do
		if now - times[i] > RATE_WINDOW then
			table.remove(times, i)
		end
	end
	return #times < maxShotsPerWindow
end

-- Lista dos personagens de todos os jogadores, para o Raycast de linha de
-- visão ignorar pessoas e só considerar o cenário.
local function getAllCharacters()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- Confere se um acerto alegado pelo cliente é plausível.
-- Retorna o Humanoid do alvo, ou nil e o motivo da recusa.
local function validateHit(shooter, origin, direction, hitPart, hitPosition, range)
	local targetCharacter = hitPart:FindFirstAncestorOfClass("Model")
	local targetPlayer = targetCharacter and Players:GetPlayerFromCharacter(targetCharacter)
	if not targetPlayer then
		return nil, "alvo não é um jogador"
	end
	if targetPlayer == shooter then
		return nil, "acertou a si mesmo"
	end
	local targetHumanoid = getAliveHumanoid(targetCharacter)
	if not targetHumanoid then
		return nil, "alvo já está morto"
	end

	local toHit = hitPosition - origin
	if toHit.Magnitude > range + 2 then
		return nil, "fora do alcance"
	end

	-- O ponto precisa estar na linha do tiro: projetamos o ponto na direção
	-- e medimos a distância perpendicular.
	local along = toHit:Dot(direction)
	local deviation = (toHit - direction * along).Magnitude
	if along < 0 or deviation > MAX_RAY_DEVIATION then
		return nil, "ponto fora da linha do tiro"
	end

	-- O ponto precisa estar perto de onde a parte está AGORA no servidor.
	-- A folga cobre o atraso da internet (o alvo andou um pouco).
	local partRadius = hitPart.Size.Magnitude / 2
	if (hitPart.Position - hitPosition).Magnitude > partRadius + MAX_TARGET_OFFSET then
		return nil, "alvo longe demais do ponto do acerto"
	end

	-- Linha de visão: não pode haver cenário entre a origem e o ponto.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = getAllCharacters()
	params.IgnoreWater = true
	local distance = toHit.Magnitude
	if distance > 0.5 then
		local blocked = Workspace:Raycast(origin, direction * (distance - 0.5), params)
		if blocked then
			return nil, "parede no caminho (" .. blocked.Instance.Name .. ")"
		end
	end

	return targetHumanoid
end

-- Arma visível para os OUTROS jogadores: uma peça simples presa à mão.
-- (Na sua própria tela, o Roblox esconde o seu personagem em primeira pessoa,
-- e você vê o viewmodel criado pelo WeaponController.)
local function attachWorldWeapon(character)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if not hand then
		return
	end

	local gun = Instance.new("Part")
	gun.Name = "PulseRifle"
	gun.Size = Vector3.new(0.35, 0.45, 2.2)
	gun.Color = Color3.fromRGB(30, 32, 45)
	gun.Material = Enum.Material.SmoothPlastic
	gun.CanCollide = false
	gun.CanQuery = false -- tiros atravessam a arma
	gun.CanTouch = false
	gun.Massless = true

	local strip = Instance.new("Part")
	strip.Name = "EnergyStrip"
	strip.Size = Vector3.new(0.12, 0.12, 1.8)
	strip.Color = defaultConfig.TracerColor
	strip.Material = Enum.Material.Neon
	strip.CanCollide = false
	strip.CanQuery = false
	strip.CanTouch = false
	strip.Massless = true

	-- Ponto de saída do laser, usado pelos outros clientes para desenhar o traço.
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -1.15)
	muzzle.Parent = gun

	local handWeld = Instance.new("WeldConstraint")
	gun.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, -0.8)
	handWeld.Part0 = hand
	handWeld.Part1 = gun
	handWeld.Parent = gun

	local stripWeld = Instance.new("WeldConstraint")
	strip.CFrame = gun.CFrame * CFrame.new(0, 0.25, 0)
	stripWeld.Part0 = gun
	stripWeld.Part1 = strip
	stripWeld.Parent = strip

	gun.Parent = character
	strip.Parent = gun
end

-- ===================================================================
-- Jogadores entrando e saindo
-- ===================================================================

local function onCharacterAdded(player, character)
	local data = playerData[player]
	if not data then
		return
	end
	-- Respawn: arma volta cheia e fria.
	data.State:Reset(os.clock())
	table.clear(data.ShotTimes)
	WeaponStateSync:FireClient(player, data.State:GetSnapshot(os.clock()))
	attachWorldWeapon(character)
end

local function onPlayerAdded(player)
	playerData[player] = {
		State = WeaponState.new(defaultConfig),
		ShotTimes = {},
	}
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onPlayerRemoving(player)
	playerData[player] = nil
end

-- ===================================================================
-- O tiro
-- ===================================================================

local function onFireWeapon(player, origin, direction, hitPart, hitPosition)
	local data = playerData[player]

	-- 1. Tipos. hitPart e hitPosition são opcionais (nil = errou tudo).
	if not isValidVector(origin) or not isValidVector(direction) then
		return reject(player, nil, "dados inválidos")
	end
	if math.abs(direction.Magnitude - 1) > 0.01 then
		return reject(player, nil, "direção não normalizada")
	end
	if hitPart ~= nil and (typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart")) then
		return reject(player, nil, "parte atingida inválida")
	end
	if hitPosition ~= nil and not isValidVector(hitPosition) then
		return reject(player, nil, "ponto do acerto inválido")
	end
	if not data then
		return
	end

	-- 2. Atirador vivo.
	local character = player.Character
	local humanoid = getAliveHumanoid(character)
	local head = character and character:FindFirstChild("Head")
	if not humanoid or not head then
		return reject(player, data, "atirador morto")
	end

	local now = os.clock()
	local config = data.State.Config

	-- 3. Cadência.
	if not passesRateLimit(data, now) then
		return reject(player, data, "cadência acima do limite")
	end

	-- 4. Energia e superaquecimento.
	local canFire, reason = data.State:CanFire(now, true)
	if not canFire then
		return reject(player, data, reason)
	end

	-- 5. Origem perto da cabeça.
	if (origin - head.Position).Magnitude > MAX_ORIGIN_OFFSET then
		return reject(player, data, "origem longe da cabeça")
	end

	-- O tiro é válido: gasta energia e calor no servidor.
	data.State:RegisterShot(now)
	table.insert(data.ShotTimes, now)

	-- Ponto final do traço do laser (para os outros desenharem).
	local endPoint = origin + direction * config.Range
	if hitPosition then
		local toHit = hitPosition - origin
		local along = toHit:Dot(direction)
		if along > 0 and along <= config.Range + 2 then
			endPoint = origin + direction * along
		end
	end

	-- 6. Acerto alegado.
	local targetHumanoid = nil
	if hitPart and hitPosition then
		local why
		targetHumanoid, why = validateHit(player, origin, direction, hitPart, hitPosition, config.Range)
		if not targetHumanoid and LOG_REJECTIONS then
			warn(string.format("[WeaponService] Acerto de %s recusado: %s", player.Name, why))
		end
	end

	-- Avisa os outros jogadores para desenharem o traço.
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			ShotFired:FireClient(other, player, origin, endPoint)
		end
	end

	-- Aplica o dano (valor do servidor, nunca do cliente).
	if targetHumanoid then
		local dealt, eliminated = CombatService.ApplyDamage(player, targetHumanoid, config.Damage)
		if dealt > 0 then
			HitConfirmed:FireClient(player, dealt, eliminated)
		end
	end
end

-- ===================================================================
-- Inicialização
-- ===================================================================

function WeaponService.Init(combatService)
	CombatService = combatService

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	FireWeapon.OnServerEvent:Connect(onFireWeapon)
end

return WeaponService
