require_relative '../spec_helper'

include Hawkular::Inventory
describe 'Inventory' do
  let(:resource_hash) do
    {
      'id' => 'root',
      'type' => {},
      'metrics' => [
        { 'family' => 'm1' },
        { 'family' => 'm2' },
        { 'family' => 'm3' }
      ],
      'children' => [
        { 'id' => 'child-01', 'type' => { 'id' => 'type-01' }, 'children' => [], 'metrics' => [{ 'family' => 'm1' }] },
        { 'id' => 'child-02', 'type' => { 'id' => 'type-02' },
          'children' => [
            {
              'id' => 'child-03', 'type' => { 'id' => 'type-02' }, 'children' => [], 'metrics' => [{ 'family' => 'm4' }]
            },
            {
              'id' => 'child-04', 'type' => { 'id' => 'type-02' }, 'children' => [], 'metrics' => [{ 'family' => 'm5' }]
            },
            {
              'id' => 'child-05', 'type' => { 'id' => 'type-03' }, 'children' => [], 'metrics' => [{ 'family' => 'm6' }]
            }
          ],
          'metrics' => [{ 'family' => 'm1' }, { 'family' => 'm2' }, { 'family' => 'm3' }]
        },
        { 'id' => 'child-06', 'type' => { 'id' => 'type-01' }, 'children' => [], 'metrics' => [{ 'family' => 'm3' }] }
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

    it 'direct children are of type resource' do
      expect(resource.children).to all(be_a(::Hawkular::Inventory::Resource))
    end

    it 'all childrens are of type resource' do
      expect(resource.children(true)).to all(be_a(::Hawkular::Inventory::Resource))
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

  describe '#metrics' do
    it 'returns top level metrics' do
      expect(resource.metrics.size).to eq(3)
    end

    it 'returns all metrics on the tree' do
      expect(resource.metrics(true).size).to eq(11)
    end

    it 'top level metrics are of type Metric' do
      expect(resource.metrics).to all(be_a(::Hawkular::Inventory::Metric))
    end

    it 'all metrics on the tree are of type Metric' do
      expect(resource.metrics(true)).to all(be_a(::Hawkular::Inventory::Metric))
    end
  end

  describe '#metrics_by_family' do
    it 'return metrics by family' do
      expect(resource.metrics_by_family('m1').size).to eq(1)
      expect(resource.metrics_by_family('m1').first.family).to eq('m1')
    end
  end

  describe 'ResultFetcher' do
    batches = [[1, 2], [3, 4], [5]]
    page_size = 2
    calls_count = 0

    let(:result_fetcher) do
      calls_count = 0
      fetch_func = lambda do |offset|
        calls_count += 1
        { 'startOffset' => offset, 'resultSize' => 5, 'results' => batches[offset / page_size] }
      end
      Hawkular::Inventory::ResultFetcher.new(fetch_func)
    end

    it 'fetches two first pages' do
      # Take first three items, expecting 2 calls
      values = result_fetcher.take(3)
      expect(values).to eq([1, 2, 3])
      expect(calls_count).to eq(2)
    end

    it 'fetches all pages while asking more' do
      # Take more, expecting 3 calls
      values = result_fetcher.take(10)
      expect(values).to eq([1, 2, 3, 4, 5])
      expect(calls_count).to eq(3)
    end

    it 'fetches all pages' do
      expect(result_fetcher.collect { |i| i }).to eq([1, 2, 3, 4, 5])
      expect(calls_count).to eq(3)
    end
  end
end
