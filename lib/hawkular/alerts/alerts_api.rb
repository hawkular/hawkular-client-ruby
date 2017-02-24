require 'hawkular/base_client'
require 'ostruct'

# Alerts module provides access to Hawkular-Alerts.
# There are three main parts here:
#   Triggers, that define alertable conditions
#     Alerts, that represent a fired Alert trigger
#     Events, that represent a fired Event trigger or an externally injected event (hawkular, not miq event)
# @see http://www.hawkular.org/docs/rest/rest-alerts.html
module Hawkular::Alerts
  # Interface to use to talk to the Hawkular-Alerts component.
  # @param entrypoint [String] base url of Hawkular-Alerts - e.g
  #   http://localhost:8080/hawkular/alerts
  # @param credentials [Hash{String=>String}] Hash of username, password, token(optional)
  # @param options [Hash{String=>String}] Additional rest client options
  class Client < Hawkular::BaseClient
    def initialize(entrypoint, credentials = {}, options = {})
      entrypoint = normalize_entrypoint_url entrypoint, 'hawkular/alerts'
      @entrypoint = entrypoint

      super(entrypoint, credentials, options)
    end

    # Return version and status information for the used version of Hawkular-Alerting
    # @return [Hash{String=>String}]
    #         ('Implementation-Version', 'Built-From-Git-SHA1', 'status')
    def fetch_version_and_status
      http_get('/status')
    end

    # Lists defined triggers in the system
    # @param [Array] ids List of trigger ids. If provided, limits to the given triggers
    # @param [Array] tags List of tags. If provided, limits to the given tags. Individual
    # tags are of the format # key|value. Tags are OR'd together. If a tag-key shows up
    # more than once, only the last one is accepted
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

    # Import multiple trigger or action definitions specified as a hash to the server.
    # @param [Hash] hash The hash with the trigger and action definitions.
    #               see the https://git.io/va5UO for more details about the structure
    # @return [Hash] The newly entities as hash
    def bulk_import_triggers(hash)
      http_post 'import/all', hash
    end

    # Creates the trigger definition.
    # @param [Trigger] trigger The trigger to be created
    # @param [Array<Condition>] conditions Array of associated conditions
    # @param [Array<Dampening>] dampenings Array of associated dampenings
    # @return [Trigger] The newly created trigger
    def create_trigger(trigger, conditions = [], dampenings = [], _actions = [])
      full_trigger = {}
      full_trigger[:trigger] = trigger.to_h
      conds = []
      conditions.each { |c| conds.push(c.to_h) }
      full_trigger[:conditions] = conds
      damps = []
      dampenings.each { |d| damps.push(d.to_h) } unless dampenings.nil?
      full_trigger[:dampenings] = damps

      http_post 'triggers/trigger', full_trigger
    end

    # Creates the group trigger definition.
    # @param [Trigger] trigger The group trigger to be created
    # @return [Trigger] The newly created group trigger
    def create_group_trigger(trigger)
      ret = http_post 'triggers/groups', trigger.to_h
      Trigger.new(ret)
    end

    # Updates a given group trigger definition
    # @param [Trigger] trigger the group trigger to be updated
    # @return [Trigger] The updated group trigger
    def update_group_trigger(trigger)
      http_put "triggers/groups/#{trigger.id}/", trigger.to_h
      get_single_trigger trigger.id, false
    end

    # Creates the group conditions definitions.
    # @param [String] trigger_id ID of the group trigger to set conditions
    # @param [String] trigger_mode Mode of the trigger where conditions are attached (:FIRING, :AUTORESOLVE)
    # @param [GroupConditionsInfo] group_conditions_info the conditions to set into the group trigger with the mapping
    #                                                    with the data_id members map
    # @return [Array<Condition>] conditions Array of associated conditions
    def set_group_conditions(trigger_id, trigger_mode, group_conditions_info)
      ret = http_put "triggers/groups/#{trigger_id}/conditions/#{trigger_mode}", group_conditions_info.to_h
      conditions = []
      ret.each { |c| conditions.push(Trigger::Condition.new(c)) }
      conditions
    end

    # Creates a member trigger
    # @param [GroupMemberInfo] group_member_info the group member to be added
    # @return [Trigger] the newly created member trigger
    def create_member_trigger(group_member_info)
      ret = http_post 'triggers/groups/members', group_member_info.to_h
      Trigger.new(ret)
    end

    # Detaches a member trigger from its group trigger
    # @param [String] trigger_id ID of the member trigger to detach
    # @return [Trigger] the orphan trigger
    def orphan_member(trigger_id)
      http_post "triggers/groups/members/#{trigger_id}/orphan", {}
      get_single_trigger trigger_id, false
    end

    # Lists members of a group trigger
    # @param [String] trigger_id ID of the group trigger to list members
    # @param [boolean] orphans flag to include orphans
    # @return [Array<Trigger>] Members found
    def list_members(trigger_id, orphans = false)
      ret = http_get "triggers/groups/#{trigger_id}/members?includeOrphans=#{orphans}"
      ret.collect { |t| Trigger.new(t) }
    end

    # Creates a dampening for a group trigger
    # @param [Dampening] dampening the dampening to create
    # @return [Dampening] the newly created dampening
    def create_group_dampening(dampening)
      ret = http_post "triggers/groups/#{dampening.trigger_id}/dampenings", dampening.to_h
      Trigger::Dampening.new(ret)
    end

    # Updates a dampening for a group trigger
    # @param [Dampening] dampening the dampening to update
    # @return [Dampening] the updated dampening
    def update_group_dampening(dampening)
      ret = http_put "triggers/groups/#{dampening.trigger_id}/dampenings/#{dampening.dampening_id}", dampening.to_h
      Trigger::Dampening.new(ret)
    end

    # Deletes the dampening of a group trigger
    # @param [String] trigger_id ID of the group trigger
    # @param [String] dampening_id ID
    def delete_group_dampening(trigger_id, dampening_id)
      http_delete "/triggers/groups/#{trigger_id}/dampenings/#{dampening_id}"
    end

    # Deletes the trigger definition.
    # @param [String] trigger_id ID of the trigger to delete
    def delete_trigger(trigger_id)
      http_delete "/triggers/#{trigger_id}"
    end

    # Deletes the group trigger definition.
    # @param [String] trigger_id ID of the group trigger to delete
    def delete_group_trigger(trigger_id)
      http_delete "/triggers/groups/#{trigger_id}"
    end

    # Obtains action definition/plugin from the server.
    # @param [String] action_plugin Id of the action plugin to fetch. If nil, all the plugins are fetched
    def get_action_definition(action_plugin = nil)
      if action_plugin.nil?
        plugins = http_get('plugins')
      else
        plugins = [action_plugin]
      end
      ret = {}
      plugins.each do |p|
        ret[p] = http_get("/plugins/#{p}")
      end
      ret
    end

    # Creates the action.
    # @param [String] plugin The id of action definition/plugin
    # @param [String] action_id The id of action
    # @param [Hash] properties Troperties of action
    # @return [Action] The newly created action
    def create_action(plugin, action_id, properties = {})
      the_plugin = hawk_escape plugin
      # Check if plugin exists
      http_get("/plugins/#{the_plugin}")

      payload = { actionId: action_id, actionPlugin: plugin, properties: properties }
      ret = http_post('/actions', payload)
      Trigger::Action.new(ret)
    end

    # Obtains one action of given action plugin from the server.
    # @param [String] plugin Id of the action plugin
    # @param [String] action_id Id of the action
    # @return [Action] the selected trigger
    def get_action(plugin, action_id)
      the_plugin = hawk_escape plugin
      the_action_id = hawk_escape action_id
      ret = http_get "/actions/#{the_plugin}/#{the_action_id}"
      Trigger::Action.new(ret)
    end

    # Deletes the action of given action plugin.
    # @param [String] plugin Id of the action plugin
    # @param [String] action_id Id of the action
    def delete_action(plugin, action_id)
      the_plugin = hawk_escape plugin
      the_action_id = hawk_escape action_id
      http_delete "/actions/#{the_plugin}/#{the_action_id}"
    end

    # Obtain the alerts for the Trigger with the passed id
    # @param [String] trigger_id Id of the trigger that has fired the alerts
    # @return [Array<Alert>] List of alerts for the trigger. Can be empty
    def get_alerts_for_trigger(trigger_id) # TODO: add additional filters
      return [] unless trigger_id

      url = '/?triggerIds=' + trigger_id
      ret = http_get(url)
      val = []
      ret.each { |a| val.push(Alert.new(a)) }
      val
    end

    # List fired alerts
    # @param [Hash]criteria optional query criteria
    # @return [Array<Alert>] List of alerts in the system. Can be empty
    def list_alerts(criteria = {})
      query = generate_query_params(criteria)
      ret = http_get('/' + query)
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

    # List Events given optional criteria. Criteria keys are strings (not symbols):
    #  startTime   numeric, milliseconds from epoch
    #  endTime     numeric, milliseconds from epoch
    #  eventIds    array of strings
    #  triggerIds  array of strings
    #  categories  array of strings
    #  tags        array of strings, each tag of format 'name|value'. Specify '*' for value to match all values
    #  thin        boolean, return lighter events (omits triggering data for trigger-generated events)
    # @param [Hash] criteria optional query criteria
    # @return [Array<Event>] List of events. Can be empty
    def list_events(*criteria)
      query = generate_query_params(*criteria)
      http_get('/events' + query).map { |e| Event.new(e) }
    end

    # Inject an event into Hawkular-alerts
    # @param [String] id Id of the event must be unique
    # @param [String] category Event category for further distinction
    # @param [String] text Some text to the user
    # @param [Hash<String,Object>] extras additional parameters
    def create_event(id, category, text, extras)
      event = {}
      event['id'] = id
      event['ctime'] = Time.now.to_i * 1000
      event['category'] = category
      event['text'] = text
      event.merge!(extras) { |_key, v1, _v2| v1 }

      http_post('/events', event)
    end

    def delete_event(id)
      http_delete "/events/#{id}"
    end
  end

  # Representation of one Trigger
  ## (22 known properties: "enabled", "autoResolveMatch", "name", "memberOf", "autoEnable",
  # "firingMatch", "tags", "id", "source", "tenantId", "eventText", "context", "eventType",
  # "autoResolveAlerts", "dataIdMap", "eventCategory", "autoDisable", "type", "description",
  # "severity", "autoResolve", "actions"])
  class Trigger
    attr_accessor :id, :name, :context, :actions, :auto_disable, :auto_enable
    attr_accessor :auto_resolve, :auto_resolve_alerts, :tags, :type
    attr_accessor :tenant, :description, :group, :severity, :event_type, :event_category, :member_of, :data_id_map
    attr_reader :conditions, :dampenings
    attr_accessor :enabled, :actions, :firing_match, :auto_resolve_match

    def initialize(trigger_hash)
      return if trigger_hash.nil?

      @_hash = trigger_hash
      @conditions = []
      @dampenings = []
      @actions = []
      @id = trigger_hash['id']
      @name = trigger_hash['name']
      @enabled = trigger_hash['enabled']
      @severity = trigger_hash['severity']
      @auto_resolve = trigger_hash['autoResolve']
      @auto_resolve_alerts = trigger_hash['autoResolveAlerts']
      @event_type = trigger_hash['eventType']
      @event_category = trigger_hash['eventCategory']
      @member_of = trigger_hash['memberOf']
      @data_id_map = trigger_hash['dataIdMap']
      @tenant = trigger_hash['tenantId']
      @description = trigger_hash['description']
      @auto_enable = trigger_hash['autoEnable']
      @auto_disable = trigger_hash['autoDisable']
      @context = trigger_hash['context']
      @type = trigger_hash['type']
      @tags = trigger_hash['tags']
      @firing_match = trigger_hash['firingMatch']
      @auto_resolve_match = trigger_hash['autoResolveMatch']
      # acts = trigger_hash['actions']
      # acts.each { |a| @actions.push(Action.new(a)) } unless acts.nil?
    end

    def to_h
      trigger_hash = {}
      to_camel = lambda do |x|
        ret = x.to_s.split('_').collect(&:capitalize).join
        ret[0, 1].downcase + ret[1..-1]
      end
      fields = [:id, :name, :enabled, :severity, :auto_resolve, :auto_resolve_alerts, :event_type, :event_category,
                :description, :auto_enable, :auto_disable, :context, :type, :tags, :member_of, :data_id_map,
                :firing_match, :auto_resolve_match]

      fields.each do |field|
        camelized_field = to_camel.call(field)
        field_value = __send__ field
        trigger_hash[camelized_field] = field_value unless field_value.nil?
      end

      trigger_hash['tenantId'] = @tenant unless @tenant.nil?
      trigger_hash['actions'] = []
      @actions.each { |d| trigger_hash['actions'].push d.to_h }

      trigger_hash
    end

    # Representing of one Condition
    class Condition
      attr_accessor :condition_id, :type, :operator, :threshold
      attr_accessor :trigger_mode, :data_id, :data2_id, :data2_multiplier
      attr_reader :condition_set_size, :condition_set_index, :trigger_id

      def initialize(cond_hash)
        @condition_id = cond_hash['conditionId']
        @type = cond_hash['type']
        @operator = cond_hash['operator']
        @threshold = cond_hash['threshold']
        @type = cond_hash['type']
        @trigger_mode = cond_hash['triggerMode']
        @data_id = cond_hash['dataId']
        @data2_id = cond_hash['data2Id']
        @data2_multiplier = cond_hash['data2Multiplier']
        @trigger_id = cond_hash['triggerId']
        @interval = cond_hash['interval']
      end

      def to_h
        cond_hash = {}
        cond_hash['conditionId'] = @condition_id
        cond_hash['type'] = @type
        cond_hash['operator'] = @operator
        cond_hash['threshold'] = @threshold
        cond_hash['type'] = @type
        cond_hash['triggerMode'] = @trigger_mode
        cond_hash['dataId'] = @data_id
        cond_hash['data2Id'] = @data2_id
        cond_hash['data2Multiplier'] = @data2_multiplier
        cond_hash['triggerId'] = @trigger_id
        cond_hash['interval'] = @interval
        cond_hash
      end
    end

    # Representing of one GroupConditionsInfo
    # - The data_id_member_map should be null if the group has no members.
    # - The data_id_member_map should be null if this is a [data-driven] group trigger.
    #   In this case the member triggers are removed and will be re-populated as incoming data demands.
    # - For [non-data-driven] group triggers with existing members the data_id_member_map is handled as follows.
    #   For members not included in the dataIdMemberMap their most recently supplied dataIdMap will be used.
    #   This means that it is not necessary to supply mappings if the new condition set uses only dataIds found
    #   in the old condition set. If the new conditions introduce new dataIds a full dataIdMemberMap must be supplied.
    class GroupConditionsInfo
      attr_accessor :conditions, :data_id_member_map

      def initialize(conditions)
        @conditions = conditions
        @data_id_member_map = {}
      end

      def to_h
        cond_hash = {}
        cond_hash['conditions'] = []
        @conditions.each { |c| cond_hash['conditions'].push(c.to_h) }
        cond_hash['dataIdMemberMap'] = @data_id_member_map
        cond_hash
      end
    end

    # Representing of one GroupMemberInfo
    class GroupMemberInfo
      attr_accessor :group_id, :member_id, :member_name, :member_description
      attr_accessor :member_context, :member_tags, :data_id_map

      def to_h
        cond_hash = {}
        cond_hash['groupId'] = @group_id
        cond_hash['memberId'] = @member_id
        cond_hash['memberName'] = @member_name
        cond_hash['memberDescription'] = @member_description
        cond_hash['memberContext'] = @member_context
        cond_hash['memberTags'] = @member_tags
        cond_hash['dataIdMap'] = @data_id_map
        cond_hash
      end
    end

    # Representation of one Dampening setting
    class Dampening
      attr_accessor :dampening_id, :trigger_id, :type, :eval_true_setting, :eval_total_setting,
                    :eval_time_setting
      attr_accessor :current_evals

      def initialize(damp_hash)
        @current_evals = {}
        @dampening_id = damp_hash['dampeningId']
        @trigger_id = damp_hash['triggerId']
        @type = damp_hash['type']
        @eval_true_setting = damp_hash['evalTrueSetting']
        @eval_total_setting = damp_hash['evalTotalSetting']
        @eval_time_setting = damp_hash['evalTimeSetting']
      end

      def to_h
        cond_hash = {}
        cond_hash['dampeningId'] = @dampening_id
        cond_hash['triggerId'] = @trigger_id
        cond_hash['type'] = @type
        cond_hash['evalTrueSetting'] = @eval_true_setting
        cond_hash['evalTotalSetting'] = @eval_total_setting
        cond_hash['evalTimeSetting'] = @eval_time_setting
        cond_hash
      end
    end

    class Action
      attr_accessor :action_plugin, :action_id, :states, :tenant_id

      def initialize(action_hash)
        return if action_hash.nil?

        @action_plugin = action_hash['actionPlugin']
        @action_id = action_hash['actionId']
        @tenant_id = action_hash['tenantId']
        @states = action_hash['states']
      end

      def to_h
        action_hash = {}
        action_hash['actionPlugin'] = @action_plugin
        action_hash['actionId'] = @action_id
        action_hash['tenantId'] = @tenant_id
        action_hash['states'] = @states
        action_hash
      end
    end
  end

  # Representation of one alert.
  # The name of the members are literally what they are in the JSON sent from the
  # server and not 'rubyfied'. So 'alertId' and not 'alert_id'
  # Check http://www.hawkular.org/docs/rest/rest-alerts.html#Alert for details
  class Alert < OpenStruct
    attr_accessor :lifecycle

    def initialize(alert_hash)
      super(alert_hash)
      @lifecycle = alert_hash['lifecycle']
    end

    def ack_by
      status_by('ACKNOWLEDGED')
    end

    def resolved_by
      status_by('RESOLVED')
    end

    def status_by(status)
      a = @lifecycle.nil? ? [] : @lifecycle.select { |l| l['status'].eql? status }
      a.empty? ? nil : a.last['user']
    end

    # for some API back compatibility
    alias_method :ackBy, :ack_by
    alias_method :resolvedBy, :resolved_by
  end

  # Representation of one event.
  # The name of the members are literally what they are in the JSON sent from the
  # server and not 'rubyfied'. So 'eventId' and not 'event_id'
  # Check http://www.hawkular.org/docs/rest/rest-alerts.html#Event for details
  class Event < OpenStruct
    def initialize(event_hash)
      super(event_hash)
    end
  end

  AlertsClient = Client
  deprecate_constant :AlertsClient if self.respond_to? :deprecate_constant
end
