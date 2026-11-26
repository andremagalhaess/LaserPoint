-- Main (Script)
-- Local no Studio: ServerScriptService > Main
-- Roda em: servidor
--
-- Único ponto de entrada do servidor. Ele carrega os serviços e chama Init()
-- de cada um, numa ordem explícita. Assim você sempre sabe onde o servidor
-- começa e quem depende de quem.
--
-- Ordem:
--   1. CombatService (não depende de ninguém)
--   2. WeaponService (precisa do CombatService para aplicar dano)
--
-- Serviços futuros (MatchService, DataService...) entram aqui, na fase deles.

local Services = script.Parent:WaitForChild("Services")

local CombatService = require(Services:WaitForChild("CombatService"))
local WeaponService = require(Services:WaitForChild("WeaponService"))

CombatService.Init()
WeaponService.Init(CombatService)

print("[LaserPoint] Servidor iniciado")
