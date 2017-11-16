require 'hawkular/base_client'
require 'hawkular/inventory/entities'
require 'ostruct'

module Hawkular::Prometheus
  class AlerterClient < Hawkular::BaseClient
    def initialize(entrypoint, credentials = {}, options = {})
      entrypoint = normalize_entrypoint_url entrypoint, 'hawkular/alerter'
      @entrypoint = entrypoint

      super(entrypoint, credentials, options)
    end

    def get_prometheus_entrypoint
      rest_client("/prometheus/endpoint").get
    end
  end

  # Interface to talk with the Prometheus server used for Middleware Manager
  # @param entrypoint [String] base url of Hawkular Services
  class Client < Hawkular::BaseClient
    def initialize(entrypoint, credentials = {}, options = {})
      prometheus_entrypoint = AlerterClient.new(entrypoint, credentials, options).get_prometheus_entrypoint
      entrypoint = normalize_entrypoint_url prometheus_entrypoint, 'api/v1'
      @entrypoint = entrypoint

      super(entrypoint, credentials, options)
    end

    def query_range(metrics: [], starts: nil, ends: nil, step: nil)
      query = metrics.map do |m|
        m.family + '{' + m.labels.map { |k, v| k.to_s + '="' + v + '"' }.join(',') + '}'
      end.join(' or ')
      response = http_get "/query_range?start=#{starts}&end=#{ends}&step=#{step}&query=#{query}"
      results = response['data']['result']
      attach_metric_in_result(results, metrics)
    end

    private

    def attach_metric_in_result(results, metrics)
      results.each do |result|
        metrics.each do |metric|
          if contains_metric_in_result(metric, result)
            result['metric'] = metric
            break
          end
        end
      end
    end

    def contains_metric_in_result(metric, result)
      if metric.family == result['metric']['__name__']
        metric.labels.each { |k, v| return false unless result['metric'][k.to_s] == v }
        true
      else
        false
      end
    end
  end
end
