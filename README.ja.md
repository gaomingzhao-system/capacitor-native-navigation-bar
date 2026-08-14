# capacitor-native-navigation-bar

Capacitor アプリ向けのネイティブ navbar・tabbar・セーフエリア通知・WebView スナップショットトランジション — **Capacitor 7 および Capacitor 8+** を単一パッケージでサポート。

このプラグインは WebView の上にリアルな UIKit / Android ビューを描画し、それらが占めるビューポートの領域をイベントと CSS 変数として通知します。また、JavaScript がルートを切り替える間、WebView のスナップショット上でネイティブトランジションを再生できます。

> 🇺🇸 [English README](./README.md)

---

## サポートバージョン

|                                    | 最小バージョン | 検証済み環境                                      |
| ---------------------------------- | -------------- | ------------------------------------------------- |
| Capacitor                          | 7.0.0          | 7.6.8 および 8.5.0                                |
| iOS デプロイメントターゲット       | 14.0           | iOS 26 シミュレーター、CocoaPods **および** SPM   |
| Android minSdk                     | 23             | API 36 エミュレーター、AGP 8.7.2 および 8.13.0    |
| Node（パッケージビルド用）         | 20.19          | 24                                                |

`peerDependencies` は `@capacitor/core: >=7.0.0 <10.0.0` です。両メジャーバージョンは
`pnpm run typecheck` で実際の `@capacitor/core` 7 および 8 の型定義に対して検証されます。

---

## インストール

```bash
npm install capacitor-native-navigation-bar && npx cap sync
```

pnpm や bun も使用できます。Capacitor CLI はいずれのレイアウトでも `package.json` を通じてプラグインを検出します。

### iOS

- Xcode 15 以降が必要です。
- **CocoaPods:** 追加設定不要 — `npx cap sync ios` が生成された Podfile に `pod 'CapacitorNativeNavigationBar'` を自動追加します。
- **Swift Package Manager:** 追加設定不要 — パッケージは `platforms: [.iOS(.v14)]` と Capacitor 7・8 両方に対応する `capacitor-swift-pm` バージョン範囲を宣言しているため、`cap sync` がピン留めしたバージョンに対して自動解決されます。
- プラグインは `bridge.viewController.view` にネイティブビューを追加します。アプリがルートビューコントローラーを置き換える場合は、その後にプラグインのビューを追加してください。

### Android

- JDK 21 が必要です（Capacitor 7 および 8 と同じ要件）。
- 追加設定不要 — モジュールはアプリの `variables.gradle` から `compileSdkVersion`、`minSdkVersion`、`targetSdkVersion` を読み取ります。
- `load()` が `Window.setDecorFitsSystemWindows(false)` を呼び出し、ネイティブバーがシステムバー領域に描画できるようにします。これはアクティビティ全体に適用されます。

---

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

### カスタム要素

`defineNativeNavigationElements()` は `<cap-native-navigation-provider>`、`<cap-native-navbar>`、`<cap-native-tabbar>` を登録します。これらは属性をプラグイン呼び出しにミラーします。同一タスク内の属性書き込みは 1 回のネイティブ呼び出しにまとめられます。

---

## API

| メソッド                     | 戻り値                        | 説明                                                                                                           |
| ---------------------------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `configure(options?)`        | `{ insets }`                  | グローバルの有効化/無効化、インセットモード、デフォルトアニメーション時間、共有カラーとガラスエフェクト。        |
| `setNavbar(options)`         | `{ insets }`                  | タイトル、サブタイトル、戻るボタン、左右アイテム、カラー、blur/glass、大タイトル。                             |
| `setTabbar(options)`         | `{ insets }`                  | タブ、選択状態、ラベル/アイコン、バッジ、カラー、`floating`/`curve` シェイプ、detached trailing `search` ロール。|
| `beginTransition(options?)`  | `{ id, direction, duration }` | WebView をスナップショットし、ライブビューを非表示にします。                                                    |
| `finishTransition(options?)` | `{ id, direction, duration }` | スナップショットをアニメーションで消します。方向: `forward`、`back`、`root`、`tab`、`zoom`、`none`。            |
| `getPluginVersion()`         | `{ version }`                 | iOS/Android では `native`、ウェブフォールバックでは `web`。                                                    |

### イベント

`navbarBack`、`navbarItemTap`、`tabSelect`、`safeAreaChanged`、`transitionStart`、`transitionEnd`。
各イベントは `NativeNavigation.addListener(...)` と `window` 上の `capNativeNavigation:<event>` の両方で配信されます。

すべてのオプション・イベントの型は [`src/definitions.ts`](./src/definitions.ts) に定義されており、`dist/esm/index.d.ts` としてパッケージに含まれています。

---

## プラットフォームごとの動作

- **iOS 26+**: フローティングタブバーにシステムの Liquid Glass `UITabBarController` を使用し、カスタムカプセルには `UIGlassEffect` を使用します。それより古い iOS では `UIBlurEffect` マテリアルにフォールバックします。Liquid Glass パス全体はランタイムの `if #available` チェックで保護されているため、iOS 14 フロアでもコンパイル・動作します。
- **Android 12+**: WebView の後ろに `RenderEffect` ブラーで `liquidGlass` エフェクトを描画します。Android 11 以前は半透明サーフェスになります。
- アイコンはインライン SVG（両プラットフォームでネイティブ描画）、SF Symbols、バンドル済み画像/drawable 名に対応しています。

詳細なプラットフォームと OS 機能のサポートマトリクスは [PLATFORM.md](./PLATFORM.md) を参照してください。

---

## 開発

```bash
pnpm install
pnpm run lint      # oxfmt --check、oxlint、tsc（@capacitor/core 7 と 8 に対して）、wiring check
pnpm run test      # vitest
pnpm run build     # tsdown → dist/esm、dist/plugin.cjs、dist/plugin.js
pnpm run verify:ios      # xcodebuild -scheme CapacitorNativeNavigationBar
pnpm run verify:android  # cd android && ./gradlew clean build test
```

Swift ユニットテストを実行する場合:

```bash
xcodebuild test -scheme CapacitorNativeNavigationBar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## ライセンス

MPL-2.0。[LICENSE](./LICENSE) および [NOTICE](./NOTICE) を参照してください。
