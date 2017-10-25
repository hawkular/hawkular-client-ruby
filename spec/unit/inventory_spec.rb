require_relative '../spec_helper'

include Hawkular::Inventory
describe 'Inventory' do
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

  describe 'ResultFetcher' do
    batches = [[1, 2], [3, 4], [5]]
    page_size = 2

    it 'fetches two first pages' do
      calls_count = 0
      fetch_func = lambda do |offset|
        calls_count += 1
        { 'startOffset' => offset, 'resultSize' => 5, 'results' => batches[offset / page_size] }
      end
      result_fetcher = Hawkular::Inventory::ResultFetcher.new(fetch_func)

      # Take first three items, expecting 2 calls
      values = result_fetcher.take(3)
      expect(values).to eq([1, 2, 3])
      expect(calls_count).to eq(2)
    end

    it 'fetches all pages while asking more' do
      calls_count = 0
      fetch_func = lambda do |offset|
        calls_count += 1
        { 'startOffset' => offset, 'resultSize' => 5, 'results' => batches[offset / page_size] }
      end
      result_fetcher = Hawkular::Inventory::ResultFetcher.new(fetch_func)

      # Take more, expecting 3 calls
      values = result_fetcher.take(10)
      expect(values).to eq([1, 2, 3, 4, 5])
      expect(calls_count).to eq(3)
    end

    it 'fetches all pages' do
      calls_count = 0
      fetch_func = lambda do |offset|
        calls_count += 1
        { 'startOffset' => offset, 'resultSize' => 5, 'results' => batches[offset / page_size] }
      end
      result_fetcher = Hawkular::Inventory::ResultFetcher.new(fetch_func)

      expect(result_fetcher.collect { |i| i }).to eq([1, 2, 3, 4, 5])
      expect(calls_count).to eq(3)
    end
  end
end
