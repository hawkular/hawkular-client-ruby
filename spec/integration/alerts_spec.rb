require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"

module Hawkular::Alerts::RSpec
  ALERTS_BASE = 'http://localhost:8080/hawkular/alerts'
  creds = { username: 'jdoe', password: 'password' }
  options = { tenant: 'hawkular' }

  describe 'Alert/Triggers', vcr: { decode_compressed_response: true } do
    before(:each) do
      @client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)
    end

    it 'Should List Triggers' do
      triggers = @client.list_triggers

      expect(triggers.size).to be(3)
    end

    it 'Should List Triggers for Tag' do
      triggers = @client.list_triggers [],
                                       ['resourceId|75bfdd05-d03d-481e-bf32-c724c7719d8b~Local']

      expect(triggers.size).to be(7)
    end

    it 'Should List Triggers for Tags' do
      triggers = @client.list_triggers [],
                                       ['resourceId|75bfdd05-d03d-481e-bf32-c724c7719d8b~Local',
                                        'app|MyShop']

      expect(triggers.size).to be(7)
    end

    it 'Should List Triggers for ID' do
      triggers = @client.list_triggers ['75bfdd05-d03d-481e-bf32-c724c7719d8b~Local_jvm_pheap']

      expect(triggers.size).to be(1)
    end

    it 'Should get a single metric Trigger' do
      trigger = @client.get_single_trigger('snert~Local_jvm_nheap')

      expect(trigger).not_to be_nil
    end

    it 'Should get a single Trigger with conditions' do
      trigger = @client.get_single_trigger 'snert~Local_jvm_nheap', true

      expect(trigger).not_to be_nil
      expect(trigger.conditions.size).to be(1)
      expect(trigger.dampenings.size).to be(1)
    end

    it 'Should bulk load triggers' do
      json = IO.read('spec/integration/hello-world-definitions.json')
      trigger_hash = JSON.parse(json)

      @client.bulk_import_triggers trigger_hash

      trigger = @client.get_single_trigger 'hello-world-trigger', true
      expect(trigger).not_to be_nil
      expect(trigger.conditions.size).to be(2)
      expect(trigger.dampenings.size).to be(0)

      @client.delete_trigger(trigger.id)
    end

    it 'Should create a basic trigger with action' do
      @client.create_action :email, 'send-via-email', 'notify-to-admins' => 'joe@acme.org'

      # Create the trigger
      t = Hawkular::Alerts::Trigger.new({})
      t.enabled = true
      t.id = 'my-cool-trigger'
      t.name = 'Just a trigger'
      t.severity = :HIGH
      t.description = 'Just a test trigger'

      # Create a condition
      c = Hawkular::Alerts::Trigger::Condition.new({})
      c.trigger_mode = :FIRING
      c.type = :THRESHOLD
      c.data_id = 'my-metric-id'
      c.operator = :LT
      c.threshold = 5

      # Reference an action definition
      a = Hawkular::Alerts::Trigger::Action.new({})
      a.action_plugin = :email
      a.action_id = 'send-via-email'
      t.actions.push a

      begin
        ft = @client.create_trigger t, [c], nil

        expect(ft).not_to be_nil

        trigger = @client.get_single_trigger t.id, true
        expect(trigger).not_to be_nil
        expect(trigger.conditions.size).to be(1)
        expect(trigger.dampenings.size).to be(0)
      ensure
        # rubocop:disable Lint/HandleExceptions
        begin
          @client.delete_trigger(t.id)
        rescue
          # I am not interested
        end
        begin
          @client.delete_action(a.action_id, a.action_plugin)
        rescue
          # I am not interested
        end
        # rubocop:enable Lint/HandleExceptions
      end
    end

    it 'Should create a firing ALL_ANY trigger' do
      # Create the trigger
      t = Hawkular::Alerts::Trigger.new({})
      t.enabled = true
      t.id = 'my-cool-trigger'
      t.name = 'Just a trigger'
      t.severity = :HIGH
      t.description = 'Just a test trigger'

      begin
        ft = @client.create_trigger t, [], nil
        expect(ft).not_to be_nil

        trigger = @client.get_single_trigger t.id, true
        expect(trigger.firing_match).to eq('ALL')
        expect(trigger.auto_resolve_match).to eq('ALL')

        @client.delete_trigger(t.id)

        t.firing_match = :ANY
        t.auto_resolve_match = :ANY

        ft = @client.create_trigger t, [], nil
        expect(ft).not_to be_nil

        trigger = @client.get_single_trigger t.id, true
        expect(trigger.firing_match).to eq('ANY')
        expect(trigger.auto_resolve_match).to eq('ANY')
      ensure
        # rubocop:disable Lint/HandleExceptions
        begin
          @client.delete_trigger(t.id)
        rescue
          # I am not interested
        end
        # rubocop:enable Lint/HandleExceptions
      end
    end

    it 'Should get the action definitions' do
      ret = @client.get_action_definition
      expect(ret.size).to be(2)
      expect(ret.key? 'email').to be_truthy

      ret = @client.get_action_definition 'email'
      expect(ret.size).to be(1)
      expect(ret['email'].size).to be(7)

      expect { @client.get_action_definition '-does-not-exist-' }
        .to raise_error(Hawkular::BaseClient::HawkularException)
    end

    it 'Should create an action' do
      @client.create_action 'email', 'my-id1', 'notify-to-admins' => 'joe@acme.org'
      @client.delete_action 'email', 'my-id1'
    end

    it 'Should not create an action for unknown plugin' do
      expect do
        @client.create_action '-does-not-exist',
                              'my-id2',
                              'notify-to-admins' => 'joe@acme.org'
      end.to raise_error(Hawkular::BaseClient::HawkularException)
    end

    it 'Should not create an action for unknown properties' do
      begin
        @client.create_action :email, 'my-id3', foo: 'bar'
      ensure
        @client.delete_action :email, 'my-id3'
      end
    end

    it 'Should create an action for webhooks' do
      begin
        @client.get_action_definition 'webhook'

        webhook_props = { 'url' => 'http://localhost:8080/bla', 'method' => 'POST' }
        @client.create_action 'webhook', 'my-id1',
                              webhook_props
        ret = @client.get_action 'webhook', 'my-id1'
        expect(ret.action_plugin).to eq('webhook')
        expect(ret.action_id).to eq('my-id1')

      ensure
        @client.delete_action 'webhook', 'my-id1'
      end
    end
  end

  describe 'Alert/Groups', vcr: { decode_compressed_response: true } do
    before(:each) do
      @client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)
    end

    it 'Should operate a complex group trigger' do
      # Create a group trigger
      t = Hawkular::Alerts::Trigger.new({})
      t.enabled = false
      t.id = 'a-group-trigger'
      t.name = 'A Group Trigger'
      t.severity = :HIGH
      t.description = 'A Group Trigger generated from test'

      # Create a condition
      c = Hawkular::Alerts::Trigger::Condition.new({})
      c.trigger_mode = :FIRING
      c.type = :THRESHOLD
      c.data_id = 'my-metric-id'
      c.operator = :LT
      c.threshold = 5

      # Create a group condition
      # no members yet
      gc = Hawkular::Alerts::Trigger::GroupConditionsInfo.new([c])

      # Create a member
      m1 = Hawkular::Alerts::Trigger::GroupMemberInfo.new
      m1.group_id = 'a-group-trigger'
      m1.member_id = 'member1'
      m1.member_name = 'Member One'
      m1.data_id_map = { 'my-metric-id' => 'my-metric-id-member1' }

      # Create a second member
      m2 = Hawkular::Alerts::Trigger::GroupMemberInfo.new
      m2.group_id = 'a-group-trigger'
      m2.member_id = 'member2'
      m2.member_name = 'Member Two'
      m2.data_id_map = { 'my-metric-id' => 'my-metric-id-member2' }

      # Create a dampening for the group trigger
      d = Hawkular::Alerts::Trigger::Dampening.new(
        'triggerId'        => 'a-group-trigger',
        'triggerMode'      => :FIRING,
        'type'             => :STRICT,
        'evalTrueSetting'  => 2,
        'evalTotalSetting' => 2
      )

      # Create a second condition
      c2 = Hawkular::Alerts::Trigger::Condition.new({})
      c2.trigger_mode = :FIRING
      c2.type = :THRESHOLD
      c2.data_id = 'my-metric-id2'
      c2.operator = :GT
      c2.threshold = 50

      # Create the second group condition
      # member2 is an orphan so, no need to update it into the data_id_member_map
      gc2 = Hawkular::Alerts::Trigger::GroupConditionsInfo.new([c, c2])
      gc2.data_id_member_map = {
        'my-metric-id'  => { 'member1' => 'my-metric-id-member1' },
        'my-metric-id2' => { 'member1' => 'my-metric-id2-member1' }
      }

      # Create a third condition of type compare
      c3 = Hawkular::Alerts::Trigger::Condition.new({})
      c3.trigger_mode = :FIRING
      c3.type = :COMPARE
      c3.data_id = 'my-metric-id3'
      c3.operator = :GT
      c3.data2_id = 'my-metric-id4'
      c3.data2_multiplier = 1

      # Create the thrid group condition
      # member 2 is still an orphan, no need to update it into the data_id_member_map
      gc3 = Hawkular::Alerts::Trigger::GroupConditionsInfo.new([c, c2, c3])
      gc3.data_id_member_map = {
        'my-metric-id'  => { 'member1' => 'my-metric-id-member1' },
        'my-metric-id2' => { 'member1' => 'my-metric-id2-member1' },
        'my-metric-id3' => { 'member1' => 'my-metric-id3-member1' },
        'my-metric-id4' => { 'member1' => 'my-metric-id4-member1' }
      }

      begin
        group_trigger = @client.create_group_trigger t
        expect(group_trigger).not_to be_nil
        expect(group_trigger.type).to eq('GROUP')

        created_conditions = @client.set_group_conditions t.id, :FIRING, gc
        expect(created_conditions.size).to be(1)

        member1 = @client.create_member_trigger m1
        expect(member1.type).to eq('MEMBER')

        full_member1 = @client.get_single_trigger member1.id, true
        expect(full_member1).not_to be_nil
        expect(full_member1.id).to eq('member1')
        expect(full_member1.conditions.size).to be(1)
        expect(full_member1.conditions[0].data_id).to eq('my-metric-id-member1')

        members = @client.list_members t.id
        expect(members.size).to be(1)

        member2 = @client.create_member_trigger m2
        expect(member2.type).to eq('MEMBER')

        full_member2 = @client.get_single_trigger member2.id, true
        expect(full_member2).not_to be_nil
        expect(full_member2.id).to eq('member2')
        expect(full_member2.conditions.size).to be(1)
        expect(full_member2.conditions[0].data_id).to eq('my-metric-id-member2')

        members = @client.list_members t.id
        expect(members.size).to be(2)

        member2 = @client.orphan_member member2.id
        expect(member2.type).to eq('ORPHAN')

        members = @client.list_members t.id
        expect(members.size).to be(1)

        orphans = @client.list_members t.id, true
        expect(orphans.size).to be(2)

        group_dampening = @client.create_group_dampening d
        expect(group_dampening).not_to be_nil
        expect(group_dampening.type).to eq('STRICT')

        full_member1 = @client.get_single_trigger member1.id, true
        expect(full_member1).not_to be_nil
        expect(full_member1.id).to eq('member1')
        expect(full_member1.dampenings.size).to be(1)
        expect(full_member1.dampenings[0].eval_true_setting).to be(2)
        expect(full_member1.dampenings[0].eval_total_setting).to be(2)

        group_trigger.tags = { 'group-tname' => 'group-tvalue' }
        group_trigger = @client.update_group_trigger group_trigger

        full_member1 = @client.get_single_trigger member1.id, false
        expect(full_member1).not_to be_nil
        expect(full_member1.tags['group-tname']).to eq('group-tvalue')

        created_conditions = @client.set_group_conditions t.id, :FIRING, gc2
        expect(created_conditions.size).to be(2)

        full_member1 = @client.get_single_trigger member1.id, true
        expect(full_member1).not_to be_nil
        expect(full_member1.conditions.size).to be(2)

        group_dampening.type = :RELAXED_COUNT
        group_dampening.eval_true_setting = 2
        group_dampening.eval_total_setting = 4
        group_dampening = @client.update_group_dampening group_dampening

        group_trigger.context = { 'alert-profiles' => 'profile1' }
        @client.update_group_trigger group_trigger

        @client.delete_group_dampening group_dampening.trigger_id, group_dampening.dampening_id

        full_member1 = @client.get_single_trigger member1.id, true
        expect(full_member1).not_to be_nil
        expect(full_member1.context['alert-profiles']).to eq('profile1')
        expect(full_member1.dampenings.size).to be(0)

        created_conditions = @client.set_group_conditions t.id, :FIRING, gc3
        expect(created_conditions.size).to be(3)

        full_member1 = @client.get_single_trigger member1.id, true
        expect(full_member1).not_to be_nil
        expect(full_member1.conditions.size).to be(3)
      ensure
        # rubocop:disable Lint/HandleExceptions
        begin
          @client.delete_group_trigger(t.id)
        rescue
          # I am not interested
        end
        # rubocop:enable Lint/HandleExceptions
      end
    end
  end

  describe 'Alert/Alerts', :vcr do
    it 'Should list alerts' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      alerts = client.list_alerts

      expect(alerts).to_not be_nil
      expect(alerts.size).to be(2)
    end

    it 'Should list alerts for trigger' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      alerts = client.get_alerts_for_trigger '75bfdd05-d03d-481e-bf32-c724c7719d8b~Local_jvm_pheap'

      expect(alerts).to_not be_nil
      expect(alerts.size).to be(1)
    end

    it 'Should list alerts for unknown trigger' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      alerts = client.get_alerts_for_trigger 'does-not-exist'

      expect(alerts).to_not be_nil
      expect(alerts.size).to be(0)
    end

    it 'Should fetch single alert' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      alert = client.get_single_alert(
        '28026b36-8fe4-4332-84c8-524e173a68bf-snert~Local_jvm_garba-1446977734134')

      expect(alert).to_not be_nil
      expect(alert.alertId)
        .to eql('28026b36-8fe4-4332-84c8-524e173a68bf-snert~Local_jvm_garba-1446977734134')
    end

    it 'Should resolve an alert' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      alert_id = '28026b36-8fe4-4332-84c8-524e173a68bf-snert~Local_jvm_garba-1446977734134'
      alert = client.get_single_alert alert_id

      expect(alert.status).to eql('OPEN')

      client.resolve_alert(alert_id, 'Heiko', 'Hello Ruby World :-)')

      alert = client.get_single_alert alert_id
      expect(alert.status).to eql('RESOLVED')
    end

    # # TODO enable when the semantics on the server side is known
    #     it 'Should resolve an alert2' do
    #       client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE,creds)
    #
    #       alert_id = '28026b36-8fe4-4332-84c8-524e173a68bf-snert~Local_jvm_garba-1446977734134'
    #       client.resolve_alert alert_id
    #
    #     end

    it 'Should acknowledge an alert' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      alert_id = '28026b36-8fe4-4332-84c8-524e173a68bf-snert~Local_jvm_garba-1446977734134'
      client.get_single_alert alert_id

      client.acknowledge_alert(alert_id, 'Heiko', 'Hello Ruby World :-)')

      alert = client.get_single_alert alert_id
      expect(alert.ackBy).to eql('Heiko')
    end
  end

  describe 'Alerts', vcr: { decode_compressed_response: true } do
    before(:each) do
      @client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)
    end

    it 'Should return the version' do
      data = @client.fetch_version_and_status
      expect(data).not_to be_nil
    end
  end

  describe 'Alert/Events', :vcr do
    VCR.configure do |c|
      c.default_cassette_options = {
        match_requests_on: [:method, VCR.request_matchers.uri_without_params(:startTime, :endTime)]
      }
    end

    it 'Should list events' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      events = client.list_events('thin' => true)

      expect(events).to_not be_nil
      expect(events.size).to be(12)
    end

    it 'Should list events using criteria' do
      now = Time.new.to_i
      start_time = (now - 7_200) * 1000
      end_time = now * 1000

      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      events = client.list_events('startTime' => start_time, 'endTime' => end_time)

      expect(events).to_not be_nil
      expect(events.size).to be(1)
    end

    it 'Should not list events using criteria' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

      events = client.list_events('startTime' => 0, 'endTime' => 1000)

      expect(events).to_not be_nil
      expect(events.size).to be(0)
    end

    it 'Should create an event' do
      the_id = "test-event@#{Time.new.to_i}"
      VCR.eject_cassette
      VCR.use_cassette('Alert/Events/Should_create_an_event',
                       erb: { id: the_id }, record: :none,
                       decode_compressed_response: true
                      ) do
        client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)

        the_event = client.create_event(the_id, 'MyCategory', 'Li la lu',
                                        context: { message: 'This is a test' },
                                        tags: { tag_name: 'tag-value' })

        expect(the_event['id']).to eql(the_id)
        expect(the_event['category']).to eql('MyCategory')

        client.delete_event the_id
      end
    end

    it 'Should delete an event' do
      the_id = "test-event@#{Time.new.to_i}"
      VCR.eject_cassette
      VCR.use_cassette('Alert/Events/Should_delete_an_event',
                       erb: { id: the_id }, record: :none,
                       decode_compressed_response: true
                      ) do
        client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)
        client.create_event(the_id, 'MyCategory', 'Li la lu',
                            context: { message: 'This is a test' },
                            tags: { tag_name: 'tag-value' })

        client.delete_event the_id
        the_event = client.list_events('thin' => true, 'eventIds' => [the_id]).first
        expect(the_event).to be_nil
      end
    end
  end

  describe 'Alert/EndToEnd', vcr: { decode_compressed_response: true } do
    before(:each) do
      @client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds, options)
    end

    it 'Should create and fire a trigger' do
      email_props = { to: 'joe@acme.org',
                      from: 'admin@acme.org' }
      begin
        @client.create_action 'email', 'send-via-email',
                              email_props
      rescue
        @client.delete_action 'email', 'send-via-email'
        @client.create_action 'email', 'send-via-email',
                              email_props
      end

      webhook_props = { url: 'http://172.31.7.177/',
                        method: 'POST' }
      begin
        @client.create_action 'webhook', 'send-via-webhook',
                              webhook_props
      rescue
        @client.delete_action 'webhook', 'send-via-webhook'
        @client.create_action 'webhook', 'send-via-webhook',
                              webhook_props
      end

      # Create the trigger
      t = Hawkular::Alerts::Trigger.new({})
      t.enabled = true
      t.id = 'my-cool-email-trigger'
      t.name = 'Just a trigger'
      t.severity = :HIGH
      t.description = 'Just a test trigger'

      # Create a condition
      c = Hawkular::Alerts::Trigger::Condition.new({})
      c.trigger_mode = :FIRING
      c.type = :THRESHOLD
      c.data_id = 'my-metric-id1'
      c.operator = :GT
      c.threshold = 5

      # Reference an action definition for email
      a = Hawkular::Alerts::Trigger::Action.new({})
      a.action_plugin = 'email'
      a.action_id = 'send-via-email'
      t.actions.push a

      # Reference an action definition for webhook
      a = Hawkular::Alerts::Trigger::Action.new({})
      a.action_plugin = 'webhook'
      a.action_id = 'send-via-webhook'
      t.actions.push a

      begin
        ft = @client.create_trigger t, [c], nil

        expect(ft).not_to be_nil

        trigger = @client.get_single_trigger t.id, true
        expect(trigger).not_to be_nil
        expect(trigger.conditions.size).to be(1)
        expect(trigger.dampenings.size).to be(0)

        # Trigger is set up - send a metric value to trigger it.
        metric_client = nil
        ::RSpec::Mocks.with_temporary_scope do
          mock_metrics_version
          metric_client = Hawkular::Metrics::Client.new('http://localhost:8080/hawkular/metrics',
                                                        creds, options)
        end

        data_point = { timestamp: Time.now.to_i * 1000, value: 42 }
        data = [{ id: 'my-metric-id1', data: [data_point] }]

        metric_client.push_data(gauges: data)

        # wait 2s for the alert engine to work if we are live
        sleep 2 if VCR.current_cassette.recording?

        # see if alert has fired
        alerts = @client.get_alerts_for_trigger 'my-cool-email-trigger'
        expect(alerts).to_not be(nil)
        alerts.each { |al| @client.resolve_alert(al.id, 'Heiko', 'Hello Ruby World :-)') }

      ensure
        # rubocop:disable Lint/HandleExceptions
        begin
          @client.delete_trigger(t.id)
        rescue
          # I am not interested
        end
        begin
          @client.delete_action('webhook', 'send-via-webhook')
        rescue
          # I am not interested
        end
        begin
          @client.delete_action('email', 'send-via-email')
        rescue
          # I am not interested
        end
        # rubocop:enable Lint/HandleExceptions
      end
    end
  end
end
