shell.setPath(shell.path()..":/usr/bin")
help.setPath(help.path()..":/usr/help")

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
local tMinepack = {"install","remove","update","fetch","list","search","info","file","log","help","version"}
local function completeMinepack( shell, nIndex, sText, tPreviousText )
    if nIndex == 1 then
        return completeMultipleChoice( sText, tMinepack, true, true )
    end
end
shell.setCompletionFunction( "usr/bin/minepack.lua", completeMinepack )
