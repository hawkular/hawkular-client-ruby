require '#{File.dirname(__FILE__)}/../spec_helper'

describe 'Base Spec' do
  it 'should know encode' do
    creds = { username: 'jdoe', password: 'password' }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    val = c.base_64_credentials(creds)

    expect(val).to eql('amRvZTpwYXNzd29yZA==')
  end

  it 'should be empty' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params
    expect(ret).to eql('')
  end

  it 'should have one param' do
    params = { name: nil, value: 'hello' }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params params

    expect(ret).to eql('?value=hello')
  end

  it 'should have two params' do
    params = { name: 'world', value: 'hello' }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params params

    expect(ret).to include('value=hello')
    expect(ret).to include('name=world')
    expect(ret).to start_with('?')
    expect(ret).to include('&')
  end

  it 'should flatten arrays' do
    params = { value: %w(hello world) }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params params

    expect(ret).to eql('?value=hello,world')
  end

  it 'should flatten arrays2' do
    params = { value: [] }

    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.generate_query_params params

    expect(ret).to eql('')
  end
end
