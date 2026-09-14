# Panely

アクティブなウインドウを、キーボードショートカットまたはトラックパッドの 4 本指ジェスチャーで
「最大化」「左半分」「右半分」に配置する macOS のメニューバーアプリです。

| 操作 | ショートカット | ジェスチャー |
| --- | --- | --- |
| 最大化 | ⌃⌥↩ | 4 本指タップ |
| 左半分 | ⌃⌥← | 4 本指で左スワイプ |
| 右半分 | ⌃⌥→ | 4 本指で右スワイプ |

「最大化」はメニューバーと Dock を除いた領域（`NSScreen.visibleFrame`）いっぱいに配置します。
macOS のネイティブフルスクリーンではありません。配置の基準はウインドウが乗っている画面です。

操作の動きは [index.html](index.html) で再生できます（ブラウザで開くか、GitHub Pages で公開します）。

## 動作環境

- macOS 14 以降、Apple Silicon で確認しています
- アクセシビリティの許可が必要です
- 設定 UI はありません。ショートカットとしきい値はコード内の定数です

## インストール

自分の Mac でビルドする方法を推奨します。

```bash
git clone https://github.com/bluerabbit/panely.git
cd panely
scripts/make_app.sh        # build/Panely.app を組み立てて署名する
open build/Panely.app      # メニューバーに常駐する
```

1. 許可が無いと「アクセシビリティの許可が必要です」というウインドウが出ます。
   「システム設定を開く」から「プライバシーとセキュリティ > アクセシビリティ」で Panely を有効にすると、
   ウインドウは自動で閉じます。
2. 他のアプリのウインドウを前面にして ⌃⌥↩（最大化）、⌃⌥←（左半分）、⌃⌥→（右半分）を押します。
   トラックパッドの 4 本指タップ、左右スワイプでも同じ動作になります。
3. 終了はメニューバーのアイコンから「Panely を終了」です。

常用する場合は `build/Panely.app` を `/Applications` に移し、
「システム設定 > 一般 > ログイン項目」に登録します。移動後はアクセシビリティ許可を一度やり直します。

### 4 本指スワイプが効かないとき

macOS の「フルスクリーンアプリ間をスワイプ」が 4 本指の設定だと左右スワイプが衝突します。
「システム設定 > トラックパッド > その他のジェスチャ」で 3 本指に変えてください。
メニューバーのメニューから設定画面を開けます。

### 署名について

`scripts/make_app.sh` はキーチェーンにある Apple Development 証明書を自動で使います。
ad-hoc 署名だとリビルドのたびにアクセシビリティ許可が外れるためです。
別の証明書を使う場合は `CODESIGN_IDENTITY` に証明書の名前か SHA-1 を渡します。

```bash
CODESIGN_IDENTITY="Apple Development: ..." scripts/make_app.sh
```

署名を変えた直後は一度だけ許可のやり直しが必要です。
アクセシビリティの一覧から Panely を「−」で削除し、Panely を起動し直して再度許可します。

## 仕組みと制約

- ショートカットは Carbon の `RegisterEventHotKey` で受け取ります
- ウインドウの配置はアクセシビリティ API で行います。位置 → 大きさ → 位置の順に書き、
  ずれていれば 50ms 後に 1 回やり直します
- 4 本指の検出には private framework の `MultitouchSupport.framework` を使います。
  このため App Sandbox は使えず、App Store 配布はできません。OS の更新で動かなくなる可能性があります
- ジェスチャーの判定は「各指の着地位置からの移動量の平均」で行います。
  3 本指や 5 本指、上下スワイプ、ピンチでは反応しません
- ネイティブフルスクリーン中のウインドウには何もしません
- Google Chrome はアクセシビリティ API のフォーカスアプリ取得に応答しないため、
  その場合だけ `NSWorkspace` の最前面アプリを使います

## 開発

```bash
swift build
swift test
```

```
Sources/
├── CMultitouch/   # MultitouchSupport の構造体定義（C ヘッダ）。関数は dlsym で取得する
└── Panely/        # 本体
    ├── App/       # main.swift、AppDelegate（メニューバー、イベント集約）
    ├── Layout/    # WindowAction、WindowLayout（配置計算。AppKit 非依存）
    ├── Gesture/   # TouchFrame、GestureRecognizer（4 本指の判定。AppKit 非依存）
    └── Services/  # AccessibilityService、HotKeyService、MultitouchService
Tests/PanelyTests/ # Layout と Gesture のユニットテスト
scripts/           # make_app.sh（.app の組み立てと署名）
```

動作ログは統合ログに出ます。

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "com.bluerabbit.panely"'
```

## CI とリリース

GitHub Actions（`macos-26` ランナー）で動かします。

- `.github/workflows/ci.yml`: `main` への push と Pull Request で `swift build`、`swift test`、
  `.app` の組み立てを行い、成果物を 7 日間保存します
- `.github/workflows/release.yml`: `v0.1.0` のようなタグを push すると `.app` を組み立て、
  zip にして GitHub Release に添付します。版数はタグから `Info.plist` に書き込みます

```bash
git tag v0.1.0
git push origin v0.1.0
```

Release の zip は Apple Silicon（arm64）専用です。
CI では証明書を使わないため、ad-hoc 署名で公証もありません。
ダウンロードした `.app` は初回に Gatekeeper の警告が出るので、右クリックの「開く」から起動します。
また ad-hoc 署名はリリースごとに別アプリとみなされ、アクセシビリティ許可のやり直しが必要です。

## 謝辞

- [Tiley](https://github.com/yusuke/tiley)（Apache-2.0）。アクセシビリティ API でのウインドウ配置
  （対象ウインドウの取得、座標変換、位置と大きさの書き込み順）と Carbon ホットキーの扱いを参考にしました
- [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport)（MIT）。
  `Sources/CMultitouch/include/CMultitouch.h` の構造体レイアウトを参照しました

## ライセンス

[MIT](LICENSE)
