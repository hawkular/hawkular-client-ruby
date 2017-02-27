require_relative '../spec_helper'

HOST = 'localhost:8080'
describe Hawkular::Metrics::Client do
  context 'client initialization' do
    it 'should accept no option' do
      credentials = { username: 'mockuser', password: 'mockpass' }
      ::RSpec::Mocks.with_temporary_scope do
        mock_metrics_version
        Hawkular::Metrics::Client.new(HOST, credentials)
      end
    end

    it 'should accept Hawkular-Tenant option' do
      credentials = { username: 'mockuser', password: 'mockpass' }
      ::RSpec::Mocks.with_temporary_scope do
        mock_metrics_version
        @client = Hawkular::Metrics::Client.new(HOST, credentials, tenant: 'foo')
        headers = @client.send(:http_headers)
        expect(headers[:'Hawkular-Tenant']).to eql('foo')
      end
    end

    it 'should define subcomponents' do
      ::RSpec::Mocks.with_temporary_scope do
        mock_metrics_version
        client = Hawkular::Metrics::Client.new HOST
        expect(client.tenants).not_to be nil
        expect(client.counters).not_to be nil
        expect(client.gauges).not_to be nil
      end
    end
  end

  context 'http comms' do
    before(:each) do
      credentials = { username: 'mockuser', password: 'mockpass' }
      ::RSpec::Mocks.with_temporary_scope do
        mock_metrics_version
        @client = Hawkular::Metrics::Client.new(HOST, credentials)
      end
    end

    it 'should add Accept: headers' do
      headers = @client.send(:http_headers)
      expect(headers[:accept]).to eql('application/json')
    end

    it 'should keep existing Accept: headers' do
      value = 'application/json; foo=bar;'
      headers = @client.send(:http_headers, accept: value)
      expect(headers[:accept]).to eql(value)
    end
  end
end
