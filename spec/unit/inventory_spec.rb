require_relative '../spec_helper'

module Hawkular::Inventory::RSpecUnit
  context 'Inventory unit test' do
    include Hawkular::Inventory

    describe 'building response object' do
      it 'should rebuild without chunks' do
        datapoints = [{
          'value' => Base64.encode64('123'),
          'timestamp' => 1000
        }, {
          'value' => Base64.encode64('456'),
          'timestamp' => 999
        }]
        rebuilt = Hawkular::Inventory::Client.rebuild_from_chunks(datapoints)
        expect(rebuilt).to eq('123')
      end

      it 'should rebuild with chunks' do
        datapoints = [{
          'value' => Base64.encode64('123'),
          'timestamp' => 1000,
          'tags' => {
            'chunks' => '3'
          }
        }, {
          'value' => Base64.encode64('456'),
          'timestamp' => 999
        }, {
          'value' => Base64.encode64('789'),
          'timestamp' => 998
        }, {
          'value' => Base64.encode64('111'),
          'timestamp' => 900
        }]
        rebuilt = Hawkular::Inventory::Client.rebuild_from_chunks(datapoints)
        expect(rebuilt).to eq('123456789')
      end

      it 'should not fail on missing data' do
        datapoints = [{
          'value' => Base64.encode64('123'),
          'timestamp' => 1000,
          'tags' => {
            'chunks' => '3'
          }
        }, {
          'value' => Base64.encode64('456'),
          'timestamp' => 999
        }]
        rebuilt = Hawkular::Inventory::Client.rebuild_from_chunks(datapoints)
        expect(rebuilt).to be nil
      end

      it 'should not fail on missing data with old data after' do
        # Timestamps are not consecutive => sanity check must be performed and return nil
        datapoints = [{
          'value' => Base64.encode64('123'),
          'timestamp' => 1000,
          'tags' => {
            'chunks' => '3'
          }
        }, {
          'value' => Base64.encode64('456'),
          'timestamp' => 999
        }, {
          'value' => Base64.encode64('111'),
          'timestamp' => 900
        }, {
          'value' => Base64.encode64('222'),
          'timestamp' => 800
        }]
        rebuilt = Hawkular::Inventory::Client.rebuild_from_chunks(datapoints)
        expect(rebuilt).to be nil
      end
    end
  end
end
