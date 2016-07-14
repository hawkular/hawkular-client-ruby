require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

desc 'Runs all the specs'
RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = './spec/**/*_spec.rb'
  task.rspec_opts = ['--color']
end

desc 'Runs the specs for metrics 0.8.0.Final'
RSpec::Core::RakeTask.new(:'old-metrics') do |task|
  task.pattern = './spec/integration/metric_spec.rb'
  task.rspec_opts = ['--color']
  ENV['SKIP_SERVICES_METRICS'] = '1'
end

RuboCop::RakeTask.new

task default: [:rubocop, :spec]
