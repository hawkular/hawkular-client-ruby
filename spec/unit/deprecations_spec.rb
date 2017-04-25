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
    # example:
    # changed_constant from: HawkularUtilsMixin, to: Hawkular::ClientUtils
  end
end
