REVIEW_TEMPLATE = ENV['REVIEW_TEMPLATE'] || 'review-jsbook'

desc 'copy sty/cls files from the review gem into sty/'
task :copy_sty do
  # pdfmaker はクラスファイルをプロジェクトの sty/ からしかコピーしないので、
  # review gem の同梱テンプレートからビルド前に写す。rake clean で消える。
  review_rootdir = Gem::Specification.find_by_name('review').gem_dir
  template_dir = File.join(review_rootdir, "templates/latex/#{REVIEW_TEMPLATE}")
  Dir.glob(File.join(template_dir, '*.cls')) do |file|
    FileUtils.cp(file, 'sty')
  end
  Dir.glob(File.join(template_dir, 'review-*.sty')) do |file|
    FileUtils.cp(file, 'sty')
  end

  if REVIEW_TEMPLATE == 'review-jsbook'
    jsbook_dir = File.join(review_rootdir, 'vendor/jsclasses')
    FileUtils.cp(File.join(jsbook_dir, 'jsbook.cls'), 'sty/jsbook.cls')
    gentombow_dir = File.join(review_rootdir, 'vendor/gentombow')
    FileUtils.cp(File.join(gentombow_dir, 'gentombow.sty'), 'sty/gentombow.sty')
  end
end

CLEAN.include([Dir.glob('sty/review-*.sty'), 'sty/*.cls', 'sty/gentombow.sty'])

Rake::Task[BOOK_PDF].enhance([:copy_sty])
