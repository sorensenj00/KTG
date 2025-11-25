-- ServerScriptService/Utility/ErrorHandler.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local ErrorHandler = {}

-- Error categories for filtering/tracking
local ErrorCategory = {
	DataStore = "DataStore",
	Network = "Network",
	Physics = "Physics",
	Gameplay = "Gameplay",
	UI = "UI",
}

-- Error severity levels
local ErrorSeverity = {
	Info = 1,
	Warning = 2,
	Error = 3,
	Critical = 4,
}

-- Configuration
local MAX_ERROR_LOG_SIZE = 100
local ENABLE_VERBOSE_LOGGING = RunService:IsStudio()

-- State
local errorLog = {}
local errorCounts = {}

-- Log error with context
local function logError(category, severity, message, context)
	local timestamp = os.time()
	local errorEntry = {
		timestamp = timestamp,
		category = category,
		severity = severity,
		message = message,
		context = context or {},
	}

	-- Add to log
	table.insert(errorLog, errorEntry)
	if #errorLog > MAX_ERROR_LOG_SIZE then
		table.remove(errorLog, 1) -- Remove oldest
	end

	-- Track counts
	errorCounts[category] = (errorCounts[category] or 0) + 1

	-- Console output with formatting
	local prefix = "ℹ️"
	if severity == ErrorSeverity.Warning then
		prefix = "⚠️"
	elseif severity == ErrorSeverity.Error then
		prefix = "❌"
	elseif severity == ErrorSeverity.Critical then
		prefix = "🔥"
	end

	local output = string.format(
		"%s [%s] %s",
		prefix,
		category,
		message
	)

	if ENABLE_VERBOSE_LOGGING and context and next(context) then
		output = output .. "\n  Context: " .. game:GetService("HttpService"):JSONEncode(context)
	end

	if severity >= ErrorSeverity.Error then
		warn(output)
	else
		print(output)
	end
end

-- Wrap function with error handling
function ErrorHandler.wrap(category, func, context)
	return function(...)
		local success, result = pcall(func, ...)
		if not success then
			logError(
				category,
				ErrorSeverity.Error,
				"Function failed: " .. tostring(result),
				context
			)
			return nil, result
		end
		return result
	end
end

-- Safe async wrapper
function ErrorHandler.wrapAsync(category, func, context)
	return function(...)
		task.spawn(function(...)
			local success, result = pcall(func, ...)
			if not success then
				logError(
					category,
					ErrorSeverity.Error,
					"Async function failed: " .. tostring(result),
					context
				)
			end
		end, ...)
	end
end

-- Log specific error types
function ErrorHandler.logDataStoreError(operation, key, error)
	logError(
		ErrorCategory.DataStore,
		ErrorSeverity.Error,
		string.format("DataStore %s failed for key '%s'", operation, key),
		{operation = operation, key = key, error = tostring(error)}
	)
end

function ErrorHandler.logNetworkError(remoteName, error)
	logError(
		ErrorCategory.Network,
		ErrorSeverity.Warning,
		string.format("Network call to '%s' failed", remoteName),
		{remote = remoteName, error = tostring(error)}
	)
end

-- Get error statistics
function ErrorHandler.getStats()
	return {
		totalErrors = #errorLog,
		errorsByCategory = errorCounts,
		recentErrors = {table.unpack(errorLog, math.max(1, #errorLog - 10), #errorLog)},
	}
end

-- Clear error log
function ErrorHandler.clear()
	errorLog = {}
	errorCounts = {}
end

-- Export error categories for external use
ErrorHandler.Category = ErrorCategory
ErrorHandler.Severity = ErrorSeverity

return ErrorHandler

