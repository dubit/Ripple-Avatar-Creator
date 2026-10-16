--!strict

--[[
	NetworkBuilder - Engine module for building Network infrastructure

	This module contains the auto-generation logic for Network.luau.
	Game developers should not need to modify this file.

	The NetworkBuilder takes a configuration object and Bolt library,
	then generates:
	- Network.Actions: Action constant tables for type-safe intent handling
	- Network.Intent: Bolt ReliableEvents for client-server communication
	- Network.State: Bolt RemoteProperties for server-client state sync
	- Network.registerIntent(): Function to retrieve ReliableEvents
	- Network.registerState(): Function to retrieve RemoteProperties
]]

local NetworkBuilder = {}

-- Build Network.Actions from controller config
-- Creates nested tables mapping controller names to action constants
-- Example: { Basket = { Add = "Add", Remove = "Remove" } }
local function buildActions(controllersConfig: { [string]: { string } })
	local actions = {}
	for controllerName, actionList in controllersConfig do
		actions[controllerName] = {}
		for _, actionName in actionList do
			actions[controllerName][actionName] = actionName
		end
	end
	return actions
end

-- Build Network.Intent from controller config
-- Creates Bolt ReliableEvents for each controller
-- Example: { Basket = ReliableEvent("BasketIntent") }
local function buildIntents(controllersConfig: { [string]: { string } }, Bolt: any)
	local intents = {}
	for controllerName in controllersConfig do
		intents[controllerName] = Bolt.ReliableEvent(controllerName .. "Intent")
	end
	return intents
end

-- Build Network.State from states config
-- Creates Bolt RemoteProperties for each model with default values
-- Example: { Basket = RemoteProperty("BasketState", { ownerId = "", items = {} }) }
local function buildStates(statesConfig: { [string]: any }, Bolt: any)
	local states = {}
	for stateName, defaultValue in statesConfig do
		states[stateName] = Bolt.RemoteProperty(stateName .. "State", defaultValue)
	end
	return states
end

--[[
	Build the complete Network module from configuration

	@param config - NetworkConfig with Controllers and States tables
	@param Bolt - Bolt networking library instance
	@return Network module with Intent, State, Actions, and registration functions
]]
function NetworkBuilder.build(config: any, Bolt: any): any
	local Network = {
		Intent = buildIntents(config.Controllers, Bolt),
		State = buildStates(config.States, Bolt),
		Actions = buildActions(config.Controllers),
	}

	--[[
		Get a Bolt ReliableEvent for controller intents

		Note: Intents are eagerly created at module load, this just returns the existing one

		@param controllerName - Name of the controller (e.g., "Basket")
		@return Bolt.ReliableEvent for this controller
	]]
	function Network.registerIntent(controllerName: string): any
		if Network.Intent[controllerName] then
			return Network.Intent[controllerName]
		end

		error(`[Network] Unknown controller intent: {controllerName}. Add it to NetworkConfig.Controllers.`)
	end

	--[[
		Get a Bolt RemoteProperty for model state synchronization

		Note: Properties are eagerly created at module load, this just returns the existing one

		@param modelName - Name of the model (e.g., "Basket")
		@return Bolt.RemoteProperty for this model
	]]
	function Network.registerState(modelName: string): any
		if Network.State[modelName] then
			return Network.State[modelName]
		end

		error(`[Network] Unknown model state: {modelName}. Add it to NetworkConfig.States.`)
	end

	return Network
end

return NetworkBuilder
