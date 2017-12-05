require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

module Hawkular::Prometheus::RSpec
  HAWKULAR_BASE = 'http://localhost:8080/'.freeze
  creds = {}
  options = {}

  describe 'Prometheus/Queries' do
    let(:cassette_name) do |example|
      description = example.description
      description
    end

    around(:each) do |example|
      record('Prometheus/Queries', credentials, cassette_name, example: example)
    end

    before(:each) do
      @client = Hawkular::Prometheus::Client.new(HAWKULAR_BASE, creds, options)
    end

    it 'Should fetch a metrics range' do
      metrics = [{ 'displayName' => 'Heap Used',
                   'family' => 'jvm_memory_bytes_used',
                   'unit' => 'BYTES',
                   'expression' => 'jvm_memory_bytes_used{area="heap",feed_id="attilan"}',
                   'labels' => { area: 'heap', feed_id: 'attilan' } },
                 { 'displayName' => 'NonHeap Used',
                   'family' => 'jvm_memory_bytes_used',
                   'unit' => 'BYTES',
                   'expression' => 'jvm_memory_bytes_used{area="nonheap",feed_id="attilan"}',
                   'labels' => { area: 'nonheap', feed_id: 'attilan' } }]

      results = @client.query_range(metrics: metrics,
                                    starts: '2017-11-28T10:00:00Z',
                                    ends: '2017-11-28T11:00:00Z',
                                    step: '5s')

      first = results.first
      second = results.last
      expect(first['metric']['displayName']).to eq 'Heap Used'
      expect(first['values'].size).to be > 0
      expect(second['metric']['displayName']).to eq 'NonHeap Used'
      expect(second['values'].size).to be > 0
    end

    it 'Should fetch up time' do
      results = @client.up_time(feed_id: 'attilan',
                                starts: '2017-11-28T10:00:00Z',
                                ends: '2017-11-28T15:00:00Z',
                                step: '60m')
      expect(results.size).to be > 0
    end

    it 'Should fetch a metrics instant' do
      metrics = [{ 'displayName' => 'Server Availability',
                   'family' => 'wildfly_server_availability',
                   'unit' => 'AVAILABILITY',
                   'expression' => 'wildfly_server_availability{feed_id="attilan"}',
                   'labels' => { feed_id: 'attilan' } }]

      results = @client.query(metrics: metrics,
                              time: '2017-11-28T10:00:00Z')

      first = results.first
      expect(first['metric']['displayName']).to eq 'Server Availability'
      expect(first['value'].size).to be > 0
    end
  end
end
