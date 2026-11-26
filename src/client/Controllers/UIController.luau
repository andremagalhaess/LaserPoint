-- UIController (ModuleScript)
-- Local no Studio: StarterPlayer > StarterPlayerScripts > Controllers > UIController
-- Roda em: cliente
-- Depende de: nada (recebe os dados do WeaponController)
-- Usado por: ClientMain (Init) e WeaponController (UpdateWeapon, ShowHitmarker, ShowElimination)
--
-- Cria o HUD por código: mira, hitmarker, vida, energia, calor, aviso de
-- OVERHEAT e o aviso de eliminação. Fazemos por código nesta fase para você
-- não precisar montar nada à mão. Na Fase 4 trocamos por GUIs desenhadas no
-- StarterGui.
--
-- O painel fica embaixo, no centro, porque no celular o canto inferior
-- esquerdo é do analógico e o inferior direito é dos botões.
--
-- Este controller só MOSTRA valores. Ele nunca decide nada.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local COLOR_PANEL = Color3.fromRGB(12, 14, 24)
local COLOR_TEXT = Color3.fromRGB(235, 240, 255)
local COLOR_HEALTH = Color3.fromRGB(90, 230, 140)
local COLOR_ENERGY = Color3.fromRGB(0, 229, 255)
local COLOR_HEAT_LOW = Color3.fromRGB(255, 170, 40)
local COLOR_HEAT_HIGH = Color3.fromRGB(255, 50, 80)
local COLOR_HIT = Color3.fromRGB(255, 255, 255)
local COLOR_KILL = Color3.fromRGB(255, 50, 80)

local HITMARKER_TIME = 0.12
local ELIMINATION_TIME = 3

local UIController = {}

local gui -- elementos criados no Init
local hitmarkerToken = 0
local eliminationToken = 0

-- Atalho para criar uma instância com propriedades numa linha só.
local function create(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

-- Cria uma barra (fundo + preenchimento + texto) e retorna as partes.
local function createBar(parent, order, label, color)
	local holder = create("Frame", {
		Name = label .. "Bar",
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)

	create("TextLabel", {
		Size = UDim2.new(0, 70, 1, 0),
		BackgroundTransparency = 1,
		Text = label,
		TextColor3 = COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
	}, holder)

	local back = create("Frame", {
		Position = UDim2.new(0, 74, 0, 3),
		Size = UDim2.new(1, -120, 1, -6),
		BackgroundColor3 = Color3.fromRGB(40, 44, 60),
		BorderSizePixel = 0,
	}, holder)

	local fill = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, back)

	local value = create("TextLabel", {
		Position = UDim2.new(1, -40, 0, 0),
		Size = UDim2.new(0, 40, 1, 0),
		BackgroundTransparency = 1,
		Text = "100",
		TextColor3 = COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
	}, holder)

	return { Fill = fill, Value = value }
end

local function setBar(bar, current, maximum)
	local ratio = 0
	if maximum > 0 then
		ratio = math.clamp(current / maximum, 0, 1)
	end
	bar.Fill.Size = UDim2.new(ratio, 0, 1, 0)
	bar.Value.Text = tostring(math.floor(current + 0.5))
end

local function buildHud()
	local screen = create("ScreenGui", {
		Name = "CombatHUD",
		ResetOnSpawn = false, -- não recria no respawn
		IgnoreGuiInset = true, -- (0,0) é o canto real da tela, então o centro é o centro
	}, player:WaitForChild("PlayerGui"))

	-- Mira: um ponto e quatro traços ao redor do centro.
	local crosshair = create("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40),
		BackgroundTransparency = 1,
	}, screen)
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = COLOR_ENERGY,
		BorderSizePixel = 0,
	}, crosshair)
	local lines = {
		{ UDim2.new(0.5, 0, 0.5, -12), UDim2.fromOffset(2, 7) }, -- cima
		{ UDim2.new(0.5, 0, 0.5, 12), UDim2.fromOffset(2, 7) }, -- baixo
		{ UDim2.new(0.5, -12, 0.5, 0), UDim2.fromOffset(7, 2) }, -- esquerda
		{ UDim2.new(0.5, 12, 0.5, 0), UDim2.fromOffset(7, 2) }, -- direita
	}
	for _, line in ipairs(lines) do
		create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = line[1],
			Size = line[2],
			BackgroundColor3 = COLOR_TEXT,
			BorderSizePixel = 0,
		}, crosshair)
	end

	-- Hitmarker: um "X" feito de dois traços girados.
	local hitmarker = create("Frame", {
		Name = "Hitmarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		Visible = false,
	}, screen)
	local hitLines = {}
	for _, rotation in ipairs({ 45, -45 }) do
		table.insert(hitLines, create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(26, 2),
			Rotation = rotation,
			BackgroundColor3 = COLOR_HIT,
			BorderSizePixel = 0,
		}, hitmarker))
	end

	-- Aviso OVERHEAT, logo abaixo da mira.
	local overheat = create("TextLabel", {
		Name = "Overheat",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 40),
		Size = UDim2.fromOffset(200, 24),
		BackgroundTransparency = 1,
		Text = "OVERHEAT",
		TextColor3 = COLOR_HEAT_HIGH,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		Visible = false,
	}, screen)

	-- Painel inferior com as três barras.
	local panel = create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(320, 76),
		BackgroundColor3 = COLOR_PANEL,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, screen)
	create("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, panel)
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	}, panel)

	local healthBar = createBar(panel, 1, "VIDA", COLOR_HEALTH)
	local energyBar = createBar(panel, 2, "ENERGIA", COLOR_ENERGY)
	local heatBar = createBar(panel, 3, "CALOR", COLOR_HEAT_LOW)

	-- Aviso de eliminação, no topo.
	local elimination = create("TextLabel", {
		Name = "Elimination",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(420, 28),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = COLOR_TEXT,
		TextStrokeTransparency = 0.5,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		Visible = false,
	}, screen)

	return {
		Hitmarker = hitmarker,
		HitLines = hitLines,
		Overheat = overheat,
		HealthBar = healthBar,
		EnergyBar = energyBar,
		HeatBar = heatBar,
		Elimination = elimination,
	}
end

-- A vida vem do Humanoid, que o servidor atualiza e o Roblox replica.
local function updateHealth()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		setBar(gui.HealthBar, math.max(0, humanoid.Health), humanoid.MaxHealth)
	else
		setBar(gui.HealthBar, 0, 100)
	end
end

-- ===================================================================
-- API
-- ===================================================================

function UIController.Init()
	gui = buildHud()
	RunService.Heartbeat:Connect(updateHealth)
end

-- Chamado a cada frame pelo WeaponController com o estado da arma.
function UIController.UpdateWeapon(snapshot, config)
	setBar(gui.EnergyBar, snapshot.Energy, config.EnergyCapacity)
	setBar(gui.HeatBar, snapshot.Heat, config.OverheatThreshold)

	-- A barra de calor vai de laranja a vermelho conforme esquenta.
	local heatRatio = math.clamp(snapshot.Heat / config.OverheatThreshold, 0, 1)
	gui.HeatBar.Fill.BackgroundColor3 = COLOR_HEAT_LOW:Lerp(COLOR_HEAT_HIGH, heatRatio)

	gui.Overheat.Visible = snapshot.Overheated
	if snapshot.Overheated then
		gui.Overheat.Text = string.format("OVERHEAT %.1fs", snapshot.OverheatRemaining)
	end
end

-- Mostra o "X" por um instante. Vermelho se eliminou.
function UIController.ShowHitmarker(eliminated)
	hitmarkerToken = hitmarkerToken + 1
	local myToken = hitmarkerToken
	local color = eliminated and COLOR_KILL or COLOR_HIT
	for _, line in ipairs(gui.HitLines) do
		line.BackgroundColor3 = color
	end
	gui.Hitmarker.Visible = true
	task.delay(HITMARKER_TIME, function()
		-- Só esconde se nenhum hitmarker mais novo apareceu nesse meio-tempo.
		if myToken == hitmarkerToken then
			gui.Hitmarker.Visible = false
		end
	end)
end

function UIController.ShowElimination(killer, victim)
	local victimName = victim and victim.DisplayName or "?"
	local text
	if killer then
		text = string.format("%s eliminou %s", killer.DisplayName, victimName)
	else
		text = string.format("%s foi eliminado", victimName)
	end
	-- Destaque quando você participa.
	if killer == player or victim == player then
		gui.Elimination.TextColor3 = COLOR_KILL
	else
		gui.Elimination.TextColor3 = COLOR_TEXT
	end

	eliminationToken = eliminationToken + 1
	local myToken = eliminationToken
	gui.Elimination.Text = text
	gui.Elimination.Visible = true
	task.delay(ELIMINATION_TIME, function()
		if myToken == eliminationToken then
			gui.Elimination.Visible = false
		end
	end)
end

return UIController
