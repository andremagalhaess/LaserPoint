-- InputController (ModuleScript)
-- Local no Studio: StarterPlayer > StarterPlayerScripts > Controllers > InputController
-- Roda em: cliente
-- Depende de: nada
-- Usado por: ClientMain
--
-- Traduz os controles em duas mensagens simples: "começou a atirar" e
-- "parou de atirar". Ele não sabe nada de armas.
--
-- ContextActionService:BindAction com o terceiro argumento = true cria
-- AUTOMATICAMENTE um botão na tela em celulares e tablets. No PC, a mesma
-- ação usa o botão esquerdo do mouse; no controle, o gatilho direito (R2).

local ContextActionService = game:GetService("ContextActionService")

local FIRE_ACTION = "LaserPointFire"

local InputController = {}

function InputController.Init(callbacks)
	local function handleFire(_actionName, inputState, _inputObject)
		if inputState == Enum.UserInputState.Begin then
			callbacks.OnFireStart()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			callbacks.OnFireEnd()
		end
		return Enum.ContextActionResult.Pass
	end

	ContextActionService:BindAction(
		FIRE_ACTION,
		handleFire,
		true, -- cria botão de toque no mobile
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:SetTitle(FIRE_ACTION, "FIRE")
end

return InputController
