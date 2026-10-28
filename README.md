# RamenRanbu(ラーメン乱舞)

Japanese Ramen Simulator(Steam AppID 4968640)の非公式 MOD です。
パンチとキックで、店の物を吹き飛ばせるようになります。

| 操作 | 動作 |
|---|---|
| **ホイール押し込み** | パンチ(ゲーム標準のパンチ エモート) |
| **右クリック** | キック(ゲーム標準のキック エモート)。何も注視していない(「開ける」などの表示が出ていない)とき、物を持っていないときだけ |

右クリックはゲームのサブ操作・ズームにも使われているため、キックは何も注視していないときだけ出ます。
キーは `config.txt` で変えられます。

- **置いてあるアイテム**(丼・調味料・食材の箱・ガスボンベなど、持ち運び・投げられる物)を吹き飛ばします。
- **ガスボンベ**はキックすると爆発します(パンチでは倒れて転がるだけです)。
- **ビルドモードで置いた設備**(棚・台・椅子・ベッドなど)を、殴った方向へ押し出します。
  - その方向に再配置できない場合(壁・他の設備・人にぶつかる、建築できる範囲の外、床が途切れる)は、
    置ける所まで動きます。20cm も動かせない場合は動きません。
  - 設備の上に載っている物も一緒に動きます。
  - **コンロなど火災の原因になる設備**(ゲーム内で燃える設定になっている設備: 一口コンロ・茹で麺機・
    冷蔵庫・シンク・ウォーターサーバーなど)は、吹き飛ばずに**出火**します。消火器で消してください。
- 客などへのパンチ/キックの効果は、ゲーム本来のものがそのまま働きます。

## ダウンロード

**[最新版のダウンロード(Releases)](https://github.com/503bad/Ramen_dynamite_kick/releases/latest)** から `RamenRanbu_<版>.zip` をダウンロードしてください
(「Source code」はソースコードなので、遊ぶだけなら不要です)。

## インストール

動作環境: Windows 10 / 11、Steam 版の Japanese Ramen Simulator。

1. 配布物の zip を任意のフォルダに展開します。
2. **`install.bat`** をダブルクリックし、表示される内容を確認して `y` を入力します。
   - ゲームのインストール先は自動で検出します。
   - MOD をゲームに読み込ませる土台(UE4SS)も同梱しています。既に他の MOD(Ramen VRM MOD など)で
     入っている場合はそれを使い、上書きしません。
3. ゲームを起動し、ホイール押し込み(パンチ)・右クリック(キック)を押します。

アンインストールは `uninstall.bat` です。インストール時に置いたファイルだけを削除します。

## マルチプレイ

当たり処理(物を飛ばす・設備を動かす・出火・爆発)は**ホストの PC で**行われ、その結果はゲーム本来の同期で全員に伝わります。

| ホスト | ゲスト | 結果 |
|---|---|---|
| MOD あり | MOD なし | ホストもゲストも、パンチ/キックで物が飛びます。ゲストはゲーム標準のエモートメニューからパンチ/キックを出します(マウスでの操作は MOD を入れた人だけ)。 |
| MOD あり | MOD あり | 全員がマウスでパンチ/キックを出せ、物が飛びます。 |
| MOD なし | MOD あり | ゲストはマウスでパンチ/キックを出せますが、物は飛びません(処理するホストに MOD が無いため)。 |

- 物を飛ばす量などの設定(`config.txt`)は、ホストのものが使われます。
- 2 人以上での動作確認はまだ行っていません(1 人プレイでの確認のみ)。仕組みはゲーム本来の同期に乗せているため、
  上の表のとおりに動く見込みです。

## 設定

`<ゲーム>\RealRamenSimulator\Binaries\Win64\ue4ss\Mods\RamenRanbu\config.txt` を編集し、ゲームを再起動します。
再インストールしても書き換えた内容は残ります。

| 項目 | 既定 | 内容 |
|---|---|---|
| `punch_key` / `kick_key` | `MIDDLE_MOUSE_BUTTON` / `RIGHT_MOUSE_BUTTON` | キー(`H` などのキーボードも可) |
| `punch_requires_no_focus` / `kick_requires_no_focus` | 0 / 1 | 1 = 注視中・物を持っているときは反応しない |
| `punch_item_speed` / `kick_item_speed` | 650 / 1400 | アイテムを飛ばす速さ(cm/秒) |
| `upward_ratio` | 0.35 | 上向きに飛ばす割合 |
| `punch_build_distance` / `kick_build_distance` | 50 / 100 | 設備を押し出す距離(cm) |
| `build_min_distance` | 20 | これより短くしか動かせないなら動かさない(cm) |
| `enable_items` / `enable_buildables` / `enable_fire` / `enable_gas_explosion` | 1 | 機能ごとの有効(1)/無効(0) |
| `auto_equip_when_host` | 1 | パンチ/キックをエモートに装備していないとき、ホストなら一時的に装備して再生する |

## 注意

- 非公式 MOD です。ゲームの開発元とは関係ありません。ゲームのアップデートで動かなくなることがあります。
- 動かした設備・飛ばした物の位置は、ゲームのセーブに残ります。
- パンチ/キックはゲームのエモートなので、**ロッカーのエモート設定で装備されている必要があります**(初期状態で装備済み)。
  外している場合、ゲストの立場では再生できません(ホストなら `auto_equip_when_host` で再生できます)。
- チャットなどの文字入力中、メニューを開いている間、ビルドモード中はパンチ・キックは出ません。
- UE4SS を Ramen VRM MOD のインストーラで入れている場合、Ramen VRM MOD をアンインストールすると UE4SS ごと消え、
  この MOD も動かなくなります。そのときはこの MOD の `install.bat` を実行し直してください。

### 手動アンインストール

インストール記録(`%LOCALAPPDATA%\RamenRanbu\install_manifest.json`)が無い場合は、
`<ゲーム>\RealRamenSimulator\Binaries\Win64\ue4ss\Mods\RamenRanbu` フォルダを削除してください。

## 開発者向け

```
mod/RamenRanbu/        UE4SS の Lua MOD
  Scripts/main.lua       起動
  Scripts/input.lua      キー → エモート再生(ローカル)
  Scripts/combat.lua     エモートの監視と当たり処理(ホストのみ)
  Scripts/buildmove.lua  設備の再配置判定と移動
  Scripts/dev.lua        開発用: dev\cmd.lua に書いた Lua をゲーム内で実行(配布物には入れない)
  config.txt
scripts/               install.bat / uninstall.bat / ramen_ranbu_setup.ps1 / make_package.ps1 / dev_deploy.ps1
third_party/ue4ss/     同梱する UE4SS(zip は git 管理外)とライセンス
docs/DESIGN.md         調査結果と設計
```

- 配布物の作成: `powershell -ExecutionPolicy Bypass -File scripts\make_package.ps1 -Version 0.1.0`
- 開発中の配置: `powershell -ExecutionPolicy Bypass -File scripts\dev_deploy.ps1`(dev フォルダ付きで配置し、
  `ue4ss\Mods\RamenRanbu\dev\cmd.lua` に書いた Lua がゲームスレッドで実行され、結果が `dev\out.txt` に出ます)

## ライセンス

同梱している UE4SS(MIT)とそれに組み込まれたライブラリのライセンス文は、配布物の `licenses\` にあります。
