-- キーでパンチ/キックのエモートを出す(自分のキャラクターのみ)。
-- エモートの再生はゲーム本来の RequestPlayEmote を使うので、相手が MOD を入れていなくても動きは見える。

local C = require("common")

local M = {}
local cfg, log
local localPC = nil
local textWidgets, textWidgetsAt = {}, -1e9

local function getLocalPC()
    if C.valid(localPC) then return localPC end
    localPC = nil
    for _, pc in ipairs(C.findAll("PlayerController")) do
        local ok, isLocal = pcall(function() return pc:IsLocalPlayerController() end)
        if ok and isLocal then localPC = pc; break end
    end
    return localPC
end

-- チャットなどの文字入力欄にフォーカスがあるか
local function isTyping()
    local now = os.clock()
    if now - textWidgetsAt > 3 then
        textWidgetsAt = now
        textWidgets = {}
        for _, cn in ipairs({ "EditableText", "EditableTextBox", "MultiLineEditableText", "MultiLineEditableTextBox" }) do
            for _, w in ipairs(C.findAll(cn)) do textWidgets[#textWidgets + 1] = w end
        end
    end
    for _, w in ipairs(textWidgets) do
        local ok, f = pcall(function() return w:HasKeyboardFocus() end)
        if ok and f then return true end
    end
    return false
end

local function isBuildMode(pc, pawn)
    for _, owner in ipairs({ pawn, pc }) do
        local ok, active = pcall(function()
            local bm = owner.BuildModeComponent
            return C.valid(bm) and bm:IsBuildModeActive()
        end)
        if ok and active then return true end
    end
    return false
end

-- pawn が持っているコンポーネントを探す(pawn ごとに覚えておく)
local compCache = {}
local function ownedComponent(pawn, className)
    local k = className .. ":" .. C.key(pawn)
    local c = compCache[k]
    if C.valid(c) then return c end
    compCache[k] = nil
    local pk = C.key(pawn)
    for _, comp in ipairs(C.findAll(className)) do
        local owner = comp:GetOwner()
        if C.valid(owner) and C.key(owner) == pk then compCache[k] = comp; return comp end
    end
    return nil
end

-- 何かを注視している(調べる・使うの表示が出ている)か、物を持っているか。
-- 右クリックはゲームのサブ操作・投げなどにも使われるので、そのときは邪魔をしない
local function isBusyWithInteraction(pawn)
    local ic = ownedComponent(pawn, "MenInteractionComponent")
    if ic then
        local ok, t = pcall(function() return ic:GetCurrentTarget() end)
        if ok and C.valid(t) then return true end
    end
    local cc = ownedComponent(pawn, "MenCarryComponent")
    if cc then
        local ok, held = pcall(function() return cc:HasHeldActor() end)
        if ok and held then return true end
    end
    return false
end

-- 1 回のマウスのクリックで 2 回呼ばれることがあるので、続けて来た同じ入力は無視する
local lastPressed = {}

local function play(tagName, requireNoFocus)
    local now = os.clock()
    if lastPressed[tagName] and now - lastPressed[tagName] < 0.3 then return end
    lastPressed[tagName] = now
    local pc = getLocalPC()
    if not pc then return end
    local pawn = pc.Pawn
    if not C.valid(pawn) then return end
    local ec = pawn.EmoteComponent
    if not C.valid(ec) then return end
    if pc.bShowMouseCursor then return end        -- メニューやUIを開いている
    if isTyping() then return end
    if isBuildMode(pc, pawn) then return end
    if requireNoFocus and isBusyWithInteraction(pawn) then return end
    if ec:IsPlayingEmote() then
        local cur = ec.ReplicatedPlayback.EmoteTag.TagName:ToString()
        if cur == C.PUNCH or cur == C.KICK then return end  -- 連打で最初からやり直さない
    end

    local tag = C.tag(tagName)
    if not ec:IsEmoteEquipped(tag) then
        -- サーバーは装備中のエモートしか再生しない
        if cfg.auto_equip_when_host == 1 and pawn:HasAuthority() then
            local tags = {}
            ec.EquippedEmoteTags:ForEach(function(_, e) tags[#tags + 1] = C.tag(e:get().TagName:ToString()) end)
            local original = {}
            for i, t in ipairs(tags) do original[i] = t end
            tags[#tags + 1] = tag
            ec:SetEquippedEmoteTagsFromAuthority(tags)
            ec:RequestPlayEmote(tag)
            -- 再生要求はその場では処理されないので、少し待ってから装備を元に戻す
            ExecuteWithDelay(500, function()
                ExecuteInGameThread(function()
                    if C.valid(ec) then ec:SetEquippedEmoteTagsFromAuthority(original) end
                end)
            end)
            return
        end
        log("このエモートが装備されていないため再生できません。ロッカーのエモート設定で装備してください: " .. tagName)
        return
    end
    ec:RequestPlayEmote(tag)
end

local function bind(keyName, tagName, requireNoFocus)
    local key = Key[keyName]
    if not key then
        log("キー名が不正です: " .. tostring(keyName))
        return
    end
    RegisterKeyBind(key, function()
        ExecuteInGameThread(function()
            local mod = package.loaded["input"] or M
            local ok, err = pcall(mod.play, tagName, requireNoFocus)
            if not ok then log("エモートの再生でエラー: " .. tostring(err)) end
        end)
    end)
end

M.play = play

function M.init(config, logger)
    cfg, log = config, logger
end

function M.start(config, logger)
    M.init(config, logger)
    bind(cfg.punch_key, C.PUNCH, cfg.punch_requires_no_focus == 1)
    bind(cfg.kick_key, C.KICK, cfg.kick_requires_no_focus == 1)
    log("キー: パンチ = " .. cfg.punch_key .. " / キック = " .. cfg.kick_key)
end

return M
