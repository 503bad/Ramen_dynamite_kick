-- RamenRanbu: パンチ/キックで物を吹き飛ばす MOD(UE4SS Lua)
--   input  … キーでパンチ/キックのエモートを出す(全員)
--   combat … 当たり処理(ホストでのみ動く。MOD を入れていないゲストの攻撃にも効く)

local VERSION = "0.1.0"
local TAG = "[RamenRanbu] "
local function log(s) print(TAG .. tostring(s) .. "\n") end

local scriptPath = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("/", "\\")
local modDir = scriptPath:match("^(.*\\)Scripts\\[^\\]*$") or ".\\"

local cfg = require("config").load(modDir .. "config.txt", log)
log("v" .. VERSION .. " を読み込みました")

local function startPart(name)
    local ok, err = pcall(function() require(name).start(cfg, log) end)
    if not ok then log(name .. " の開始に失敗: " .. tostring(err)) end
end
startPart("input")
startPart("combat")

-- 開発用のコマンド受付(dev.lua は配布物に含めない)
local devFile = io.open(modDir .. "Scripts\\dev.lua", "r")
if devFile then
    devFile:close()
    _G.RR = { log = log, cfg = cfg, modDir = modDir }
    require("dev").start(modDir, _G.RR)
end
