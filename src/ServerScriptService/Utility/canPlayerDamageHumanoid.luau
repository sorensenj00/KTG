--[[
    Module: canPlayerDamageHumanoid
    Description: Determines if an attacker (Player or Bot) can damage a target Humanoid based on team rules and game state.
    
    Dependencies:
    - Players (Roblox Service)
    
    Public API:
    - canPlayerDamageHumanoid(attacker: Player | Model, taggedHumanoid: Humanoid): boolean
        Returns true if the attacker can damage the target, false otherwise.
        Handles PvP team checks, bot FFA rules, and neutral player logic.
    
    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")

local function canPlayerDamageHumanoid(attacker: Player | Model, taggedHumanoid: Humanoid): boolean
	-- If the humanoid is already dead, no need to apply more damage
	if taggedHumanoid.Health <= 0 then
		return false
	end

	local taggedCharacter = taggedHumanoid.Parent
	local taggedPlayer = Players:GetPlayerFromCharacter(taggedCharacter)
	
	-- 1. Attacker is a Bot (Model)
	if attacker:IsA("Model") then
		-- Bot can damage anyone except itself (self-damage check usually done before calling this or via exclusion)
		if taggedCharacter == attacker then
			return false
		end
		return true -- FFA for bots
	end

	-- 2. Attacker is a Player
	if not attacker:IsA("Player") then
		return false -- Should not happen if types are correct
	end

	-- If the player tagged a non-player humanoid (e.g. Bot) then allow damage
	if not taggedPlayer then
		return true
	end

	if attacker.Neutral or taggedPlayer.Neutral then
		-- If either player is neutral (i.e. not on a team) then allow damage
		return true
	else
		-- Only allow damage if the players are not on the same team
		return attacker.Team ~= taggedPlayer.Team
	end
end

return canPlayerDamageHumanoid
