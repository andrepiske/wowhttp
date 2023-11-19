
Gem::Specification.new do |s|
  s.name = 'appmaker'
  s.version = '0.0.7'
  s.summary = 'Make some apps'
  s.authors = ['Andre Piske']
  s.files = Dir.glob('lib/**/*.rb') + Dir.glob('bin/**/*')
  s.license = 'MIT'
  s.homepage = 'https://github.com/andrepiske/wowhttp'

  s.executables << 'appmaker'

  s.add_runtime_dependency 'marcel', '~> 1.0'
  s.add_runtime_dependency 'arraybuffer', '~> 0.0.6'
  s.add_runtime_dependency 'nio4r', '~> 2.0'
  s.add_runtime_dependency 'concurrent-ruby', '~> 1.0'

  if RUBY_PLATFORM == 'java'
    # s.add_runtime_dependency 'jruby-openssl', '~> 0.10.4'
  end

  s.add_development_dependency 'rspec', '~> 3.9'
end
