# capacitor-native-navigation-bar

**Capacitor 7** アプリ向けのネイティブ navbar・tabbar・セーフエリア通知・WebView スナップショットトランジション。npm パッケージとして **ESM のみ** で配布されます。

このプラグインは WebView の上にリアルな UIKit / Android ビューを描画し、それらが占めるビューポートの領域をイベントと CSS 変数として通知します。また、JavaScript がルートを切り替える間、WebView のスナップショット上でネイティブトランジションを再生できます。

> 🇺🇸 [English README](./README.md)

## サポートバージョン

|                                   | 本リリース   | 補足                                                 |
| --------------------------------- | ------------ | ---------------------------------------------------- |
| Capacitor                         | 7.x のみ     | `peerDependencies`: `@capacitor/core: ^7.0.0`        |
| モジュール形式                    | ESM のみ     | CommonJS・IIFE/UMD・`unpkg` バンドルなし             |
| Node.js（本パッケージのビルド用） | 22.13.0 以上 | 22.23.2 および現行 LTS の 24.19.0 で検証             |
| TypeScript                        | 7.x          | ネイティブコンパイラー。[後述](#typescript-7) を参照 |
| iOS デプロイメントターゲット      | 15.0         | Capacitor 7 自身の 14.0 より高い設定 — 後述          |
| Android `minSdk`                  | 30（11）     | Capacitor 7 自身の 23 より高い設定 — 後述            |

バージョン **7.2.0** が最初の npm 公開版です。パッケージのメジャー
バージョンは対応する Capacitor のメジャーに合わせるため、このリリース系列は
Capacitor 7 のみをサポートします。

### アプリ側のフロアもこのプラグインのフロアに合わせる必要があります

このプラグインの iOS・Android フロアは、最新 OS サポートのために **意図的に**
Capacitor 7 自身のデフォルトより高く設定されています。プラグインの最小要件が
Capacitor 自体の要件を上回ること自体は問題ありませんが、それには **利用側アプリ**
も同じフロアを満たしている必要があります。

- **iOS**: Capacitor 7 のテンプレートは Podfile に `platform :ios, '14.0'`、
  Xcode プロジェクトのデプロイメントターゲットに 14.0 を設定します。このプラグ
  インをインストールする前に、両方を **15.0** に引き上げてください。
  - **Swift Package Manager はこの不一致でビルドが失敗します**（検証済み）:
    `The package product 'CapacitorNativeNavigationBar' requires minimum
platform version 15.0 for the iOS platform, but this target supports
14.0`。
  - **CocoaPods は失敗しません** — pod のターゲットが 15.0、アプリが 14.0 の
    ままでもビルドは成功します（Xcode では依存先のデプロイメントターゲット
    がアプリより高いこと自体は許容されます）。それでも引き上げることを推奨
    します。そうしないとアプリ自身は iOS 14 サポートを謳いながら、内部では
    `if #available` の外側で iOS 15 の API が常に利用可能だと仮定したコード
    をリンクすることになります。
- **Android**: Capacitor 7 のテンプレートは `android/variables.gradle` に
  `minSdkVersion = 23` を設定します。このプラグインをインストールする前に
  **30** に引き上げてください。そうしないとマニフェストマージで失敗します
  （`uses-sdk:minSdkVersion 23 cannot be smaller than version 30 declared in
library`）。さらに `compileSdkVersion = 36` と Android Gradle Plugin 8.10.0
  以上が必要です。既定の AndroidX Core 1.18.0 が、この消費側最低条件を公開して
  います。

## インストール

```bash
npm install capacitor-native-navigation-bar && npx cap sync
```

pnpm や bun も使用できます。Capacitor CLI はいずれのレイアウトでも `package.json` を通じてプラグインを検出します。

### iOS

- Xcode 16 以降が必要です（Capacitor 7 のツールチェーン要件）。
- 同期する前に、アプリの iOS デプロイメントターゲットを 15.0 に引き上げてください（上記参照）。
- **CocoaPods:** それ以外の追加設定は不要 — `npx cap sync ios` が生成された Podfile に `pod 'CapacitorNativeNavigationBar'` を自動追加します。
- **Swift Package Manager:** こちらも追加設定不要 — パッケージは `platforms: [.iOS(.v15)]` と、Capacitor 7 系のみに固定した `capacitor-swift-pm`（`from: "7.0.0"`）を宣言しているため、`cap sync` がピン留めした 7.x パッチバージョンに対して自動解決されます。
- プラグインは `bridge.viewController.view` にネイティブビューを追加します。アプリがルートビューコントローラーを置き換える場合は、その後にプラグインのビューを追加してください。

### Android

- JDK 21 を使用してください。
- 同期する前に、`android/variables.gradle` で `minSdkVersion = 30` と
  `compileSdkVersion = 36` を設定してください（上記参照）。
- Android Gradle Plugin 8.10.0 以上を使用してください。このリポジトリの
  スタンドアロン基準は AGP 8.13.2 / Gradle 8.14.3 です。
  `targetSdkVersion` はアプリ側の値を読み取り、スタンドアロン時は API 36 へ
  フォールバックします。
- `load()` が `Window.setDecorFitsSystemWindows(false)` を呼び出し、ネイティブバーがシステムバー領域に描画できるようにします。これはアクティビティ全体に適用されます。

## 使い方

```ts
import {
  NativeNavigation,
  beginZoomTransition,
  finishZoomTransition,
} from "capacitor-native-navigation-bar"

await NativeNavigation.configure({ animationDuration: 300 })

await NativeNavigation.setNavbar({
  title: "ライブラリ",
  backButton: { visible: true },
  rightItems: [{ id: "search", icon: { ios: { sfSymbol: "magnifyingglass" }, svg: "<svg …/>" } }],
  colors: { tint: "#0a84ff" },
})

const { insets } = await NativeNavigation.setTabbar({
  selectedId: "home",
  tabs: [
    { id: "home", title: "ホーム", icon: { svg: "<svg …/>" } },
    { id: "library", title: "ライブラリ", badge: 3, icon: { svg: "<svg …/>" } },
    { id: "search", title: "検索", role: "search", icon: { svg: "<svg …/>" } },
  ],
  style: { shape: "floating", height: 64, bottomGap: 10 },
})

NativeNavigation.addListener("tabSelect", ({ id }) => router.go(id))
NativeNavigation.addListener("navbarBack", () => router.back())
NativeNavigation.addListener("safeAreaChanged", ({ insets }) => console.log(insets))
```

### インセット（Insets）

通知される値は WebView がネイティブナビゲーションとの重なりを避けるために追加で確保すべき content-avoidance inset であり、OS の raw safe area そのものや、ネイティブバーの物理フレーム全体の高さをそのまま表すものとは限りません。状態を変更するすべてのメソッドはこれらのインセットを返します。同じ値が `safeAreaChanged` イベントと `<html>` への CSS 変数として通知されます（`contentInsetMode: 'none'` でない限り）。

```css
body {
  padding-top: var(--cap-native-navigation-top);
  padding-bottom: var(--cap-native-navigation-bottom);
}
/* その他: --cap-native-navigation-left/right,
   --cap-native-navbar-height, --cap-native-tabbar-height */
```

iOS 26でフローティングタブバーがsystem Liquid Glass `UITabBarController`によって管理される場合、bottom safe areaはUIKit側ですでに管理されています。この経路では同じ領域をWebView側で二重に確保しないよう、`bottom`と`tabbarHeight`から`safeAreaInsets.bottom`を除外します。

custom tab bar、`curve`シェイプ、Liquid Glassを使用しない経路、およびiOS 15〜25では、従来どおりbottom safe areaを含む値を返します。

プラグインのCSS変数を使用する場合、system Liquid Glass経路で`--cap-native-navigation-bottom`へ`env(safe-area-inset-bottom)`を無条件に再加算しないでください。再加算すると、今回防止した下部余白の重複が再発する可能性があります。

値は Android の画面密度に依存せず、全プラットフォームで CSS pixel／native point
単位です。`contentInsetMode: "none"` へ切り替えると、それ以前の `"css"` 設定が
書き込んだ変数は削除されます。

`configure`、`setNavbar`、`setTabbar` は差分更新です。省略したフィールドは、
ネストした `colors`、`glass`、`style` を含めて以前の値を維持します。状態を消す
場合は、空配列などの値を明示的に渡してください。

### ネイティブトランジション

ルート変更をラップして、古いページのスナップショット上でネイティブアニメーションを再生します。

```ts
await NativeNavigation.beginTransition({ direction: "forward" })
await router.push("/details")
await NativeNavigation.finishTransition({ direction: "forward" })
```

`beginZoomTransition(element)` / `finishZoomTransition(element)` は Apple Zoom スタイルのトランジションに使用します。ビューポート座標内の要素 rect を受け取ります。

終了できるのは現在アクティブなトランジションだけです。明示した id が一致しない
場合は、アクティブなスナップショットを壊さずに reject されます。

`finishTransition` が呼び出されないまま終わってしまった場合（アプリ側のバグ、
2 つの呼び出しの間で例外が発生した場合、あるいはトランジション中にアプリがバッ
クグラウンドに回った場合）でも、両プラットフォームとも自己回復します。ウォッ
チドッグタイマーが要求された時間の経過後まもなく WebView を強制的に復元し、
アプリが先にバックグラウンドに回った場合は iOS・Android のどちらも即座に強制
復元します。ペアで待ち受けているリスナーが取り残されないよう、その場合も
`transitionEnd` イベントは発火します。詳細は [PLATFORM.md](./PLATFORM.md) を
参照してください。

### カスタム要素

`defineNativeNavigationElements()` は `<cap-native-navigation-provider>`、`<cap-native-navbar>`、`<cap-native-tabbar>` を登録します。これらは属性をプラグイン呼び出しにミラーします。同一タスク内の属性書き込みは 1 回のネイティブ呼び出しにまとめられます。

## API

### `NativeNavigation` メソッド

| メソッド                     | 戻り値                                      | 説明                                                                                                                 |
| ---------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `configure(options?)`        | `Promise<NativeNavigationInsetsResult>`     | グローバルの有効化/無効化、インセットモード、デフォルトアニメーション時間、共有カラーとガラスエフェクト。            |
| `setNavbar(options)`         | `Promise<NativeNavigationInsetsResult>`     | タイトル、サブタイトル、戻るボタン、左右アイテム、カラー、blur/glass、大タイトル。                                   |
| `setTabbar(options)`         | `Promise<NativeNavigationInsetsResult>`     | タブ、選択状態、ラベル/アイコン、バッジ、カラー、`floating`/`curve` シェイプ、detached trailing `search` ロール。    |
| `beginTransition(options?)`  | `Promise<NativeNavigationTransitionResult>` | WebView をスナップショットし、ネイティブトランジションの準備をします。                                               |
| `finishTransition(options?)` | `Promise<NativeNavigationTransitionResult>` | スナップショットを現在の画面へアニメーションで切り替えます。方向: `forward`、`back`、`root`、`tab`、`zoom`、`none`。 |
| `getPluginVersion()`         | `Promise<PluginVersionResult>`              | バージョン識別子を返します: iOS/Android では `native`、ウェブフォールバックでは `web`。                              |
| `addListener(event, cb)`     | `Promise<PluginListenerHandle>`             | プラグインのイベントを購読します。                                                                                   |

### ズームトランジション用ヘルパー関数

| 関数                                      | 戻り値                                      | 説明                                                                                          |
| ----------------------------------------- | ------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `getNativeNavigationRect(target)`         | `NativeNavigationRect`                      | `Element`、`DOMRect`、または `NativeNavigationRect` をビューポート座標系へ変換します。        |
| `beginZoomTransition(target, options?)`   | `Promise<NativeNavigationTransitionResult>` | `target` の要素/rect を `sourceRect` として Apple Zoom スタイルのトランジションを開始します。 |
| `finishZoomTransition(target?, options?)` | `Promise<NativeNavigationTransitionResult>` | 遷移先ルートの任意の `target` 要素/rect へ Apple Zoom スタイルのトランジションを完了します。  |

### カスタム要素

`defineNativeNavigationElements()` を呼び出すことで、ブラウザの Custom Elements レジストリに要素を登録できます:

| カスタム要素                       | 対応する呼び出し               | サポート属性                                                                                                                                                                                                                                                                                                     |
| ---------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<cap-native-navigation-provider>` | `NativeNavigation.configure()` | `enabled`, `platform-style`, `content-inset-mode`, `animation-duration`, `colors`, `glass`                                                                                                                                                                                                                       |
| `<cap-native-navbar>`              | `NativeNavigation.setNavbar()` | `hidden`, `title`, `subtitle`, `large`, `transparent`, `blur-effect`, `back-button`, `back-title`, `left-items`, `right-items`, `colors`, `glass`, `animated`                                                                                                                                                    |
| `<cap-native-tabbar>`              | `NativeNavigation.setTabbar()` | `hidden`, `tabs`, `selected-id`, `labels`, `label-visibility-mode`, `icons`, `colors`, `glass`, `style`, `blur-effect`, `disable-transparent-on-scroll-edge`, `disable-indicator`, `indicator-color`, `ripple-color`, `badge-background-color`, `badge-text-color`, `experimental-baked-tint-colors`, `animated` |

### イベント

| イベント名        | ペイロードの型                         | 説明                                                                            |
| ----------------- | -------------------------------------- | ------------------------------------------------------------------------------- |
| `navbarBack`      | `NativeNavigationBackEvent`            | ネイティブ navbar の戻るボタンがタップされたときに発火                          |
| `navbarItemTap`   | `NativeNavigationBarItemTapEvent`      | navbar の左右アクションボタンがタップされたときに発火                           |
| `tabSelect`       | `NativeNavigationTabSelectEvent`       | タブ項目が選択されたときに発火                                                  |
| `safeAreaChanged` | `NativeNavigationSafeAreaChangedEvent` | プラグインが通知するネイティブナビゲーション用content insetが変化したときに発火 |
| `transitionStart` | `NativeNavigationTransitionEvent`      | ネイティブスナップショットトランジション開始時に発火                            |
| `transitionEnd`   | `NativeNavigationTransitionEvent`      | ネイティブスナップショットトランジション完了時に発火                            |

各イベントは `window` 上でも `capNativeNavigation:<eventName>` として配信されます。

### エクスポートされている型

すべてのオプション・イベント・戻り値の型はパッケージのルートからエクスポートされ、[`src/definitions.ts`](./src/definitions.ts) で定義されています（`dist/index.d.ts` として同梱）:

- オプション & 設定: `NativeNavigationConfigureOptions`, `NativeNavigationNavbarOptions`, `NativeNavigationTabbarOptions`, `NativeNavigationTabbarStyle`, `NativeNavigationTab`, `NativeNavigationBarButton`, `NativeNavigationBackButton`, `NativeNavigationIcon`, `NativeNavigationColors`, `NativeNavigationGlassOptions`, `NativeNavigationGlassEffect`, `NativeNavigationBlurEffect`, `NativeNavigationPlatformStyle`, `NativeNavigationContentInsetMode`, `NativeNavigationTabLabelVisibilityMode`, `NativeNavigationTabRole`, `NativeNavigationTabbarShape`。
- トランジション & ジオメトリ: `NativeNavigationBeginTransitionOptions`, `NativeNavigationFinishTransitionOptions`, `NativeNavigationTransitionResult`, `NativeNavigationTransitionDirection`, `NativeNavigationRect`, `NativeNavigationRectTarget`, `NativeNavigationInsets`, `NativeNavigationInsetsResult`。
- イベント & ハンドラー: `NativeNavigationBackEvent`, `NativeNavigationBarItemTapEvent`, `NativeNavigationTabSelectEvent`, `NativeNavigationSafeAreaChangedEvent`, `NativeNavigationTransitionEvent`。
- プラグインインターフェース: `NativeNavigationPlugin`, `PluginVersionResult`。

## プラットフォームごとの動作

- **iOS 26+**: フローティングタブバーにシステムの Liquid Glass `UITabBarController` を使用し、カスタムカプセルには `UIGlassEffect` を使用します。system Liquid Glass タブバー経路では、下部余白の重複を防ぐため、通知される bottom inset からシステム管理下の bottom safe area を除外します。カスタムカプセルおよび旧 iOS 経路では、従来どおり bottom safe area を含む計算を維持します。iOS 15〜25 では `UIBlurEffect` マテリアルにフォールバックします。Liquid Glass パス全体はランタイムの `if #available` チェックで保護されているため、iOS 15 フロアでも問題なくコンパイル・動作します。
- **Android 12+**: WebView の後ろに `RenderEffect` ブラーで `liquidGlass` エフェクトを描画します。Android 11 は半透明サーフェスにフォールバックします。
- アイコンはインライン SVG（両プラットフォームでネイティブ描画）、SF Symbols、バンドル済み画像/drawable 名に対応しています。

詳細なプラットフォームと OS 機能のサポートマトリクスは [PLATFORM.md](./PLATFORM.md) を参照してください。

## TypeScript 7

本パッケージは **ネイティブ** TypeScript 7 コンパイラー（`typescript@^7.0.2`）
で型チェック・ビルドされています。これは従来のインプロセス JS コンパイラー
API（`ts.createProgram`、`ts.transpileModule` など）をもはや公開していません
— `require("typescript")` はバージョン文字列と、新しい低レベルの
`typescript/unstable/*` AST API 群のみを公開します。実体のコンパイラーはプラ
ットフォーム固有のネイティブバイナリ（例: `@typescript/typescript-darwin-arm64`）
として配布されます。

これはこのパッケージのツールチェーンを拡張する際に重要です。`tsdown` の宣言
ファイルバンドラー（`rolldown-plugin-dts`）はすでに TypeScript 7 を検出し、旧
API を呼び出す代わりにネイティブの `tsc` バイナリを起動するため、宣言ファイル
生成は無改修で動作します（本リポジトリのビルドで確認済み）。旧 API に強く依
存するツール（`ts-morph`、一部モードの `vue-tsc` など）を追加する場合は、事前
に TypeScript 7 対応状況を確認してください。本パッケージでは現在そのようなツ
ールは使用していません。

`tsdown` はビルド時に `TypeScript 7.0 does not yet have a stable API and is
experimental. Some options will be unavailable.` という警告を表示します。これ
は想定内であり、生成物には影響しません — `dist/index.d.ts` の内容確認、および
`verify:web` 内の `attw`/`publint` チェックで確認済みです。

## 開発

```bash
pnpm install
pnpm run lint      # oxfmt --check、oxlint、tsc（TypeScript 7）、wiring check
pnpm run test      # vitest
pnpm run build     # tsdown → dist/index.js + dist/index.d.ts（ESM のみ）
pnpm run check:package  # publint --strict + attw --pack . --profile esm-only
pnpm run verify:ios      # xcodebuild -scheme CapacitorNativeNavigationBar
pnpm run verify:android  # cd android && ./gradlew clean build test
```

`pnpm run verify:ios:test` で iOS シミュレーター上の Swift ユニットテストを実行します。

## バージョニング

バージョン **7.2.0** は `capacitor-native-navigation-bar` の最初の npm 公開版です。
このパッケージ名では、以前の `1.x`・`2.x` 公開版は存在しません。メジャー
バージョンは対応する Capacitor のメジャーに合わせます。`7.x` は Capacitor 7、
将来の Capacitor 8 対応は別の `8.x` リリース系列として提供します。

## [`@capgo/capacitor-native-navigation`](https://github.com/Cap-go/capacitor-native-navigation) との技術比較

本パッケージと Cap-go 8.3.0 の、ビルド構成とネイティブ実装に関する主な違いだけを
まとめています。

| 項目                     | 本パッケージ                                                                                                        | Cap-go 版                                                                         |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Capacitor の基準         | Capacitor 7 のみ（`@capacitor/core: ^7.0.0`）                                                                       | Capacitor 8+ の peer range（`@capacitor/core: >=8.0.0`）、開発基準は 8.x          |
| JavaScript 出力          | `dist/index.js` の ESM のみ                                                                                         | `module`・`main`・`unpkg` による ESM、CommonJS、IIFE/UMD                          |
| ビルドツールチェーン     | TypeScript 7 ネイティブコンパイラー、`tsdown`、pnpm 11.9、Node.js 22.13 以上                                        | TypeScript 5.9、`tsc`、Rollup、Bun スクリプト、Node.js 22 以上                    |
| iOS SwiftPM 依存関係     | `capacitor-swift-pm` の `7.0.0` 以上、product は `CapacitorNativeNavigationBar`                                     | `capacitor-swift-pm` の `8.0.0` 以上、product は `CapgoCapacitorNativeNavigation` |
| Android ビルド基準       | フォールバック SDK 36、AGP 8.13.2、Gradle 8.14.3、Java 21 言語／バイトコード                                        | フォールバック SDK 36、AGP 8.13.0、Gradle 8.14.3、Java 21 バイトコード            |
| Android 最低 SDK         | `minSdkVersion 30` を固定して強制                                                                                   | ホスト側の `minSdkVersion` があれば継承し、未指定時は 24                          |
| トランジション復旧       | iOS・Android のウォッチドッグと、バックグラウンド移行時の即時復旧                                                   | 現在のネイティブ実装に同等の復旧処理なし                                          |
| Android のリサイズと解放 | content root のサイズ変更時に再レイアウトし、destroy 時にビュー／リスナーを削除し、トランジション Bitmap を recycle | 対応する root サイズ監視、teardown、トランジション Bitmap の明示的 recycle なし   |

## ライセンス

MPL-2.0。[LICENSE](./LICENSE) および [NOTICE](./NOTICE) を参照してください。
