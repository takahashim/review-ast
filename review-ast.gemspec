# frozen_string_literal: true

Gem::Specification.new do |gem|
  gem.name        = 'review-ast'
  gem.version     = '0.1.0.pre'
  gem.platform    = Gem::Platform::RUBY
  gem.license     = 'LGPL'
  gem.authors     = %w[kmuto takahashim]
  gem.summary     = 'AST subsystem and multi-format renderers for Re:VIEW'
  gem.description = 'Provides an AST-based compiler/renderer pipeline on top of the review gem, ' \
                    'exposed via review-ast-dump / review-ast-dump2re / review-ast-compile.'
  gem.homepage    = 'https://github.com/takahashim/review-ast'

  gem.files       = Dir['lib/**/*.rb', 'bin/*', 'README.md']
  gem.executables = %w[review-ast-dump review-ast-dump2re review-ast-compile]
  gem.require_paths = ['lib']
  gem.required_ruby_version = '>= 3.1'

  gem.add_dependency('review', '~> 5.11')
  gem.add_dependency('diff-lcs')
  gem.add_dependency('nokogiri')
  gem.add_dependency('unicode-eaw')

  gem.add_development_dependency('math_ml')
  gem.add_development_dependency('rake')
  gem.add_development_dependency('test-unit')
end
