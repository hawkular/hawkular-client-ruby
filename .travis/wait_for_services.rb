#!/usr/bin/env ruby
require 'net/http'
require 'json'

services = {
  'hawkular-services' => {
    url: 'http://localhost:8080/hawkular/status',
    is_ready: -> (response) { response.code == '200' }
  },
  'metrics' => {
    url: 'http://localhost:8080/hawkular/metrics/status',
    is_ready: -> (response) { response.code == '200' && JSON.parse(response.body)['MetricsService'] == 'STARTED' }
  },
  'alerts' => {
    url: 'http://localhost:8080/hawkular/alerts/status',
    is_ready: -> (response) { response.code == '200' && JSON.parse(response.body)['status'] == 'STARTED' }
  }
}

wait_time = 5
max_attempts = 50

attempt = 0
services.each do |name, service|
  loop do
    uri = URI(service[:url])
    begin
      response = Net::HTTP.get_response(uri)
      break if service[:is_ready].call(response)
      puts "Waiting for: #{name}"
    rescue
      puts 'Waiting for Hawkular-Services to accept connections'
    end
    if attempt < max_attempts
      sleep wait_time
      attempt += 1
    else
      puts "Can't connect to [#{name}] using url [#{service[:url]}] after [#{attempt}] attemps"
      exit 1
    end
  end
end
puts 'Waiting 1 minute for agent to complete it\'s first round...'
sleep 60
puts 'Hawkular-services started successfully... '
