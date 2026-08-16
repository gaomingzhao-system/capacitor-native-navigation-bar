from pathlib import Path
import re
import textwrap

ROOT = Path(__file__).resolve().parents[1]


def load(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def save(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace(path: str, old: str, new: str, required: bool = True) -> None:
    text = load(path)
    if old not in text:
        if required:
            raise RuntimeError(f"{path}: missing {old[:100]!r}")
        return
    save(path, text.replace(old, textwrap.dedent(new).strip("\n"), 1))


def regex(path: str, pattern: str, replacement: str, required: bool = True) -> None:
    text = load(path)
    updated, count = re.subn(pattern, textwrap.dedent(replacement).strip("\n"), text, count=1, flags=re.S)
    if count != 1:
        if required:
            raise RuntimeError(f"{path}: pattern did not match: {pattern}")
        return
    save(path, updated)


if not (ROOT / "src/patch.ts").exists():
    raise RuntimeError("phase 1 did not produce src/patch.ts")
if not (ROOT / "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavbarActions.java").exists():
    raise RuntimeError("phase 2 did not produce NativeNavbarActions.java")

# Keep runtime null in the facade without creating an impossible intersection type.
replace(
    "src/plugin-facade.ts",
    '''type RuntimeTabbarPatch = NativeNavigationTabbarOptions & {
  selectedId?: string | null
  tabs?: NativeNavigationTabs | null
  style?: NativeNavigationTabbarStyle | null
}''',
    '''type RuntimeTabbarPatch = Omit<NativeNavigationTabbarOptions, "selectedId" | "tabs" | "style"> & {
  selectedId?: string | null
  tabs?: NativeNavigationTabs | null
  style?: NativeNavigationTabbarStyle | null
}''',
    required=False,
)

# Removing the declarative duration restores the documented default immediately.
replace(
    "src/components.ts",
    '''setChanged(patch, changed, "animation-duration", "animationDuration", numberAttribute(this, "animation-duration"))''',
    '''setChanged(
        patch,
        changed,
        "animation-duration",
        "animationDuration",
        numberAttribute(this, "animation-duration") ?? 350,
      )''',
    required=False,
)

# Swift numeric expression must remain floating point on every compiler.
replace(
    "ios/Sources/NativeNavigationBarPlugin/SVGIconRenderer.swift",
    '''let alpha = 4 / 3 * tan((angle2 - angle1) / 4)''',
    '''let alpha = CGFloat(4.0 / 3.0) * tan((angle2 - angle1) / 4)''',
    required=False,
)

# The current source may qualify tabbarStyle with `self`; add animation for either spelling.
if "configureFloatingBar" not in load("ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift"):
    regex(
        "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift",
        r'''            tabBar\.configure\(\n                items: items,\n                selectedIndex: resolvedSelectedIndex,\n                labelVisibilityMode: labelVisibilityMode,\n                icons: icons,\n                style: self\.tabbarStyle\n            \)''',
        r'''
            let configureFloatingBar = {
                tabBar.configure(
                    items: items,
                    selectedIndex: resolvedSelectedIndex,
                    labelVisibilityMode: labelVisibilityMode,
                    icons: icons,
                    style: self.tabbarStyle
                )
            }
            if options.bool("animated", default: false) {
                UIView.transition(
                    with: tabBar,
                    duration: 0.2,
                    options: [.transitionCrossDissolve, .allowUserInteraction],
                    animations: configureFloatingBar
                )
            } else {
                configureFloatingBar()
            }''',
    )

# Ensure both native hidden branches honor the animation option.
android_path = "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java"
android = load(android_path)
android = android.replace(
    '''        guardHiddenNavbarPlaceholder();''',
    '''        guardHiddenNavbarPlaceholder();''',
)
# Replace any remaining direct navbar hide inside applyNavbarState.
apply_nav_start = android.find("private void applyNavbarState()")
apply_tab_start = android.find("private void applyTabbarState()")
if apply_nav_start >= 0 and apply_tab_start > apply_nav_start:
    segment = android[apply_nav_start:apply_tab_start]
    segment = segment.replace(
        "navbarContainer.setVisibility(View.GONE);",
        '''setChromeVisibility(
                    navbarContainer,
                    false,
                    navbarState.optBoolean("animated", false)
                );''',
    )
    android = android[:apply_nav_start] + segment + android[apply_tab_start:]
if apply_tab_start >= 0:
    segment = android[apply_tab_start:]
    segment = segment.replace(
        "tabbarContainer.setVisibility(View.GONE);",
        '''setChromeVisibility(
                    tabbarContainer,
                    false,
                    tabbarState.optBoolean("animated", false)
                );''',
    )
    segment = segment.replace(
        "tabbarContainer.setVisibility(View.VISIBLE);",
        '''setChromeVisibility(
                tabbarContainer,
                true,
                tabbarState.optBoolean("animated", false)
            );''',
    )
    android = android[:apply_tab_start] + segment
save(android_path, android)

# Correct generated CI indentation if the one-shot transformer appended at root.
ci_path = ".github/workflows/ci.yml"
ci = load(ci_path)
marker = "\nandroid-instrumentation:\n"
if marker in ci:
    before, after = ci.split(marker, 1)
    block = "android-instrumentation:\n" + after
    block = "\n".join(("  " + line) if line else line for line in block.split("\n"))
    ci = before + "\n" + block
    save(ci_path, ci)

# Static audit: every reported S1/S2 mitigation must be represented in source.
audits = {
    "src/plugin-facade.ts": [
        "enqueueTabbarOperation",
        "observerRegistration = undefined",
        "validateNativeNavigationTransitionOptions",
        "const result = await bridge.setTabbar(effectiveOptions)",
    ],
    "src/components.ts": [
        "nativeNavigationError",
        "capNativeNavigation:error",
        "title: this.getAttribute(\"back-title\")",
    ],
    "ios/Sources/NativeNavigationBarPlugin/NativeNavigationPlugin.swift": [
        "teardownNativeChrome",
        "nativeNavigationRestoreLiftedViews",
        "nativeNavigationSnapshotRendererScale",
        "platformStyle 'android' is not available on iOS",
        "configureFloatingBar",
    ],
    "ios/Sources/NativeNavigationBarPlugin/SVGIconRenderer.swift": [
        "fillColor",
        "appendArc",
        "ellipseDerivative",
    ],
    "android/src/main/java/app/nativenavigationbar/capacitor/NativeNavigationPlugin.java": [
        "addToolbarLeadingItems",
        "manageEdgeToEdge",
        "platformStyle 'ios' is not available on Android",
        "new Handler(Looper.getMainLooper()).post",
        "setChromeVisibility",
    ],
    "android/src/main/java/app/nativenavigationbar/capacitor/GlassBackdropView.java": [
        "SHARED_SOURCE_FRAMES",
        "captureIfNeeded",
        "MAX_SHARED_SNAPSHOT_PIXELS",
    ],
    ".github/workflows/ci.yml": [
        "Validate CocoaPods integration",
        "Android API 30 instrumentation",
        "connectedDebugAndroidTest",
    ],
}
for path, required_markers in audits.items():
    text = load(path)
    missing = [marker for marker in required_markers if marker not in text]
    if missing:
        raise RuntimeError(f"{path}: missing mitigation markers: {missing}")

print("S1/S2 source audit passed")
