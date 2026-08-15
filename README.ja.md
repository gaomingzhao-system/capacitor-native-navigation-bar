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
| Android `minSdk`                  | 24（7.0）    | Capacitor 7 自身の 23 より高い設定 — 後述            |

このリリースには Capacitor 8 サポートは **含まれていません**。詳細は
[1.x / Capacitor 7+8 リリースからの移行](#1x--capacitor-78-リリースからの移行)
を参照してください。

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
  **24** に引き上げてください。そうしないとマニフェストマージで失敗します
  （`uses-sdk:minSdkVersion 23 cannot be smaller than version 24 declared in
library`。検証済み）。

## インストール

```bash
npm install capacitor-native-navigation-bar && npx cap sync
```

pnpm や bun も使用できます。Capacitor CLI はいずれのレイアウトでも `package.json` を通じてプラグインを検出します。

### iOS

- Xcode 15 以降が必要です。
- 同期する前に、アプリの iOS デプロイメントターゲットを 15.0 に引き上げてください（上記参照）。
- **CocoaPods:** それ以外の追加設定は不要 — `npx cap sync ios` が生成された Podfile に `pod 'CapacitorNativeNavigationBar'` を自動追加します。
- **Swift Package Manager:** こちらも追加設定不要 — パッケージは `platforms: [.iOS(.v15)]` と、Capacitor 7 系のみに固定した `capacitor-swift-pm`（`from: "7.0.0"`）を宣言しているため、`cap sync` がピン留めした 7.x パッチバージョンに対して自動解決されます。
- プラグインは `bridge.viewController.view` にネイティブビューを追加します。アプリがルートビューコントローラーを置き換える場合は、その後にプラグインのビューを追加してください。

### Android

- JDK 21 が必要です（Capacitor 7 と同じ要件）。
- 同期する前に、`android/variables.gradle` の `minSdkVersion` を 24 に引き上げてください（上記参照）。
- それ以外は、モジュールはアプリの `variables.gradle` から `compileSdkVersion` と `targetSdkVersion` を読み取ります。スタンドアロンビルド時のフォールバックは Capacitor 7 自身のデフォルト（35）です。
- `load()` が `Window.setDecorFitsSystemWindows(false)` を呼び出し、ネイティブバーがシステムバー領域に描画できるようにします。これはアクティビティ全体に適用されます。

## 使い方

```ts
import {
  NativeNavigation,
  beginZoomTransition,
  finishZoomTransition,
} from "capacitor-native-navigation-bar";

await NativeNavigation.configure({ animationDuration: 300 });

await NativeNavigation.setNavbar({
  title: "ライブラリ",
  backButton: { visible: true },
  rightItems: [{ id: "search", icon: { ios: { sfSymbol: "magnifyingglass" }, svg: "<svg …/>" } }],
  colors: { tint: "#0a84ff" },
});

const { insets } = await NativeNavigation.setTabbar({
  selectedId: "home",
  tabs: [
    { id: "home", title: "ホーム", icon: { svg: "<svg …/>" } },
    { id: "library", title: "ライブラリ", badge: 3, icon: { svg: "<svg …/>" } },
    { id: "search", title: "検索", role: "search", icon: { svg: "<svg …/>" } },
  ],
  style: { shape: "floating", height: 64, bottomGap: 10 },
});

NativeNavigation.addListener("tabSelect", ({ id }) => router.go(id));
NativeNavigation.addListener("navbarBack", () => router.back());
NativeNavigation.addListener("safeAreaChanged", ({ insets }) => console.log(insets));
```

### インセット（Insets）

状態を変更するすべてのメソッドはネイティブバーが占めるインセットを返します。同じ値が `safeAreaChanged` イベントと `<html>` への CSS 変数として通知されます（`contentInsetMode: 'none'` でない限り）。

```css
body {
  padding-top: var(--cap-native-navigation-top);
  padding-bottom: var(--cap-native-navigation-bottom);
}
/* その他: --cap-native-navigation-left/right,
   --cap-native-navbar-height, --cap-native-tabbar-height */
```

### ネイティブトランジション

ルート変更をラップして、古いページのスナップショット上でネイティブアニメーションを再生します。

```ts
await NativeNavigation.beginTransition({ direction: "forward" });
await router.push("/details");
await NativeNavigation.finishTransition({ direction: "forward" });
```

`beginZoomTransition(element)` / `finishZoomTransition(element)` は Apple Zoom スタイルのトランジションに使用します。ビューポート座標内の要素 rect を受け取ります。

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

| メソッド                     | 戻り値                        | 説明                                                                                                              |
| ---------------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `configure(options?)`        | `{ insets }`                  | グローバルの有効化/無効化、インセットモード、デフォルトアニメーション時間、共有カラーとガラスエフェクト。         |
| `setNavbar(options)`         | `{ insets }`                  | タイトル、サブタイトル、戻るボタン、左右アイテム、カラー、blur/glass、大タイトル。                                |
| `setTabbar(options)`         | `{ insets }`                  | タブ、選択状態、ラベル/アイコン、バッジ、カラー、`floating`/`curve` シェイプ、detached trailing `search` ロール。 |
| `beginTransition(options?)`  | `{ id, direction, duration }` | WebView をスナップショットし、ライブビューを非表示にします。                                                      |
| `finishTransition(options?)` | `{ id, direction, duration }` | スナップショットをアニメーションで消します。方向: `forward`、`back`、`root`、`tab`、`zoom`、`none`。              |
| `getPluginVersion()`         | `{ version }`                 | iOS/Android では `native`、ウェブフォールバックでは `web`。                                                       |

### イベント

`navbarBack`、`navbarItemTap`、`tabSelect`、`safeAreaChanged`、`transitionStart`、`transitionEnd`。
各イベントは `NativeNavigation.addListener(...)` と `window` 上の `capNativeNavigation:<event>` の両方で配信されます。

すべてのオプション・イベントの型は [`src/definitions.ts`](./src/definitions.ts) に定義されており、`dist/index.d.ts` としてパッケージに含まれています。

## プラットフォームごとの動作

- **iOS 26+**: フローティングタブバーにシステムの Liquid Glass `UITabBarController` を使用し、カスタムカプセルには `UIGlassEffect` を使用します。iOS 15〜25 では `UIBlurEffect` マテリアルにフォールバックします。Liquid Glass パス全体はランタイムの `if #available` チェックで保護されているため、iOS 15 フロアでも問題なくコンパイル・動作します。
- **Android 12+**: WebView の後ろに `RenderEffect` ブラーで `liquidGlass` エフェクトを描画します。Android 7〜11 は半透明サーフェスになります。
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

## 1.x / Capacitor 7+8 リリースからの移行

本リリース（2.0.0）は、以前の「Capacitor 二重サポート・二重モジュール形式」
リリースからの意図的な破壊的変更です。

1. **ESM のみ。** ビルドツールが純粋な ESM 依存関係（`require()` 不可、
   IIFE/CDN バンドルなし）を扱えない場合は、ツールチェーンを更新できるまで
   以前のリリースを使い続けてください。
2. **Capacitor 7 のみ。** `peerDependencies` は `>=7.0.0 <10.0.0` から
   `^7.0.0` に変更されました。Capacitor 8 アプリは、Capacitor 8 サポートが
   別リリースとして提供されるまで、以前のリリースを使い続けてください。
3. **ネイティブフロアの引き上げ。** iOS 15.0、Android API 24 — 上記の通りアプ
   リ自身のフロアも引き上げてください。
4. **本パッケージのビルドに Node.js 22.13.0 以上が必要です。** ソースからビル
   ドするコントリビューターにのみ影響します。公開済みの `dist/` はビルド時の
   Node.js バージョンの影響を受けません（Node 22 LTS 自体は 22.11.0 から開始
   しますが、追加の 2 パッチバージョンは pnpm 11.9.0 自身の最小要件です。詳細
   は [PLATFORM.md](./PLATFORM.md) を参照してください）。

プラグイン自体の公開 API は変更されていません。`NativeNavigation` ブリッジ名、
すべてのメソッド名、オプション/イベントの形状、カスタム要素名、CSS 変数名は
以前のリリースと同一です。

## [`@capgo/capacitor-native-navigation`](https://github.com/Cap-go/capacitor-native-navigation) との技術比較

本パッケージと Cap-go 8.3.0 の、ビルド構成とネイティブ実装に関する主な違いだけを
まとめています。

| 項目                     | 本パッケージ                                                                                                        | Cap-go 版                                                                         |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Capacitor の基準         | Capacitor 7 のみ（`@capacitor/core: ^7.0.0`）                                                                       | Capacitor 8+ の peer range（`@capacitor/core: >=8.0.0`）、開発基準は 8.x          |
| JavaScript 出力          | `dist/index.js` の ESM のみ                                                                                         | `module`・`main`・`unpkg` による ESM、CommonJS、IIFE/UMD                          |
| ビルドツールチェーン     | TypeScript 7 ネイティブコンパイラー、`tsdown`、pnpm 11.9、Node.js 22.13 以上                                        | TypeScript 5.9、`tsc`、Rollup、Bun スクリプト、Node.js 22 以上                    |
| iOS SwiftPM 依存関係     | `capacitor-swift-pm` の `7.0.0` 以上、product は `CapacitorNativeNavigationBar`                                     | `capacitor-swift-pm` の `8.0.0` 以上、product は `CapgoCapacitorNativeNavigation` |
| Android ビルド基準       | フォールバック SDK 35、AGP 8.7.2、Java 17 バイトコード                                                              | フォールバック SDK 36、AGP 8.13.0、Java 21 バイトコード                           |
| Android 最低 SDK         | `minSdkVersion 24` を固定して強制                                                                                   | ホスト側の `minSdkVersion` があれば継承し、未指定時は 24                          |
| トランジション復旧       | iOS・Android のウォッチドッグと、バックグラウンド移行時の即時復旧                                                   | 現在のネイティブ実装に同等の復旧処理なし                                          |
| Android のリサイズと解放 | content root のサイズ変更時に再レイアウトし、destroy 時にビュー／リスナーを削除し、トランジション Bitmap を recycle | 対応する root サイズ監視、teardown、トランジション Bitmap の明示的 recycle なし   |

## ライセンス

MPL-2.0。[LICENSE](./LICENSE) および [NOTICE](./NOTICE) を参照してください。
