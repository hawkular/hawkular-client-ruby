module Hawkular::Metrics
  class Client

    # Base class for accessing metric definition and data of all types (counters, gauges, availabilities)
    class Metrics

      # @parem client [Hawkular::Metrics::Client]
      # @param metricType [String] metric type (one of "counter", "gauge", "availability")
      # @resource [String] REST resource name for accessing metrics of given type (one of "counters", "gauges", "availability")
      def initialize(client, metricType, resource)
        @client = client
        @type = metricType
        @resource = resource
      end

      # create new  metric definition
      # @param definition [MetricDefinition or Hash] gauge/counter/availability options.
      def create(definition)
        if definition.kind_of?(Hawkular::Metrics::MetricDefinition)
          definition = definition.hash
        end
        @client.http_post('/'+@resource, definition)
      end

      # query metric definitions by tags
      # @param tags [Hash]
      def query(tags)
          tags = tags.map do |k,v|
            "#{k}:#{v}"
          end
          @client.http_get("/metrics/?type=#{@type}&tags=#{tags.join(',')}").map do |g|
            Hawkular::Metrics::MetricDefinition::new(g)
          end
      end

      # get metric definition by id
      # @param id [String]
      def get(id)
        Hawkular::Metrics::MetricDefinition::new(@client.http_get("/#{@resource}/#{id}"))
      end

      # update tags for given metric definition
      # @param metricDefinition [Hawkular::Metrics::MetricDefinition]
      def update_tags(metricDefinition)
        @client.http_put("/#{@resource}/#{metricDefinition.id}/tags",metricDefinition.hash[:tags])
      end

      def push_data(id, data)
        if !data.kind_of?(Array)
          data = [data]
        end

        data.each { |p|
          p[:timestamp] ||= Integer(Time::now.to_f * 1000)
        }
        @client.http_post("/#{@resource}/#{id}/data", data)
      end

      # retrieve metric data
      # @id [String] metric definition id
      def get_data(id)
        @client.http_get("/#{@resource}/#{id}/data")
      end
    end

    # Class that interracts with "gauge" metric types
    class Gauges < Metrics

      def initialize(client)
        super(client, 'gauge', 'gauges')
      end

    end

    # Class that interracts with "counter" metric types
    class Counters < Metrics

      def initialize(client)
        super(client, 'counter', 'counters')
      end

      # get rate for given metric
      # @param id [String] metric ID
      def get_rate(id)
        @client.http_get("/#{@resource}/#{id}/rate")
      end
    end

    # Class that interracts with "availability" metric types
    class Availability < Metrics

      def initialize(client)
        super(client, 'availability', 'availability')
      end

    end


  end
end
