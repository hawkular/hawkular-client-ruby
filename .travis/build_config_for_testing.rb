#!/usr/bin/env ruby
require 'yaml'

exit unless ARGV.size == 1

filename = ARGV[0]
config = YAML.load_file filename

config['metric-set-dmr'].each do |metric_set_dmr|
  metric_set_dmr['metric-dmr'].each do |metric_dmr|
    next unless metric_dmr['name'] == 'Heap Used'
    metric_dmr['interval'] = 5
    metric_dmr['time-units'] = 'seconds'
  end
end

config['platform']['memory'] =  { 'interval' => 5, 'time-units' => 'seconds' }

# Ping more frequently
config['subsystem']['ping-period-secs'] = 5

File.open(filename, 'w') do |f|
  YAML.dump(config, f)
end
