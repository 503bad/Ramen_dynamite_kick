-- 共通の小物
local M = {}

M.PUNCH = "Men.Emote.Action.Punch"
M.KICK = "Men.Emote.Action.Kick"

function M.valid(o)
    if o == nil then return false end
    local ok, r = pcall(function() return o:IsValid() end)
    return ok and r == true
end

function M.isDefault(o)
    local ok, n = pcall(function() return o:GetFullName() end)
    return (not ok) or n:find("Default__", 1, true) ~= nil
end

-- FindAllOf の結果から CDO と無効なものを除く
function M.findAll(className)
    local res = {}
    for _, o in ipairs(FindAllOf(className) or {}) do
        if M.valid(o) and not M.isDefault(o) then res[#res + 1] = o end
    end
    return res
end

local cache = {}
function M.static(path)
    local o = cache[path]
    if M.valid(o) then return o end
    o = StaticFindObject(path)
    if M.valid(o) then cache[path] = o; return o end
    return nil
end

function M.cls(name) return M.static("/Script/RealRamenSimulator." .. name) end
function M.engineCls(name) return M.static("/Script/Engine." .. name) end

function M.isA(o, cls)
    if not cls then return false end
    local ok, r = pcall(function() return o:IsA(cls) end)
    return ok and r == true
end

function M.className(o)
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or "?"
end

function M.key(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    if ok and a then return a end
    return tostring(o)
end

function M.tag(name) return { TagName = FName(name) } end

function M.vec(x, y, z) return { X = x, Y = y, Z = z } end

function M.bounds(actor, onlyColliding)
    local o, e = {}, {}
    actor:GetActorBounds(onlyColliding ~= false, o, e, false)
    return o, e
end

return M
