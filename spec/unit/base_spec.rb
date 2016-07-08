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

    expect(ret).to eq('')
  end

  it 'should escape numbers' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.hawk_escape 12_345

    expect(ret).to eq('12345')
  end

  it 'should escape alpha' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.hawk_escape 'a12345'

    expect(ret).to eq('a12345')
  end

  it 'should escape strange stuff' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')
    ret = c.hawk_escape 'a1%2 3|45/'

    expect(ret).to eq('a1%252%203%7c45%2f')
  end

  it 'should pass http_proxy_uri to rest_client' do
    proxy_uri = 'http://myproxy.com'
    c = Hawkular::BaseClient.new('not-needed-for-this-test', {},
                                 { http_proxy_uri: proxy_uri })
    rc = c.rest_client('myurl')

    expect(rc.options[:proxy]).to eq(proxy_uri)
  end

  it 'Should normalize different types of url and suffix combinations with or without slash' do
    c = Hawkular::BaseClient.new('not-needed-for-this-test')

    ret = c.normalize_entrypoint_url 'http://localhost:8080', '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080', '/hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080', 'hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080', 'hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/', '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/', '/hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/', 'hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/', 'hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts', '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts', '/hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts', 'hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts', 'hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts/', '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts/', '/hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts/', 'hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://localhost:8080/hawkular/alerts/', 'hawkular/alerts'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'http://127.0.0.1/hawkular/alerts/', 'hawkular/alerts'
    expect(ret).to eq('http://127.0.0.1/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'https://127.0.0.1/hawkular/alerts/', 'hawkular/alerts'
    expect(ret).to eq('https://127.0.0.1/hawkular/alerts')

    ret = c.normalize_entrypoint_url 'https://localhost:8080/', 'hawkular/alerts'
    expect(ret).to eq('https://localhost:8080/hawkular/alerts')

    expect { c.normalize_entrypoint_url 'https://localhost:8080/hawkular/alerts', '' }.to raise_error(ArgumentError)

    uri = URI.parse 'https://localhost:8080/'
    ret = c.normalize_entrypoint_url uri, 'hawkular/alerts'
    expect(ret).to eq('https://localhost:8080/hawkular/alerts')

    uri = URI.parse 'http://localhost:8080/hawkular/alerts/'
    ret = c.normalize_entrypoint_url uri, '/hawkular/alerts/'
    expect(ret).to eq('http://localhost:8080/hawkular/alerts')
  end
end
