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
  # 14.0 is Capacitor 7's iOS deployment target. CocoaPods refuses to integrate
  # a pod whose minimum is higher than the host target's, so this has to match
  # the *oldest* supported Capacitor, not the newest. Newer iOS APIs are behind
  # runtime `if #available` checks.
  s.ios.deployment_target = '14.0'
  # Unversioned on purpose: the app's Podfile already pins Capacitor via the
  # generated `pod 'Capacitor', :path => '…/@capacitor/ios'` entry, so this
  # resolves to whichever major the app installed.
  s.dependency 'Capacitor'
  s.swift_version = '5.9'
end
