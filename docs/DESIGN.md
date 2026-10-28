# 設計と調査結果

調査日: 2026-10-29。ゲームの exe は 2026-10-28 更新版。調査は UE4SS の Lua(開発用コマンド受付 `dev.lua`)で
実行中のゲームの値を読んで行った。クラス定義は `E:\develop\ramen_vrm_mod\research\probe_20261026\CXXHeaderDump`
(2026-10-26 版のヘッダー)を参照。

## ゲーム側にあったもの

### エモート(パンチ/キックは最初からある)
- `UMenEmoteComponent`(プレイヤーの `EmoteComponent`)。カタログ `/Game/Men/MasterData/Player/DA_Men_Player_EmoteList`。
- `Men.Emote.Action.Punch`(`AM_Men_037_Punch`、攻撃判定 `MenEmoteAttackWindow` = 0.672〜0.830 秒、
  `DA_Men_PunchAttack`: Impulse 1200)と `Men.Emote.Action.Kick`(`AM_Men_047_Kick`、0.959〜1.341 秒、
  `DA_Men_KickAttack`: Impulse 3000、bHeavy)。どちらも UnlockLevel 1、初期装備。
- `RequestPlayEmote(FMenEmoteTag)` → サーバーで再生 → `ReplicatedPlayback {EmoteTag, BodyMode, Serial, ServerStartTimeSeconds}`
  が全員に同期される。**装備していないエモートはサーバーが拒否する**(Serial が増えない)。
- ゲーム本来の攻撃判定は客など(キャラクター)向けで、置いてあるアイテムや設備には何も起きない(実験で確認)。
- 入力: G は `IA_Men_OpenDailyCostomerOrder`(本日のラーメン)。H / J はどの入力マッピングにも無い。右クリックは `IA_Men_SecondaryInteract` と `IA_Men_Zoom`、ホイール押し込みは未使用。

### アイテム(`AMenItemActorBase`)
- 置かれたアイテムは `CarryPhysicsBaseState = DroppedSettled(3)`、ルートの StaticMesh は**物理演算中・移動の同期あり**
  (`bReplicateMovement`)。→ ホストで速度を与えれば全員に反映される。
- `WakeAllRigidBodies` してから `AddImpulse(速度変化)`。起こさないと次のフレームで速度が 0 に戻る。
- 飛んだあとはゲームが自分で `DroppedSettled` に戻す。
- `MulticastApplyInitialPlacementSettleState` を呼ぶと自由度ロックが付いて動かなくなった(使わないこと)。
- 対象外: 持たれている(1)、シンク・まな板・設備の中・盛り付け(4〜7)、他の物に付いている(重ねた食器)、`IsCarryPickupLocked`。
- 生成: `UMenItemSpawnSubsystem:SpawnItem({TagName}, Transform)`。ガスボンベは `Men.ItemId.Cookware.GasCylinder`。

### ガスボンベ(`AMenGasCylinderActor`)
- `Explode()` で爆発(エフェクトは `MulticastPlayExplosionEffect` で全員に、周囲への爆風・連鎖もゲーム本来の処理)。

### 設備(`AMenBuildableActor`)
- 移動の同期あり(`bReplicateMovement`)。ホストで `K2_SetActorLocation` すれば全員に反映され、位置はセーブに残る。
- 燃える設定: `FlammableComponent:IsFlammableEnabled()` が真なのは一口コンロ・茹で麺機(2 種)・冷蔵庫・シンク・
  ウォーターサーバー(このマップで確認)。`Ignite()` で出火(「火事が発生しています」表示・消火器で消せる)。
- 再配置の判定: ゲームの `UMenBuildPlacementValidator::ComputePlacement` は引数の構造体(建築定義の InstancedStruct を含む)を
  Lua から正しく組み立てるのが難しいため使わず、次の自前の判定にした(`buildmove.lua`)。
  - 床置きであること(真下の床までの距離と、形が置き場所より下へ垂れ下がっていないこと。天井照明を除くため)
  - 移動先で他の物と重ならない(`BoxOverlapActors`。床から 8cm 上〜上端、水平は外接箱より 5cm 小さい箱)。
    隣の設備・人は移動前から接していたなら許す。壁などの固定物は常にぶつかる扱い。アイテムは無視(押しのける)
  - 建築できる範囲の中(`IsLocationInsideAllowedArea(Floor)`、元の位置が範囲内のときのみ)
  - 床が同じ高さで続いている(中央と四隅のトレース)、建築禁止の範囲(`AMenBuildForbiddenVolume`)に入らない
  - 指定距離で置けなければ 10cm ずつ縮め、`build_min_distance` 未満なら動かさない
- 床のトレースは、始点が壁メッシュに埋まることがある(カウンターの台など)ので、複数ヒットのうち上向きの面を採る。
- レベルの静的メッシュは `MeshPackActor_*`(原点に置かれた 1 アクター)にまとまっている。床面から 4〜5cm の薄いメッシュを含む。

## 構成

- `input.lua`(全員): ホイール押し込み / 右クリック → `RequestPlayEmote`。右クリックは注視中・物を持っているとき無視(`MenInteractionComponent:GetCurrentTarget`、`MenCarryComponent:HasHeldActor`)。1 クリックで 2 回呼ばれるので 0.3 秒以内の再入力は無視。メニュー表示中(マウスカーソル表示)、文字入力欄にフォーカス、
  ビルドモード中、パンチ/キック再生中は無視。未装備なら、ホストのときだけ一時的に装備に加えて再生し 0.5 秒後に戻す。
- `combat.lua`(ホストのみ。`GameState:HasAuthority()`): 33ms ごとに全プレイヤーの `ReplicatedPlayback.Serial` を監視し、
  パンチ/キックが始まったら、`ServerStartTimeSeconds` から数えてモンタージュの攻撃判定の時間帯に当たり判定を行う。
  - 判定は攻撃者の向きの箱(パンチ: 前 25〜115cm・高さ 75〜165cm・幅 ±40cm、キック: 前 25〜145cm・高さ 0〜155cm・幅 ±45cm)と
    対象の外接箱の重なり。手足の骨ではなく箱にしたのは、相手側でアニメーションが更新されていない場合も安定させるため
    (実測: パンチの右手は前 83cm・高さ 130〜140cm、キックの足先は前 110〜130cm・高さ 100〜145cm)。
  - アイテムは箱に入ったものすべて、設備は 1 回の攻撃で最も手前の 1 つ。当たったら `MulticastAttackHitSound` で音を鳴らす。
- ゲーム本来のエモート再生の同期をそのまま使うので、MOD を入れていないゲストのパンチ/キックにもホストの MOD が効く。

## UE4SS(Lua)で踏んだ注意点

- `require` はファイル内容をキャッシュする。開発中の再読み込みは `dofile` で行う。
- 空(nullptr)の UObject に `GetFName()` 等を呼ぶと UE4SS 内でアクセス違反になりゲームが落ちる(pcall では防げない)。
  必ず `IsValid()` を確認してから呼ぶ。
- `LoopAsync` から `ExecuteInGameThread` に出した処理が実行されないことがある(MOD の再読み込み時に発生)。
  完了待ちのフラグには 1 秒のタイムアウトを付けた。
- out 引数(`GetActorBounds`、`BoxOverlapActors`、`LineTrace*` の結果)は空のテーブルを渡すと中身が入る。

## 未確認

- 2 人以上での動作(ホスト MOD あり / ゲスト MOD なし の組み合わせを含む)。
- ゲストの画面での、飛んだアイテムの見え方(ゲーム本来の物理の同期に依存)。
- 他のマップ(Playground 以外)での建築範囲の判定。
