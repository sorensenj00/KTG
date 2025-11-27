local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShotReplicator = {}

-- Config
local REPLICATION_RATE = 1/20 -- 20 times per second (50ms latency)
local lastReplicationTime = 0
local shotBuffer = {}

-- Remotes
local remotes = ReplicatedStorage.Blaster:WaitForChild("Remotes")
local replicateShotRemote = remotes:WaitForChild("ReplicateShot")

function ShotReplicator.Buffer(tool, originPosition, visualRayResults)
	table.insert(shotBuffer, {
		tool = tool,
		origin = originPosition,
		results = visualRayResults
	})
end

function ShotReplicator.Start()
	RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - lastReplicationTime >= REPLICATION_RATE then
			lastReplicationTime = now

			if #shotBuffer > 0 then
				-- Fire all buffered shots in one packet
				replicateShotRemote:FireAllClients(shotBuffer)

				-- Clear buffer
				table.clear(shotBuffer)
			end
		end
	end)
end

return ShotReplicator
