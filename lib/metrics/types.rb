module Hawkular
  module Metrics
    class BaseObject
      attr_reader :json
      attr_accessor :id

      def initialize(json)
        @json = json
        if !json.nil?
          @id = @json['id']
        end
      end
    end

    class Tenant < BaseObject
    end

    class MetricDefinition < BaseObject
      attr_accessor :tenantId, :dataRetention, :tags

      def initialize(json=nil)
        super(json)
        if !json.nil?
          @tenantId = @json['tenantId']
          @dataRetention = @json['dataRetention']
          @tags = @json['tags']
        end
      end

      def hash
        h = {:id => @id, :tenantId => @tenantId, :dataRetention => @dataRetention, :tags => @tags}
        h.delete_if { |k, v| v.nil? }
        h
      end

    end
  end
end
