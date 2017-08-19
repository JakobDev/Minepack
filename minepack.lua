os.loadAPI("/usr/apis/minepackapi")

minepackapi.loadConfig("/etc/minepack/config.conf",[[
#Warning: If you edit the Path, you might have Problems 
#with removing a Package. Plese move all files to the
#new location, if you edit the Path.
#
#Set the default target
defaultTarget=/usr/bin
#Set the Path for Help Files
helpPath=/usr/help/
#Write a Log
writeLog=true
#Select the Directory, in which minepack should
#place his files
minepackDirectory=/var/minepack
]])

if not fs.exists("/etc/minepack/sources.list") then
local writeh = fs.open("/etc/minepack/sources.list","w")
writeh.write([[
#There are two types list and repo
#List is a List with Repos. For a exmaple look at 
#Syntax: list <url>
#https://raw.githubusercontent.com/lyqyd/cc-packman/master/repolist
#repo is just a single repo file
#Syntax repo <name>;<url>
#Example:
#repo wilma456;https://raw.githubusercontent.com/Wilma456/Computercraft/master/packlist
list https://raw.githubusercontent.com/lyqyd/cc-packman/master/repolist]])
writeh.close()
end

local function downloadFile(sUrl,sFile)
    local fileh = http.get(sUrl)
    if fileh == nil then
        return false
    end
    local writefi = fs.open(sFile,"w")
    writefi.write(fileh.readAll())
    writefi.close()
    fileh.close()
    return true
end

local function getPackageName(sName)
sName = sName:lower()
if minepackapi.list[sName] == nil then
    printError("Package not found")
    error()
end
local sPack = minepackapi.list[sName]["fullName"]
if sPack == nil then
    for k,v in pairs(minepackapi.list[sName]) do
        sPack = v.fullName
    end
end
return sPack
end

local function install(sName,bForce)
if sName ==nil then
    printError("Usage: minepack install <package>")
    return
end
minepackapi.load()
local sPack = getPackageName(sName)
if minepackapi.installed[sPack] and not bForce then
    print("Package "..sPack.." is already installed")
    return
end
for k,v in pairs(minepackapi.findDependencies(sPack)) do
    print("Install "..k)
    minepackapi.list[k]:install(getfenv())
end
end

local function remove(sName)
if sName ==nil then
    printError("Usage: minepack remove <package>")
    return
end
minepackapi.load()
local sPack = getPackageName(sName)
if not minepackapi.installed[sPack] then
    print("Package "..sPack.." is not installed")
    return
end
print("Remove "..sPack)
minepackapi.list[sPack]:remove(getfenv())
end

local function update()
local tUpdate = {}
minepackapi.load()
write("The following packages will be updated: ")
for k,v in pairs(minepackapi.installed) do
    if k:find("/") ~= nil then
        if minepackapi.installed[k]["version"] ~= minepackapi.list[k]["version"] then
            write(k.." ")
            table.insert(tUpdate,k)
        end
    end
end
write("\n")
if #tUpdate == 0 then
    print("None")
else
    print("Continue? (Y/n)")
    while true do
        local ev,me = os.pullEvent("key")
        if me == keys.y or me == keys.enter then
            break
        elseif me == keys.n then
            return
        end
    end
end
for k,v in ipairs(tUpdate) do
    print("Updating "..v)
    minepackapi.list[v]:upgrade()
end
end

local function fetchList(sRepo)
local repolist = http.get(sRepo)
while true do
    local linecon = repolist.readLine()
    if linecon == nil then
        break
    else
        local sName, sUrl = linecon:match("([^ ]+) ([^ ]+)")
        print("Fetch "..sName)
        if downloadFile(sUrl,minepackapi.config.minepackDirectory.."/repositories/"..sName..".txt") == false then
            printError("Could not fetch package "..sName)
        end
    end
end
repolist:close()
end

local function fetch()
local readh = io.open("/etc/minepack/sources.list","r")
for linecon in readh:lines() do
    if linecon:find("#") ~= 1 then
        local sHead, sBody = linecon:match("([^ ]+) ([^ ]+)")
        if sHead == "list" then
            fetchList(sBody)
        elseif sHead == "repo" then
            local sName, sUrl = sBody:match("([^;]+);([^;]+)")
            print("Fetch "..sName)
            print(sUrl)
            if downloadFile(sUrl,minepackapi.config.minepackDirectory.."/repositories/"..sName..".txt") == false then
                printError("Could not fetch package "..sName)
            end
        else
            print("Unknown type in /etc/sources")
        end
    end
end
readh:close()
end

local function list()
minepackapi.load()
for k,v in pairs(minepackapi.installed) do
    if k:find("/") ~= nil then
        print(k)
    end
end
end

local function search()
minepackapi.load()
for k,v in pairs(minepackapi.list) do
    if k:find("/") ~= nil then
        print(k)
    end
end
end

local function info(sName)
    if sName == nil then
       printError("minepack info <package>")
       return
    end
    minepackapi.load()
    local name = getPackageName(sName)
    local info = minepackapi.list[name]
    print("Name: "..info.name)
    print("Repository: "..info.repo)
    io.write("Category: ")
    for cate,_ in pairs(info.category) do
        io.write(cate.." ")
    end
    print()
    print("Version: "..info.version)
    print("Size: "..info.size.." Bytes")
    print("Target: "..info.target)
    print("Filename: "..info.download.type.filename)
    io.write("Dependecies: ")
    local testdep = false
    info.dependencies[name] = nil
    for dep,_ in pairs(info.dependencies) do
        io.write(dep.." ")
        testdep = true
    end
    if testdep == false then
        io.write("None")
    end
    print()
    print("Description: "..info.description)
end

local function file(sName)
    if sName == nil then
       printError("Usage: minepack file <file>")
       return
    end
    if sName:find("/") == 1 then
        sName = sName:sub(2)
    end
    minepackapi.load()
    for k,v in pairs(minepackapi.list) do
        if k:find("/") ~= nil then
            if type(v.target) == "string" and type(v.download.type.filename) == "string" then
                if fs.combine(v.target,v.download.type.filename):find(sName) ~= nil then
                    print(k)
                end
                --print(fs.combine(v.target,v.download.type.filename))
            end
        end
    end
end

local function log()
    if not fs.exists(minepackapi.config.minepackDirectory.."/log.txt") then
        print("No log available")
        return
    end
    local w,h = term.getSize()
    local file = io.open( minepackapi.config.minepackDirectory.."/log.txt" )
    local nLinesPrinted = 0
    local sLine = file:read()
    local nLines = 0
    while sLine do
        nLines = nLines + textutils.pagedPrint( sLine, (h-3) - nLines )
        sLine = file:read()
    end
    file:close()
end

local function help()
print([[
minepack install <package>
minepack remove <package>
minepack update
minepack fetch
minepack fetch update
minepack list
minepack search
minepack info <package>
minepack file <file>
minepack log
minepack help
minepack version]])
end

local tArgs = {...}

if tArgs[1] == "install" then
    install(tArgs[2])
elseif tArgs[1] == "remove" then
    remove(tArgs[2])
elseif tArgs[1] == "update" then
    update()
elseif tArgs[1] == "fetch" and tArgs[2] == "update" then
    fetch("https://raw.githubusercontent.com/lyqyd/cc-packman/master/repolist")
    update()
elseif tArgs[1] == "fetch" then
    fetch("https://raw.githubusercontent.com/lyqyd/cc-packman/master/repolist")
elseif tArgs[1] == "list" then
    list()
elseif tArgs[1] == "search" then
    search()
elseif tArgs[1] == "info" then
    info(tArgs[2])
elseif tArgs[1] == "file" then
    file(tArgs[2])
elseif tArgs[1] == "log" then
    log()
elseif tArgs[1] == "help" then
    help()
elseif tArgs[1] == "version" then
    print("Version 1.1")
else
    print("Unknown Command. Please run minepack help for a list of Commands")
end
