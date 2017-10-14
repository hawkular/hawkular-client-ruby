require_relative '../spec_helper'

include Hawkular::InventoryV4
describe 'Inventory v4' do
  let(:resource_hash) do
    {
      'id' => 'root',
      'type' => {},
      'children' => [
        { 'id' => 'child-01', 'type' => { 'id' => 'type-01' }, 'children' => [] },
        { 'id' => 'child-02', 'type' => { 'id' => 'type-02' },
          'children' => [
            { 'id' => 'child-03', 'type' => { 'id' => 'type-02' }, 'children' => [] },
            { 'id' => 'child-04', 'type' => { 'id' => 'type-02' }, 'children' => [] },
            { 'id' => 'child-05', 'type' => { 'id' => 'type-03' }, 'children' => [] }
          ]
        },
        { 'id' => 'child-06', 'type' => { 'id' => 'type-01' }, 'children' => [] }
      ]
    }
  end

  describe 'children by type' do
    it 'should return direct children' do
      r = Resource.new(resource_hash)
      expect(r.children_by_type('type-02').size).to eq(1)
    end

    it 'should return 0 when direct children type is not found' do
      r = Resource.new(resource_hash)
      expect(r.children_by_type('type-03').size).to eq(0)
    end

    it 'should work recursive' do
      r = Resource.new(resource_hash)
      expect(r.children_by_type('type-02', true).size).to eq(3)
    end

    it 'should work recursive when the type is not on top' do
      r = Resource.new(resource_hash)
      expect(r.children_by_type('type-03', true).size).to eq(1)
    end
  end
end
