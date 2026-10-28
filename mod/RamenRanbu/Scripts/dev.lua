-- 開発用: Mods\RamenRanbu\dev\cmd.lua に書いた Lua をゲームスレッドで実行し、結果を dev\out.txt と UE4SS.log に出す。
-- dev フォルダが無ければ何もしない(配布物には dev フォルダを含めない)。

local M = {}

function M.start(modDir, util)
    local devDir = modDir .. "dev\\"
    local probe = io.open(devDir .. "enabled", "r")
    if not probe then return end
    probe:close()
    util.log("開発用コマンド受付を開始: " .. devDir .. "cmd.lua")

    local function writeOut(text)
        local f = io.open(devDir .. "out.txt", "a")
        if f then f:write(text .. "\n"); f:close() end
    end

    _G.out = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        local s = table.concat(parts, " ")
        writeOut(s)
    end

    LoopAsync(300, function()
        local f = io.open(devDir .. "cmd.lua", "r")
        if not f then return false end
        local src = f:read("a")
        f:close()
        os.remove(devDir .. "cmd.lua")
        ExecuteInGameThread(function()
            writeOut("---- " .. os.date("%H:%M:%S"))
            local chunk, err = load(src, "cmd", "t", _G)
            if not chunk then writeOut("compile error: " .. tostring(err)); writeOut("---- end"); return end
            local ok, e = xpcall(chunk, debug.traceback)
            if not ok then writeOut("error: " .. tostring(e)) end
            writeOut("---- end")
        end)
        return false
    end)
end

return M
