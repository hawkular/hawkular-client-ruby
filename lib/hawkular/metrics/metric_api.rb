require 'erb'

module Hawkular::Metrics
  # Client to access the Hawkular_metrics subsystem
  class Client
    # @!visibility private
    def default_timestamp(array)
      n = now
      array.each do |p|
        p[:timestamp] ||= n
      end
      array
    end

    # Return version and status information for the used version of Hawkular-Metrics
    # @return [Hash{String=>String}]
    #         ('Implementation-Version', 'Built-From-Git-SHA1', 'Status')
    def fetch_version_and_status
      http_get('/status')
    end

    # Push data for multiple metrics of all supported types
    # @param gauges [Array]
    # @param counters [Array]
    # @param availabilities [Array]
    # @example push datapoints of 2 counter metrics
    #    client = Hawkular::Metrics::client::new
    #    client.push_data(counters: [{:id => "counter1", :data => [{:value => 1}, {:value => 2}]},
    #                        {:id => "counter2", :data => [{:value => 1}, {:value => 3}]}])
    # @example push gauge and availability datapoints
    #    client.push_data(gauges: [{:id => "gauge1", :data => [{:value => 1}, {:value => 2}]}],
    #                           availabilities: [{:id => "avail1", :data => [{:value => "up"}]}])
    def push_data(gauges: [], counters: [], availabilities: [])
      gauges.each { |g| default_timestamp g[:data] }
      counters.each { |g| default_timestamp g[:data] }
      availabilities.each { |g| default_timestamp g[:data] }
      data = { gauges: gauges, counters: counters, availabilities: availabilities }
      path = '/metrics/'
      @legacy_api ? path << 'data' : path << 'raw'
      http_post(path, data)
    end

    # Fetch stats for multiple metrics of all supported types
    # @param gauge_ids [Array[String]] list of gauge ids
    # @param counter_ids [Array[String]] list of counter ids
    # @param avail_ids [Array[String]] list of availability ids
    # @param starts [Integer] optional timestamp (default now - 8h)
    # @param ends [Integer] optional timestamp (default now)
    # @param bucket_duration [String] optional interval (default 3600s)
    # @return [Hash] stats grouped per type
    # @example
    #   client = Hawkular::Metrics::client::new
    #   client.query_stats(
    #     gauge_ids: ['G1', 'G2'],
    #     counter_ids: ['C2', 'C3'],
    #     avail_ids: ['A2', 'A3'],
    #     starts: 200,
    #     ends: 500,
    #     bucket_duration: '150ms'
    #   )
    def query_stats(gauge_ids: [], counter_ids: [], avail_ids: [], starts: nil, ends: nil, bucket_duration: '3600s')
      path = '/metrics/stats/query'
      metrics = { gauge: gauge_ids, counter: counter_ids, availability: avail_ids }
      data = { metrics: metrics, start: starts, end: ends, bucketDuration: bucket_duration }
      http_post(path, data)
    end

    # Base class for accessing metric definition and data of all
    # types (counters, gauges, availabilities).
    class Metrics
      # @param client [Client]
      # @param metric_type [String] metric type (one of "counter", "gauge", "availability")
      # @param resource [String] REST resource name for accessing metrics
      #    of given type (one of "counters", "gauges", "availability")
      def initialize(client, metric_type, resource)
        @client = client
        @type = metric_type
        @resource = resource
        @legacy_api = client.legacy_api
      end

      # Create new  metric definition
      # @param definition [MetricDefinition or Hash] gauge/counter/availability options.
      # @example Create gauge metric definition using Hash
      #   client = Hawkular::Metrics::client::new
      #   client.gauges.create({:id => "id", :dataRetention => 90,
      #                         :tags => {:tag1 => "value1"}, :tenantId => "your tenant id"})
      def create(definition)
        if definition.is_a?(Hawkular::Metrics::MetricDefinition)
          definition = definition.hash
        end
        @client.http_post('/' + @resource, definition)
      end

      # Query metric definitions by tags
      # @param tags [Hash]
      # @return [Array[MetricDefinition]]
      def query(tags = nil)
        tags_filter = tags.nil? ? '' : "&tags=#{tags_param(tags)}"
        @client.http_get("/metrics/?type=#{@type}#{tags_filter}").map do |g|
          Hawkular::Metrics::MetricDefinition.new(g)
        end
      end

      # Get metric definition by id
      # @param id [String]
      # @return [MetricDefinition]
      def get(id)
        the_id = ERB::Util.url_encode id
        Hawkular::Metrics::MetricDefinition.new(@client.http_get("/#{@resource}/#{the_id}"))
      end

      # update tags for given metric definition
      # @param metric_definition [MetricDefinition]
      def update_tags(metric_definition)
        metric_definition_id = ERB::Util.url_encode metric_definition.id
        @client.http_put("/#{@resource}/#{metric_definition_id}/tags", metric_definition.hash[:tags])
      end

      # Push metric data
      # @param id [String] metric definition ID
      # @param data [Array[Hash]] Single datapoint or array of datapoints
      # @example Push counter data with timestamp
      #   client = Hawkular::Metics::Client::new
      #   now = Integer(Time::now.to_f * 1000)
      #   client.counters.push_data("counter id", [{:value => 1, :timestamp => now - 1000},
      #                                            {:value => 2, :timestamp => now}])
      # @example Push single availability without timestamp
      #   client.avail.push_data("avail_id", {:value => "up"})
      # @example Push gague data with tags
      #   client.gagues.push_data("gauge_id", [{:value => 0.1, :tags => {:tagName => "myMin"}},
      #                                        {:value => 99.9, :tags => {:tagName => "myMax"}}])
      def push_data(id, data)
        data = [data] unless data.is_a?(Array)
        uri = "/#{@resource}/#{ERB::Util.url_encode(id)}/"
        @legacy_api ? uri << 'data' : uri << 'raw'
        @client.default_timestamp data
        @client.http_post(uri, data)
      end

      # Retrieve metric datapoints
      # @param id [String] metric definition id
      # @param starts [Integer] optional timestamp (default now - 8h)
      # @param ends [Integer] optional timestamp (default now)
      # @param buckets [Integer] optional desired number of buckets over the specified timerange
      # @param bucketDuration [String] optional interval (default no aggregation)
      # @param percentiles [String] optional percentiles to calculate
      # @param limit [Integer] optional limit the number of data points returned
      # @param order [String] optional Data point sort order, based on timestamp (ASC, DESC)
      # @return [Array[Hash]] datapoints
      # @see #push_data #push_data for datapoint detail
      def get_data(id, starts: nil, ends: nil, bucketDuration: nil, buckets: nil, percentiles: nil, limit: nil,
                   order: nil)
        params = { start: starts, end: ends, bucketDuration: bucketDuration, buckets: buckets,
                   percentiles: percentiles, limit: limit, order: order }
        get_data_helper(id, params)
      end

      # Retrieve raw data for multiple metrics.
      # @param ids [Array[String]] metric definition ids
      # @param starts [Integer] optional timestamp (default now - 8h)
      # @param ends [Integer] optional timestamp (default now)
      # @param limit [Integer] optional limit the number of data points returned
      # @param order [String] optional Data point sort order, based on timestamp (ASC, DESC)
      # @return [Array[Hash]] named datapoints
      def raw_data(ids, starts: nil, ends: nil, limit: nil, order: nil)
        params = { ids: ids, start: starts, end: ends, limit: limit, order: order }
        @client.http_post("/#{@resource}/raw/query", params)
      end

      # Retrieve metric datapoints by tags
      # @param tags [Hash]
      # @param starts [Integer] optional timestamp (default now - 8h)
      # @param ends [Integer] optional timestamp (default now)
      # @param bucketDuration [String] optional interval (default no aggregation)
      # @return [Array[Hash]] datapoints
      # @see #push_data #push_data for datapoint detail
      def get_data_by_tags(tags, starts: nil, ends: nil, bucketDuration: nil)
        params = { tags: tags_param(tags), start: starts,
                   end: ends, bucketDuration: bucketDuration }
        path = "/#{@resource}/"
        @legacy_api ? path << 'data/?' : path << 'stats/?'
        resp = @client.http_get(path + encode_params(params))
        resp.is_a?(Array) ? resp : [] # API returns no content (empty Hash) instead of empty array
      end

      def tags_param(tags)
        tags.map { |k, v| "#{k}:#{v}" }.join(',')
      end

      def encode_params(params)
        URI.encode_www_form(params.select { |_k, v| !v.nil? })
      end

      private

      def get_data_helper(id, params)
        path = "/#{@resource}/#{ERB::Util.url_encode(id)}/"
        if @legacy_api
          path << 'data/?'
        else
          (params[:bucketDuration].nil? && params[:buckets].nil?) ? path << 'raw/?' : path << 'stats/?'
        end
        path << encode_params(params)
        resp = @client.http_get(path)
        resp.is_a?(Array) ? resp : [] # API returns no content (empty Hash) instead of empty array
      end
    end

    # Class that interacts with "gauge" metric types
    class Gauges < Metrics
      # @param client [Client]
      def initialize(client)
        super(client, 'gauge', 'gauges')
      end

      # Retrieve time ranges when given gauge matches given operation and threshold
      # @param id [String] gauge ID
      # @param starts [Integer] timestamp (default now - 8h)
      # @param ends [Integer] timestamp (default now)
      # @param threshold [Numeric]
      # @param operation [String] A comparison operation to perform between values and the
      #   threshold. Supported operations include "ge", "gte", "lt", "lte", and "eq"
      # @example Get time periods when metric "gauge1" was under 10 in past 4 hours
      #   before4h = client.now - (4 * 60 * 60 * 1000)
      #   client.gauges.get_periods("gauge1", starts: before4h, threshold: 10, operation: "lte")
      def get_periods(id, starts: nil, ends: nil, threshold: nil, operation: nil)
        params = { start: starts, end: ends, threshold: threshold, op: operation }
        @client.http_get("/#{@resource}/#{ERB::Util.url_encode(id)}/periods?" + encode_params(params))
      end
    end

    # Class that interacts with "counter" metric types
    class Counters < Metrics
      # @param client [Client]
      def initialize(client)
        super(client, 'counter', 'counters')
      end

      # Retrieve metric rate points
      # @param id [String] metric definition id
      # @param starts [Integer] optional timestamp (default now - 8h)
      # @param ends [Integer] optional timestamp (default now)
      # @param bucket_duration [String] optional interval (default no
      #                       aggregation)
      # @return [Array[Hash]] rate points
      def get_rate(id, starts: nil, ends: nil, bucket_duration: nil)
        path = "/#{@resource}/#{ERB::Util.url_encode(id)}/rate"
        path << '/stats' unless bucket_duration.nil? && @legacy_api
        params = { start: starts, end: ends, bucketDuration: bucket_duration }
        resp = @client.http_get(path + '?' + encode_params(params))
        # API returns no content (empty Hash) instead of empty array
        resp.is_a?(Array) ? resp : []
      end
    end

    # Class that interacts with "availability" metric types
    class Availability < Metrics
      # @param client [Client]
      def initialize(client)
        super(client, 'availability', 'availability')
      end

      # Retrieve metric datapoints
      # @param id [String] metric definition id
      # @param starts [Integer] optional timestamp (default now - 8h)
      # @param ends [Integer] optional timestamp (default now)
      # @param buckets [Integer] optional desired number of buckets over the specified timerange
      # @param bucketDuration [String] optional interval (default no aggregation)
      # @param distinct [String] optional set to true to return only distinct, contiguous values
      # @param limit [Integer] optional limit the number of data points returned
      # @param order [String] optional Data point sort order, based on timestamp (ASC, DESC)
      # @return [Array[Hash]] datapoints
      # @see #push_data #push_data for datapoint detail
      def get_data(id, starts: nil, ends: nil, bucketDuration: nil, buckets: nil, distinct: nil, limit: nil,
        order: nil)
        params = { start: starts, end: ends, bucketDuration: bucketDuration, buckets: buckets,
                   distinct: distinct, limit: limit, order: order }
        get_data_helper(id, params)
      end
    end
  end
end
