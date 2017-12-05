require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

module Hawkular::Prometheus::RSpec
  HAWKULAR_BASE = 'http://localhost:8080/'
  creds = {
    username: 'jdoe',
    password: 'password'
  }
  options = {}

  describe 'Prometheus/Queries' do
    let(:cassette_name) do |example|
      description = example.description
      description
    end

    let(:inventory_client) do
      Hawkular::Inventory::Client.new(HAWKULAR_BASE, creds, options)
    end

    let(:prometheus_client) do
      Hawkular::Prometheus::Client.new(HAWKULAR_BASE, creds, options)
    end

    around(:each) do |example|
      record('Prometheus/Queries', credentials, cassette_name, example: example)
    end

    it 'Should fetch a metrics range' do
      metrics = inventory_client
                .resources_for_type('WildFly Server WF10')
                .first
                .metrics
                .select { |metric| ['Heap Used', 'NonHeap Used'].include?(metric.name) }
                .map(&:to_h)

      now = '2017-11-05T11:25:00Z'
      before = '2017-11-05T11:20:00Z'

      results = prometheus_client.query_range(metrics: metrics,
                                              starts: before,
                                              ends: now,
                                              step: '5s')

      first = results.first
      second = results.last
      expect(first['metric']['displayName']).to eq 'Heap Used'
      expect(second['metric']['displayName']).to eq 'NonHeap Used'
    end

    it 'Should fetch up time' do
      feed_id = inventory_client
                .resources_for_type('WildFly Server WF10')
                .first
                .feed

      now = '2017-11-05T11:25:00Z'
      before = '2017-11-05T11:20:00Z'

      results = prometheus_client.up_time(feed_id: feed_id,
                                          starts: before,
                                          ends: now,
                                          step: '5s')
      expect(results).to be_truthy
    end

    it 'Should fetch a metrics instant' do
      metrics = inventory_client
                .resources_for_type('WildFly Server WF10')
                .first
                .metrics
                .select { |metric| ['Server Availability'].include?(metric.name) }
                .map(&:to_h)

      now = '2017-11-05T11:25:00Z'

      results = prometheus_client.query(metrics: metrics,
                                        time: now)

      first = results.first
      expect(first['metric']['displayName']).to eq 'Server Availability'
    end
  end
end
