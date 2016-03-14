require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"

module Hawkular::Alerts::RSpec
  ALERTS_BASE = 'http://localhost:8080/hawkular/alerts'
  creds = { username: 'jdoe', password: 'password' }

  describe 'Alert/Triggers', vcr: { decode_compressed_response: true } do
    before(:each) do
      @client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)
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

      @client.bulk_load_triggers trigger_hash

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

  describe 'Alert/Alerts', :vcr do
    it 'Should list alerts' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      alerts = client.list_alerts

      expect(alerts).to_not be_nil
      expect(alerts.size).to be(2)
    end

    it 'Should list alerts for trigger' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      alerts = client.get_alerts_for_trigger '75bfdd05-d03d-481e-bf32-c724c7719d8b~Local_jvm_pheap'

      expect(alerts).to_not be_nil
      expect(alerts.size).to be(1)
    end

    it 'Should list alerts for unknown trigger' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      alerts = client.get_alerts_for_trigger 'does-not-exist'

      expect(alerts).to_not be_nil
      expect(alerts.size).to be(0)
    end

    it 'Should fetch single alert' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      alert = client.get_single_alert(
        '28026b36-8fe4-4332-84c8-524e173a68bf-snert~Local_jvm_garba-1446977734134')

      expect(alert).to_not be_nil
      expect(alert.alertId)
        .to eql('28026b36-8fe4-4332-84c8-524e173a68bf-snert~Local_jvm_garba-1446977734134')
    end

    it 'Should resolve an alert' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

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
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      alert_id = '28026b36-8fe4-4332-84c8-524e173a68bf-snert~Local_jvm_garba-1446977734134'
      client.get_single_alert alert_id

      client.acknowledge_alert(alert_id, 'Heiko', 'Hello Ruby World :-)')

      alert = client.get_single_alert alert_id
      expect(alert.ackBy).to eql('Heiko')
    end
  end

  # TODO: enable when alerts supports it
  # describe 'Alerts' do
  #   it 'Should return the version' do
  #     data = @client.get_version_and_status
  #     expect(data).not_to be_nil
  #   end
  # end

  describe 'Alert/Events', :vcr do
    VCR.configure do |c|
      c.default_cassette_options = {
        match_requests_on: [:method, VCR.request_matchers.uri_without_params(:startTime, :endTime)]
      }
    end

    it 'Should list events' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      events = client.list_events('thin' => true)

      expect(events).to_not be_nil
      expect(events.size).to be(12)
    end

    it 'Should list events using criteria' do
      now = Time.new.to_i
      start_time = (now - 7_200) * 1000
      end_time = now * 1000

      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      events = client.list_events('startTime' => start_time, 'endTime' => end_time)

      expect(events).to_not be_nil
      expect(events.size).to be(1)
    end

    it 'Should not list events using criteria' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      events = client.list_events('startTime' => 0, 'endTime' => 1000)

      expect(events).to_not be_nil
      expect(events.size).to be(0)
    end
  end

  describe 'Alert/EndToEnd', vcr: { decode_compressed_response: true } do
    before(:each) do
      @client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)
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
        metric_client = Hawkular::Metrics::Client.new('http://localhost:8080/hawkular/metrics',
                                                      creds)

        data_point = { timestamp: Time.now.to_i * 1000, value: 42 }
        data = [{ id: 'my-metric-id1', data: [data_point] }]

        metric_client.push_data(gauges: data)

        # wait 2s for the alert engine to work
        sleep 2

        # see if alert has fired
        alerts = @client.get_alerts_for_trigger 'my-cool-email-trigger'
        expect(alerts).to_not be(nil)
        alerts.each { |al| @client.resolve_alert(al.id, 'Heiko', 'Hello Ruby World :-)') }

      ensure
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
      end
    end
  end
end
