# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# REVIEW_HEAD=<branch> (or 1 for master) builds against Re:VIEW from GitHub
# instead of the released gem -- the nightly job does this to catch upstream
# changes that break review-ast (which subclasses the makers and relies on
# their internals) before they are released.
if (review_head = ENV.fetch('REVIEW_HEAD', nil)) && !review_head.empty?
  gem 'review', github: 'kmuto/review', branch: review_head == '1' ? 'master' : review_head
end

# PDF backend of review-ast-vivliostylemaker, loaded only when that maker
# prints (it reports how to add it otherwise). vivlio-pdf needs Ruby >= 3.2;
# on 3.1 the rest of review-ast and its tests run without it.
gem 'vivlio-pdf', github: 'takahashim/vivlio-pdf' if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')
