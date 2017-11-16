require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

module Hawkular::Prometheus::RSpec
  HAWKULAR_BASE = 'http://localhost:8080/'
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
    it 'Should Fetch Metrics' do
      metrics = [
        Hawkular::Inventory::Metric.new('displayName' => 'Heap Used',
                                        'family' => 'jvm_memory_bytes_used',
                                        'unit' => 'BYTES',
                                        'labels' => { area: 'heap', feed_id: 'attilan' }),
        Hawkular::Inventory::Metric.new('displayName' => 'NonHeap Used',
                                        'family' => 'jvm_memory_bytes_used',
                                        'unit' => 'BYTES',
                                        'labels' => { area: 'nonheap', feed_id: 'attilan' })
      ]

      results = @client.query_range(metrics: metrics,
                                    starts: '2017-11-17T14:48:00Z',
                                    ends: '2017-11-17T14:49:00Z',
                                    step: '5s')

      expect(results.map { |r| r['metric'].name }).to include('Heap Used', 'NonHeap Used')
      expect(results[0]['values'].size).to be > 0
      expect(results[1]['values'].size).to be > 0
    end
  end
end
