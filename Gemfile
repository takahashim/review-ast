# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# PDF backend of review-ast-vivliostylemaker, loaded only when that maker
# prints (it reports how to add it otherwise). vivlio-pdf needs Ruby >= 3.2;
# on 3.1 the rest of review-ast and its tests run without it.
gem 'vivlio-pdf', github: 'takahashim/vivlio-pdf' if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')
