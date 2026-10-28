-- 設備(ビルドで置いた物)を、再配置できる場合だけ押し出す。ホスト(サーバー)でのみ呼ぶ。
-- 設備は移動の同期(bReplicateMovement)が有効なので、ホストで位置を変えればゲスト側にも反映される。

local C = require("common")

local M = {}

local OBJ_WORLD_STATIC, OBJ_WORLD_DYNAMIC, OBJ_PAWN = 0, 1, 2
-- 重なり判定の箱を、設備の外接箱より水平方向にこれだけ小さくする(cm)。外接箱は見た目より少し大きいため
local SHRINK = 5
-- 判定箱の下端を床からこれだけ上げる(cm)。床の仕上げ材・敷居などの薄いメッシュを壁扱いしないため
local FLOOR_CLEARANCE = 8

-- 床・壁・建具など、押しても動かさないもの(クラス名の部分一致)
local EXCLUDE_PATTERNS = { "Wall", "Floor", "Ceiling", "Stair", "Window", "Entrance", "Door", "Pillar", "Chohan", "Noren", "Sign", "Poster", "Hood" }

local function K() return C.static("/Script/Engine.Default__KismetSystemLibrary") end
local function Validator() return C.static("/Script/RealRamenSimulator.Default__MenBuildPlacementValidator") end

-- 真下の床の高さ(見つからなければ nil)。始点が壁などに埋まっていても床を拾えるよう、
-- 全ヒットのうち上向きの面で最も高いものを床とする
local function floorZ(world, x, y, z, ignore)
    local hits = {}
    K():LineTraceMultiForObjects(world, C.vec(x, y, z + 20), C.vec(x, y, z - 40),
        { OBJ_WORLD_STATIC, OBJ_WORLD_DYNAMIC }, false, ignore, 0, hits, true,
        { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    local best = nil
    for _, h in ipairs(hits) do
        local hit = h.get and h:get() or h
        if not hit.bStartPenetrating and hit.ImpactNormal.Z > 0.7 then
            local hz = hit.ImpactPoint.Z
            if best == nil or hz > best then best = hz end
        end
    end
    return best
end

local function overlapSet(world, center, extent, ignore)
    local out = {}
    K():BoxOverlapActors(world, center, extent, { OBJ_WORLD_STATIC, OBJ_WORLD_DYNAMIC, OBJ_PAWN }, nil, ignore, out)
    local set, list = {}, {}
    for _, a in ipairs(out) do
        local actor = a.get and a:get() or a
        if C.valid(actor) then
            local k = C.key(actor)
            if not set[k] then set[k] = actor; list[#list + 1] = actor end
        end
    end
    return set, list
end

local function aabbIntersects(o1, e1, o2, e2)
    return math.abs(o1.X - o2.X) <= e1.X + e2.X and math.abs(o1.Y - o2.Y) <= e1.Y + e2.Y and math.abs(o1.Z - o2.Z) <= e1.Z + e2.Z
end

-- 押してよい設備か(動かせるかの判定とは別。対象外なら理由を返す)
function M.eligible(b)
    local cn = C.className(b)
    for _, p in ipairs(EXCLUDE_PATTERNS) do
        if cn:find(p, 1, true) then return false, "対象外の種類" end
    end
    local ok, id = pcall(function() return b.ItemId.TagName:ToString() end)
    if not ok or id == "None" or id == "" then return false, "アイテムIDなし" end
    if b:IsRelocateReserved() then return false, "移動中" end
    local root = b.RootComponent
    if C.valid(root) and C.valid(root:GetAttachParent()) then return false, "他の物に付いている" end
    return true
end

-- 床に置かれている設備か(壁・天井に付いている物は false)。
-- 天井の照明は天井板の上面を「床」として拾ってしまうので、形が置き場所より下へ垂れ下がっていないことも確かめる
function M.isFloorStanding(b)
    local l = b:K2_GetActorLocation()
    local fz = floorZ(b, l.X, l.Y, l.Z, { b })
    if fz == nil or math.abs(fz - l.Z) > 10 then return false, fz end
    local o, e = C.bounds(b, true)
    if o.Z - e.Z < l.Z - 8 then return false, fz end
    return true, fz
end

-- b の上に載っている物(アイテムと、床置きでない設備)
local function findRiders(b, o, e, candidates)
    local riders = {}
    local bottom = o.Z - e.Z
    for _, c in ipairs(candidates) do
        local a = c.actor
        if C.valid(a) and C.key(a) ~= C.key(b) then
            local ok, l = pcall(function() return a:K2_GetActorLocation() end)
            if ok and math.abs(l.X - o.X) <= e.X and math.abs(l.Y - o.Y) <= e.Y and l.Z > bottom + 15 and l.Z < o.Z + e.Z + 40 then
                local ride = false
                if c.isItem then
                    local root = a.RootComponent
                    ride = C.valid(root) and not C.valid(root:GetAttachParent())
                elseif c.isBuild then
                    -- 台の上のモニターなど(床から 15cm 以上高い位置に置かれている設備)
                    local root = a.RootComponent
                    ride = C.valid(root) and not C.valid(root:GetAttachParent())
                end
                if ride then riders[#riders + 1] = { actor = a, start = l } end
            end
        end
    end
    return riders
end

-- 移動先 D で置けるか。置けないときは理由を返す
local function canPlaceAt(ctx, dx, dy)
    local o, e, L = ctx.o, ctx.e, ctx.L
    local world = ctx.b
    -- 他の物と重ならないか(移動前から接していた物は除く)
    local zBottom = o.Z - e.Z + FLOOR_CLEARANCE
    local zTop = o.Z + e.Z - 1
    local center = C.vec(o.X + dx, o.Y + dy, (zBottom + zTop) / 2)
    local extent = C.vec(math.max(e.X - SHRINK, 1), math.max(e.Y - SHRINK, 1), math.max((zTop - zBottom) / 2, 1))
    local _, list = overlapSet(world, center, extent, ctx.ignore)
    for _, a in ipairs(list) do
        local k = C.key(a)
        if not ctx.ignoreSet[k] and not C.isA(a, C.cls("MenItemActorBase")) then
            -- 隣の設備・人は、移動前から接していたなら許す。壁などの固定物は常にぶつかる扱い
            local movable = C.isA(a, C.cls("MenBuildableActor")) or C.isA(a, C.engineCls("Pawn"))
            if not (movable and ctx.srcOverlap[k]) then
                return false, "ぶつかる: " .. C.className(a)
            end
        end
    end
    -- 建築できる範囲の中か(元の位置が範囲内のときだけ確認する)
    if ctx.srcInside then
        local V = Validator()
        local pts = { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
        for _, p in ipairs(pts) do
            local x = o.X + dx + p[1] * math.max(e.X - 5, 0)
            local y = o.Y + dy + p[2] * math.max(e.Y - 5, 0)
            if not V:IsLocationInsideAllowedArea(world, 0, C.vec(x, y, L.Z)) then return false, "建築できる範囲の外" end
        end
    end
    -- 床が同じ高さで続いているか
    local pts = { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
    for _, p in ipairs(pts) do
        local x = o.X + dx + p[1] * math.max(e.X - 10, 0)
        local y = o.Y + dy + p[2] * math.max(e.Y - 10, 0)
        local fz = floorZ(world, x, y, ctx.floorZ, ctx.ignore)
        if fz == nil or math.abs(fz - ctx.floorZ) > 4 then return false, "床がない・段差" end
    end
    -- 建築禁止の範囲
    local dO = C.vec(o.X + dx, o.Y + dy, o.Z)
    for _, v in ipairs(ctx.forbidden) do
        if C.valid(v) then
            local vo, ve = C.bounds(v, false)
            if aabbIntersects(dO, e, vo, ve) then return false, "建築禁止の範囲" end
        end
    end
    return true
end

local function slide(b, riders, L, dx, dy, onDone)
    local steps, i = 8, 0
    LoopAsync(25, function()
        i = i + 1
        local step = i
        ExecuteInGameThread(function()
            if not C.valid(b) then return end
            local t = step / steps
            local k = 1 - (1 - t) * (1 - t)  -- だんだん遅く
            b:K2_SetActorLocation(C.vec(L.X + dx * k, L.Y + dy * k, L.Z), false, {}, true)
            for _, r in ipairs(riders) do
                if C.valid(r.actor) then
                    r.actor:K2_SetActorLocation(C.vec(r.start.X + dx * k, r.start.Y + dy * k, r.start.Z), false, {}, true)
                end
            end
            if step == steps and onDone then onDone() end
        end)
        return i >= steps
    end)
end

-- 移動先の判定に使う情報をまとめる(動かせない設備なら nil と理由)
function M.prepare(b, candidates, attacker)
    local ok, why = M.eligible(b)
    if not ok then return nil, why end
    local standing, fz = M.isFloorStanding(b)
    if not standing then return nil, "床に置かれていない" end

    local L = b:K2_GetActorLocation()
    local o, e = C.bounds(b, true)
    local riders = findRiders(b, o, e, candidates)
    local ignore = { b }
    local ignoreSet = { [C.key(b)] = true }
    for _, r in ipairs(riders) do ignore[#ignore + 1] = r.actor; ignoreSet[C.key(r.actor)] = true end
    if C.valid(attacker) then ignore[#ignore + 1] = attacker; ignoreSet[C.key(attacker)] = true end

    local zBottom = o.Z - e.Z + FLOOR_CLEARANCE
    local zTop = o.Z + e.Z - 1
    local srcOverlap = overlapSet(b, C.vec(o.X, o.Y, (zBottom + zTop) / 2),
        C.vec(math.max(e.X - SHRINK, 1), math.max(e.Y - SHRINK, 1), math.max((zTop - zBottom) / 2, 1)), ignore)

    local ctx = {
        b = b, L = L, o = o, e = e, floorZ = fz, ignore = ignore, ignoreSet = ignoreSet, srcOverlap = srcOverlap,
        srcInside = Validator():IsLocationInsideAllowedArea(b, 0, C.vec(L.X, L.Y, L.Z)),
        forbidden = C.findAll("MenBuildForbiddenVolume"),
        riders = riders,
    }
    return ctx
end

M.canPlaceAt = canPlaceAt

-- dirX, dirY: 水平の単位ベクトル。distance: 動かしたい距離。candidates: 周囲の物の一覧(載っている物を探すのに使う)
-- 戻り値: 動かした距離と載っていた物の数(動かせなければ nil と理由)
function M.push(b, dirX, dirY, distance, minDistance, candidates, attacker)
    local ctx, why = M.prepare(b, candidates, attacker)
    if not ctx then return nil, why end
    local d = distance
    local lastReason = nil
    while d >= minDistance - 0.01 do
        local can, reason = canPlaceAt(ctx, dirX * d, dirY * d)
        if can then
            slide(b, ctx.riders, ctx.L, dirX * d, dirY * d)
            return d, #ctx.riders
        end
        lastReason = reason
        d = d - math.max(minDistance / 2, 10)
    end
    return nil, lastReason or "動かせない"
end

return M
