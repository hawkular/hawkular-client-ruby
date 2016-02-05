module Hawkular
  module Metrics
    class BaseObject
      attr_reader :json
      attr_accessor :id

      def initialize(json)
        @json = json
        @id = @json['id'] unless json.nil?
      end
    end

    class Tenant < BaseObject
    end

    class MetricDefinition < BaseObject
      attr_accessor :tenant_id, :data_retention, :tags

      def initialize(json = nil)
        super(json)
        unless json.nil?
          @tenant_id = @json['tenantId']
          @data_retention = @json['dataRetention']
          @tags = @json['tags']
        end
      end

      def hash
        h = { id: @id, tenantId: @tenant_id,
              dataRetention: @data_retention, tags: @tags }
        h.delete_if { |_k, v| v.nil? }
        h
      end
    end
  end
end
