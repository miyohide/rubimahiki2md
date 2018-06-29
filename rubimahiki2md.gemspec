# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rubimahiki2md/version'

Gem::Specification.new do |spec|
  spec.name          = "rubimahiki2md"
  spec.version       = Rubimahiki2md::VERSION
  spec.authors       = ["miyohide"]
  spec.email         = ["miyohide@gmail.com"]

  spec.summary       = %q{convert Rubima Hiki to Markdown.}
  spec.description   = %q{convert Rubima Hiki to Markdown.}
  spec.homepage      = "https://github.com/miyohide/rubimahiki2md"
  spec.license       = "BSD-3-clause"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = ["rubimahiki2md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.13"
  spec.add_development_dependency "rake", "~> 10.0"
end
