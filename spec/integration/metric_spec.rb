require "#{File.dirname(__FILE__)}/../spec_helper"
require 'securerandom'

# examples related to Hawkular Metrics

# time constants
t4h = 4 * 60 * 60 * 1000

# more or less generic methodc common for all metric types (counters,
# gauges, availabilities)
def create_metric_using_hash(endpoint)
  id = SecureRandom.uuid
  endpoint.create(id: id, data_retention: 123, tags: { some: 'value' },
                  tenant_id: @tenant)
  metric = endpoint.get(id)

  expect(metric).to be_a(Hawkular::Metrics::MetricDefinition)
  expect(metric.id).to eql(id)
  expect(metric.data_retention).to eql(123)
  expect(metric.tenant_id).to eql(@tenant)
end

def create_metric_using_md(endpoint)
  metric = Hawkular::Metrics::MetricDefinition.new
  metric.id = SecureRandom.uuid
  metric.data_retention = 90
  metric.tags = { tag: 'value' }
  endpoint.create(metric)

  created = endpoint.get(metric.id)
  expect(created).to be_a(Hawkular::Metrics::MetricDefinition)
  expect(created.id).to eql(metric.id)
  expect(created.data_retention).to eql(metric.data_retention)
end

def push_data_to_non_existing_metric(endpoint, data)
  id = SecureRandom.uuid
  # push one value without timestamp (which means now)
  endpoint.push_data(id, data)

  data = endpoint.get_data(id)
  expect(data.size).to be 1

  # verify metric was auto-created
  counter = endpoint.get(id)
  expect(counter).to be_a(Hawkular::Metrics::MetricDefinition)
  expect(counter.id).to eql(id)
end

def update_metric_by_tags(endpoint)
  id = SecureRandom.uuid
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

describe 'Tenants' do
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

  it 'Should send mixed metric request' do
    id = SecureRandom.uuid

    expect(@client.counters.get_data(id).size).to be 0
    expect(@client.gauges.get_data(id).size).to be 0
    expect(@client.avail.get_data(id).size).to be 0

    @client.push_data(
      counters:       [{ id: id, data: [{ value: 1 }] }],
      availabilities: [{ id: id, data: [{ value: 'down' }] }],
      gauges:         [{ id: id, data: [{ value: 1.1 }] }]
    )

    expect(@client.counters.get_data(id).size).to be 1
    expect(@client.gauges.get_data(id).size).to be 1
    expect(@client.avail.get_data(id).size).to be 1
  end
end

describe 'Counter metrics' do
  before(:all) do
    setup_client_new_tenant
  end

  it 'Should create and return counter using Hash parameter' do
    create_metric_using_hash @client.counters
  end

  it 'Should create counter definition using MetricDefinition parameter' do
    create_metric_using_md @client.counters
  end

  it 'Should push metric data to existing counter' do
    id = SecureRandom.uuid
    # create counter
    @client.counters.create(id: id)
    now = @client.now

    # push 3  values with timestamps
    @client.counters.push_data(id, [
      { value: 1, timestamp: now - 30 },
      { value: 2, timestamp: now - 20 },
      { value: 3, timestamp: now - 10 }
    ])

    data = @client.counters.get_data(id)
    expect(data.size).to be 3

    # push one value without timestamp (which means now)
    @client.counters.push_data(id, value: 4)
    data = @client.counters.get_data(id)
    expect(data.size).to be 4

    # retrieve values from past
    data = @client.counters.get_data(id, starts: @client.now - (2 * t4h),
                                         ends: @client.now - t4h)
    expect(data.empty?).to be true
  end

  it 'Should push metric data to non-existing counter' do
    push_data_to_non_existing_metric(@client.counters, value: 4)
  end
end

describe 'Availability metrics' do
  before(:all) do
    setup_client_new_tenant
  end

  it 'Should create and return Availability using Hash parameter' do
    create_metric_using_hash(@client.avail)
  end

  it 'Should create Availability definition using MetricDefinition parameter' do
    create_metric_using_md(@client.avail)
  end

  it 'Should push metric data to non-existing Availability' do
    push_data_to_non_existing_metric(@client.avail, value: 'UP')
  end
  it 'Should update tags for Availability definition' do
    update_metric_by_tags(@client.avail)
  end
end

describe 'Gauge metrics' do
  before(:all) do
    setup_client_new_tenant
  end

  it 'Should create gauge definition using MetricDefinition' do
    create_metric_using_md(@client.gauges)
  end

  it 'Should create gauge definition using Hash' do
    create_metric_using_hash(@client.gauges)
  end

  it 'Should push metric data to non-existing gauge' do
    push_data_to_non_existing_metric(@client.gauges, value: 3.1415926)
  end

  it 'Should push metric data to existing gauge' do
    id = SecureRandom.uuid
    # create gauge
    @client.gauges.create(id: id)
    now = @client.now

    # push 3  values with timestamps
    @client.gauges.push_data(id, [
      { value: 1, timestamp: now - 30 },
      { value: 2, timestamp: now - 20 },
      { value: 3, timestamp: now - 10 }
    ])

    data = @client.gauges.get_data(id)
    expect(data.size).to be 3

    # push one value without timestamp (which means now)
    @client.gauges.push_data(id, value: 4)
    data = @client.gauges.get_data(id)
    expect(data.size).to be 4

    # retrieve values from past
    data = @client.counters.get_data(id, starts: @client.now - (2 * t4h),
                                         ends: @client.now - t4h)
    expect(data.empty?).to be true
  end

  it 'Should update tags for gauge definition' do
    update_metric_by_tags @client.gauges
  end

  it 'Should return periods' do
    id = SecureRandom.uuid
    now = @client.now
    # push 3  values with timestamps
    @client.gauges.push_data(id, [
      { value: 1, timestamp: now - 30 },
      { value: 2, timestamp: now - 20 },
      { value: 3, timestamp: now }
    ])

    before4h = @client.now - t4h
    data = @client.gauges.get_periods(id, operation: 'lte', threshold: 4,
                                          starts: before4h)
    expect(data.size).to be 1
    expect(data[0][0]).to eql(now - 30)
    expect(data[0][1]).to eql(now)
  end
end
