# frozen_string_literal: true

require_relative "lib/mr_shell/version"

Gem::Specification.new do |spec|
  spec.name = "mr_shell"
  spec.version = MrShell::VERSION
  spec.authors = ["Artem Vorozhtsov"]
  spec.summary = "A toy streaming MapReduce and functional programming toolkit"
  spec.description = "Model the MapReduce paradigm with lazy local pipelines."
  spec.homepage = "https://github.com/avorozhtsov/mr_shell"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["README.md", "mr_shell.gemspec", "bin/*", "examples/**/*.rb", "lib/**/*.rb"]
  spec.bindir = "bin"
  spec.executables = ["mr"]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "source_code_uri" => "https://github.com/avorozhtsov/mr_shell",
    "bug_tracker_uri" => "https://github.com/avorozhtsov/mr_shell/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.70.0"
end
