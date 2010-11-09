require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "revactor"
    gem.summary = "Network programming for a concurrent world"
    gem.description = "Revactor wraps up Fibers as Erlang-like actors, allowing you to build concurrent network applications that handle large numbers of connections without the 'callback spaghetti' of event frameworks"
    gem.email = "tony@medioh.com"
    gem.homepage = "http://github.com/tarcieri/revactor"
    gem.authors = ["Tony Arcieri"]
    gem.add_dependency "cool.io", "~> 0.9.0"
    gem.add_development_dependency "rspec", "~> 2.0.0"
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = 'spec/**/*_spec.rb'
  spec.rspec_opts = %w[-fs -c -b]
end

RSpec::Core::RakeTask.new(:rcov) do |spec|
  spec.pattern = 'spec/**/*_spec.rb'
  spec.rcov = true
  spec.rspec_opts = %w[-fs -c -b]
end

task :spec => :check_dependencies
task :default => :spec

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "revactor #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
