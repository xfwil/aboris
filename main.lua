local Params = getgenv().Params or {}
local GAME_FOLDER = Params.Folder or "GAG"

local placeVersion = game.PlaceVersion or 0
local FINAL_FOLDER = "HUKI/" .. GAME_FOLDER .. "_" .. tostring(placeVersion)

local RS = game:GetService("ReplicatedStorage")
local decompileFunc = decompile
	or (Instance and typeof(Instance.new("ModuleScript").Source) == "string" and function(s)
		return s.Source
	end)
	or nil

local totalFoldersCreated = 0
local totalFilesCreated = 0

local function logMessage(msg)
	if rconsoleprint then
		rconsoleprint(msg .. "\n")
	else
		print(msg)
	end
end

local function sanitizeName(name)
	return name:gsub('[%\\%/%:%*%?%"%<%>%|]', "_")
end

local function hasChildren(instance)
	return #instance:GetChildren() > 0
end

local function getScriptSource(scriptInstance)
	if decompileFunc then
		local success, res = pcall(decompileFunc, scriptInstance)
		if success and type(res) == "string" and #res > 0 then
			return res
		end
	end
	local success, res = pcall(function()
		return scriptInstance.Source
	end)
	if success and type(res) == "string" and #res > 0 then
		return res
	end
	return string.format("-- [Dump Error] Failed to read script source: %s", scriptInstance.Name)
end

local function dumpStructure(instance, currentPath)
	local name = sanitizeName(instance.Name)
	local isScript = instance:IsA("LuaSourceContainer")
	local hasKids = hasChildren(instance)

	if not isScript and not hasKids then
		return
	end

	-- Hitung perkiraan panjang path penuh di Windows saat ini
	-- Batas maksimal aman adalah ~210 karakter untuk menyisakan ruang bagi nama file + ekstensi
	local currentPathLength = #currentPath + #name

	if isScript then
		local sourceText = getScriptSource(instance)

		if hasKids then
			if currentPathLength < 210 then
				-- JALUR AMAN: Buat folder seperti biasa (Bisa tembus tingkat 5+ selama nama pendek)
				local newFolderPath = currentPath .. "/" .. name
				makefolder(newFolderPath)
				totalFoldersCreated = totalFoldersCreated + 1
				writefile(newFolderPath .. "/init.lua", sourceText)
				totalFilesCreated = totalFilesCreated + 1

				for _, child in pairs(instance:GetChildren()) do
					dumpStructure(child, newFolderPath)
				end
			else
				-- JALUR DARURAT: Path hampir menembus 260 karakter, aktifkan flat mode untuk sisanya
				local flatName = name
				writefile(currentPath .. "/" .. flatName .. ".init.lua", sourceText)
				totalFilesCreated = totalFilesCreated + 1

				for _, child in pairs(instance:GetChildren()) do
					local function dumpFlat(target, prefix)
						local cName = sanitizeName(target.Name)
						if target:IsA("LuaSourceContainer") then
							writefile(currentPath .. "/" .. prefix .. "." .. cName .. ".lua", getScriptSource(target))
							totalFilesCreated = totalFilesCreated + 1
						end
						for _, subChild in pairs(target:GetChildren()) do
							dumpFlat(subChild, prefix .. "." .. cName)
						end
					end
					dumpFlat(child, flatName)
				end
			end
		else
			local fileName = currentPath .. "/" .. name .. ".lua"
			writefile(fileName, sourceText)
			totalFilesCreated = totalFilesCreated + 1
		end
	else
		if currentPathLength < 210 then
			-- JALUR AMAN: Buat folder container biasa
			local newFolderPath = currentPath .. "/" .. name
			makefolder(newFolderPath)
			totalFoldersCreated = totalFoldersCreated + 1

			for _, child in pairs(instance:GetChildren()) do
				dumpStructure(child, newFolderPath)
			end
		else
			-- JALUR DARURAT: Flat mode untuk folder container yang terlalu dalam/panjang
			for _, child in pairs(instance:GetChildren()) do
				local function dumpFlat(target, prefix)
					local cName = sanitizeName(target.Name)
					if target:IsA("LuaSourceContainer") then
						writefile(currentPath .. "/" .. prefix .. "." .. cName .. ".lua", getScriptSource(target))
						totalFilesCreated = totalFilesCreated + 1
					end
					for _, subChild in pairs(target:GetChildren()) do
						dumpFlat(subChild, prefix .. "." .. cName)
					end
				end
				dumpFlat(child, name)
			end
		end
	end
end

local function drawProgressBar(current, total, currentItemName)
	local percent = math.floor((current / total) * 100)
	local barLength = 20
	local filledLength = math.floor((percent / 100) * barLength)
	local bar = string.rep("█", filledLength) .. string.rep("░", barLength - filledLength)

	local output =
		string.format("\r[*] Progress: [%s] %d%% (%d/%d) | Current: %s", bar, percent, current, total, currentItemName)
	if rconsoleprint then
		rconsoleprint(output)
	else
		print(string.format("[*] Progress: %d%% - Extracting: %s", percent, currentItemName))
	end
end

if rconsoleclear then
	rconsoleclear()
end
logMessage("==========================================================")
logMessage("                         Aboris                           ")
logMessage("==========================================================")
logMessage("[*] Target Game    : " .. GAME_FOLDER)
logMessage("[*] Place Version  : " .. tostring(placeVersion))
logMessage("[*] Output Path    : workspace/" .. FINAL_FOLDER)
logMessage("----------------------------------------------------------")
logMessage("[*] Extracting asset structures, please wait...")
logMessage("----------------------------------------------------------")

pcall(function()
	makefolder("HUKI")
end)
pcall(function()
	makefolder(FINAL_FOLDER)
end)

local children = RS:GetChildren()
local totalItems = #children

for index, child in pairs(children) do
	local shortName = #child.Name > 20 and string.sub(child.Name, 1, 17) .. "..." or child.Name
	if rconsoleclear and index > 1 then
		rconsoleprint("\r" .. string.rep(" ", 100) .. "\r")
	end
	drawProgressBar(index, totalItems, shortName)
	dumpStructure(child, FINAL_FOLDER)
	task.wait(0.01)
end

logMessage("\n----------------------------------------------------------")
logMessage("                     DUMP SUCCESS!                        ")
logMessage("----------------------------------------------------------")
logMessage("[✓] Output Directory : workspace/" .. FINAL_FOLDER)
logMessage("[✓] Folders Created  : " .. totalFoldersCreated .. " directories")
logMessage("[✓] Lua Files Created: " .. totalFilesCreated .. " files")
logMessage("==========================================================")
