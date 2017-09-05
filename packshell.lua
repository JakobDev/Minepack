shell.setPath(shell.path()..":/usr/bin")
help.setPath(help.path()..":/usr/help")

os.loadAPI("/usr/apis/minepackapi")
minepackapi.load()

local function completeMultipleChoice( sText, tOptions, bAddSpaces )
    local tResults = {}
    for n=1,#tOptions do
        local sOption = tOptions[n]
        if #sOption + (bAddSpaces and 1 or 0) > #sText and string.sub( sOption, 1, #sText ) == sText then
            local sResult = string.sub( sOption, #sText + 1 )
            if bAddSpaces then
                table.insert( tResults, sResult .. " " )
            else
                table.insert( tResults, sResult )
            end
        end
    end
    return tResults
end
local tMinepack = {"install","remove","update","fetch","list","download","search","info","file","log","help","version"}
local tSearch = {}
for k,v in pairs(minepackapi.list) do
    table.insert(tSearch,k)
end
local tList = {}
for k,v in pairs(minepackapi.installed) do
    table.insert(tList,k)
end
local function completeMinepack( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, tMinepack, true, true )
    elseif nIndex == 2 then
        if tPreviousText[2] == "install" or tPreviousText[2] == "info" or tPreviousText[2] == "download" then
            return completeMultipleChoice( sText, tSearch, true, true )
        elseif tPreviousText[2] == "remove" then
            return completeMultipleChoice( sText, tList, true, true )
        elseif tPreviousText[2] == "fetch" then
            return completeMultipleChoice( sText, {"update"}, true, true )
        end
    end
end
shell.setCompletionFunction( "usr/bin/minepack.lua", completeMinepack )
