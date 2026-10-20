--!strict

--[[
	SpringSolver

	Pure math module for damped harmonic oscillator spring physics.
	No React dependency — operates on flat number arrays.

	Complex types (UDim2, Color3, Vector2) are decomposed into number
	arrays, solved component-wise, then recomposed.

	Physics model (semi-implicit Euler):
		velocity += (-force * displacement - dampening * velocity) / mass * dt
		position += velocity * dt
]]

local SpringSolver = {}

-- ============================================================================
-- TYPES
-- ============================================================================

export type SpringConfig = {
	force: number,
	dampening: number,
	mass: number,
}

export type SpringState = {
	position: { number },
	velocity: { number },
	target: { number },
	settled: boolean,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local VELOCITY_THRESHOLD = 0.01
local POSITION_THRESHOLD = 0.001

SpringSolver.DEFAULT_CONFIG = {
	force = 180,
	dampening = 20,
	mass = 1,
} :: SpringConfig

-- ============================================================================
-- VALUE DECOMPOSITION / RECOMPOSITION
-- ============================================================================

function SpringSolver.decompose(value: any): { number }
	local t = typeof(value)

	if t == "number" then
		return { value }
	elseif t == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	elseif t == "UDim" then
		return { value.Scale, value.Offset }
	elseif t == "Vector2" then
		return { value.X, value.Y }
	elseif t == "Color3" then
		return { value.R, value.G, value.B }
	else
		error(`SpringSolver: unsupported type "{t}"`)
	end
end

function SpringSolver.recompose(components: { number }, template: any): any
	local t = typeof(template)

	if t == "number" then
		return components[1]
	elseif t == "UDim2" then
		return UDim2.new(components[1], components[2], components[3], components[4])
	elseif t == "UDim" then
		return UDim.new(components[1], components[2])
	elseif t == "Vector2" then
		return Vector2.new(components[1], components[2])
	elseif t == "Color3" then
		return Color3.new(
			math.clamp(components[1], 0, 1),
			math.clamp(components[2], 0, 1),
			math.clamp(components[3], 0, 1)
		)
	else
		error(`SpringSolver: unsupported type "{t}"`)
	end
end

-- ============================================================================
-- SPRING STATE CREATION
-- ============================================================================

function SpringSolver.create(initialValue: any, targetValue: any): SpringState
	local position = SpringSolver.decompose(initialValue)
	local target = SpringSolver.decompose(targetValue)
	local velocity: { number } = {}

	for i = 1, #position do
		velocity[i] = 0
	end

	return {
		position = position,
		velocity = velocity,
		target = target,
		settled = false,
	}
end

-- ============================================================================
-- SOLVER
-- ============================================================================

local MAX_STEP = 1 / 240 -- seconds

function SpringSolver.step(state: SpringState, config: SpringConfig, dt: number): SpringState
	local position = state.position
	local velocity = state.velocity
	local target = state.target
	local force = config.force
	local dampening = config.dampening
	local mass = config.mass

	local newPosition: { number } = {}
	local newVelocity: { number } = {}
	local allSettled = true

	-- Small fixed sub-steps: one big step per frame overshoots further each
	-- frame when the frame rate drops (Studio unfocused, a slow device), and a
	-- stiff spring then oscillates and grows instead of settling.
	dt = math.min(dt, 0.25) -- a long hitch shouldn't cost thousands of steps
	local steps = math.max(1, math.ceil(dt / MAX_STEP))
	local h = dt / steps
	for i = 1, #position do
		local p = position[i]
		local v = velocity[i]
		for _ = 1, steps do
			local acceleration = (-force * (p - target[i]) - dampening * v) / mass
			v += acceleration * h
			p += v * h
		end

		newVelocity[i] = v
		newPosition[i] = p

		if math.abs(v) > VELOCITY_THRESHOLD or math.abs(p - target[i]) > POSITION_THRESHOLD then
			allSettled = false
		end
	end

	-- Snap to target when settled to avoid floating point drift
	if allSettled then
		for i = 1, #target do
			newPosition[i] = target[i]
			newVelocity[i] = 0
		end
	end

	return {
		position = newPosition,
		velocity = newVelocity,
		target = target,
		settled = allSettled,
	}
end

function SpringSolver.isSettled(state: SpringState): boolean
	return state.settled
end

-- Update target while preserving current position and velocity
function SpringSolver.retarget(state: SpringState, newTarget: { number }): SpringState
	return {
		position = state.position,
		velocity = state.velocity,
		target = newTarget,
		settled = false,
	}
end

return SpringSolver
