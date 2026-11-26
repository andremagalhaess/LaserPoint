-- CameraController (ModuleScript)
-- Local no Studio: StarterPlayer > StarterPlayerScripts > Controllers > CameraController
-- Roda em: cliente
-- Depende de: nada
-- Usado por: ClientMain (Init) e WeaponController (Kick)
--
-- A primeira pessoa em si vem da propriedade StarterPlayer.CameraMode =
-- LockFirstPerson (o Roblox trava a câmera na cabeça e prende o mouse no
-- centro). Este controller só cuida de duas coisas:
--   1. Campo de visão (FOV).
--   2. Um recuo leve a cada tiro, que volta sozinho.
--
-- Como o recuo funciona: a cada frame, logo depois que a câmera padrão do
-- Roblox se atualiza, giramos a câmera um pouco para cima. Aplicamos só a
-- DIFERENÇA desde o frame anterior, para que, quando o recuo diminui, a
-- câmera volte exatamente para onde o jogador estava mirando.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FIELD_OF_VIEW = 80
local KICK_PER_SHOT = math.rad(0.6) -- quanto sobe por tiro
local MAX_KICK = math.rad(3) -- limite acumulado
local RECOVERY_SPEED = 12 -- quanto maior, mais rápido volta

local CameraController = {}

local kickTarget = 0 -- quanto de recuo queremos agora
local kickApplied = 0 -- quanto de recuo já está aplicado na câmera

local function onRenderStep(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.FieldOfView = FIELD_OF_VIEW

	-- O recuo diminui exponencialmente: rápido no começo, suave no fim.
	kickTarget = kickTarget * math.exp(-RECOVERY_SPEED * dt)
	if kickTarget < 1e-4 then
		kickTarget = 0
	end

	local delta = kickTarget - kickApplied
	if delta ~= 0 then
		camera.CFrame = camera.CFrame * CFrame.Angles(delta, 0, 0)
		kickApplied = kickTarget
	end
end

function CameraController.Init()
	-- Prioridade Camera + 1 = roda logo depois da câmera padrão do Roblox.
	RunService:BindToRenderStep("LaserPointCamera", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
end

-- Chamado pelo WeaponController a cada tiro.
function CameraController.Kick()
	kickTarget = math.min(kickTarget + KICK_PER_SHOT, MAX_KICK)
end

return CameraController
