--[[
The MIT License (MIT)

Copyright (c) 2012 Lyqyd, (c) 2017 Wilma456

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

You can find the original here:
https://github.com/lyqyd/cc-packman/blob/master/package
--]]

list = {}
installed = {}
installRoot = "/"
config = {}
local unpack = unpack or table.unpack

local function postStatus(type, text)
	os.queueEvent("package_status", type, text)
	while true do
		local event = {os.pullEvent("package_status")}
		if event[1] == "package_status" then break end
	end
end

local function printInformation(text)
	postStatus("info", text)
end

local function printWarning(text)
	postStatus("warning", text)
end

local function printError(text)
	postStatus("error", text)
end

local function findFileEntry(fileList, path)
	local entryFound = false
	for i = 1, #fileList do
		if fileList[i].path == path then
			entryFound = i
			break
		end
	end
	return entryFound
end

local function updateFileInfo(fileList, path, version)
	local entry = findFileEntry(fileList, path)
	if entry then
		fileList[entry].path = path
		fileList[entry].version = version
	else
		table.insert(fileList, {path = path, version = version})
	end
end

local transactionQueue = {}
local currentPackage

local Transaction = {
	writeFile = function(self)
		local path = fs.combine(minepackapi.installRoot, self.path)
		if fs.exists(path) then
			local handle = io.open(path, "r")
			if handle then
				self.backup = handle:read("*a")
				handle:close()
			end
		end
		local handle = io.open(path, "w")
		if handle then
			printInformation("Writing file "..path)
			handle:write(self.contents)
			handle:close()
		else
			return false
		end
		return true
	end,
	deleteFile = function(self)
		local path = fs.combine(minepackapi.installRoot, self.path)
		if fs.exists(path) then
			local handle = io.open(path, "r")
			if handle then
				self.backup = handle:read("*a")
				handle:close()
			end
		end
		printInformation("Deleting file "..path)
		fs.delete(path)
		return not fs.exists(path)
	end,
	makeDirectory = function(self)
		local path = fs.combine(minepackapi.installRoot, self.path)
		if not fs.exists(path) then
			printInformation("Creating directory "..path)
			fs.makeDir(path)
		end
		return fs.isDir(path)
	end,
	removeDirectory = function(self)
		local path = fs.combine(minepackapi.installRoot, self.path)
		if fs.exists(path) and fs.isDir(path) and #(fs.list(path)) == 0 then
			printInformation("Removing directory "..path)
			fs.delete(path)
		end
		return not fs.exists(path)
	end,
	updateInfo = function(self)
		newLine = self.path..(self.version and ";"..self.version or "")
		local lineFound = false
		for i = 1, #self.contents do
			if self.path == string.match(self.contents[i], "^([^;]+)") then
				--found the right entry, modify correctly now.
				lineFound = true
				self.contents[i] = newLine
				updateFileInfo(minepackapi.installed[self.pack.fullName].files, self.path, self.version)
				break
			end
		end
		if not lineFound and newLine then
			--didn't find a matching line in the loop, add a new line at the end.
			table.insert(self.contents, newLine)
		end
	end,
	removeInfo = function(self)
		for i = 1, #self.contents do
			if self.path == string.match(self.contents[i], "^([^;]+)") then
				table.remove(self.contents, i)
				local entry = findFileEntry(minepackapi.installed[self.pack.fullName].files, self.path)
				if entry then
					table.remove(minepackapi.installed[self.pack.fullName].files, entry)
				end
				break
			end
		end
	end,
}

function Transaction.finish(self)
	if Transaction[self.type] then
		return Transaction[self.type](self)
	else
		return false
	end
end

function Transaction.rollback(self)
	if Transaction[self.type] then
		if self.type == "writeFile" then
			if self.backup ~= nil then
				self.contents = self.backup
				return Transaction.writeFile(self)
			else
				return Transaction.deleteFile(self)
			end
		elseif self.type == "deleteFile" then
			if self.backup ~= nil then
				self.contents = self.backup
				return Transaction.writeFile(self)
			end
		elseif self.type == "makeDirectory" then
			return Transaction.removeDirectory(self)
		elseif self.type == "removeDirectory" then
			return Transaction.makeDirectory(self)
		end
	else
		return false
	end
end

local tmeta = {__index = Transaction}

local function newTransaction(pack, path, type, contents, version)
	local transaction = {
		pack = pack,
		path = path,
		type = type,
		contents = contents,
		version = version,
		backup = nil,
	}

	setmetatable(transaction, tmeta)

	return transaction
end

function loadConfig(sPath,sDefault)
if not fs.exists(sPath) then
    local writefi = fs.open(sPath,"w")
    writefi.write(sDefault)
    writefi.close()
end
local fileh = io.open(sPath)
for linecon in fileh:lines() do
    if linecon:find("#") ~= 1 then
        local sHead, sBody = linecon:match("([^=]+)=([^=]+)")
        minepackapi.config[sHead] = sBody
    end
end
fileh:close()
end

local TransQueue = {
	addFile = function(self, path, contents, version)
		table.insert(self.transactions, newTransaction(self.pack, path, "writeFile", contents, version))
	end,
	removeFile = function(self, path)
		table.insert(self.transactions, newTransaction(self.pack, path, "deleteFile"))
	end,
	makeDir = function(self, path)
		if string.match(path, "(.-)/[^/]+$") and not fs.exists(fs.combine(minepackapi.installRoot, string.match(path, "(.-)/[^/]+$"))) then
			self:makeDir(string.match(path, "(.-)/[^/]+$"))
		end
		if not fs.exists(fs.combine(minepackapi.installRoot, path)) then
			table.insert(self.transactions, newTransaction(self.pack, path, "makeDirectory"))
		end
	end,
	removeDir = function(self, path)
		table.insert(self.transactions, newTransaction(self.pack, path, "removeDirectory"))
	end,
	env = function(self)
		return {
			addFile = function(path, contents, version)
				self:addFile(path, contents, version)
			end,
			removeFile = function(path)
				self:removeFile(path)
			end,
			makeDir = function(path)
				self:makeDir(path)
			end,
			removeDir = function(path)
				self:removeDir(path)
			end,
		}
	end,
	finish = function(self)
		local installedFile = fs.combine(fs.combine(minepackapi.installRoot, minepackapi.config.minepackDirectory.."/installed"), self.pack.fullName..".txt")
		local installedData = {}
		if installed[self.pack.fullName] and fs.exists(installedFile) then
			local handle = io.open(installedFile, "r")
			if handle then
				for line in handle:lines() do
					table.insert(installedData, line)
				end
				handle:close()

				--strip version number if present
				if #installedData >= 1 then
					table.remove(installedData, 1)
				end
			end
		end

		--ensure installed table entry exists
		if not minepackapi.installed[self.pack.fullName] then
			minepackapi.installed[self.pack.fullName] = {
				version = self.pack.version,
				files = {},
			}
			if not minepackapi.installed[self.pack.name] then minepackapi.installed[self.pack.name] = {[self.pack.repo] = minepackapi.installed[self.pack.fullName]} end
		end

		local fileInfoUpdates = {}

		local lastTransaction = false

		for i = 1, #self.transactions do
			if not self.transactions[i]:finish() then
				--clean up already-processed transactions and exit
				printWarning("Transaction failed! Rolling back...")
				for j = i, 1, -1 do
					self.transactions[i]:rollback()
					return false
				end
			end
			--construct new line (or nil to remove entry, if present)
			local newLine
			if self.transactions[i].type == "writeFile" then
				table.insert(fileInfoUpdates, newTransaction(self.pack, self.transactions[i].path, "updateInfo", installedData, self.transactions[i].version))
			elseif self.transactions[i].type == "makeDirectory" then
				table.insert(fileInfoUpdates, newTransaction(self.pack, self.transactions[i].path, "updateInfo", installedData))
			elseif self.transactions[i].type == "deleteFile" or self.transactions[i].type == "removeDirectory" then
				table.insert(fileInfoUpdates, newTransaction(self.pack, self.transactions[i].path, "removeInfo", installedData))
			end
		end

		--modify installed data to match the transactions succesfully executed.
		printInformation("Updating Database")
		for i = 1, #fileInfoUpdates do
			fileInfoUpdates[i]:finish()
		end

		if self.removing and #installedData == 0 then
			fs.delete(installedFile)

			--remove entries from installed packages table if removing minepackapi.
			minepackapi.installed[self.pack.name][self.pack.repo] = nil
			local othersWithName = false
			for k, v in pairs(minepackapi.installed[self.pack.name]) do
				if v then
					othersWithName = true
					break
				end
			end
			if not othersWithName then
				minepackapi.installed[self.pack.name] = nil
			end
			minepackapi.installed[self.pack.fullName] = nil
		else
			--write out file again, if any content exists for it.
			table.insert(installedData, 1, tostring(self.pack.version))
			if not fs.exists(fs.combine(fs.combine(minepackapi.installRoot, minepackapi.config.minepackDirectory.."/installed"), self.pack.repo..".txt")) then fs.makeDir(fs.combine(fs.combine(minepackapi.installRoot, minepackapi.config.minepackDirectory.."/installed"), self.pack.repo..".txt")) end
			local handle = io.open(installedFile, "w")
			if handle then
				for k, v in ipairs(installedData) do
					handle:write(v.."\n")
				end
				handle:close()
			end
		end
		return true
	end,
}

local queueMeta = {__index = TransQueue}

function newTransactionQueue(packName, removing)
	local pack
	if minepackapi.list[packName] and minepackapi.list[packName].version then pack = minepackapi.list[packName] else return nil, "No such package!" end
	local queue = {
		pack = pack,
		removing = removing,
		transactions = {},
	}

	setmetatable(queue, queueMeta)

	return queue
end

local downloadTypes = {
	github = {
		author = true,
		repository = true,
		branch = true,
	},
	bitbucket = {
		author = true,
		repository = true,
		branch = true,
	},
	pastebin = {
		url = true,
		filename = true,
	},
	raw = {
		url = true,
		filename = true,
	},
	multi = {},
	grin = {
		author = true,
		repository = true,
	},
	meta = {},
}

local updateTypes = {
	github = "incremental",
	bitbucket = "incremental",
	grin = "replace",
	raw = "overwrite",
	multi = "overwrite",
	pastebin = "overwrite",
	meta = "overwrite",
}

local lookupFunctions = {}

lookupFunctions.github = function(info)
	local function getDirectoryContents(path)
		local fType, fPath, fVer = {}, {}, {}
		local response = http.get("https://api.github.com/repos/"..info.author.."/"..info.repository.."/contents/"..path.."?ref="..info.branch)
		if response then
			response = response.readAll()
			if response ~= nil then
				for str in response:gmatch('"type":%s*"(%w+)",') do table.insert(fType, str) end
				for str in response:gmatch('"path":%s*"([^\"]+)",') do table.insert(fPath, str) end
				for str in response:gmatch('"sha":%s*"([^\"]+)",') do table.insert(fVer, str) end
			end
		else
			printWarning("Can't fetch repository information")
			return nil
		end
		local directoryContents = {}
		for i=1, #fType do
			directoryContents[i] = {type = fType[i], path = fPath[i], version = fVer[i]}
		end
		return directoryContents
	end
	local function addDirectoryContents(path, contentsTable)
		local contents = getDirectoryContents(path)
		if not contents then return nil, "no contents" end
		for n, file in ipairs(contents) do
			if file.type == "dir" then
				addDirectoryContents(file.path, contentsTable)
			else
				table.insert(contentsTable, {path = file.path, version = file.version})
			end
		end
		return contentsTable
	end
	return addDirectoryContents("", {})
end

lookupFunctions.bitbucket = function(info)
	local function getDirectoryContents(path)
		local directoryContents = {}
		local response = http.get("https://api.bitbucket.org/1.0/repositories/"..info.author.."/"..info.repository.."/src/"..info.branch..path)
		if response then
			response = response.readAll()
			if response ~= nil then
				for str in string.gmatch(string.match(response, '"directories": %[(.-)%]'), '"([^,\"]+)"') do table.insert(directoryContents, {type = "dir", path = str}) end
				for str, ver in string.gmatch(string.match(response, '"files": %[(.-)%]'), '"path": "([^\"]+)".-"revision": "([^\"]+)"') do table.insert(directoryContents, {type = "file", path = str, version = ver}) end
			end
		else
			printWarning("Can't fetch repository information")
			return nil
		end
		return directoryContents
	end
	local function addDirectoryContents(path, contentsTable)
		local contents = getDirectoryContents(path)
		for n, file in ipairs(contents) do
			if file.type == "dir" then
				addDirectoryContents(path..file.path.."/", contentsTable)
			else
				table.insert(contentsTable, {path = file.path, version = file.version})
			end
		end
		return contentsTable
	end
	return addDirectoryContents("/", {})
end

-- Local function to download a url raw
local function raw(url)
	printInformation("Fetching: "..url)
	http.request(url)
	while true do
		local event = {os.pullEvent()}
		if event[1] == "http_success" then
			printInformation("Done!")
			return event[3].readAll()
		elseif event[1] == "http_failure" then
			printWarning("Unable to fetch file "..event[2])
			return false
		end
	end
end

local downloadFunctions = {}

downloadFunctions.raw = function(pack, env, queue, info)
	-- Delegate to local raw
	local path = fs.combine(pack.target, info.filename)

	if string.match(path, "(.-)/[^/]+$") then
		queue:makeDir(string.match(path, "(.-)/[^/]+$"))
	end
	local content = raw(info.url)
	if content then
		queue:addFile(path, content)
		return true
	else
		return false
	end
end

downloadFunctions.multi = function(pack, env, queue, info)
	local files = info.files
	for i = 1, #files do
		local path = fs.combine(pack.target, files[i].name)

		if string.match(path, "(.-)/[^/]+$") then
			queue:makeDir(string.match(path, "(.-)/[^/]+$"))
		end
		local content = raw(files[i].url)
		if content then
			queue:addFile(path, content)
		else
			return false
		end
	end
	return true
end

downloadFunctions.github = function(pack, env, queue, info)
	local contents = lookupFunctions.github(info)
	if not contents then return nil, "content fetch failure" end
	local localTarget = pack.target or ""
	for num, file in ipairs(contents) do
		local path = fs.combine(localTarget, file.path)
		if string.match(path, "(.-)/[^/]+$") then
			queue:makeDir(string.match(path, "(.-)/[^/]+$"))
		end
		local content = raw("https://raw.github.com/"..info.author.."/"..info.repository.."/"..info.branch.."/"..file.path)
		if content then
			queue:addFile(path, content, file.version)
		else
			return false
		end
	end
	return true
end

downloadFunctions.bitbucket = function(pack, env, queue, info)
	local contents = lookupFunctions.bitbucket(info)
	local localTarget = pack.target or ""
	for num, file in ipairs(contents) do
		local path = fs.combine(localTarget, file.path)
		if string.match(path, "(.-)/[^/]+$") then
			queue:makeDir(string.match(path, "(.-)/[^/]+$"))
		end
		local content = raw("https://bitbucket.org/"..info.author.."/"..info.repository.."/raw/"..info.branch.."/"..file.path)
		if content then
			queue:addFile(path, content, file.version)
		else
			return false
		end
	end
	return true
end

downloadFunctions.pastebin = function(pack, env, queue, info)
	local path = fs.combine(pack.target, info.filename) 

	if string.match(path, "(.-)/[^/]+$") then
		queue:makeDir(string.match(path, "(.-)/[^/]+$"))
	end
	local content = raw("http://pastebin.com/raw.php?i="..info.url)
	if content then
		queue:addFile(path, content)
		return true
	else
		return false
	end
end

downloadFunctions.grin = function(pack, env, queue, info)
	local fullName = pack.repo.."/"..pack.name
	local status
	parallel.waitForAny(function()
		status = env.shell.run("pastebin run VuBNx3va -e -u", info.author, "-r", info.repository, fs.combine(fs.combine(minepackapi.installRoot, pack.target), pack.name))
	end, function()
		while true do
			local e, msg = os.pullEvent("grin_install_status")
			printInformation(msg)
		end
	end)
	return status
end

downloadFunctions.meta = function(pack, env, queue)
	return true
end

local function findInstalledVersionByPath(packName, path)
	for i, file in ipairs(minepackapi.installed[packName].files) do
		if file.path == path then return file.version end
	end
end

local new_fs = {}

local Package = {
	install = function(self, env)
		local queue
		if downloadFunctions[self.download.type.type] then
			queue = newTransactionQueue(self.fullName)
			if not downloadFunctions[self.download.type.type](self, env, queue, self.download.type) then return false end
		else
			return false
		end

		if not queue:finish() then return false end

		--execute startup script, if present.
		if self.setup then
			local queue = newTransactionQueue(self.fullName)
			--packman key included solely for backwards compatibility, usage is deprecated in favor of pack.
			local setupArgs = {}
			for match in string.gmatch(self.setup, "(%S+)") do
				table.insert(setupArgs, match)
			end
			setupArgs[1] = fs.combine(fs.combine(minepackapi.installRoot, self.target), setupArgs[1])
			local envQueue = queue:env()
			if not os.run({shell = env.shell, packman = envQueue, pack = envQueue, fs = new_fs}, unpack(setupArgs)) then
				--setup script threw an error.
				printWarning("Package "..self.fullName.." failed to install, removing")
				return self:remove(env)
			end

			--this must be done a second time to finalize any changes made by the install script.
			return queue:finish()
		end

        if self.man then
            local helph = http.get(self.man)
            if helph then
                local writeh = fs.open(minepackapi.config.helpPath..self.name,"w")
                writeh.write(helph.readAll())
                writeh.close()
                helph.close()
            end
        end

        if minepackapi.config.writeLog == "true" then
            local logh = fs.open(minepackapi.config.minepackDirectory.."/log.txt","a")
            logh.write("Installed "..self.fullName.."\n")
            logh.close()
        end

		return true
	end,
	remove = function(self, env)
		if not minepackapi.installed[self.fullName] then return false end
		local queue = newTransactionQueue(self.fullName, true)

		if self.cleanup then
			local queue = newTransactionQueue(self.fullName, true)
			local cleanupArgs = {}
			for match in string.gmatch(self.cleanup, "(%S+)") do
				table.insert(cleanupArgs, match)
			end
			cleanupArgs[1] = fs.combine(fs.combine(minepackapi.installRoot, self.target), cleanupArgs[1])
			local envQueue = queue:env()
			os.run({shell = env.shell, packman = envQueue, pack = envQueue, fs = new_fs}, unpack(cleanupArgs))
			if not queue:finish() then return false end
		end

		local fileList = minepackapi.installed[self.fullName].files
		for i = #fileList, 1, -1 do
			if fs.exists(fs.combine(minepackapi.installRoot, fileList[i].path)) and fs.isDir(fs.combine(minepackapi.installRoot, fileList[i].path)) then
				queue:removeDir(fileList[i].path)
			else
				queue:removeFile(fileList[i].path)
			end

		end
        
        if fs.exists(minepackapi.config.helpPath..self.name) then
            fs.delete(minepackapi.config.helpPath..self.name)
        end
        
        if minepackapi.config.writeLog == "true" then
            local logh = fs.open(minepackapi.config.minepackDirectory.."/log.txt","a")
            logh.write("Removed "..self.fullName.."\n")
            logh.close()
        end

		return queue:finish()
	end,
	upgrade = function(self, env)
		if not minepackapi.installed[self.fullName] then return false end
		local queue = newTransactionQueue(self.fullName)
        if minepackapi.config.writeLog == "true" then
            local logh = fs.open(minepackapi.config.minepackDirectory.."/log.txt","a")
            logh.write("Updated "..self.fullName.."\n")
            logh.close()
        end
		if updateTypes[self.download.type.type] == "incremental" then
			local updatedFiles = {}
			local contents = lookupFunctions[self.download.type.type](self.download.type)
			for num, file in ipairs(contents) do
				local path = fs.combine(self.target, file.path)
				if file.version ~= findInstalledVersionByPath(self.fullName, path) then
					if string.match(path, "(.-)/[^/]+$") then
						queue:makeDir(string.match(path, "(.-)/[^/]+$"))
					end
					if self.download.type.type == "github" then
						local content = raw("https://raw.github.com/"..self.download.type.author.."/"..self.download.type.repository.."/"..self.download.type.branch.."/"..file.path)
						if content then
							queue:addFile(path, content, file.version)
						else
							return false
						end
					elseif self.download.type.type == "bitbucket" then
						local content = raw("https://bitbucket.org/"..self.download.type.author.."/"..self.download.type.repository.."/raw/"..self.download.type.branch.."/"..file.path)
						if content then
							queue:addFile(path, content, file.version)
						else
							return false
						end
					end
				end
				updatedFiles[path] = true
			end

			for i, fileInfo in ipairs(minepackapi.installed[self.fullName].files) do
				if not updatedFiles[fileInfo.path] and fileInfo.version ~= minepackapi.installed[self.fullName].version then
					if not fs.isDir(fs.combine(minepackapi.installRoot, fileInfo.path)) or (fs.isDir(fs.combine(minepackapi.installRoot, fileInfo.path)) and #(fs.list(fs.combine(minepackapi.installRoot, fileInfo.path))) == 0) then
						queue:removeFile(fileInfo.path)
					end
				end
			end

			
			return queue:finish()
		elseif updateTypes[self.download.type.type] == "overwrite" then
			if not downloadFunctions[self.download.type.type](self, env, queue, self.download.type) then return false end
			return queue:finish()
		elseif updateTypes[self.download.type.type] == "replace" then
			return self:remove(env) and self:install(env)
		end
	end,
}

local pmetatable = {__index = Package}

function new(name, repo)
	local p = {
		name = name,
		repo = repo,
		fullName = repo.."/"..name,
		version = "",
		size = 0,
		category = {},
		dependencies = {},
		--installation folder target
		target = minepackapi.config.defaultTarget,
		setup = nil,
		remove = nil,
        man = nil,
        description = "None",
		download = {}
	}

	setmetatable(p, pmetatable)

	return p
end

function findDependencies(packageName, _dependencyTable)
	local dependencyTable = _dependencyTable or {}
	if minepackapi.list[packageName] then
		dependencyTable[packageName] = true
		for packName in pairs(minepackapi.list[packageName].dependencies) do
			packName = packName:lower()
			if packName ~= "none" and not dependencyTable[packName] then
				dependencyTable, errmsg = minepackapi.findDependencies(packName, dependencyTable)
				if not dependencyTable then return nil, errmsg end
			end
		end
	else
		return nil, packageName
	end
	return dependencyTable
end

if not fs.exists("/usr/bin") then fs.makeDir("/usr/bin") end
--process package list
local function addPacks(file)
    --fs,getName(file).sub(1,-5) doesn't work
    local tmpstr = fs.getName(file)
	local packName = tmpstr:sub(1,-5)
	local state = ""
	local typeState = nil
	local listHandle = io.open(file, "r")
	local entryTable
	local lineCount = 1
	if listHandle then
		for line in listHandle:lines() do
			if state == "type" or state == "help" then
				local allAttributes = true
				for attribute in pairs(downloadTypes[entryTable.download[state].type]) do
					if not entryTable.download[state][attribute] then
						allAttributes = false
						break
					end
				end
				if allAttributes then
					state = "main"
				end
			end
			local property,hasValue,value = string.match(line, "^%s*([^=%s]+)%s*(=?)%s*(.-)%s*$")
			if typeState and property ~= "file" then typeState = nil end
			hasValue=hasValue~="" or nil
			if property == "name" and state == "" then
				if state == "" then
					entryTable = new(string.lower(value), packName)
					entryTable.target = minepackapi.config.defaultTarget
					state = "main"
				else
					if state ~= "dirty" then
						printWarning("Unexpected 'name' at line "..lineCount.." in "..file)
						state = "dirty"
					end
				end
			elseif property == "type" or property == "help" then
				if state == "main" then
					entryTable.download[property] = {type = string.match(value, "^(%S*)$")}
					if downloadFunctions[entryTable.download[property].type] then
						if entryTable.download[property].type == "multi" then
							entryTable.download[property].files = {}
							typeState = property
							state = "main"
						else
							state = property
						end
					else
						if state ~= "dirty" then
							printWarning("Unknown Repository Format at line "..lineCount.." in "..file)
							state = "dirty"
						end
					end
				else
					if state ~= "dirty" then
						printWarning("Unexpected 'type' at line "..lineCount.." in "..file)
						state = "dirty"
					end
				end
			elseif property == "file" then
				if typeState then
					local fileTable = entryTable.download[typeState].files 
					local name, url = string.match(value, "(%S+)%s+(.*)")
					fileTable[#fileTable + 1] = {name = name, url = url}
				else
					printWarning("Unexpected "..property.." at line "..lineCount.." in "..file)
					state = "dirty"
				end
			elseif property == "target" or property == "setup" or property == "update" or property == "cleanup" or property == "version" or property == "size" or property == "man" or property == "description" then
				if state == "main" then
					entryTable[property] = value
				else
					if state ~= "dirty" then
						printWarning("Unexpected "..property.." at line "..lineCount.." in "..file)
						state = "dirty"
					end
				end
			elseif property == "dependencies" or property == "category" then
				if state == "main" then
					for str in string.gmatch(value, "(%S+)") do
						entryTable[property][str] = true
					end
				else
					if state ~= "dirty" then
						printWarning("Unexpected "..property.." at line "..lineCount.." in "..file)
						state = "dirty"
					end
				end
			elseif property == "end" then
				if state == "dirty" then
					state = ""
				elseif state == "type" then
					printWarning("Unexpected end at line "..lineCount.." in "..file)
					state = ""
				elseif state == "main" then
					--this line is the required entries for a valid repolist entry.
					if entryTable.download.type and (#entryTable.version > 0 and (tonumber(entryTable.size) > 0 or entryTable.download.type.type == "meta")) then
						local i
						for name in pairs(entryTable.dependencies) do
							i = true
							break
						end
						if i then
							list[packName.."/"..entryTable.name] = entryTable
							if list[entryTable.name] then
								list[entryTable.name][packName] = entryTable
							else
								list[entryTable.name] = {[packName] = entryTable}
							end
						end
					else
						entryTable = nil
					end
					state = ""
				end
			elseif state == "type" or state == "help" then
				local propertyFound = false
				for prop in pairs(downloadTypes[entryTable.download[state].type]) do
					if property == prop then
						propertyFound = true
						break
					end
				end
				if propertyFound then
					entryTable.download[state][property] = value
				else
					printWarning("Unexpected "..property.." at line "..lineCount.." in "..file)
					state = "dirty"
				end
			end
			lineCount = lineCount + 1
		end
		if state ~= "" then
			printWarning("Expected 'end' at line "..lineCount.." in "..file)
		end
		listHandle:close()
	else
		printError("Could not open repository list!")
	end
end

function load()
	for k, v in pairs(minepackapi.list) do
		minepackapi.list[k] = nil
	end
	if fs.exists(minepackapi.config.minepackDirectory.."/repositories") then
		for _, file in ipairs(fs.list(minepackapi.config.minepackDirectory.."/repositories")) do
			addPacks(minepackapi.config.minepackDirectory.."/repositories/"..file)
		end
	end

	for k, v in pairs(minepackapi.installed) do
		minepackapi.installed[k] = nil
	end
	if fs.exists(fs.combine(minepackapi.installRoot, minepackapi.config.minepackDirectory.."/installed")) and fs.isDir(fs.combine(minepackapi.installRoot, minepackapi.config.minepackDirectory.."/installed")) then
		for _, repo in ipairs(fs.list(fs.combine(minepackapi.installRoot, minepackapi.config.minepackDirectory.."/installed"))) do
			for _, file in ipairs(fs.list(fs.combine(fs.combine(minepackapi.installRoot, minepackapi.config.minepackDirectory.."/installed"), repo))) do
				local name = repo.."/"..file:sub(1,-5)
				local handle = io.open(fs.combine(fs.combine(fs.combine(minepackapi.installRoot, minepackapi.config.minepackDirectory.."/installed"), repo), file), "r")
				if handle then
					installed[name] = {files = {}}
					local packVersion
					for line in handle:lines() do
						if not packVersion then
							packVersion = line
							installed[name].version = packVersion
						else
							local path, version = string.match(line, "([^;]+);(.*)")
							if path and version then
								installed[name].files[#installed[name].files + 1] = {path = path, version = version}
							else
								installed[name].files[#installed[name].files + 1] = {path = line, version = packVersion}
							end
						end
					end
					handle:close()
					if installed[file:sub(1,-5)] then
						installed[file:sub(1,-5)][repo] = installed[name]
					else
						installed[file:sub(1,-5)] = {[repo] = installed[name]}
					end
				else
					printWarning("Couldn't open package db file: "..file)
				end
			end
		end
	end

	for k, v in pairs(new_fs) do
		new_fs[k] = nil
	end
	do
		local root = minepackapi.installRoot
		--override fs api to use installRoot, recreated when loading to accomodate installRoot changes.
		local function fsWrap(name,f,n)
			return function(...)
				local args = { ... }
				for k,v in ipairs(args) do
					if n == nil or k <= n then
						args[k] = fs.combine(root, v)
					end
				end
				return f(unpack(args))
			end
		end
		for k,v in pairs(fs) do
			new_fs[k] = fsWrap(k,v,nil)
		end
		new_fs.open = fsWrap("open",fs.open,1)
		new_fs.combine = fs.combine
		new_fs.getName = fs.getName
		new_fs.getDir = fs.getDir
	end
end
