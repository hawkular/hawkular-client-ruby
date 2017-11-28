require 'hawkular/base_client'
require 'hawkular/inventory/entities'
require 'ostruct'

module Hawkular::Prometheus
  class Alerter < Hawkular::BaseClient
    def initialize(entrypoint, credentials = {}, options = {})
      @entrypoint = normalize_entrypoint_url entrypoint, 'hawkular/alerter'
      super(@entrypoint, credentials, options)
    end

    def prometheus_entrypoint
      rest_client('/prometheus/endpoint').get
    end
  end

  # Interface to talk with the Prometheus server used for Middleware Manager
  # @param entrypoint [String] base url of Hawkular Services
  class Client < Hawkular::BaseClient
    def initialize(entrypoint, credentials = {}, options = {})
      prometheus_entrypoint = Alerter.new(entrypoint, credentials, options).prometheus_entrypoint
      @entrypoint = normalize_entrypoint_url prometheus_entrypoint, 'api/v1'
      super(@entrypoint, credentials, options)
    end

    def query(metrics: [], time: nil)
      results = []
      metrics.each do |metric|
        query = metric['expression']
        puts("DELETEME p8s - /query?time=#{time}&query=#{query}")
        response = http_get "/query?start=#{time}&query=#{query}"
        result = response['data']['result'].empty? ? {} : response['data']['result'].first
        result['metric'] = metric
        results << result
      end
      puts("DELETEME p8s - query #{results}")
      results
    end

    def query_range(metrics: [], starts: nil, ends: nil, step: nil)
      results = []
      metrics.each do |metric|
        query = metric['expression']
        puts("DELETEME p8s - /query_range?start=#{starts}&end=#{ends}&step=#{step}&query=#{query}")
        response = http_get "/query_range?start=#{starts}&end=#{ends}&step=#{step}&query=#{query}"
        result = response['data']['result'].empty? ? {} : response['data']['result'].first
        result['metric'] = metric
        # DELETEME this, it's to have this info, as a worker can't show the stdout correctly
        # result['query'] = "/query_range?start=#{starts}&end=#{ends}&step=#{step}&query=#{query}"
        results << result
      end
      puts("DELETEME p8s - query_range #{results}")
      results
    end

    def up_time(feed_id: nil, starts: nil, ends: nil, step: nil)
      query = "up{feed_id=\"#{feed_id}\"}"
      puts("DELETEME p8s - up_time /query_range?start=#{starts}&end=#{ends}&step=#{step}&query=#{query}")
      response = http_get "/query_range?start=#{starts}&end=#{ends}&step=#{step}&query=#{query}"
      puts("DELETEME p8s - up_time feed_id #{feed_id} #{response['data']['result']}")
      if response['data']['result'].empty?
        []
      else
        response['data']['result'].first['values']
      end
    end
  end
end
