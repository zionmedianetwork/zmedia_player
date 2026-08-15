Pod::Spec.new do |s|
  s.name             = 'zmedia_player'
  s.version          = '0.2.5'
  s.summary          = 'A comprehensive Flutter media player package.'
  s.description      = <<-DESC
A comprehensive Flutter media player package with advanced features for video and audio playback.
                       DESC
  s.homepage         = 'https://github.com/zionmedianetwork/zmedia_player'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Zion Media Network' => 'contact@zionmedianetwork.com' }
  s.source           = { :path => '.' }
  # Sources are shared with the Swift Package Manager layout under
  # zmedia_player/Sources/zmedia_player so both CocoaPods and SPM build the
  # same files.
  s.source_files = 'zmedia_player/Sources/zmedia_player/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
