Pod::Spec.new do |s|
  s.name = 'AuroraNative'
  s.version = '1.0.0'
  s.summary = 'Local Aurora widget snapshots and nap activities'
  s.description = 'App Group snapshot bridge for the Aurora application.'
  s.license = { :type => 'MIT' }
  s.author = 'Aurora'
  s.homepage = 'https://github.com/nmapaye/aurora'
  s.platforms = { :ios => '15.1' }
  s.source = { :git => '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.source_files = '**/*.swift'
  s.swift_version = '5.0'
end
