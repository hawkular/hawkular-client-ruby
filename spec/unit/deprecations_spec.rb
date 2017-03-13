require_relative '../spec_helper'

describe 'Deprecations' do
  def self.changed_constant(from:, to:)
    describe to do
      it 'is still accessible by its old name' do
        expect(from).to eq to
      end
    end
  end

  describe 'pre-3.0' do
    changed_constant from: HawkularUtilsMixin, to: Hawkular::ClientUtils
    changed_constant from: Hawkular::Operations::OperationsClient, to: Hawkular::Operations::Client
    changed_constant from: Hawkular::Alerts::AlertsClient, to: Hawkular::Alerts::Client
    changed_constant from: Hawkular::Token::TokenClient, to: Hawkular::Token::Client
    changed_constant from: Hawkular::Inventory::InventoryClient, to: Hawkular::Inventory::Client
  end
end
