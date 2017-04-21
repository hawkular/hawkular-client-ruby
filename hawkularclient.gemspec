# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hawkular/version'

Gem::Specification.new do |gem|
  gem.name          = 'hawkular-client'
  gem.version       = Hawkular::VERSION
  gem.authors       = ['Libor Zoubek', 'Heiko W. Rupp', 'Jirka Kremser', 'Federico Simoncelli']
  gem.email         = %w(lzoubek@redhat.com hrupp@redhat.com jkremser@redhat.com)
  gem.homepage      = 'https://github.com/hawkular/hawkular-client-ruby'
  gem.summary       = 'A Ruby client for Hawkular'
  gem.license       = 'Apache-2.0'
  gem.required_ruby_version = '>= 2.0.0'
  gem.description = <<-EOS
    A Ruby client for Hawkular
  EOS

  gem.files         = `git ls-files -z`.split("\x0")
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']

  gem.add_runtime_dependency('rest-client', '~> 2.0.0')
  gem.add_runtime_dependency('websocket-client-simple', '~> 0.3.0')
  gem.add_runtime_dependency('addressable')
  gem.add_development_dependency('shoulda')
  gem.add_development_dependency('rspec-rails', '~> 3.1')
  gem.add_development_dependency('rake', '< 11')
  gem.add_development_dependency('simple-websocket-vcr', '= 0.0.7')
  gem.add_development_dependency('yard')
  gem.add_development_dependency('webmock', '~> 1.24.0')
  gem.add_development_dependency('vcr')
  gem.add_development_dependency('rubocop', '= 0.34.2')
  gem.add_development_dependency('coveralls')
  gem.add_development_dependency('rack', '~> 1.6.4')
  gem.add_development_dependency('pry-byebug')

  gem.rdoc_options << '--title' << gem.name <<
    '--main' << 'README.rdoc' << '--line-numbers' << '--inline-source'
  gem.extra_rdoc_files = ['README.rdoc', 'CHANGES.rdoc']
end
