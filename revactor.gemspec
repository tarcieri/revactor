require 'rubygems'

GEMSPEC = Gem::Specification.new do |s|
  s.name = "revactor"
  s.version = "0.1.0"
  s.authors = "Tony Arcieri"
  s.email = "tony@medioh.com"
  s.date = "2008-1-15"
  s.summary = "Revactor is an Actor implementation for writing high performance concurrent programs"
  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 1.9.0'

  # Gem contents
  s.files = Dir.glob("{lib,examples,tools}/**/*") + ['Rakefile', 'revactor.gemspec']

  # Dependencies
  s.add_dependency("rev", ">= 0.1.2")
  s.add_dependency("case", ">= 0.3")

  # RubyForge info
  s.homepage = "http://revactor.org"
  s.rubyforge_project = "revactor"

  # RDoc settings
  s.has_rdoc = true
  s.rdoc_options = %w(--title Revactor --main README --line-numbers)
  s.extra_rdoc_files = ["LICENSE", "README", "CHANGES"]
end
