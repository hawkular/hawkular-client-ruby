# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'metrics/version'

Gem::Specification.new do |gem|
  gem.name          = "hawkular-client"
  gem.version       = Hawkular::Metrics::VERSION
  gem.authors       = ['Libor Zoubek']
  gem.email         = ['lzoubek@redhat.com']
  gem.homepage      = "https://github.com/hawkular/hawkular-client-ruby"
  gem.summary       = %q{A Ruby client for Hawkular}
  gem.description   = <<-EOS
    A Ruby client for Hawkular
  EOS

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency('rest-client')
  gem.add_development_dependency('shoulda')
  gem.add_development_dependency('rspec-rails', '~> 2.6')
  gem.add_development_dependency('rake')
  gem.add_development_dependency('yard')
  gem.add_development_dependency('webmock')
  gem.add_development_dependency('vcr')

  gem.rdoc_options << '--title' << gem.name << '--main' << 'README.rdoc' << '--line-numbers' << '--inline-source'
  gem.extra_rdoc_files = ['README.rdoc', 'CHANGES.rdoc']
end
