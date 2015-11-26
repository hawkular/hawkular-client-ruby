require "#{File.dirname(__FILE__)}/../vcr/vcr_setup"
require "#{File.dirname(__FILE__)}/../spec_helper"

module Hawkular::Alerts::RSpec
  ALERTS_BASE = 'http://localhost:8080/hawkular/alerts'
  creds = { username: 'jdoe', password: 'password' }

  describe 'Alert/Triggers', :vcr do
    it 'Should List Triggers' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      triggers = client.list_triggers

      expect(triggers.size).to be(3)
    end

    it 'Should List Triggers for Tag' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      triggers = client.list_triggers [], ['resourceId|75bfdd05-d03d-481e-bf32-c724c7719d8b~Local']

      expect(triggers.size).to be(7)
    end

    it 'Should List Triggers for Tags' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      triggers = client.list_triggers [], ['resourceId|75bfdd05-d03d-481e-bf32-c724c7719d8b~Local',
                                           'app|MyShop']

      expect(triggers.size).to be(7)
    end

    it 'Should List Triggers for ID' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      triggers = client.list_triggers ['75bfdd05-d03d-481e-bf32-c724c7719d8b~Local_jvm_pheap']

      expect(triggers.size).to be(1)
    end

    it 'Should get a single metric Trigger' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      trigger = client.get_single_trigger('snert~Local_jvm_nheap')

      expect(trigger).not_to be_nil
    end

    it 'Should get a single Trigger with conditions' do
      client = Hawkular::Alerts::AlertsClient.new(ALERTS_BASE, creds)

      trigger = client.get_single_trigger 'snert~Local_jvm_nheap', true

      expect(trigger).not_to be_nil
      expect(trigger.conditions.size).to be(1)
      expect(trigger.dampenings.size).to be(1)
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
end
