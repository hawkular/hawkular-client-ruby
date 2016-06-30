require 'hawkular/inventory/inventory_api'
require 'hawkular/metrics/metrics_client.rb'
require 'hawkular/alerts/alerts_api'
require 'hawkular/tokens/tokens_api'
require 'hawkular/operations/operations_api'
require 'hawkular/base_client'

module Hawkular
  class Client
    attr_reader :inventory, :metrics, :alerts, :operations, :tokens, :state

    def initialize(hash)
      hash[:entrypoint] ||= 'http://localhost:8080'
      hash[:credentials] ||= {}
      hash[:options] ||= {}
      @state = hash

      @inventory = Inventory::InventoryClient.create(entrypoint: "#{hash[:entrypoint]}/hawkular/inventory",
                                                     credentials: hash[:credentials],
                                                     options: hash[:options])

      @metrics = Metrics::Client.new("#{hash[:entrypoint]}/hawkular/metrics",
                                     hash[:credentials],
                                     hash[:options])

      @alerts = Alerts::AlertsClient.new("#{hash[:entrypoint]}/hawkular/alerts",
                                         hash[:credentials],
                                         hash[:options])

      @tokens = Token::TokenClient.new(hash[:entrypoint],
                                       hash[:credentials],
                                       hash[:options])
    end

    def method_missing(name, *args, &block)
      delegate_client = case name
                        when /^inventory_/ then @inventory
                        when /^metrics_/ then @metrics
                        when /^alerts_/ then @alerts
                        when /^operations_/ then @operations ||= init_operations_client
                        when /^tokens_/ then @tokens
                        else
                          fail "unknown method prefix `#{name}`, allowed prefixes:"\
      '`inventory_`, `metrics_`,`alerts_`,`operations_`, `tokens_`'
                        end
      method = name.to_s.sub(/^[^_]+_/, '')
      delegate_client.__send__(method, *args, &block)
    end

    # adds a way to explicitly open the new web socket connection (the default is to recycle it)
    # @param open_new [Boolean] if true, opens the new websocket connection
    def operations(open_new = false)
      @operations = init_operations_client if open_new
      @operations ||= init_operations_client
    end

    def to_s
      'client'
    end

    private

    # this is in a dedicated method, because constructor opens the websocket connection to make the handshake
    def init_operations_client
      Operations::OperationsClient.new(entrypoint: @state[:entrypoint].gsub(/^https?/, 'ws'),
                                       credentials: @state[:credentials],
                                       options: @state[:options])
    end
  end
end
