require_relative '../spec_helper'

include Hawkular::Inventory

describe 'CanonicalPath' do
  # positive cases :)
  context 'with valid path' do
    it 'should be parseable' do
      expect(CanonicalPath.parse('/t;t1/f;f1/r;r1'))
        .to be == CanonicalPath.new(tenant_id: 't1', feed_id: 'f1', resource_ids: ['r1'])

      expect(CanonicalPath.parse('/t;t1/f;f1/m;m1'))
        .to be == CanonicalPath.new(tenant_id: 't1', feed_id: 'f1', metric_id: 'm1')

      expect(CanonicalPath.parse('/t;t1/f;f1/rt;rt1'))
        .to be == CanonicalPath.new(tenant_id: 't1', feed_id: 'f1', resource_type_id: 'rt1')

      expect(CanonicalPath.parse('/t;t1/f;f1/mt;mt1'))
        .to be == CanonicalPath.new(tenant_id: 't1', feed_id: 'f1', metric_type_id: 'mt1')

      expect(CanonicalPath.parse('/t;t1/e;e1/r;r1'))
        .to be == CanonicalPath.new(tenant_id: 't1', environment_id: 'e1', resource_ids: ['r1'])

      expect(CanonicalPath.parse('/t;t1/e;e1/m;m1'))
        .to be == CanonicalPath.new(tenant_id: 't1', environment_id: 'e1', metric_id: 'm1')

      expect(CanonicalPath.parse('/t;t1/rt;rt1'))
        .to be == CanonicalPath.new(tenant_id: 't1', resource_type_id: 'rt1')

      expect(CanonicalPath.parse('/t;t1/mt;mt1'))
        .to be == CanonicalPath.new(tenant_id: 't1', metric_type_id: 'mt1')
    end

    it 'with resource hierarchy should be parseable' do
      expect(CanonicalPath.parse('/t;t1/f;f1/r;r1/r;r2/r;r3/r;r4/r;r5'))
        .to be == CanonicalPath.new(tenant_id: 't1', feed_id: 'f1', resource_ids: %w(r1 r2 r3 r4 r5))
      expect(CanonicalPath.parse('/t;t1/e;e1/r;r1/r;r2/r;r3'))
        .to be == CanonicalPath.new(tenant_id: 't1', environment_id: 'e1', resource_ids: %w(r1 r2 r3))
    end

    it 'with resource hierarchy should be upable' do
      expect(CanonicalPath.parse('/t;t1/f;f1/r;r1/r;r2/r;r3/r;r4/r;r5').up)
        .to be == CanonicalPath.new(tenant_id: 't1', feed_id: 'f1', resource_ids: %w(r1 r2 r3 r4))
      expect(CanonicalPath.parse('/t;t1/e;e1/r;r1').up)
        .to be == CanonicalPath.new(tenant_id: 't1', environment_id: 'e1', resource_ids: [])
      expect(CanonicalPath.parse('/t;t1/e;e1').up)
        .to be == CanonicalPath.new(tenant_id: 't1', environment_id: 'e1', resource_ids: [])
    end

    it 'should be identity when calling parse and then to_s' do
      path_str = '/t;t1/e;e1/r;r1/r;r2'
      path1 = CanonicalPath.parse(path_str)
      expect(CanonicalPath.parse(path1.to_s)).to be == path1
      expect(path1.to_s).to eql(path_str)

      path2 = CanonicalPath.new(tenant_id: 'tenant', resource_type_id: 'type')
      expect(CanonicalPath.parse(path2.to_s)).to be == path2
      expect(CanonicalPath.parse(CanonicalPath.parse(path2.to_s).to_s)).to be == path2
    end

    it 'should be readable' do
      tenant_id = 'tenant'
      feed_id = 'feed'
      metric_type_id = 'm_type'
      res1_id = 'resource_1'
      res2_id = 'resource_2'

      path = CanonicalPath.parse("/t;#{tenant_id}/f;#{feed_id}/mt;#{metric_type_id}")
      expect(path.tenant_id).to eql(tenant_id)
      expect(path.feed_id).to eql(feed_id)
      expect(path.metric_type_id).to eql(metric_type_id)

      other_path = CanonicalPath.parse("/t;#{tenant_id}/f;#{feed_id}/r;#{res1_id}/r;#{res2_id}")
      expect(other_path.tenant_id).to eql(tenant_id)
      expect(other_path.feed_id).to eql(feed_id)
      expect(other_path.resource_ids).to eql([res1_id, res2_id])
    end

    it 'should be immutable' do
      feed = Hawkular::Inventory::CanonicalPath.new(feed_id: 'feed')
      r1 = feed.down('r1')
      r2 = feed.down('r2')
      r3 = r1.down('r3')
      r1_again = r3.up
      feed_again = r1.up
      expect(feed.to_s).to eq('/t;/f;feed')
      expect(r1.to_s).to eq('/t;/f;feed/r;r1')
      expect(r2.to_s).to eq('/t;/f;feed/r;r2')
      expect(r3.to_s).to eq('/t;/f;feed/r;r1/r;r3')
      expect(r1_again.to_s).to eq('/t;/f;feed/r;r1')
      expect(feed_again.to_s).to eq('/t;/f;feed')
    end
  end

  # negative cases :(
  it 'with empty path cannot be parsed' do
    expect { CanonicalPath.parse(nil) }.to raise_error(Hawkular::ArgumentError)
    expect { CanonicalPath.parse('') }.to raise_error(Hawkular::ArgumentError)
    expect { CanonicalPath.parse(' ') }.to raise_error(Hawkular::ArgumentError)
  end

  context 'with no tenant id' do
    xit 'should not be parseable' do
      expect { CanonicalPath.parse('/f;myFeed/rt;resType') }.to raise_error(Hawkular::ArgumentError)
    end

    xit 'should not be constructed' do
      expect { CanonicalPath.new(feed_id: 'something') }.to raise_error(Hawkular::ArgumentError)
    end
  end

  it 'with empty path cannot be parsed' do
    expect { CanonicalPath.parse(nil) }.to raise_error(Hawkular::ArgumentError)
    expect { CanonicalPath.parse('') }.to raise_error(Hawkular::ArgumentError)
    expect { CanonicalPath.parse(' ') }.to raise_error(Hawkular::ArgumentError)
  end
end
