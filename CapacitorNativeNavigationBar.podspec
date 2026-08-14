require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

# package.json repository URLs carry npm's `git+` prefix and a `.git` suffix;
# CocoaPods wants a plain https URL for `homepage` and a clean git URL for
# `source`, so normalise once here.
repository_url = package['repository']['url'].sub(/\Agit\+/, '')
homepage_url = repository_url.sub(/\.git\z/, '')

Pod::Spec.new do |s|
  s.name = 'CapacitorNativeNavigationBar'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = homepage_url
  s.author = package['author'] || 'capacitor-native-navigation-bar contributors'
  s.source = { :git => repository_url, :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,c,cc,mm,cpp}'
  # This plugin's own floor (15.0) is intentionally higher than Capacitor 7's
  # own deployment target (14.0). Verified empirically: CocoaPods does NOT
  # refuse to install this into an app whose Podfile still says
  # `platform :ios, '14.0'` — it happily builds with this pod's target at 15.0
  # and the app's at 14.0 (per-target deployment targets are valid Xcode
  # config). The risk is at *runtime*, not build time: the app would then
  # claim iOS 14 support (allowing installs on devices this code was never
  # exercised on) while this pod assumes iOS 15 APIs are unconditionally
  # available below its own `if #available` guards. Raise the Podfile's
  # `platform :ios` to 15.0 anyway so the app's declared minimum OS support
  # matches what it actually ships — see README.md. (Swift Package Manager, by
  # contrast, DOES hard-fail the build on this mismatch — also verified.)
  # iOS APIs newer than 15.0 remain behind runtime `if #available` checks.
  s.ios.deployment_target = '15.0'
  # Unversioned on purpose: the app's Podfile already pins Capacitor via the
  # generated `pod 'Capacitor', :path => '…/@capacitor/ios'` entry, so this
  # resolves to whichever major the app installed.
  s.dependency 'Capacitor'
  s.swift_version = '5.9'
end
