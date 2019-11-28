
Gem::Specification.new do |s|
  s.name = 'appmaker'
  s.version = '0.0.1'
  s.summary = 'Make some apps'
  s.authors = ['Andre Piske']
  s.files = Dir.glob('lib/**/*.rb') + Dir.glob('bin/**/*')
  s.license = 'MIT'
  s.homepage = 'https://github.com/andrepiske/wowhttp'

  s.post_install_message = 'No more excuses not do to an awesome app'

  s.executables << 'appmaker'

  s.add_runtime_dependency 'marcel'
  s.add_runtime_dependency 'nio4r', '~> 2.0'
  s.add_runtime_dependency 'concurrent-ruby', '~> 1.0'

  if RUBY_PLATFORM =~ /java/
    s.add_dependency 'jruby-openssl', '~> 0.10.2'
  end
end
