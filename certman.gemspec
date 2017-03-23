# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'certman/version'

Gem::Specification.new do |spec|
  spec.name          = 'certman'
  spec.version       = Certman::VERSION
  spec.authors       = ['k1LoW']
  spec.email         = ['k1lowxb@gmail.com']

  spec.summary       = 'CLI tool for AWS Certificate Manager.'
  spec.description   = 'CLI tool for AWS Certificate Manager.'
  spec.homepage      = 'https://github.com/k1LoW/certman'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.2'
  spec.add_runtime_dependency 'aws-sdk', '< 2.9'
  spec.add_runtime_dependency 'awsecrets', '~> 1.8'
  spec.add_runtime_dependency 'thor'
  spec.add_runtime_dependency 'public_suffix'
  spec.add_runtime_dependency 'oga'
  spec.add_runtime_dependency 'tty-prompt'
  spec.add_runtime_dependency 'tty-spinner'
  spec.add_runtime_dependency 'pastel'
  spec.add_development_dependency 'bundler', '~> 1.12'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 0.47.0'
  spec.add_development_dependency 'octorelease'
  spec.add_development_dependency 'pry'
end
