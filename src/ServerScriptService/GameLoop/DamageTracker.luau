local DamageTracker = {}

-- Damage tracking: [victimCharacter] = { [attackerEntity] = totalDamage }
local damageData = {}

-- Reset all damage tracking every 10 seconds
task.spawn(function()
	while true do
		task.wait(10)
		damageData = {}
		print("🔄 DamageTracker: Reset all damage tracking")
	end
end)

-- Record damage dealt
-- attacker: Player or Bot Model
-- victimCharacter: Character Model (player character or bot)
-- damage: number
function DamageTracker.RecordDamage(attacker, victimCharacter, damage)
	if not attacker or not victimCharacter or not damage or damage <= 0 then
		return
	end

	if not damageData[victimCharacter] then
		damageData[victimCharacter] = {}
	end

	if not damageData[victimCharacter][attacker] then
		damageData[victimCharacter][attacker] = 0
	end

	damageData[victimCharacter][attacker] = damageData[victimCharacter][attacker] + damage
end

-- Get all attackers and their damage for a victim
-- Returns: { [attacker] = damageAmount }
function DamageTracker.GetDamageDealers(victimCharacter)
	if not victimCharacter or not damageData[victimCharacter] then
		return {}
	end

	return damageData[victimCharacter]
end

-- Clear damage data for a specific victim (called when they die)
function DamageTracker.ClearVictimData(victimCharacter)
	if victimCharacter and damageData[victimCharacter] then
		damageData[victimCharacter] = nil
	end
end

return DamageTracker

