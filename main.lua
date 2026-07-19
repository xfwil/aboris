local Params = getgenv().Params or {}
local GAME_FOLDER = Params.Folder or "GAG"
local PATH_PREFIX_LEN = Params.PathPrefixLength or 60
local SKIP_NAMES = Params.Skip or { "Assets" }

local placeVersion = game.PlaceVersion or 0
local FINAL_FOLDER = "HUKI/" .. GAME_FOLDER .. "_" .. tostring(placeVersion)

local RS = game:GetService("ReplicatedStorage")
local decompileFunc = decompile
	or (Instance and typeof(Instance.new("ModuleScript").Source) == "string" and function(s)
		return s.Source
	end)
	or nil

local REMOTE_CLASSES = {
	"RemoteEvent",
	"RemoteFunction",
	"BindableEvent",
	"BindableFunction",
	"UnreliableRemoteEvent",
}

local totalFoldersCreated = 0
local totalFilesCreated = 0
local okScripts = 0
local failedScripts = 0
local errors = {}

local function logMessage(msg)
	print(msg)
end

local function sanitizeName(name)
	return name:gsub('[%\\%/%:%*%?%"%<%>%|]', "_")
end

-- Catat kegagalan ke daftar errors module-level agar bisa ditulis ke _errors.log di akhir
local function logError(kind, path, detail)
	local line = string.format("[%s] %s", kind, path)
	if detail ~= nil then
		line = line .. " -- " .. tostring(detail)
	end
	table.insert(errors, line)
end

-- Bungkus writefile dengan pcall supaya satu path yang gagal tidak menghentikan seluruh dump
local function safeWrite(path, content)
	local ok, err = pcall(writefile, path, content)
	if ok then
		totalFilesCreated = totalFilesCreated + 1
		return true
	end
	logError("write", path, err)
	return false
end

-- Bungkus makefolder dengan pcall, sama seperti safeWrite
local function safeFolder(path)
	local ok, err = pcall(makefolder, path)
	if ok then
		totalFoldersCreated = totalFoldersCreated + 1
		return true
	end
	logError("folder", path, err)
	return false
end

-- Cek nama persis (exact match) terhadap SKIP_NAMES, bukan substring
local function isSkipped(name)
	for _, skipName in ipairs(SKIP_NAMES) do
		if name == skipName then
			return true
		end
	end
	return false
end

-- Pass baca-saja: bentuk pohon asli, tidak terpengaruh flat mode atau kegagalan tulis
local function buildTree(instance, depth, lines, skipped)
	local line = string.rep("  ", depth) .. instance.Name .. " [" .. instance.ClassName .. "]"
	if skipped then
		table.insert(lines, line .. "  -- skipped")
		return
	end
	table.insert(lines, line)
	for _, child in ipairs(instance:GetChildren()) do
		buildTree(child, depth + 1, lines, false)
	end
end

local function hasChildren(instance)
	return #instance:GetChildren() > 0
end

local function getScriptSource(scriptInstance)
	if decompileFunc then
		local success, res = pcall(decompileFunc, scriptInstance)
		if success and type(res) == "string" and #res > 0 then
			return res, true
		end
	end
	local success, res = pcall(function()
		return scriptInstance.Source
	end)
	if success and type(res) == "string" and #res > 0 then
		return res, true
	end
	return string.format("-- [Dump Error] Failed to read script source: %s", scriptInstance.Name), false
end

-- Bungkus getScriptSource: hitung sukses/gagal dan catat path lengkap yang gagal
local function dumpSource(scriptInstance)
	local src, ok = getScriptSource(scriptInstance)
	if ok then
		okScripts = okScripts + 1
	else
		failedScripts = failedScripts + 1
		logError("source", scriptInstance:GetFullName())
	end
	return src, ok
end

local function isRemoteClass(instance)
	for _, className in ipairs(REMOTE_CLASSES) do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local function collectRemotes(instance)
	local remotes = {}
	for _, child in pairs(instance:GetChildren()) do
		if isRemoteClass(child) then
			local className = child.ClassName
			if not remotes[className] then
				remotes[className] = {}
			end
			table.insert(remotes[className], child.Name)
		end
	end
	return remotes
end

local function writeRemotesFile(remotes, folderPath)
	local hasAny = false
	for _ in pairs(remotes) do
		hasAny = true
		break
	end
	if not hasAny then
		return
	end

	local lines = { "return {" }
	for className, names in pairs(remotes) do
		table.insert(lines, "\t" .. className .. " = {")
		for _, name in ipairs(names) do
			table.insert(lines, '\t\t"' .. name .. '",')
		end
		table.insert(lines, "\t},")
	end
	table.insert(lines, "}")

	safeWrite(folderPath .. "/_remotes.lua", table.concat(lines, "\n"))
end

local function dumpStructure(instance, currentPath)
	local name = sanitizeName(instance.Name)
	local isScript = instance:IsA("LuaSourceContainer")
	local hasKids = hasChildren(instance)

	-- Skip remotes (they are collected separately by parent)
	if isRemoteClass(instance) then
		return
	end

	if not isScript and not hasKids then
		return
	end

	-- Hitung perkiraan panjang path penuh di Windows saat ini
	-- Batas maksimal aman adalah ~210 karakter untuk menyisakan ruang bagi nama file + ekstensi
	local currentPathLength = #currentPath + #name

	if isScript then
		local sourceText = dumpSource(instance)

		if hasKids then
			if currentPathLength < 210 then
				-- JALUR AMAN: Buat folder seperti biasa (Bisa tembus tingkat 5+ selama nama pendek)
				local newFolderPath = currentPath .. "/" .. name
				safeFolder(newFolderPath)
				safeWrite(newFolderPath .. "/init.lua", sourceText)

				writeRemotesFile(collectRemotes(instance), newFolderPath)

				for _, child in pairs(instance:GetChildren()) do
					dumpStructure(child, newFolderPath)
				end
			else
				-- JALUR DARURAT: Path hampir menembus 260 karakter, aktifkan flat mode untuk sisanya
				local flatName = name
				safeWrite(currentPath .. "/" .. flatName .. ".init.lua", sourceText)

				for _, child in pairs(instance:GetChildren()) do
					local function dumpFlat(target, prefix)
						local cName = sanitizeName(target.Name)
						if target:IsA("LuaSourceContainer") then
							safeWrite(currentPath .. "/" .. prefix .. "." .. cName .. ".lua", dumpSource(target))
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
			safeWrite(fileName, sourceText)
		end
	else
		if currentPathLength < 210 then
			-- JALUR AMAN: Buat folder container biasa
			local newFolderPath = currentPath .. "/" .. name
			safeFolder(newFolderPath)

			writeRemotesFile(collectRemotes(instance), newFolderPath)

			for _, child in pairs(instance:GetChildren()) do
				dumpStructure(child, newFolderPath)
			end
		else
			-- JALUR DARURAT: Flat mode untuk folder container yang terlalu dalam/panjang
			for _, child in pairs(instance:GetChildren()) do
				local function dumpFlat(target, prefix)
					local cName = sanitizeName(target.Name)
					if target:IsA("LuaSourceContainer") then
						safeWrite(currentPath .. "/" .. prefix .. "." .. cName .. ".lua", dumpSource(target))
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

	print(string.format("[*] Progress: [%s] %d%% (%d/%d) | Current: %s", bar, percent, current, total, currentItemName))
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

-- Folder root: hanya dibuat kalau belum ada, supaya run berulang tidak
-- mencatat error palsu di _errors.log
if not isfolder("HUKI") then
	safeFolder("HUKI")
end
if not isfolder(FINAL_FOLDER) then
	safeFolder(FINAL_FOLDER)
end

-- Collect remotes at root level of ReplicatedStorage
writeRemotesFile(collectRemotes(RS), FINAL_FOLDER)

local treeLines = { "ReplicatedStorage [ReplicatedStorage]" }
for _, child in ipairs(RS:GetChildren()) do
	buildTree(child, 1, treeLines, isSkipped(child.Name))
end
safeWrite(FINAL_FOLDER .. "/_tree.txt", table.concat(treeLines, "\n"))
logMessage("[*] Tree written: " .. #treeLines .. " instances")

local children = RS:GetChildren()
local totalItems = #children

for index, child in pairs(children) do
	local shortName = #child.Name > 20 and string.sub(child.Name, 1, 17) .. "..." or child.Name

	-- Skip nama yang cocok persis dengan SKIP_NAMES (bukan substring)
	if isSkipped(child.Name) then
		print(string.format("[*] Skipped: %s (%d/%d)", shortName, index, totalItems))
		task.wait(0.01)
		continue
	end

	drawProgressBar(index, totalItems, shortName)
	dumpStructure(child, FINAL_FOLDER)
	task.wait(0.01)
end

-- Tulis error log mentah: pakai pcall(writefile,...) langsung, BUKAN safeWrite,
-- karena safeWrite akan menambah ke errors -- yaitu list yang sedang kita tulis ini.
if #errors > 0 then
	pcall(writefile, FINAL_FOLDER .. "/_errors.log", table.concat(errors, "\n"))
end

logMessage("\n----------------------------------------------------------")
logMessage("                     DUMP SUCCESS!                        ")
logMessage("----------------------------------------------------------")
logMessage("[✓] Output Directory : workspace/" .. FINAL_FOLDER)
logMessage("[✓] Folders Created  : " .. totalFoldersCreated .. " directories")
logMessage("[✓] Lua Files Created: " .. totalFilesCreated .. " files")
logMessage("[✓] Scripts          : " .. okScripts .. " ok, " .. failedScripts .. " failed")
if #errors > 0 then
	logMessage("[!] Errors           : " .. #errors .. " -- lihat _errors.log")
end
logMessage("==========================================================")
