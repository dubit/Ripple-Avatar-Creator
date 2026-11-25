--!strict

--[[
	OnboardingModel (User scope — persisted per player)

	Which onboarding steps the player has done, so each hint shows only until
	they've used the thing it points at, in this session or any later one.
	Steps are short names:
	  ring   opened the recommendation ring (tapped themselves)

	Marked done by the controllers that see the step happen
	(RecommendationsController, on rec_open). Testing: `/onboardingmodel
	reset` clears every step, so the hints show again.
]]

local AbstractModel = require(script.Parent.Parent.AbstractModel)

local OnboardingModel = {}
OnboardingModel.__index = OnboardingModel
setmetatable(OnboardingModel, AbstractModel)

export type OnboardingModel = typeof(setmetatable({} :: {
	done: { string }, -- steps done, in the order done
}, OnboardingModel)) & AbstractModel.AbstractModel

function OnboardingModel.new(ownerId: string): OnboardingModel
	local self = AbstractModel.new("OnboardingModel", ownerId, "User") :: any
	setmetatable(self, OnboardingModel)
	self.done = {}
	return self :: OnboardingModel
end

function OnboardingModel.get(ownerId: string): OnboardingModel?
	return AbstractModel.getOrWait("OnboardingModel", ownerId, function()
		return OnboardingModel.new(ownerId)
	end) :: OnboardingModel?
end

function OnboardingModel.remove(ownerId: string): ()
	AbstractModel.removeInstance("OnboardingModel", ownerId)
end

function OnboardingModel:has(step: string): boolean
	return table.find(self.done, step) ~= nil
end

-- Mark a step done (no-op if it already is).
function OnboardingModel:complete(step: string): ()
	if self:has(step) then
		return
	end
	table.insert(self.done, step)
	self:syncState()
end

-- Forget every step: the hints show again (the /onboardingmodel reset command).
function OnboardingModel:reset(): ()
	self.done = {}
	self:syncState()
end

return OnboardingModel
