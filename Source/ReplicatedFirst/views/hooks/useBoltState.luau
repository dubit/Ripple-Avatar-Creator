--!strict

--[[
	useBoltState

	Custom React hook that bridges Bolt RemoteProperty state into React.
	Bolt's :Observe() fires the callback immediately with the current value,
	then on every subsequent update. The returned function unsubscribes.

	Usage:
		local basket = useBoltState(Network.State.Basket, {
			ownerId = "",
			items = {},
		})
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))

local function useBoltState<T>(remoteProperty: any, initialValue: T): T
	local state, setState = React.useState(initialValue)

	React.useEffect(function()
		local unsubscribe = remoteProperty:Observe(function(newValue: T)
			setState(newValue)
		end)

		return function()
			if type(unsubscribe) == "function" then
				unsubscribe()
			end
		end
	end, {})

	return state
end

return useBoltState
