module Hawkular::Metrics
  class Client
    # Provides access to tenants API
    class Tenants
      # @param client [Client]
      def initialize(client)
        @client = client
        @resource = 'tenants'
      end

      # Create new tenant
      # @param id [String] tenant ID/Name
      def create(id)
        @client.http_post("/#{@resource}", id: id)
      end

      # Query existing tenants
      # @return [Array[Tenant]]
      def query
        @client.http_get("/#{@resource}").map do |t|
          Hawkular::Metrics::Tenant.new(t)
        end
      end
    end
  end
end
