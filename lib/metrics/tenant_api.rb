module Hawkular::Metrics
  class Client
    # Provides access to tenants API
    class Tenants

    def initialize(client)
        @client = client
      end

      # Create new tenant
      # @param [String] tenant ID/Name
      def create(id)
        @client.http_post("/tenants", {:id => id})
      end

      # Query existing tenants
      def query
        @client.http_get("/tenants").map do |t|
          Hawkular::Metrics::Tenant::new(t)
        end
      end
    end
  end
end
