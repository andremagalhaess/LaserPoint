-- WeaponConfig (ModuleScript)
-- Local no Studio: ReplicatedStorage > Modules > WeaponConfig
-- Usado por: servidor (WeaponService) e cliente (WeaponController, UIController)
--
-- Todos os números das armas ficam aqui. Para balancear uma arma, mude um valor
-- desta tabela; nenhuma lógica precisa ser alterada.
--
-- O cliente também lê este arquivo, mas isso não é um problema de segurança:
-- o servidor usa a SUA cópia para decidir dano, cadência, calor e energia.
-- Um cliente que altere a cópia local só engana a si mesmo.

local WeaponConfig = {}

-- Arma que todo jogador recebe ao nascer (Fase 1: só a Pulse Rifle).
WeaponConfig.Default = "PulseRifle"

WeaponConfig.PulseRifle = {
	DisplayName = "PULSE RIFLE",

	-- Combate
	Damage = 18, -- dano por tiro (vida padrão é 100, então 6 tiros eliminam)
	FireRate = 450, -- tiros por minuto (450 = um tiro a cada 0,133 s)
	Range = 300, -- alcance máximo do Raycast, em studs

	-- Temperatura
	HeatPerShot = 6, -- calor somado a cada tiro
	CoolingRate = 35, -- calor que cai por segundo (sempre, mesmo atirando)
	OverheatThreshold = 100, -- ao chegar aqui, a arma superaquece
	OverheatRecoveryTime = 1.5, -- segundos travada; depois o calor volta a 0

	-- Energia
	EnergyCapacity = 100, -- energia máxima
	EnergyPerShot = 2, -- energia gasta por tiro
	EnergyRegenRate = 20, -- energia recuperada por segundo
	EnergyRegenDelay = 1, -- segundos sem atirar antes de começar a recuperar
	-- (armas mais pesadas terão um EnergyRegenDelay maior, como uma "recarga")

	-- Visual (só o cliente usa)
	TracerColor = Color3.fromRGB(0, 229, 255),
}

return WeaponConfig
