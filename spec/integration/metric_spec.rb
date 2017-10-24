require_relative '../vcr/vcr_setup'
require_relative '../spec_helper'

require 'securerandom'

SKIP_SECURE_CONTEXT = ENV['SKIP_SECURE_CONTEXT'] || '1'
SKIP_SECURE_CONTEXT.freeze

# examples related to Hawkular Metrics

# time constants
t4h = 4 * 60 * 60 * 1000

# test contexts
v8_context = :metrics_0_8_0
services_context = :metrics_services

# ssl contexts
SECURE_CONTEXT = :Secure
NON_SECURE_CONTEXT = :NonSecure

security_contexts = [NON_SECURE_CONTEXT, SECURE_CONTEXT].freeze
vcr_test_tenant_postfix = "-vcr-tenant-#{SecureRandom.uuid}".freeze

security_contexts.each do |security_context|
  next if security_context == SECURE_CONTEXT && SKIP_SECURE_CONTEXT == '1'

  [v8_context, services_context].each do |metrics_context|
    if ENV['SKIP_V8_METRICS'] == '1' && metrics_context == v8_context
      puts 'skipping v8 metrics'
      next
    end
    if ENV['SKIP_SERVICES_METRICS'] == '1' && metrics_context == services_context
      puts 'skipping services metrics'
      next
    end
    # Secure context not supported for v8
    next if security_context == SECURE_CONTEXT && metrics_context == v8_context

    setup_options = {
      type: security_context
    }.freeze

    describe "#{metrics_context} #{security_context}" do
      vcr_test_tenant = "#{security_context}#{metrics_context}#{vcr_test_tenant_postfix}".freeze

      let(:cassette_name) do |example|
        if example.respond_to?(:example_group) && !example.example_group.description.start_with?(metrics_context.to_s)
          example.example_group.description + '/'
        else
          ''
        end + example.description
      end

      before(:all) do
        @admin_token = ENV['ADMIN_TOKEN'] || SecureRandom.uuid
      end

      let(:vcr_bindings) do
        { id: @random_id, vcr_test_tenant: vcr_test_tenant, admin_token: @admin_token }
      end

      around(:each) do |example|
        run_for = example.metadata[:run_for]
        if run_for.nil? || run_for.empty? || run_for.include?(metrics_context)
          @random_id = SecureRandom.uuid
          if example.metadata[:skip_auto_vcr]
            example.run
          else
            record("Metrics/#{security_context}/#{metrics_context}",
                   vcr_bindings,
                   cassette_name,
                   example: example)
          end
        end
      end

      after(:all) do
        record_cleanup("Metrics/#{security_context}/#{metrics_context}")
      end

      describe 'Simple' do
        it 'Should be Cool' do
          url = metrics_context == v8_context ? entrypoint('v8', 'metrics') : entrypoint(security_context, 'metrics')
          Net::HTTP.get_response(URI(url))
        end
      end

      describe 'Tenants', run_for: [v8_context, services_context] do
        before(:all) do
          options = setup_options.merge admin_token: @admin_token
          record("Metrics/#{security_context}/#{metrics_context}",
                 options,
                 'Tenants/setup_client') do
            if metrics_context == v8_context
              setup_v8_client
            else
              setup_client(options)
            end
          end
        end

        it 'Should create and return tenant' do
          tenant = @random_id
          @client.tenants.create(tenant)
          created = @client.tenants.query.select { |t| t.id == tenant }
          expect(created).not_to be nil
        end
      end

      describe 'No Tenant', run_for: [services_context] do
        it 'Should fail' do
          setup_client_without_tenant(setup_options)
          begin
            @client.counters.push_data(@random_id, value: 4)
          rescue # rubocop:disable Lint/HandleExceptions
            # This is good
          else
            fail 'The call should have failed due to missing tenant'
          end
        end
      end

      describe 'Mixed metrics', run_for: [v8_context, services_context] do
        before(:all) do
          options = setup_options.merge(tenant: vcr_test_tenant)
          record("Metrics/#{security_context}/#{metrics_context}",
                 options,
                 'Mixed_metrics/setup_client') do
            if metrics_context == v8_context
              setup_v8_client tenant: vcr_test_tenant
            else
              setup_client(setup_options)
            end
          end
        end

        it 'Should requests raw data for multiple metrics', :skip_auto_vcr, run_for: [services_context] do
          id1 = SecureRandom.uuid
          id2 = SecureRandom.uuid
          id3 = SecureRandom.uuid
          id4 = SecureRandom.uuid

          ids = [id1, id2, id3]
          bindings = { id1: id1, id2: id2, id3: id3, id4: id4 }
          example = proc do
            @client = setup_client(setup_options.merge tenant: vcr_test_tenant)

            expect(@client.counters.raw_data(ids).size).to be 0
            expect(@client.gauges.raw_data(ids).size).to be 0
            expect(@client.avail.raw_data(ids).size).to be 0

            @client.push_data(
              counters: [
                { id: id1, data: [{ value: 1 }] },
                { id: id2, data: [{ value: 2 }] },
                { id: id3, data: [{ value: 3 }] }
              ],
              availabilities: [
                { id: id1, data: [{ value: 'up' }] },
                { id: id2, data: [{ value: 'down' }] },
                { id: id3, data: [{ value: 'up' }] },
                { id: id4, data: [{ value: 'up', timestamp: 10_000 },
                                  { value: 'down', timestamp: 100_000 },
                                  { value: 'admin', timestamp: 1_000_000 }] }
              ],
              gauges: [
                { id: id1, data: [{ value: 1.1 }] },
                { id: id2, data: [{ value: 2.2 }] },
                { id: id3, data: [{ value: 3.3 }] }
              ]
            )

            c_metrics = @client.counters.raw_data(ids)
            g_metrics = @client.gauges.raw_data(ids)
            a_metrics = @client.avail.raw_data(ids)
            # also check the get_data way of fetching avail data, with params
            a_metric  = @client.avail.get_data(id4, starts: 100, ends: 2_000_000, distinct: 'true', order: 'ASC')
            expect(c_metrics.size).to be 3
            expect(c_metrics).to include(
              { 'id' => id1, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 1 }] },
              { 'id' => id2, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 2 }] },
              { 'id' => id3, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 3 }] }
            )

            expect(g_metrics.size).to be 3
            expect(g_metrics).to include(
              { 'id' => id1, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 1.1 }] },
              { 'id' => id2, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 2.2 }] },
              { 'id' => id3, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 3.3 }] }
            )

            expect(a_metrics.size).to be 3
            expect(a_metrics).to include(
              { 'id' => id1, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 'up' }] },
              { 'id' => id2, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 'down' }] },
              { 'id' => id3, 'data' => [{ 'timestamp' => a_kind_of(Integer), 'value' => 'up' }] }
            )

            expect(a_metric.size).to be 3
            expect(a_metric).to include(
              { 'timestamp' => 10_000, 'value' => 'up' },
              { 'timestamp' => 100_000, 'value' => 'down' },
              { 'timestamp' => 1_000_000, 'value' => 'admin' }
            )
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end

        it 'Should send mixed metric request of a single type' do
          @client.push_data(counters: [{ id: @random_id, data: [{ value: 1 }] }])
          data = @client.counters.get_data(@random_id)
          expect(data.size).to be 1

          @client.push_data(availabilities: [{ id: @random_id, data: [{ value: 'down' }] }])
          data = @client.avail.get_data(@random_id)
          expect(data.size).to be 1

          @client.push_data(gauges: [{ id: @random_id, data: [{ value: 1.1 }] }])
          data = @client.gauges.get_data(@random_id)
          expect(data.size).to be 1
        end

        it 'Should send mixed metric request' do
          expect(@client.counters.get_data(@random_id).size).to be 0
          expect(@client.gauges.get_data(@random_id).size).to be 0
          expect(@client.avail.get_data(@random_id).size).to be 0

          @client.push_data(
            counters: [{ id: @random_id, data: [{ value: 1 }] }],
            availabilities: [{ id: @random_id, data: [{ value: 'down' }] }],
            gauges: [{ id: @random_id, data: [{ value: 1.1 }] }]
          )

          expect(@client.counters.get_data(@random_id).size).to be 1
          expect(@client.gauges.get_data(@random_id).size).to be 1
          expect(@client.avail.get_data(@random_id).size).to be 1
        end

        it 'Should fetch stats for mixed metric', run_for: [services_context] do
          expect(@client.counters.get_data(@random_id).size).to be 0
          expect(@client.gauges.get_data(@random_id).size).to be 0
          expect(@client.avail.get_data(@random_id).size).to be 0

          @client.push_data(
            counters: [{ id: @random_id, data: [{ value: 1 }] }],
            availabilities: [{ id: @random_id, data: [{ value: 'down' }] }],
            gauges: [{ id: @random_id, data: [{ value: 1.1 }] }]
          )

          timestamps = []
          timestamps.push(@client.counters.get_data(@random_id).first['timestamp'])
          timestamps.push(@client.gauges.get_data(@random_id).first['timestamp'])
          timestamps.push(@client.avail.get_data(@random_id).first['timestamp'])

          stats = @client.query_stats(
            gauge_ids: [@random_id],
            counter_ids: [@random_id],
            avail_ids: [@random_id],
            starts: timestamps.min,
            ends: timestamps.max + 1,
            bucket_duration: "#{timestamps.max - timestamps.min + 1}ms"
          )

          expect(stats.size).to be 3
          expect(stats['gauge'][@random_id].first['avg']).to be 1.1
          expect(stats['counter'][@random_id].first['avg']).to be 1.0
          expect(stats['availability'][@random_id].first['downtimeCount']).to be 1
        end

        it 'Should fetch rate stats for mixed metric', run_for: [services_context] do
          expect(@client.counters.get_data(@random_id).size).to be 0

          @client.push_data(counters: [{ id: @random_id, data: [{ value: 100.0 }] }])
          @client.push_data(counters: [{ id: @random_id, data: [{ value: 110.0 }] }])
          @client.push_data(counters: [{ id: @random_id, data: [{ value: 130.0 }] }])
          @client.push_data(counters: [{ id: @random_id, data: [{ value: 200.0 }] }])

          data = @client.counters.get_data(@random_id)
          expect(data.size).to be 4
          timestamps = data.map { |d| d['timestamp'] }

          stats = @client.query_stats(
            counter_ids: [@random_id],
            starts: timestamps.min,
            ends: timestamps.max + 1,
            rates: true,
            bucket_duration: "#{timestamps.max - timestamps.min + 1}ms"
          )

          expect(stats.size).to be 2
          expect(stats['counter'][@random_id].size).to be 1
          expect(stats['counter_rate'][@random_id].size).to be 1
        end
      end

      describe 'Counter metrics' do
        before(:all) do
          @tenant = vcr_test_tenant
          options = setup_options.merge(tenant: @tenant)
          record("Metrics/#{security_context}/#{metrics_context}",
                 options,
                 'Counter_metrics/setup_client') do
            if metrics_context == v8_context
              setup_v8_client tenant: @tenant
            else
              setup_client(setup_options.merge(tenant: @tenant))
            end
          end
        end

        it 'Should create and return counter using Hash parameter' do
          create_metric_using_hash @client.counters, @random_id, @tenant
        end

        it 'Should create counter definition using MetricDefinition parameter' do
          create_metric_using_md @client.counters, @random_id
        end

        it 'Should push metric data to existing counter', :skip_auto_vcr do
          now = @client.now
          minus10 = now - 10
          minus20 = now - 20
          minus30 = now - 30
          minus8h = now - (2 * t4h)
          minus4h = now - t4h

          bindings = { id: @random_id, minus10: minus10, minus20: minus20, minus30: minus30,
                       minus8h: minus8h, minus4h: minus4h }
          example = proc do
            # create counter
            @client.counters.create(id: @random_id)

            # push 3  values with timestamps
            @client.counters.push_data(@random_id, [{ value: 1, timestamp: minus30 },
                                                    { value: 2, timestamp: minus20 },
                                                    { value: 3, timestamp: minus10 }])

            data = @client.counters.get_data(@random_id)
            expect(data.size).to be 3

            # push one value without timestamp (which means now)
            @client.counters.push_data(@random_id, value: 4)
            data = @client.counters.get_data(@random_id)
            expect(data.size).to be 4

            # retrieve values from past
            data = @client.counters.get_data(@random_id, starts: minus8h, ends: minus4h)
            expect(data.empty?).to be true
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end

        # limit and order were introduced in 0.11.0 => skipping for 0.8.0
        it 'Should get metrics with limit and order', run_for: [services_context], skip_auto_vcr: true do
          now = @client.now
          minus10 = now - 10
          minus20 = now - 20
          minus30 = now - 30
          minus8h = now - (2 * t4h)
          minus4h = now - t4h
          bindings = { id: @random_id, minus10: minus10, minus20: minus20, minus30: minus30,
                       minus8h: minus8h, minus4h: minus4h }

          example = proc do
            # create counter
            @client.counters.create(id: @random_id)

            # push 3 values with timestamps
            @client.counters.push_data(@random_id, [{ value: 1, timestamp: minus30 },
                                                    { value: 2, timestamp: minus20 },
                                                    { value: 3, timestamp: minus10 }])

            data = @client.counters.get_data(@random_id)
            expect(data.size).to be 3

            # push one value without timestamp (which means now)
            @client.counters.push_data(@random_id, value: 4)
            data = @client.counters.get_data(@random_id)
            expect(data.size).to be 4

            # retrieve values with limit
            data = @client.counters.get_data(@random_id, limit: 1, order: 'DESC')
            expect(data.size).to be 1
            expect(data.first['value']).to be 4

            # retrieve values from past
            data = @client.counters.get_data(@random_id, starts: minus8h, ends: minus4h)
            expect(data.empty?).to be true
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end

        it 'Should get metrics as bucketed results', :skip_auto_vcr do
          now = @client.now
          minus5 = now - 5
          minus10 = now - 10
          minus20 = now - 20
          minus30 = now - 30
          minus40 = now - 40
          minus50 = now - 50
          minus60 = now - 60
          minus70 = now - 70
          minus80 = now - 80
          minus90 = now - 90
          minus100 = now - 100
          minus105 = now - 105
          minus110 = now - 110
          bindings = { id: @random_id, minus5: minus5, minus10: minus10, minus20: minus20, minus30: minus30,
                       minus40: minus40, minus50: minus50, minus60: minus60, minus70: minus70, minus80: minus80,
                       minus90: minus90, minus100: minus100, minus105: minus105, minus110: minus110 }
          example = proc do
            # create counter
            @client.counters.create(id: @random_id)

            # push 10 values with timestamps
            @client.counters.push_data(@random_id, [{ value: 110, timestamp: minus110 },
                                                    { value: 100, timestamp: minus100 },
                                                    { value: 90, timestamp: minus90 },
                                                    { value: 80, timestamp: minus80 },
                                                    { value: 70, timestamp: minus70 },
                                                    { value: 60, timestamp: minus60 },
                                                    { value: 50, timestamp: minus50 },
                                                    { value: 40, timestamp: minus40 },
                                                    { value: 30, timestamp: minus30 },
                                                    { value: 20, timestamp: minus20 },
                                                    { value: 10, timestamp: minus10 }])
            err = 0.001
            data = @client.counters.get_data(@random_id, starts: minus105, ends: minus5, buckets: 5)
            expect(data.size).to be 5
            expect(data.first['avg']).to be_within(err).of(95.0)
            expect(data.first['max']).to be_within(err).of(100.0)
            expect(data.first['samples']).to be 2

            data = @client.counters.get_data(@random_id, starts: minus105, ends: minus5, buckets: 2)
            expect(data.size).to be 2
            expect(data.first['avg']).to be_within(err).of(80.0)
            expect(data.first['samples']).to be 5

            data = @client.counters.get_data(@random_id, starts: minus105, ends: minus5, bucketDuration: '50ms')
            expect(data.size).to be 2
            expect(data.first['avg']).to be_within(err).of(80.0)
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end

        it 'Should push metric data to non-existing counter' do
          push_data_to_non_existing_metric @client.counters, { value: 4 }, @random_id
        end
      end

      describe 'Availability metrics' do
        before(:all) do
          @tenant = vcr_test_tenant
          options = setup_options.merge(tenant: @tenant)
          record("Metrics/#{security_context}/#{metrics_context}",
                 options,
                 'Availability_metrics/setup_client') do
            if metrics_context == v8_context
              setup_v8_client tenant: @tenant
            else
              setup_client(setup_options.merge(tenant: @tenant))
            end
          end
        end

        it 'Should create and return Availability using Hash parameter' do
          create_metric_using_hash @client.avail, @random_id, @tenant
        end

        it 'Should create Availability definition using MetricDefinition parameter' do
          create_metric_using_md @client.avail, @random_id
        end

        it 'Should push metric data to non-existing Availability' do
          push_data_to_non_existing_metric @client.avail, { value: 'UP' }, @random_id
        end

        it 'Should update tags for Availability definition' do
          update_metric_by_tags @client.avail, @random_id
        end

        it 'Should raise ArgumentError availability does not accept percentiles param' do
          expect { @client.avail.get_data(@random_id, percentiles: 50) }.to raise_error(ArgumentError)
        end

        it 'Should group contiguous values', :skip_auto_vcr, run_for: [services_context] do
          now = @client.now
          minus10 = now - 10
          minus20 = now - 20
          minus30 = now - 30
          minus40 = now - 40
          minus50 = now - 50
          bindings = { id: @random_id, minus10: minus10, minus20: minus20, minus30: minus30, minus40: minus40,
                       minus50: minus50, now: now }
          example = proc do
            @client = setup_client(setup_options.merge tenant: vcr_test_tenant)
            @client.avail.push_data(@random_id, [
              { timestamp: minus50, value: 'up' },
              { timestamp: minus40, value: 'up' },
              { timestamp: minus30, value: 'down' },
              { timestamp: minus20, value: 'down' },
              { timestamp: minus10, value: 'down' },
              { timestamp: now, value: 'up' }
            ])
            result = @client.avail.get_data(@random_id, distinct: true, order: 'ASC')
            expect(result).to eq([
              { 'timestamp' => minus50, 'value' => 'up' },
              { 'timestamp' => minus30, 'value' => 'down' },
              { 'timestamp' => now, 'value' => 'up' }
            ])
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end
      end

      describe 'Gauge metrics' do
        hawkular_tenant_id = 'hawkular'.freeze

        let(:hawkular_mem_id) do
          inventory_client = setup_inventory_client(entrypoint(security_context, 'inventory'),
                                                    tenant: hawkular_tenant_id)
          memory_rs = inventory_client.resources_for_type('Platform_Memory')[0]
          metric = memory_rs.metrics.select { |r| r.name == 'Total Memory' }[0]
          metric.hawkular_id
        end

        before(:all) do
          @tenant = vcr_test_tenant
          record("Metrics/#{security_context}/#{metrics_context}",
                 setup_options.merge(tenant: @tenant),
                 'Gauge_metrics/setup_client') do
            if metrics_context == v8_context
              setup_v8_client tenant: @tenant
            else
              setup_client(setup_options.merge(tenant: @tenant))
            end
          end
        end

        it 'Should create gauge definition using MetricDefinition' do
          create_metric_using_md @client.gauges, @random_id
        end

        it 'Should create gauge definition using Hash' do
          create_metric_using_hash @client.gauges, @random_id, @tenant
        end

        it 'Should push metric data to non-existing gauge' do
          push_data_to_non_existing_metric @client.gauges, { value: 3.1415926 }, @random_id
        end

        # let's do the recording manually
        it 'Should push metric data to existing gauge', :skip_auto_vcr do
          now = @client.now
          ends = now - t4h
          starts = now - (2 * t4h)
          now10 = now - 10
          now20 = now - 20
          now30 = now - 30
          bindings = { id: @random_id, ends: ends, starts: starts, now10: now10, now20: now20, now30: now30 }
          example = proc do
            # create gauge
            @client.gauges.create(id: @random_id)

            # push 3  values with timestamps
            @client.gauges.push_data(@random_id,
                                     [{ value: 1, timestamp: now30 },
                                      { value: 2, timestamp: now20 },
                                      { value: 3, timestamp: now10 }])

            data = @client.gauges.get_data(@random_id)
            expect(data.size).to be 3

            # push one value without timestamp (which means now)
            @client.gauges.push_data(@random_id, value: 4)
            data = @client.gauges.get_data(@random_id)
            expect(data.size).to be 4

            # retrieve values from past
            data = @client.counters.get_data(@random_id, starts: starts, ends: ends)
            expect(data.empty?).to be true
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end

        it 'Should update tags for gauge definition' do
          update_metric_by_tags @client.gauges, @random_id
        end

        it 'Should return periods', :skip_auto_vcr do
          now = @client.now
          before4h = now - t4h
          minus20 = now - 20
          minus30 = now - 30
          bindings = { start: now, before4h: before4h, minus20: minus20, minus30: minus30 }
          example = proc do
            # push 3  values with timestamps
            @client.gauges.push_data(@random_id, [{ value: 1, timestamp: minus30 },
                                                  { value: 2, timestamp: minus20 },
                                                  { value: 3, timestamp: now }])

            data = @client.gauges.get_periods(@random_id, operation: 'lte', threshold: 4, starts: before4h)
            expect(data.size).to be 1
            expect(data[0][0]).to eql(now - 30)
            expect(data[0][1]).to eql(now)
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end

        it 'Should return platform memory def', :skip_auto_vcr, run_for: [services_context] do
          bindings = { tenant: hawkular_tenant_id }
          example = proc do
            if metrics_context == v8_context
              setup_v8_client tenant: hawkular_tenant_id
            else
              setup_client(setup_options.merge tenant: hawkular_tenant_id)
            end

            data = @client.gauges.get(hawkular_mem_id)

            expect(data).not_to be_nil
            expect(data.id).not_to be_nil
            expect(data.tenant_id).to eq(hawkular_tenant_id)
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end

        it 'Should return platform memory', :skip_auto_vcr, run_for: [services_context] do
          bindings = { tenant: hawkular_tenant_id }
          example = proc do
            # this id depends on OS and the feed id
            if metrics_context == v8_context
              setup_v8_client tenant: tenant_id
            else
              setup_client(setup_options.merge tenant: hawkular_tenant_id)
            end

            data = @client.gauges.get_data(hawkular_mem_id)
            expect(data.size).to be > 2 # needs the services to be running for more than 2 minutes
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end
      end

      describe 'Status' do
        it 'Should return the version' do
          if metrics_context == v8_context
            setup_v8_client
          else
            setup_client setup_options
          end
          data = @client.fetch_version_and_status
          expect(data).not_to be_nil
        end
      end

      describe 'String metrics', run_for: [services_context] do
        before(:each) do
          @tenant = vcr_test_tenant
          options = setup_options.merge(tenant: @tenant)
          record("Metrics/#{security_context}/#{metrics_context}",
                 options,
                 'String_metrics/setup_client') do
            setup_client(options)
          end
        end

        it 'Should create string definition using MetricDefinition' do
          create_metric_using_md @client.strings, @random_id
        end

        it 'Should create string definition using Hash' do
          create_metric_using_hash @client.strings, @random_id, @tenant
        end

        it 'Should push metric data to non-existing string' do
          push_data_to_non_existing_metric @client.strings, { value: 'Hello world' }, @random_id
        end

        it 'Should push metric data to existing string', :skip_auto_vcr do
          now = @client.now
          ends = now - t4h
          starts = now - (2 * t4h)
          now10 = now - 10
          now20 = now - 20
          now30 = now - 30
          bindings = { id: @random_id, ends: ends, starts: starts, now10: now10, now20: now20, now30: now30 }
          example = proc do
            # create gauge
            @client.strings.create(id: @random_id)

            # push 3  values with timestamps
            @client.strings.push_data(@random_id,
                                      [
                                        { value: 'Value1', timestamp: now30 },
                                        { value: 'Value2', timestamp: now20 },
                                        { value: 'Value3', timestamp: now10 }
                                      ])

            data = @client.strings.get_data(@random_id)
            expect(data.size).to be 3

            # push one value without timestamp (which means now)
            @client.strings.push_data(@random_id, value: 'Now')
            data = @client.strings.get_data(@random_id)
            expect(data.size).to be 4

            # retrieve values from past
            data = @client.strings.get_data(@random_id, starts: starts, ends: ends)
            expect(data.empty?).to be true
          end
          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end
      end

      describe 'All Tags for metrics', run_for: [services_context] do
        before(:each) do
          @tenant = SecureRandom.uuid
          options = setup_options.merge(tenant: @tenant)
          record("Metrics/#{security_context}/#{metrics_context}",
                 options,
                 'Tags_Metrics/setup_client') do
            setup_client(options)
          end
        end

        it 'Should fetch all metrics with some tags', :skip_auto_vcr do
          id1 = SecureRandom.uuid
          id2 = SecureRandom.uuid
          id3 = SecureRandom.uuid
          id4 = SecureRandom.uuid

          bindings = { id1: id1, id2: id2, id3: id3, id4: id4 }
          tag = { miq_metric: true }
          example = proc do
            create_metric_using_md @client.gauges, id1, tag
            create_metric_using_md @client.gauges, id2, tag
            create_metric_using_md @client.gauges, id3, tag
            create_metric_using_md @client.gauges, id4, tag

            create_metric_using_md @client.avail, id1, tag
            create_metric_using_md @client.avail, id2, tag
            create_metric_using_md @client.avail, id3, tag
            create_metric_using_md @client.avail, id4, tag

            create_metric_using_md @client.counters, id1, tag
            create_metric_using_md @client.counters, id2, tag
            create_metric_using_md @client.counters, id3, tag
            create_metric_using_md @client.counters, id4, tag

            @client.push_data(
              counters: [
                { id: id1, data: [{ value: 1 }] },
                { id: id2, data: [{ value: 2 }] },
                { id: id3, data: [{ value: 3 }] }
              ],
              availabilities: [
                { id: id1, data: [{ value: 'up' }] },
                { id: id2, data: [{ value: 'down' }] },
                { id: id3, data: [{ value: 'up' }] },
                { id: id4, data: [{ value: 'up', timestamp: 10_000 },
                                  { value: 'down', timestamp: 100_000 },
                                  { value: 'admin', timestamp: 1_000_000 }] }
              ],
              gauges: [
                { id: id1, data: [{ value: 1.1 }] },
                { id: id2, data: [{ value: 2.2 }] },
                { id: id3, data: [{ value: 3.3 }] }
              ]
            )
            data = @client.data_by_tags(tag, buckets: 1)

            expect(data.size).to eql(3)
            expect(data['gauge'].size).to eql(4)
            expect(data['availability'].size).to eql(4)
            expect(data['counter'].size).to eql(4)
          end

          record("Metrics/#{security_context}/#{metrics_context}",
                 vcr_bindings.merge(bindings),
                 cassette_name,
                 example: example)
        end

        it 'Should fetch all metric tags for metrics definitions' do
          tags_m1 = {
            tag1: 'value1',
            tag2: 'value2',
            tag3: 'value3'
          }

          tags_m2 = {
            tag1: 'value1',
            tag4: 'value4',
            tag5: 'value5'
          }

          tags_m3 = {
            tag1: 'value1',
            tag4: 'value4',
            tag5: 'value5.1'
          }

          create_metric_using_md @client.gauges, 'metric_1', tags_m1
          create_metric_using_md @client.avail, 'metric_2', tags_m2
          create_metric_using_md @client.counters, 'metric_2', tags_m3
          create_metric_using_md @client.counters, 'metric_3', {}

          expected_result = [
            { 'tag1' => 'value1' },
            { 'tag2' => 'value2' },
            { 'tag3' => 'value3' },
            { 'tag4' => 'value4' },
            { 'tag5' => 'value5' },
            { 'tag5' => 'value5.1' }
          ]
          expect(@client.tags.to_set).to eql(expected_result.to_set)
        end
      end
    end
  end

  vcr_test_tenant = "#{security_context}#{vcr_test_tenant_postfix}".freeze

  context security_context do
    describe 'Metric ID with special characters' do
      before(:all) do
        record("Metrics/#{security_context}/ID_with_special_characters",
               { tenant: vcr_test_tenant },
               'setup_client') do
          setup_client(type: security_context, tenant: vcr_test_tenant)
        end
      end

      around(:each) do |example|
        record("Metrics/#{security_context}/ID_with_special_characters",
               { vcr_test_tenant: vcr_test_tenant },
               example.description,
               example: example)
      end

      after(:all) do
        record_cleanup("Metrics/#{security_context}/ID_with_special_characters")
      end

      id_gauge = 'MI~R~[8b*}{\'\\14#?/5-7%92e[-c9_.r1//;/74eddf/L=c~~]~MT~    *  /'\
                 ' Met@ics~Aggre&? ated s  Active" Ses;ns'
      id_avail = 'AA~R~[8b*}{\'\\14#?/5-7%92[d-c9_.r1///7;:4eddf/L=c~~]~MT~ A  *  %-Met@ics~Aggre&?ated " Sess{ons'
      id_counter = 'AA~R~[8b*}{\'\\14#?/5-7%92[d-c9_.r1///7;:4eddf/L=c~~]~MT~  %-Met@ics~Aggre&?ated " Sess{ons'

      it 'Should create gauge definition' do
        create_metric_using_md @client.gauges, id_gauge
      end

      it 'Should create Availability definition' do
        create_metric_using_md @client.avail, id_avail
      end

      it 'Should create Counter definition' do
        create_metric_using_md @client.counters, id_counter
      end

      it 'Should push metric data to existing gauge' do
        @client.gauges.push_data(id_gauge, [
          { value: 0.1,  tags: { tagName: 'myMin' } },
          { value: 99.9, tags: { tagName: 'myMax' } }
        ])
      end

      it 'Should update tags for gauge definition' do
        deff = @client.gauges.get(id_gauge)
        deff.tags = {
          name1: 'value1',
          name2: 'value2',
          name3: 'value3'
        }
        @client.gauges.update_tags(deff)
        deff_updated = @client.gauges.get(id_gauge)
        expected_result = {
          'name1' => 'value1',
          'name2' => 'value2',
          'name3' => 'value3',
          'tag'   => 'value'
        }
        expect(deff_updated.tags).to eq(expected_result)
      end

      it 'Should update tags for Availability definition' do
        deff_avail = @client.avail.get(id_avail)
        deff_avail.tags = {
          name1: 'value1',
          name2: 'value2',
          name3: 'value3'
        }
        @client.avail.update_tags(deff_avail)
        deff_avail_updated = @client.avail.get(id_avail)
        expected_result = {
          'name1' => 'value1',
          'name2' => 'value2',
          'name3' => 'value3',
          'tag'   => 'value'
        }
        expect(deff_avail_updated.tags).to eq(expected_result)
      end

      it 'Get metric definition by id' do
        @client.gauges.get(id_gauge)
      end

      it 'Retrieve metric rate points' do
        @client.gauges.get(id_gauge)
        @client.counters.get_rate id_counter
      end
    end
  end
end
