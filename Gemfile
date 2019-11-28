# frozen_string_literal: true
source "https://rubygems.org"
git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem 'nio4r', '~> 2.2.0'

# gem 'pg'
gem 'connection_pool'
gem 'redis'

gem 'stackprof'

gem 'mustermann'
gem 'erubi', '~> 1.7.0'

group :development, :test do
  gem 'pry'

  unless RUBY_ENGINE == 'jruby'
    gem 'pry-byebug'
  end
end
