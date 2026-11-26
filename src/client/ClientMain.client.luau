-- ClientMain (LocalScript)
-- Local no Studio: StarterPlayer > StarterPlayerScripts > ClientMain
-- Roda em: cliente (um por jogador)
--
-- Único ponto de entrada do cliente. Carrega os controllers e liga um ao outro.
-- Nenhum controller faz require de outro: quem conecta é este script. Isso
-- evita dependências circulares e deixa claro quem conversa com quem.
--
--   InputController  --(apertou/soltou)-->  WeaponController
--   WeaponController --(recuo)-->           CameraController
--   WeaponController --(estado da arma)-->  UIController

local Controllers = script.Parent:WaitForChild("Controllers")

local CameraController = require(Controllers:WaitForChild("CameraController"))
local InputController = require(Controllers:WaitForChild("InputController"))
local WeaponController = require(Controllers:WaitForChild("WeaponController"))
local UIController = require(Controllers:WaitForChild("UIController"))

CameraController.Init()
UIController.Init()

WeaponController.Init({
	Camera = CameraController,
	UI = UIController,
})

InputController.Init({
	OnFireStart = function()
		WeaponController.SetTrigger(true)
	end,
	OnFireEnd = function()
		WeaponController.SetTrigger(false)
	end,
})

print("[LaserPoint] Cliente iniciado")
