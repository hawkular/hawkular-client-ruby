require 'hawkular'
require 'ostruct'

# Alerts module provides access to Hawkular-Alerts.
# There are two main parts here: Triggers, that define alertable conditions
# and Alerts that represent a fired trigger.
# @see http://www.hawkular.org/docs/rest/rest-alerts.html
module Hawkular::Alerts
  # Interface to use to talk to the Hawkular-Alerts component.
  # @param entrypoint [String] base url of Hawkular-Alerts - e.g
  #   http://localhost:8080/hawkular/alerts
  # @param credentials [Hash{String=>String}] Hash of username, password, token(optional)
  class AlertsClient < Hawkular::BaseClient
    def initialize(entrypoint = nil, credentials = {})
      @entrypoint = entrypoint

      super(entrypoint, credentials)
    end

    # Lists defined triggers in the system
    # @param [Array] ids List of trigger ids. If provided, limits to the given triggers
    # @param [Array] tags List of tags. If provided, limits to the given tags
    # @return [Array<Trigger>] Triggers found
    def list_triggers(ids = [], tags = [])
      query = generate_query_params 'triggerIds' => ids, 'tags' => tags
      sub_url = '/triggers' + query

      ret = http_get(sub_url)

      val = []
      ret.each { |t| val.push(Trigger.new(t)) }
      val
    end

    # Obtains one Trigger definition from the server.
    # @param [String] trigger_id Id of the trigger to fetch
    # @param full If true then conditions and dampenings for the trigger are also fetched
    # @return [Trigger] the selected trigger
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

    # List fired alerts
    # @return [Array<Alert>] List of alerts in the system. Can be empty
    def list_alerts
      ret = http_get('/')
      val = []
      ret.each { |a| val.push(Alert.new(a)) }
      val
    end

    # Retrieve a single Alert by its id
    # @param [String] alert_id id of the alert to fetch
    # @return [Alert] Alert object retrieved
    def get_single_alert(alert_id)
      ret = http_get('/alert/' + alert_id)
      val = Alert.new(ret)
      val
    end

    # Mark one alert as resolved
    # @param [String] alert_id Id of the alert to resolve
    # @param [String] by name of the user resolving the alert
    # @param [String] comment A comment on the resolution
    def resolve_alert(alert_id, by = nil, comment = nil)
      sub_url = "/resolve/#{alert_id}"
      query = generate_query_params 'resolvedBy' => by, 'resolvedNotes' => comment
      sub_url += query
      http_put(sub_url, {})

      true
    end

    # Mark one alert as acknowledged
    # @param [String] alert_id Id of the alert to ack
    # @param [String] by name of the user acknowledging the alert
    # @param [String] comment A comment on the acknowledge
    def acknowledge_alert(alert_id, by = nil, comment = nil)
      sub_url = "/ack/#{alert_id}"
      query = generate_query_params 'ackBy' => by, 'ackNotes' => comment
      sub_url += query
      http_put(sub_url, {})

      true
    end
  end

  # Representation of one Trigger
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

    # Representing of one Condition
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

    # Representation of one Dampening setting
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
