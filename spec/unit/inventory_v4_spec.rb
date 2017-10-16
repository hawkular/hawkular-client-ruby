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

  let(:resource) do
    Resource.new(resource_hash)
  end

  describe '#children' do
    it 'returns direct children' do
      expect(resource.children.size).to eq(3)
    end

    it 'returns all children' do
      expect(resource.children(true).size).to eq(6)
    end
  end

  describe '#children_by_type' do
    it 'returns direct children' do
      expect(resource.children_by_type('type-02').size).to eq(1)
    end

    it 'returns 0 when direct children type is not found' do
      expect(resource.children_by_type('type-03').size).to eq(0)
    end

    it 'works recursive' do
      expect(resource.children_by_type('type-02', true).size).to eq(3)
    end

    it 'works recursive and does not matter if the type is not on top' do
      expect(resource.children_by_type('type-03', true).size).to eq(1)
    end
  end
end
