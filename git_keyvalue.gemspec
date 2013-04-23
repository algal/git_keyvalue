# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'git_keyvalue/version'

Gem::Specification.new do |spec|
  spec.name          = "git_keyvalue"
  spec.version       = GitKeyvalue::VERSION
  spec.authors       = ["Alexis Gallagher"]
  spec.email         = ["alexis@alexisgallagher.com"]
  spec.description   = %q{Treat a remote git repo as a simple key/value store}
  spec.summary       = %q{Treat a remote git repo as a simple key/value store}
  spec.homepage      = "https://github.com/algal/git_keyvalue"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.has_rdoc = 'yard'
  spec.extra_rdoc_files      = ['README.md']
  spec.required_ruby_version = '>= 1.9.3'
  spec.requirements          = 'git (known good with v1.7.9.6)'

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "redcarpet"
end
