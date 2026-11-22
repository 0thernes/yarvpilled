# frozen_string_literal: true
require "rake/testtask"
require "fileutils"

desc "Compile the ruby.h C extension into lib/yarvpilled/"
task :compile do
  build = File.expand_path("tmp/build", __dir__)
  FileUtils.mkdir_p(build)
  Dir.chdir(build) do
    sh "ruby #{File.expand_path('ext/yarvpilled_native/extconf.rb', __dir__)}"
    sh "make -s"
    so = Dir["yarvpilled_native.{so,bundle}"].first
    FileUtils.cp(so, File.expand_path("lib/yarvpilled/", __dir__))
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << "lib" << "test"
  t.test_files = FileList["test/test_*.rb"]
  t.warning = false
end

task default: %i[compile test]
