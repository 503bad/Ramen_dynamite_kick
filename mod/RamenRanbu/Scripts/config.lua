-- 設定: Mods\RamenRanbu\config.txt(key = value)を読む。無い項目は既定値。

local M = {}

M.defaults = {
    punch_key = "MIDDLE_MOUSE_BUTTON",
    kick_key = "RIGHT_MOUSE_BUTTON",
    -- 1 = 何かを注視している・物を持っているときは反応しない(右クリックなどゲームと共用のキー向け)
    punch_requires_no_focus = 0,
    kick_requires_no_focus = 1,
    -- アイテムを飛ばす速さ(cm/秒)。上向き成分は速さ × upward_ratio
    punch_item_speed = 650,
    kick_item_speed = 1400,
    upward_ratio = 0.35,
    item_spin_degrees = 360,
    -- 設備(ビルドで置いた物)を動かす距離(cm)
    punch_build_distance = 50,
    kick_build_distance = 100,
    -- 再配置できる距離を探すときの最短距離(cm)。これより短くしか動けないなら動かさない
    build_min_distance = 20,
    -- 1 = 有効 / 0 = 無効
    enable_items = 1,
    enable_buildables = 1,
    enable_fire = 1,
    enable_gas_explosion = 1,
    -- パンチ/キックが装備されていないとき、ホストなら一時的に装備に加えて再生する
    auto_equip_when_host = 1,
    log_hits = 1,
}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function M.load(path, log)
    local cfg = {}
    for k, v in pairs(M.defaults) do cfg[k] = v end
    local f = io.open(path, "r")
    if not f then
        log("config.txt が無いので既定値を使います")
        return cfg
    end
    for line in f:lines() do
        line = line:gsub("^\239\187\191", "")
        if not line:match("^%s*[;#]") then
            local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if k and M.defaults[k] ~= nil then
                if type(M.defaults[k]) == "number" then
                    local n = tonumber(v)
                    if n then cfg[k] = n else log("config.txt: 数値ではないので無視します: " .. trim(line)) end
                else
                    cfg[k] = v:upper()
                end
            end
        end
    end
    f:close()
    return cfg
end

return M
