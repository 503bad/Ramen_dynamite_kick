-- パンチ/キックの当たり処理。ホスト(サーバー)でだけ動く。
-- 全プレイヤーのエモート再生状態(ReplicatedPlayback)を見張るので、MOD を入れていないゲストが
-- ゲーム標準のエモートメニューから出したパンチ/キックにも効く。
-- 結果(アイテムの物理・設備の位置・火災・爆発)はゲーム本来の同期に乗って全員に反映される。

local C = require("common")
local BuildMove = require("buildmove")

local M = {}

local cfg, log
local pawns, pawnsRefreshedAt = {}, -1e9
local lastSerial = {}
local attacks = {}
local windowCache = {}

-- 当たり判定の箱(攻撃者の向きの座標系。f = 前方、r = 横、h = 足元からの高さ。cm)
local VOLUME = {
    [C.PUNCH] = { f0 = 25, f1 = 115, r = 40, h0 = 75, h1 = 165 },
    [C.KICK]  = { f0 = 25, f1 = 145, r = 45, h0 = 0,  h1 = 155 },
}
-- モンタージュから読めなかったときの攻撃判定の時間帯(秒。AM_Men_037_Punch / AM_Men_047_Kick の値)
local DEFAULT_WINDOW = {
    [C.PUNCH] = { 0.672, 0.830 },
    [C.KICK]  = { 0.959, 1.341 },
}

local function attackWindow(ec, tag)
    local m = ec.ActiveMontage
    if C.valid(m) then
        local name = m:GetFullName()
        local w = windowCache[name]
        if w == nil then
            w = false
            pcall(function()
                m.Notifies:ForEach(function(_, e)
                    local n = e:get()
                    if n.NotifyName:ToString() == "MenEmoteAttackWindow" then
                        w = { n.LinkValue, n.LinkValue + n.Duration }
                    end
                end)
            end)
            windowCache[name] = w
        end
        if w then return w end
    end
    return DEFAULT_WINDOW[tag]
end

local function refreshPawns(now)
    if now - pawnsRefreshedAt < 2 then return end
    pawnsRefreshedAt = now
    pawns = C.findAll("MenPlayerCharacter")
end

local function frame(pawn)
    local l = pawn:K2_GetActorLocation()
    local f = pawn:GetActorForwardVector()
    local len = math.sqrt(f.X * f.X + f.Y * f.Y)
    if len < 1e-3 then len = 1 end
    local fx, fy = f.X / len, f.Y / len
    local half = 90
    pcall(function() half = pawn.RootComponent:GetScaledCapsuleHalfHeight() end)
    -- UE は左手系: 右 = (-fy, fx)
    return { x = l.X, y = l.Y, feet = l.Z - half, fx = fx, fy = fy, rx = -fy, ry = fx }
end

-- 対象の AABB が攻撃の箱と重なるか。重なれば「狙いからの遠さ」(前方の距離 + 横のずれ×2)を返す
local function inVolume(fr, vol, o, e)
    local dx, dy = o.X - fr.x, o.Y - fr.y
    local cf = dx * fr.fx + dy * fr.fy
    local cr = dx * fr.rx + dy * fr.ry
    local hf = math.abs(e.X * fr.fx) + math.abs(e.Y * fr.fy)
    local hr = math.abs(e.X * fr.rx) + math.abs(e.Y * fr.ry)
    local h = o.Z - fr.feet
    if cf + hf < vol.f0 or cf - hf > vol.f1 then return nil end
    if math.abs(cr) - hr > vol.r then return nil end
    if h + e.Z < vol.h0 or h - e.Z > vol.h1 then return nil end
    return math.max(cf, 0) + math.abs(cr) * 2
end

local function gatherCandidates(pawn)
    local fr = frame(pawn)
    local list = {}
    local function add(className, kind)
        for _, a in ipairs(C.findAll(className)) do
            local ok, l = pcall(function() return a:K2_GetActorLocation() end)
            if ok then
                local dx, dy = l.X - fr.x, l.Y - fr.y
                if dx * dx + dy * dy < 350 * 350 then
                    list[#list + 1] = { actor = a, isItem = kind == "item", isBuild = kind == "build",
                        isGas = kind == "item" and C.isA(a, C.cls("MenGasCylinderActor")) }
                end
            end
        end
    end
    add("MenItemActorBase", "item")
    add("MenBuildableActor", "build")
    return list
end

local function playHitSound(atk, loc)
    if atk.soundPlayed then return end
    atk.soundPlayed = true
    pcall(function() atk.ec:MulticastAttackHitSound(loc) end)
end

local function hitItem(atk, c, fr)
    local a = c.actor
    local base = a.CarryPhysicsBaseState
    if base == 1 then return end  -- 誰かが持っている
    local loc = a:K2_GetActorLocation()

    if c.isGas and atk.tag == C.KICK and cfg.enable_gas_explosion == 1 then
        if not a:HasExploded() then
            a:Explode()
            log("キックでガスボンベが爆発")
            playHitSound(atk, loc)
        end
        return
    end
    if cfg.enable_items ~= 1 then return end
    local root = a.RootComponent
    if not C.valid(root) then return end
    if C.valid(root:GetAttachParent()) then return end            -- 重ねた食器など、他の物に付いている
    if base == 4 or base == 5 or base == 6 or base == 7 then return end  -- シンク・まな板・設備の中・盛り付け
    if a:IsCarryPickupLocked() then return end                      -- 客が使っている等
    if not root:IsSimulatingPhysics(FName("None")) then return end

    -- 正面を主に、攻撃者から見た方向を少し混ぜる
    local dx, dy = loc.X - fr.x, loc.Y - fr.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 1e-3 then dx, dy = dx / d, dy / d else dx, dy = fr.fx, fr.fy end
    local vx, vy = fr.fx * 0.75 + dx * 0.25, fr.fy * 0.75 + dy * 0.25
    local vl = math.sqrt(vx * vx + vy * vy)
    vx, vy = vx / vl, vy / vl
    local speed = atk.tag == C.KICK and cfg.kick_item_speed or cfg.punch_item_speed
    root:WakeAllRigidBodies()
    root:AddImpulse(C.vec(vx * speed, vy * speed, speed * cfg.upward_ratio), FName("None"), true)
    local spin = cfg.item_spin_degrees
    pcall(function() root:AddAngularImpulseInDegrees(C.vec(fr.rx * spin, fr.ry * spin, 0), FName("None"), true) end)
    playHitSound(atk, loc)
    atk.itemCount = (atk.itemCount or 0) + 1
end

local function hitBuildable(atk, c, fr)
    local b = c.actor
    local name = C.className(b)
    local flam = b.FlammableComponent
    local flammable = false
    pcall(function() flammable = C.valid(flam) and flam:IsFlammableEnabled() end)
    if flammable then
        -- コンロなど火元になる設備は吹き飛ばずに出火する
        if cfg.enable_fire == 1 and not flam:IsBurning() then
            flam:Ignite()
            playHitSound(atk, b:K2_GetActorLocation())
            log(name .. " から出火")
        end
        return
    end
    if cfg.enable_buildables ~= 1 then return end
    local dist = atk.tag == C.KICK and cfg.kick_build_distance or cfg.punch_build_distance
    local moved, info = BuildMove.push(b, fr.fx, fr.fy, dist, cfg.build_min_distance, atk.cands, atk.pawn)
    if moved then
        playHitSound(atk, b:K2_GetActorLocation())
        log(string.format("%s を %.0fcm 動かしました(載っている物 %d 個)", name, moved, info))
    elseif cfg.log_hits == 1 then
        log(name .. " は動かせません: " .. tostring(info))
    end
end

local function processHits(atk)
    local fr = frame(atk.pawn)
    local vol = VOLUME[atk.tag]
    if not atk.cands then atk.cands = gatherCandidates(atk.pawn) end
    local bestBuild, bestF = nil, nil
    for _, c in ipairs(atk.cands) do
        local k = C.key(c.actor)
        if not atk.hit[k] and C.valid(c.actor) then
            local ok, o, e = pcall(C.bounds, c.actor, true)
            if ok then
                local f = inVolume(fr, vol, o, e)
                if f then
                    if c.isItem then
                        atk.hit[k] = true
                        local ok2, err = pcall(hitItem, atk, c, fr)
                        if not ok2 then log("アイテムの処理でエラー: " .. tostring(err)) end
                    elseif c.isBuild and not atk.buildDone then
                        if not bestF or f < bestF then bestBuild, bestF = c, f end
                    end
                end
            end
        end
    end
    -- 設備は 1 回の攻撃で 1 つ(いちばん真正面の手前)だけ
    if bestBuild then
        atk.buildDone = true
        atk.hit[C.key(bestBuild.actor)] = true
        local ok, err = pcall(hitBuildable, atk, bestBuild, fr)
        if not ok then log("設備の処理でエラー: " .. tostring(err)) end
    end
end

local function tick()
    local anyPawn = nil
    for _, p in ipairs(pawns) do if C.valid(p) then anyPawn = p; break end end
    local world = anyPawn and anyPawn:GetWorld()
    local gs = C.valid(world) and world.GameState or nil
    local nowReal = os.clock()
    refreshPawns(nowReal)
    if not C.valid(gs) then return end
    if not gs:HasAuthority() then return end  -- ゲストでは何もしない(ホストが処理する)
    local now = gs:GetServerWorldTimeSeconds()

    for _, pawn in ipairs(pawns) do
        if C.valid(pawn) then
            local ec = pawn.EmoteComponent
            if C.valid(ec) then
                local k = C.key(pawn)
                local rp = ec.ReplicatedPlayback
                local serial = rp.Serial
                if lastSerial[k] == nil then
                    lastSerial[k] = serial
                elseif lastSerial[k] ~= serial then
                    lastSerial[k] = serial
                    local tag = rp.EmoteTag.TagName:ToString()
                    if VOLUME[tag] then
                        attacks[k] = { pawn = pawn, ec = ec, tag = tag, serial = serial, start = rp.ServerStartTimeSeconds, hit = {} }
                    else
                        attacks[k] = nil
                    end
                end
            end
        end
    end

    for k, atk in pairs(attacks) do
        if not C.valid(atk.pawn) or not C.valid(atk.ec) or atk.ec.ReplicatedPlayback.Serial ~= atk.serial then
            attacks[k] = nil
        else
            local w = atk.window or attackWindow(atk.ec, atk.tag)
            atk.window = w
            local t = now - atk.start
            if t > w[2] + 0.05 then
                if cfg.log_hits == 1 and (atk.itemCount or 0) > 0 then
                    log(string.format("%s でアイテム %d 個を飛ばしました", atk.tag == C.KICK and "キック" or "パンチ", atk.itemCount))
                end
                attacks[k] = nil
            elseif t >= w[1] then
                local ok, err = pcall(processHits, atk)
                if not ok then log("当たり処理でエラー: " .. tostring(err)); attacks[k] = nil end
            end
        end
    end
end

function M.init(config, logger)
    cfg, log = config, logger
end

M.tick = tick

-- 開発用: 内部状態の要約
function M.debugState()
    local n = 0
    for _ in pairs(attacks) do n = n + 1 end
    local s = {}
    for k, v in pairs(lastSerial) do s[#s + 1] = tostring(k) .. "=" .. tostring(v) end
    return string.format("pawns=%d attacks=%d serials={%s} refreshedAt=%.1f now=%.1f", #pawns, n, table.concat(s, ","), pawnsRefreshedAt, os.clock())
end

function M.start(config, logger)
    M.init(config, logger)
    -- ゲームスレッドへの依頼が終わるまで次を出さない。ただし依頼が捨てられた場合(マップ移動時など)に
    -- 止まったままにならないよう、1 秒たったら出し直す
    local busySince = nil
    LoopAsync(33, function()
        local now = os.clock()
        if busySince and now - busySince < 1.0 then return false end
        busySince = now
        ExecuteInGameThread(function()
            -- 開発時の再読み込みに備えて、毎回 package.loaded から最新のモジュールを引く
            local mod = package.loaded["combat"] or M
            local ok, err = pcall(mod.tick)
            if not ok then log("tick でエラー: " .. tostring(err)) end
            busySince = nil
        end)
        return false
    end)
end

return M
