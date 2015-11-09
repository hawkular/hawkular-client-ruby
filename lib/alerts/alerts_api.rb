require 'hawkular'
require 'ostruct'

module Hawkular::Alerts
  class AlertsClient < Hawkular::BaseClient
    def initialize(entrypoint = nil, credentials = {})
      @entrypoint = entrypoint

      super(entrypoint, credentials)
    end

    def list_triggers(ids = [], tags = [])
      query = '/triggers'
      query += '?'
      query = 'triggerIds=' + ids unless ids.empty? # TODO: flatten array
      query = '&' unless ids.empty? && tags.empty?
      query = 'tags=' + tags unless tags.empty? # TODO: flatten tags array

      ret = http_get(query)

      val = []
      ret.each { |t| val.push(Trigger.new(t)) }
      val
    end

    def get_single_trigger(trigger_id, full = false)
      the_trigger = '/triggers/' + trigger_id
      ret = http_get(the_trigger)
      trigger = Trigger.new(ret)

      if full
        ret = http_get(the_trigger + '/conditions')
        ret.each { |c| trigger.conditions.push(Trigger::Condition.new(c)) }
        ret = http_get(the_trigger + '/dampenings')
        ret.each { |c| trigger.dampenings.push(Trigger::Dampening.new(c)) }
      end

      trigger
    end

    def list_alerts
      ret = http_get('/')
      val = []
      ret.each { |a| val.push(Alert.new(a)) }
      val
    end

    def get_single_alert(alert_id)
      ret = http_get('/alert/' + alert_id)
      val = Alert.new(ret)
      val
    end

    def resolve_alert(alert_id, by = nil, comment = nil)
      sub_url = "/resolve/#{alert_id}"
      query = generate_query_params 'resolvedBy' => by, 'resolvedNotes' => comment
      # sub_url += '?' unless by.nil? && comment.nil?
      # sub_url += "resolvedBy=#{by}" unless by.nil?
      # sub_url += '&' unless by.nil? || comment.nil?
      # sub_url += "resolvedNotes=#{comment}" unless comment.nil?
      sub_url += query
      http_put(sub_url, {})

      true
    end

    def acknowledge_alert(alert_id, by = nil, comment = nil)
      sub_url = "/ack/#{alert_id}"
      query = generate_query_params 'ackBy' => by, 'ackNotes' => comment
      # sub_url += '?' unless by.nil? && comment.nil?
      # sub_url += "ackBy=#{by}" unless by.nil?
      # sub_url += '&' unless by.nil? || comment.nil?
      # sub_url += "ackNotes=#{comment}" unless comment.nil?
      sub_url += query
      http_put(sub_url, {})

      true
    end
  end

  class Trigger
    attr_reader :id, :name, :context, :actions, :autoDisable, :autoEnable
    attr_reader :autoResolve, :autoResolveAlerts
    attr_reader :tenant, :description, :enabled, :group, :severity
    attr_reader :conditions, :dampenings
    def initialize(trigger_hash)
      @conditions = []
      @dampenings = []
      @id = trigger_hash['id']
      @name = trigger_hash['name']
      @enabled = trigger_hash['enabled']
      @severity = trigger_hash['severity']
    end

    class Condition
      attr_reader :condition_id, :type, :operator_low, :operator_high, :threshold_low
      attr_reader :in_range, :threshold_high

      def initialize(cond_hash)
        @condition_id = cond_hash['conditionId']
        @type = cond_hash['type']
        @operator_low = cond_hash['operatorLow']
        @operator_high = cond_hash['operatorHigh']
        @threshold_low = cond_hash['thresholdLow']
        @threshold_high = cond_hash['thresholdHigh']
        @in_range = cond_hash['inRange']
      end
    end

    class Dampening
      attr_reader :dampeining_id, :type, :eval_true_setting, :eval_total_setting, :eval_time_setting
      attr_reader :current_evals

      def initialize(damp_hash)
        @current_evals = {}
        @dampening_id = damp_hash['dampeningId']
        @type = damp_hash['type']
        @eval_true_setting = damp_hash['evalTrueSetting']
        @eval_total_setting = damp_hash['evalTotalSetting']
        @eval_time_setting = damp_hash['evalTimeSetting']
      end
    end
  end

  # Representation of one alert.
  # The name of the members are literally what they are in the JSON sent from the
  # server and not 'rubyfied'. So 'alertId' and not 'alert_ic'
  # Check http://www.hawkular.org/docs/rest/rest-alerts.html#Alert for details
  class Alert < OpenStruct
    def initialize(alert_hash)
      super(alert_hash)
    end
  end
end
