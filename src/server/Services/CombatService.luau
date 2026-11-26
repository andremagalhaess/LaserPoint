-- CombatService (ModuleScript)
-- Local no Studio: ServerScriptService > Services > CombatService
-- Roda em: servidor
-- Depende de: nada (só serviços do Roblox e o RemoteEvent PlayerEliminated)
-- Usado por: Main (chama Init) e WeaponService (chama ApplyDamage)
--
-- Responsável por vida, dano, eliminação e respawn.
--
-- A vida usa o Humanoid.Health do próprio Roblox. Só o servidor altera esse
-- valor, e o Roblox replica para todos os clientes automaticamente. Por isso
-- não precisamos de RemoteEvent para a vida.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerEliminated = Remotes:WaitForChild("PlayerEliminated")

local MAX_HEALTH = 100
local RESPAWN_TIME = 3 -- segundos, definido no GDD (Team Deathmatch)

local CombatService = {}

-- Guarda quem deu o último dano em cada Humanoid, para saber quem eliminou.
-- __mode = "k" deixa a tabela "fraca": quando o Humanoid é destruído no
-- respawn, a entrada some sozinha e não acumula lixo na memória.
local lastAttacker = setmetatable({}, { __mode = "k" })

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.MaxHealth = MAX_HEALTH
	humanoid.Health = MAX_HEALTH

	-- Died dispara uma vez, quando a vida chega a 0.
	humanoid.Died:Connect(function()
		local killer = lastAttacker[humanoid]
		lastAttacker[humanoid] = nil
		-- killer pode ser nil (por exemplo, se caiu do mapa).
		PlayerEliminated:FireAllClients(killer, player)
		if killer then
			print(string.format("[CombatService] %s eliminou %s", killer.Name, player.Name))
		else
			print(string.format("[CombatService] %s foi eliminado", player.Name))
		end
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function CombatService.Init()
	-- Respawn nativo do Roblox: o personagem volta sozinho depois de RESPAWN_TIME.
	-- Na Fase 3, o MatchService assume os spawns por time.
	Players.RespawnTime = RESPAWN_TIME

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

-- Aplica dano de "attacker" (Player) em "humanoid".
-- Só o WeaponService chama esta função, DEPOIS de validar o tiro.
-- Retorna: dano realmente causado, e se eliminou.
function CombatService.ApplyDamage(attacker, humanoid, amount)
	if humanoid.Health <= 0 then
		return 0, false
	end

	local before = humanoid.Health
	lastAttacker[humanoid] = attacker

	-- TakeDamage respeita o ForceField (proteção de alguns segundos ao nascer).
	-- Com ForceField ativo, nenhum dano é aplicado.
	humanoid:TakeDamage(amount)

	local dealt = before - humanoid.Health
	return dealt, humanoid.Health <= 0
end

return CombatService
