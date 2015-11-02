require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"
require 'securerandom'

# examples related to Hawkular Metrics

# time constants
t4h = 4 * 60 * 60 * 1000

# more or less generic method common for all metric types (counters, gauges, availabilities)
def create_metric_using_hash(endpoint, id)
  endpoint.create(id: id, dataRetention: 123, tags: { some: 'value' }, tenantId: @tenant)
  metric = endpoint.get(id)

  expect(metric).to be_a(Hawkular::Metrics::MetricDefinition)
  expect(metric.id).to eql(id)
  expect(metric.data_retention).to eql(123)
  expect(metric.tenant_id).to eql(@tenant)
end

def create_metric_using_md(endpoint, id)
  metric = Hawkular::Metrics::MetricDefinition.new
  metric.id = id
  metric.data_retention = 90
  metric.tags = { tag: 'value' }
  endpoint.create(metric)

  created = endpoint.get(metric.id)
  expect(created).to be_a(Hawkular::Metrics::MetricDefinition)
  expect(created.id).to eql(metric.id)
  expect(created.data_retention).to eql(metric.data_retention)
end

def push_data_to_non_existing_metric(endpoint, data, id)
  # push one value without timestamp (which means now)
  endpoint.push_data(id, data)

  data = endpoint.get_data(id)
  expect(data.size).to be 1

  # verify metric was auto-created
  counter = endpoint.get(id)
  expect(counter).to be_a(Hawkular::Metrics::MetricDefinition)
  expect(counter.id).to eql(id)
end

def update_metric_by_tags(endpoint, id)
  endpoint.create(id: id, tags: { myTag: id })
  metric = endpoint.get(id)
  metric.tags = { newTag: 'newValue' }
  endpoint.update_tags(metric)

  metric = endpoint.get(id)
  expect(metric.tags).to include('newTag' => 'newValue', 'myTag' => id)

  # query API for a metric with given tag
  data = endpoint.query(myTag: id)
  expect(data.size).to be 1
end

describe 'Simple', :vcr do
  it 'Should be Cool' do
    Net::HTTP.get_response(URI('http://localhost:8080/'))
  end
end

describe 'Tenants', vcr: { match_requests_on: [:uri, :method], record: :none } do
  before(:all) do
    setup_client
  end

  it 'Should create and return tenant' do
    tenant = SecureRandom.uuid
    @client.tenants.create(tenant)
    created = @client.tenants.query.select { |t| t.id == tenant }
    expect(created).not_to be nil
  end
end

describe 'Mixed metrics' do
  before(:all) do
    setup_client_new_tenant
  end

  it 'Should send mixed metric request of a single type' do
    id = SecureRandom.uuid

    VCR.use_cassette('Mixed_metrics/Should send mixed metric request of a single type',
                     erb: { id: id }, record: :none
                    ) do
      @client.push_data(counters: [{ id: id, data: [{ value: 1 }] }])
      data = @client.counters.get_data(id)
      expect(data.size).to be 1

      @client.push_data(availabilities: [{ id: id, data: [{ value: 'down' }] }])
      data = @client.avail.get_data(id)
      expect(data.size).to be 1

      @client.push_data(gauges: [{ id: id, data: [{ value: 1.1 }] }])
      data = @client.gauges.get_data(id)
      expect(data.size).to be 1
    end
  end
  #  end

  it 'Should send mixed metric request' do
    id = SecureRandom.uuid
    VCR.use_cassette('Mixed_metrics/Should send mixed metric request',
                     erb: { id: id }, record: :none
                    ) do
      expect(@client.counters.get_data(id).size).to be 0
      expect(@client.gauges.get_data(id).size).to be 0
      expect(@client.avail.get_data(id).size).to be 0

      @client.push_data(
        counters: [{ id: id, data: [{ value: 1 }] }],
        availabilities: [{ id: id, data: [{ value: 'down' }] }],
        gauges: [{ id: id, data: [{ value: 1.1 }] }]
      )

      expect(@client.counters.get_data(id).size).to be 1
      expect(@client.gauges.get_data(id).size).to be 1
      expect(@client.avail.get_data(id).size).to be 1
    end
  end
end

describe 'Counter metrics' do
  before(:all) do
    setup_client_new_tenant
  end

  it 'Should create and return counter using Hash parameter' do
    id = SecureRandom.uuid
    VCR.use_cassette('Counter_metrics/Should create and return counter using Hash parameter',
                     erb: { id: id }, record: :none
                    ) do
      create_metric_using_hash @client.counters, id
    end
  end

  it 'Should create counter definition using MetricDefinition parameter' do
    id = SecureRandom.uuid
    VCR.use_cassette(
      'Counter_metrics/Should create counter definition using MetricDefinition parameter',
      erb: { id: id }, record: :none
    ) do
      create_metric_using_md @client.counters, id
    end
  end

  it 'Should push metric data to existing counter' do
    id = SecureRandom.uuid
    now = @client.now

    VCR.use_cassette('Counter_metrics/Should push metric data to existing counter',
                     erb: { id: id, ends: now - t4h, starts: now - (2 * t4h),
                            minus20: now - 20, minus30: now - 30, minus10: now - 10,
                            now: now }, record: :none
                    ) do
      # create counter
      @client.counters.create(id: id)

      # push 3  values with timestamps
      @client.counters.push_data(id, [{ value: 1, timestamp: now - 30 },
                                      { value: 2, timestamp: now - 20 },
                                      { value: 3, timestamp: now - 10 }])

      data = @client.counters.get_data(id)
      expect(data.size).to be 3

      # push one value without timestamp (which means now)
      @client.counters.push_data(id, value: 4)
      data = @client.counters.get_data(id)
      expect(data.size).to be 4

      # retrieve values from past
      data = @client.counters.get_data(id, starts: now - (2 * t4h), ends: now - t4h)
      expect(data.empty?).to be true
    end
  end

  it 'Should push metric data to non-existing counter' do
    id = SecureRandom.uuid

    VCR.use_cassette('Counter_metrics/Should push metric data to non-existing counter',
                     erb: { id: id }, record: :none
                    ) do
      push_data_to_non_existing_metric @client.counters, { value: 4 }, id
    end
  end
end

describe 'Availability metrics' do
  before(:all) do
    setup_client_new_tenant
  end

  it 'Should create and return Availability using Hash parameter' do
    id = SecureRandom.uuid
    VCR.use_cassette(
      'Availability_metrics/Should create and return Availability using Hash parameter',
      erb: { id: id }, record: :none
    ) do
      create_metric_using_hash @client.avail, id
    end
  end

  it 'Should create Availability definition using MetricDefinition parameter' do
    id = SecureRandom.uuid
    VCR.use_cassette(
      'Availability_metrics/Should create Availability definition using MetricDefinition parameter',
      erb: { id: id }, record: :none
    ) do
      create_metric_using_md @client.avail, id
    end
  end

  it 'Should push metric data to non-existing Availability' do
    id = SecureRandom.uuid

    VCR.use_cassette('Availability_metrics/Should push metric data to non-existing Availability',
                     erb: { id: id }, record: :none
                    ) do
      push_data_to_non_existing_metric @client.avail, { value: 'UP' }, id
    end
  end

  it 'Should update tags for Availability definition' do
    id = SecureRandom.uuid

    VCR.use_cassette('Availability_metrics/Should update tags for Availability definition',
                     erb: { id: id }, record: :none
                    ) do
      update_metric_by_tags @client.avail, id
    end
  end
end

describe 'Gauge metrics' do
  before(:all) do
    setup_client_new_tenant
  end

  it 'Should create gauge definition using MetricDefinition' do
    id = SecureRandom.uuid

    VCR.use_cassette('Gauge_metrics/Should create gauge definition using MetricDefinition',
                     erb: { id: id }, record: :none
                    ) do
      create_metric_using_md @client.gauges, id
    end
  end

  it 'Should create gauge definition using Hash' do
    id = SecureRandom.uuid

    VCR.use_cassette('Gauge_metrics/Should create gauge definition using Hash',
                     erb: { id: id }, record: :none
                    ) do
      create_metric_using_hash @client.gauges, id
    end
  end

  it 'Should push metric data to non-existing gauge' do
    id = SecureRandom.uuid

    VCR.use_cassette('Gauge_metrics/Should push metric data to non-existing gauge',
                     erb: { id: id }, record: :none
                    ) do
      push_data_to_non_existing_metric @client.gauges, { value: 3.1415926 }, id
    end
  end

  it 'Should push metric data to existing gauge' do
    id = SecureRandom.uuid
    now = @client.now

    VCR.use_cassette('Gauge_metrics/Should push metric data to existing gauge',
                     erb: { id: id, ends: now - t4h, starts: now - (2 * t4h) }, record: :none
                    ) do
      # create gauge
      @client.gauges.create(id: id)

      # push 3  values with timestamps
      @client.gauges.push_data(id,
                               [{ value: 1, timestamp: now - 30 },
                                { value: 2, timestamp: now - 20 },
                                { value: 3, timestamp: now - 10 }])

      data = @client.gauges.get_data(id)
      expect(data.size).to be 3

      # push one value without timestamp (which means now)
      @client.gauges.push_data(id, value: 4)
      data = @client.gauges.get_data(id)
      expect(data.size).to be 4

      # retrieve values from past
      data = @client.counters.get_data(id, starts: now - (2 * t4h), ends: now - t4h)
      expect(data.empty?).to be true
    end
  end

  it 'Should update tags for gauge definition' do
    id = SecureRandom.uuid

    VCR.use_cassette('Gauge_metrics/Should update tags for gauge definition',
                     erb: { id: id }, record: :none
                    ) do
      update_metric_by_tags @client.gauges, id
    end
  end

  it 'Should return periods' do
    id = SecureRandom.uuid
    now = @client.now
    before4h = now - t4h

    VCR.use_cassette('Gauge_metrics/Should return periods',
                     erb: {  id: id, start: now, before4h: before4h,
                             minus20: now - 20, minus30: now - 30 },
                     record: :none) do
      # push 3  values with timestamps
      @client.gauges.push_data(id, [{ value: 1, timestamp: now - 30 },
                                    { value: 2, timestamp: now - 20 },
                                    { value: 3, timestamp: now }])

      data = @client.gauges.get_periods(id, operation: 'lte', threshold: 4, starts: before4h)
      expect(data.size).to be 1
      expect(data[0][0]).to eql(now - 30)
      expect(data[0][1]).to eql(now)
    end
  end
end
