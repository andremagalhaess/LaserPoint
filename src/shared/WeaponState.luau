-- WeaponState (ModuleScript)
-- Local no Studio: ReplicatedStorage > Modules > WeaponState
-- Usado por: WeaponService (servidor, é quem vale) e WeaponController (cliente,
-- só para o HUD e o tiro local responderem na hora).
--
-- Este módulo guarda a energia e a temperatura de UMA arma e sabe responder:
--   "posso atirar agora?"   -> CanFire(now)
--   "atirei agora"          -> RegisterShot(now)
--   "como está a arma?"     -> GetSnapshot(now)
--
-- Ele não usa RemoteEvents, não cria efeitos e não sabe quem é o jogador.
-- É só matemática. Por isso o servidor e o cliente podem usar o mesmo código.
--
-- COMO O TEMPO FUNCIONA (sem loop a cada frame)
-- Em vez de diminuir o calor 60 vezes por segundo, guardamos o valor e o
-- instante da última atualização (LastUpdate). Quando alguém pergunta algo,
-- a função _advance(now) calcula quanto tempo passou e aplica de uma vez:
--   calor agora = calor antes - CoolingRate * segundos que passaram
-- O resultado é o mesmo, e o servidor não gasta nada com armas paradas.
--
-- "now" é sempre um número em segundos vindo de os.clock(). Cada lado (servidor
-- ou cliente) usa o próprio relógio; os dois nunca comparam horários entre si.

local WeaponState = {}
WeaponState.__index = WeaponState

-- Cria o estado de uma arma a partir da tabela de WeaponConfig.
function WeaponState.new(config)
	local self = setmetatable({}, WeaponState)
	self.Config = config
	self.FireInterval = 60 / config.FireRate -- segundos entre tiros
	self:Reset(os.clock())
	return self
end

-- Volta ao estado inicial: energia cheia, calor zero, sem superaquecimento.
-- Chamado ao criar e a cada respawn.
function WeaponState:Reset(now)
	self.Heat = 0
	self.Energy = self.Config.EnergyCapacity
	self.OverheatedUntil = 0 -- 0 = não está superaquecida
	self.LastShotTime = -math.huge -- "nunca atirou"
	self.LastUpdate = now
end

-- Aplica o tempo que passou desde LastUpdate até now (resfriamento e recarga).
-- O "_" no nome indica uso interno: os outros scripts não precisam chamar.
function WeaponState:_advance(now)
	local elapsed = now - self.LastUpdate
	if elapsed <= 0 then
		return
	end
	local config = self.Config

	-- 1) Temperatura
	if self.OverheatedUntil > 0 then
		-- Superaquecida: o calor fica no máximo até destravar.
		if now >= self.OverheatedUntil then
			self.OverheatedUntil = 0
			self.Heat = 0
		end
	else
		self.Heat = math.max(0, self.Heat - config.CoolingRate * elapsed)
	end

	-- 2) Energia: só recarrega depois de EnergyRegenDelay segundos sem atirar.
	local regenStart = self.LastShotTime + config.EnergyRegenDelay
	local regenFrom = math.max(self.LastUpdate, regenStart)
	if now > regenFrom then
		self.Energy = math.min(config.EnergyCapacity, self.Energy + config.EnergyRegenRate * (now - regenFrom))
	end

	self.LastUpdate = now
end

-- Responde se a arma pode disparar agora.
-- Retorna: true  ou  false, "motivo"
--
-- skipIntervalCheck: o servidor passa true porque controla a cadência de outro
-- jeito (veja WeaponService). Pela internet, dois tiros podem chegar quase
-- juntos mesmo que o cliente tenha atirado no ritmo certo.
function WeaponState:CanFire(now, skipIntervalCheck)
	self:_advance(now)

	if self.OverheatedUntil > 0 then
		return false, "Overheated"
	end
	if self.Energy < self.Config.EnergyPerShot then
		return false, "NoEnergy"
	end
	if not skipIntervalCheck and (now - self.LastShotTime) < self.FireInterval then
		return false, "FireRate"
	end
	return true
end

-- Registra um tiro: soma calor, gasta energia e, se passar do limite,
-- trava a arma por OverheatRecoveryTime segundos.
-- Retorna true se este tiro causou superaquecimento.
function WeaponState:RegisterShot(now)
	self:_advance(now)
	local config = self.Config

	self.Energy = math.max(0, self.Energy - config.EnergyPerShot)
	self.Heat = self.Heat + config.HeatPerShot
	self.LastShotTime = now

	if self.Heat >= config.OverheatThreshold then
		self.Heat = config.OverheatThreshold
		self.OverheatedUntil = now + config.OverheatRecoveryTime
		return true
	end
	return false
end

-- Retorna uma tabela simples com o estado atual. É isso que o HUD desenha e
-- que o servidor envia ao cliente pelo RemoteEvent WeaponStateSync.
-- Note que mandamos o TEMPO RESTANTE do superaquecimento, e não o horário
-- em que ele termina, porque os relógios do servidor e do cliente são diferentes.
function WeaponState:GetSnapshot(now)
	self:_advance(now)
	local remaining = 0
	if self.OverheatedUntil > 0 then
		remaining = math.max(0, self.OverheatedUntil - now)
	end
	return {
		Energy = self.Energy,
		Heat = self.Heat,
		Overheated = self.OverheatedUntil > 0,
		OverheatRemaining = remaining,
	}
end

-- Usado só pelo cliente: substitui a previsão local pelos valores do servidor.
function WeaponState:ApplySnapshot(snapshot, now)
	self.Energy = snapshot.Energy
	self.Heat = snapshot.Heat
	if snapshot.Overheated then
		self.OverheatedUntil = now + snapshot.OverheatRemaining
	else
		self.OverheatedUntil = 0
	end
	self.LastUpdate = now
end

return WeaponState
