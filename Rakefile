require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

desc 'Runs all the specs'
RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = './spec/**/*_spec.rb'
  task.rspec_opts = ['--color']
end

desc 'Runs the specs for the inventory 0.16.x (old REST API)'
RSpec::Core::RakeTask.new(:'old-inventory') do |task|
  task.pattern = './spec/integration/inventory_spec.rb'
  task.rspec_opts = ['--color']
  task.ruby_opts = ['INVENTORY_VERSION=0.16.2.Final']
end

RuboCop::RakeTask.new

task default: [:rubocop, :spec, :'old-inventory']
