require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"
require 'securerandom'

# examples related to Hawkular Metrics

# time constants
t4h = 4 * 60 * 60 * 1000

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

describe 'No_Tenant' do
  it 'Should fail' do
    id = SecureRandom.uuid

    VCR.use_cassette('No_Tenant/Should fail', erb: { id: id }, record: :none) do
      setup_client

      begin
        @client.counters.push_data(id, value: 4)
      rescue # rubocop:disable Lint/HandleExceptions
        # This is good
      else
        fail 'The call should have failed due to missing tenant'
      end
    end
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

  it 'Should requests raw data for multiple metrics' do
    @client = setup_client(username: 'jdoe', password: 'password', tenant: 'vcr-test')
    ids = [SecureRandom.uuid, SecureRandom.uuid, SecureRandom.uuid]
    VCR.use_cassette('Mixed_metrics/Should requests raw data for multiple metrics',
                     erb: { ids: ids }, record: :none
                    ) do
      expect(@client.counters.raw_data(ids).size).to be 0
      expect(@client.gauges.raw_data(ids).size).to be 0
      expect(@client.avail.raw_data(ids).size).to be 0

      @client.push_data(
        counters: [
          { id: ids[0], data: [{ value: 1 }] },
          { id: ids[1], data: [{ value: 2 }] },
          { id: ids[2], data: [{ value: 3 }] }
        ],
        availabilities: [
          { id: ids[0], data: [{ value: 'up' }] },
          { id: ids[1], data: [{ value: 'down' }] },
          { id: ids[2], data: [{ value: 'up' }] }
        ],
        gauges: [
          { id: ids[0], data: [{ value: 1.1 }] },
          { id: ids[1], data: [{ value: 2.2 }] },
          { id: ids[2], data: [{ value: 3.3 }] }
        ]
      )

      counter_metrics = @client.counters.raw_data(ids)
      gauges_metrics = @client.gauges.raw_data(ids)
      availability_metrics = @client.avail.raw_data(ids)

      expect(counter_metrics.size).to be 3
      expect(counter_metrics).to include(
        { 'id' => ids[0], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 1 }] },
        { 'id' => ids[1], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 2 }] },
        { 'id' => ids[2], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 3 }] }
      )

      expect(gauges_metrics.size).to be 3
      expect(gauges_metrics).to include(
        { 'id' => ids[0], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 1.1 }] },
        { 'id' => ids[1], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 2.2 }] },
        { 'id' => ids[2], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 3.3 }] }
      )

      expect(availability_metrics.size).to be 3
      expect(availability_metrics).to include(
        { 'id' => ids[0], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 'up' }] },
        { 'id' => ids[1], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 'down' }] },
        { 'id' => ids[2], 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 'up' }] }
      )
    end
  end

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
      create_metric_using_hash @client.counters, id, @tenant
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

  it 'Should get metrics with limit and order' do
    @client = setup_client(username: 'jdoe', password: 'password')
    id = SecureRandom.uuid
    now = 1_462_872_284_000

    VCR.use_cassette('Counter_metrics/Should get metrics with limit and order',
                     decode_compressed_response: true,
                     erb: { id: id, ends: now - t4h, starts: now - (2 * t4h),
                            minus10: now - 10, minus20: now - 20, minus30: now - 30,
                            now: now }, record: :none
                    ) do
      # create counter
      @client.counters.create(id: id)

      # push 3 values with timestamps
      @client.counters.push_data(id, [{ value: 1, timestamp: now - 30 },
                                      { value: 2, timestamp: now - 20 },
                                      { value: 3, timestamp: now - 10 }])

      data = @client.counters.get_data(id)
      expect(data.size).to be 3

      # push one value without timestamp (which means now)
      @client.counters.push_data(id, value: 4)
      data = @client.counters.get_data(id)
      expect(data.size).to be 4

      # retrieve values with limit
      data = @client.counters.get_data(id, limit: 1, order: 'DESC')
      expect(data.size).to be 1
      expect(data.first['value']).to be 4

      # retrieve values from past
      data = @client.counters.get_data(id, starts: now - (2 * t4h), ends: now - t4h)
      expect(data.empty?).to be true
    end
  end

  it 'Should get metrics as bucketed results' do
    @client = setup_client(username: 'jdoe', password: 'password')
    id = SecureRandom.uuid
    now = @client.now

    VCR.use_cassette('Counter_metrics/Should get metrics as bucketed results',
                     decode_compressed_response: true,
                     erb: { id: id, now: now }, record: :none
                    ) do
      # create counter
      @client.counters.create(id: id)

      # push 10 values with timestamps
      @client.counters.push_data(id, [{ value: 110, timestamp: now - 110 },
                                      { value: 100, timestamp: now - 100 },
                                      { value: 90, timestamp: now - 90 },
                                      { value: 80, timestamp: now - 80 },
                                      { value: 70, timestamp: now - 70 },
                                      { value: 60, timestamp: now - 60 },
                                      { value: 50, timestamp: now - 50 },
                                      { value: 40, timestamp: now - 40 },
                                      { value: 30, timestamp: now - 30 },
                                      { value: 20, timestamp: now - 20 },
                                      { value: 10, timestamp: now - 10 }])
      ERR = 0.001
      data = @client.counters.get_data(id, starts: now - 105, ends: now - 5, buckets: 5)
      expect(data.size).to be 5
      expect(data.first['avg']).to be_within(ERR).of(95.0)
      expect(data.first['max']).to be_within(ERR).of(100.0)
      expect(data.first['samples']).to be 2

      data = @client.counters.get_data(id, starts: now - 105, ends: now - 5, buckets: 2)
      expect(data.size).to be 2
      expect(data.first['avg']).to be_within(ERR).of(80.0)
      expect(data.first['samples']).to be 5

      data = @client.counters.get_data(id, starts: now - 105, ends: now - 5, bucketDuration: '50ms')
      expect(data.size).to be 2
      expect(data.first['avg']).to be_within(ERR).of(80.0)
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
      create_metric_using_hash @client.avail, id, @tenant
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
      create_metric_using_hash @client.gauges, id, @tenant
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

  it 'Should return platform memory def' do
    tenant_id = '28026b36-8fe4-4332-84c8-524e173a68bf'
    setup_client tenant: tenant_id

    VCR.use_cassette('Gauge_metrics/Platform mem def') do
      # The next id is not a real one, but shortened for rubocpo
      mem_id = 'MI~R~[snert~platform~/OP_SYSTEM=Apple (Capitan) 42/MEMORY=Mem]~MT~Total Memory'
      data = @client.gauges.get(mem_id)

      expect(data).not_to be_nil
      expect(data.id).not_to be_nil
      expect(data.tenant_id).to eq(tenant_id)
    end
  end

  it 'Should return platform memory' do
    setup_client tenant: '28026b36-8fe4-4332-84c8-524e173a68bf'

    VCR.use_cassette('Gauge_metrics/Platform mem') do
      # The next id is not a real one, but shortened for rubocpo
      mem_id = 'MI~R~[snert~platform~/OP_SYSTEM=Apple (Capitan) 42/MEMORY=Mem]~MT~Total Memory'
      data = @client.gauges.get_data(mem_id)
      expect(data.size).to be 71
    end
  end

  it 'Should return the version' do
    VCR.use_cassette('Metrics/Status') do
      data = @client.fetch_version_and_status
      expect(data).not_to be_nil
    end
  end
end
