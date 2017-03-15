require 'hawkular/inventory/inventory_api'
require 'hawkular/metrics/metrics_client'
require 'hawkular/alerts/alerts_api'
require 'hawkular/tokens/tokens_api'
require 'hawkular/operations/operations_api'
require 'hawkular/base_client'

module Hawkular
  class Client
    attr_reader :inventory, :metrics, :alerts, :operations, :tokens, :state

    def initialize(hash)
      hash[:credentials] ||= {}
      hash[:options] ||= {}
      fail 'no parameter ":entrypoint" given' if hash[:entrypoint].nil?
      @state = hash
    end

    def method_missing(name, *args, &block)
      delegate_client = case name
                        when /^inventory_/ then inventory
                        when /^metrics_/ then metrics
                        when /^alerts_/ then alerts
                        when /^operations_/ then operations
                        when /^tokens_/ then tokens
                        else
                          fail "unknown method prefix `#{name}`, allowed prefixes:"\
      '`inventory_`, `metrics_`,`alerts_`,`operations_`, `tokens_`'
                        end
      method = name.to_s.sub(/^[^_]+_/, '')
      delegate_client.__send__(method, *args, &block)
    end

    def inventory
      @inventory ||= Inventory::Client.new("#{@state[:entrypoint]}/hawkular/metrics",
                                           @state[:credentials],
                                           @state[:options])
    end

    def metrics
      @metrics ||= Metrics::Client.new("#{@state[:entrypoint]}/hawkular/metrics",
                                       @state[:credentials],
                                       @state[:options])
    end

    def alerts
      @alerts ||= Alerts::Client.new("#{@state[:entrypoint]}/hawkular/alerts",
                                     @state[:credentials],
                                     @state[:options])
    end

    # adds a way to explicitly open the new web socket connection (the default is to recycle it)
    # @param open_new [Boolean] if true, opens the new websocket connection
    def operations(open_new = false)
      @operations = init_operations_client if open_new
      @operations ||= init_operations_client
    end

    def tokens
      @tokens ||= Token::Client.new(@state[:entrypoint],
                                    @state[:credentials],
                                    @state[:options])
    end

    private

    # this is in a dedicated method, because constructor opens the websocket connection to make the handshake
    def init_operations_client
      Operations::Client.new(entrypoint: @state[:entrypoint],
                             credentials: @state[:credentials],
                             options: @state[:options])
    end
  end
end
