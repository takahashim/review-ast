# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/**/test_*.rb']
  t.verbose = false
  t.warning = false
end

desc '版面（型）を Typst / Vivliostyle / LaTeX で突き合わせる（doc/design-hanmen §7.3）。' \
     "引数に出力先を渡すと生成 PDF を残す: rake 'hanmen:compare[out]'"
task 'hanmen:compare', [:outdir] do |_t, args|
  script = File.expand_path('tools/hanmen-compare/compare.rb', __dir__)
  ruby [script, args[:outdir]].compact.join(' ')
end

task default: :test
