require 'rake'
require 'rake/rdoctask'
require 'rake/gempackagetask'
load 'revactor.gemspec'

# Default Rake task
task :default => :rdoc

# RDoc
Rake::RDocTask.new(:rdoc) do |task|
  task.rdoc_dir = 'doc'
  task.title    = 'Revactor'
  task.options = %w(--title Revactor --main README --line-numbers)
  task.rdoc_files.include('bin/**/*.rb')
  task.rdoc_files.include('lib/**/*.rb')
  task.rdoc_files.include('README')
end

# Gem
Rake::GemPackageTask.new(GEMSPEC) do |pkg|
  pkg.need_tar = true
end

# RSpec
begin
require 'spec/rake/spectask'

SPECS = FileList['spec/**/*_spec.rb']

Spec::Rake::SpecTask.new(:spec) do |task|
  task.spec_files = SPECS
end

namespace :spec do
  Spec::Rake::SpecTask.new(:print) do |task|
    task.spec_files = SPECS
    task.spec_opts="-f s".split
  end

  Spec::Rake::SpecTask.new(:rcov) do |task|
    task.spec_files = SPECS
    task.rcov = true
    task.rcov_opts = ['--exclude', 'spec']
  end
end

rescue LoadError
end
