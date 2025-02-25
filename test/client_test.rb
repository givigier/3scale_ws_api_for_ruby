require 'minitest/autorun'

require 'fakeweb'
require 'mocha/setup'

require '3scale/client'

class ThreeScale::ClientTest < MiniTest::Unit::TestCase

  def client(options = {})
    ThreeScale::Client.new({:provider_key => '1234abcd'}.merge(options))
  end

  def setup
    FakeWeb.clean_registry
    FakeWeb.allow_net_connect = false

    @client = client
    @host   = ThreeScale::Client::DEFAULT_HOST
  end

  def test_raises_exception_if_provider_key_is_missing
    assert_raises ArgumentError do
      ThreeScale::Client.new({})
    end
  end

  def test_default_host
    client = ThreeScale::Client.new(:provider_key => '1234abcd')

    assert_equal 'su1.3scale.net', client.host
  end

  def test_custom_host
    client = ThreeScale::Client.new(:provider_key => '1234abcd', :host => "example.com")

    assert_equal 'example.com', client.host
  end

  def test_default_protocol
    client = ThreeScale::Client.new(:provider_key => 'test')
    assert_equal false, client.http.use_ssl?
  end

  def test_insecure_protocol
    client = ThreeScale::Client.new(:provider_key => 'test', :secure => false)
    assert_equal false, client.http.use_ssl?
  end

  def test_secure_protocol
    client = ThreeScale::Client.new(:provider_key => 'test', :secure => true)
    assert_equal true, client.http.use_ssl?
  end

  def test_authrep_usage_is_encoded
    assert_authrep_url_with_params "&%5Busage%5D%5Bmethod%5D=666"

    @client.authrep({:usage => {:method=> 666}})
  end

  def test_secure_authrep
    assert_secure_authrep_url_with_params
    client(:secure => true).authrep({})
  end

  def test_authrep_usage_values_are_encoded
    assert_authrep_url_with_params "&%5Busage%5D%5Bhits%5D=%230"

    @client.authrep({:usage => {:hits => "#0"}})
  end

  def test_authrep_usage_defaults_to_hits_1
    assert_authrep_url_with_params "&%5Busage%5D%5Bhits%5D=1"

    @client.authrep({})
  end

  def test_authrep_supports_app_id_app_key_auth_mode
    assert_authrep_url_with_params "&app_id=appid&app_key=appkey&%5Busage%5D%5Bhits%5D=1"

    @client.authrep(:app_id => "appid", :app_key => "appkey")
  end

  def test_authrep_supports_service_id
    assert_authrep_url_with_params "&%5Busage%5D%5Bhits%5D=1&service_id=serviceid"

    @client.authrep(:service_id => "serviceid")
  end

  #TODO these authrep tests
  # def test_authrep_supports_api_key_auth_mode; end
  # def test_authrep_log_is_encoded;end
  # def test_authrep_passes_all_params_to_backend;end

  def test_successful_authorize
    body = '<status>
              <authorized>true</authorized>
              <plan>Ultimate</plan>

              <usage_reports>
                <usage_report metric="hits" period="day">
                  <period_start>2010-04-26 00:00:00 +0000</period_start>
                  <period_end>2010-04-27 00:00:00 +0000</period_end>
                  <current_value>10023</current_value>
                  <max_value>50000</max_value>
                </usage_report>

                <usage_report metric="hits" period="month">
                  <period_start>2010-04-01 00:00:00 +0000</period_start>
                  <period_end>2010-05-01 00:00:00 +0000</period_end>
                  <current_value>999872</current_value>
                  <max_value>150000</max_value>
                </usage_report>
              </usage_reports>
            </status>'

    FakeWeb.register_uri(:get, "http://#{@host}/transactions/authorize.xml?provider_key=1234abcd&app_id=foo", :status => ['200', 'OK'], :body => body)

    response = @client.authorize(:app_id => 'foo')

    assert response.success?
    assert_equal 'Ultimate', response.plan
    assert_equal 2, response.usage_reports.size

    assert_equal :day, response.usage_reports[0].period
    assert_equal Time.utc(2010, 4, 26), response.usage_reports[0].period_start
    assert_equal Time.utc(2010, 4, 27), response.usage_reports[0].period_end
    assert_equal 10023, response.usage_reports[0].current_value
    assert_equal 50000, response.usage_reports[0].max_value

    assert_equal :month, response.usage_reports[1].period
    assert_equal Time.utc(2010, 4, 1), response.usage_reports[1].period_start
    assert_equal Time.utc(2010, 5, 1), response.usage_reports[1].period_end
    assert_equal 999872, response.usage_reports[1].current_value
    assert_equal 150000, response.usage_reports[1].max_value
  end

  def test_successful_authorize_with_app_keys
    body = '<status>
              <authorized>true</authorized>
              <plan>Ultimate</plan>
            </status>'

    FakeWeb.register_uri(:get, "http://#{@host}/transactions/authorize.xml?provider_key=1234abcd&app_id=foo&app_key=toosecret", :status => ['200', 'OK'], :body => body)

    response = @client.authorize(:app_id => 'foo', :app_key => 'toosecret')
    assert response.success?
  end

  def test_successful_authorize_with_user_key
    body = '<status>
              <authorized>true</authorized>
              <plan>Ultimate</plan>
            </status>'

    FakeWeb.register_uri(:get, "http://#{@host}/transactions/authorize.xml?provider_key=1234abcd&user_key=foo", :status => ['200', 'OK'], :body => body)

    response = @client.authorize(:user_key => 'foo')
    assert response.success?
  end

  def test_authorize_with_exceeded_usage_limits
    body = '<status>
              <authorized>false</authorized>
              <reason>usage limits are exceeded</reason>

              <plan>Ultimate</plan>

              <usage_reports>
                <usage_report metric="hits" period="day" exceeded="true">
                  <period_start>2010-04-26 00:00:00 +0000</period_start>
                  <period_end>2010-04-27 00:00:00 +0000</period_end>
                  <current_value>50002</current_value>
                  <max_value>50000</max_value>
                </usage_report>

                <usage_report metric="hits" period="month">
                  <period_start>2010-04-01 00:00:00 +0000</period_start>
                  <period_end>2010-05-01 00:00:00 +0000</period_end>
                  <current_value>999872</current_value>
                  <max_value>150000</max_value>
                </usage_report>
              </usage_reports>
            </status>'

    FakeWeb.register_uri(:get, "http://#{@host}/transactions/authorize.xml?provider_key=1234abcd&app_id=foo", :status => ['409'], :body => body)

    response = @client.authorize(:app_id => 'foo')

    assert !response.success?
    assert_equal 'usage limits are exceeded', response.error_message
    assert response.usage_reports[0].exceeded?
  end

  def test_authorize_with_invalid_app_id
    body = '<error code="application_not_found">application with id="foo" was not found</error>'

    FakeWeb.register_uri(:get, "http://#{@host}/transactions/authorize.xml?provider_key=1234abcd&app_id=foo", :status => ['403', 'Forbidden'], :body => body)

    response = @client.authorize(:app_id => 'foo')

    assert !response.success?
    assert_equal 'application_not_found',                   response.error_code
    assert_equal 'application with id="foo" was not found', response.error_message
  end

  def test_authorize_with_server_error
    FakeWeb.register_uri(:get, "http://#{@host}/transactions/authorize.xml?provider_key=1234abcd&app_id=foo", :status => ['500', 'Internal Server Error'], :body => 'OMG! WTF!')

    assert_raises ThreeScale::ServerError do
      @client.authorize(:app_id => 'foo')
    end
  end

  def test_successful_oauth_authorize
    body = '<status>
              <authorized>true</authorized>
              <application>
                <id>94bd2de3</id>
                <key>883bdb8dbc3b6b77dbcf26845560fdbb</key>
                <redirect_url>http://localhost:8080/oauth/oauth_redirect</redirect_url>
              </application>
              <plan>Ultimate</plan>
              <usage_reports>
                <usage_report metric="hits" period="week">
                  <period_start>2012-01-30 00:00:00 +0000</period_start>
                  <period_end>2012-02-06 00:00:00 +0000</period_end>
                  <max_value>5000</max_value>
                  <current_value>1</current_value>
                </usage_report>
                <usage_report metric="update" period="minute">
                  <period_start>2012-02-03 00:00:00 +0000</period_start>
                  <period_end>2012-02-03 00:00:00 +0000</period_end>
                  <max_value>0</max_value>
                  <current_value>0</current_value>
                </usage_report>
              </usage_reports>
            </status>'

    FakeWeb.register_uri(:get, "http://#{@host}/transactions/oauth_authorize.xml?provider_key=1234abcd&app_id=foo&redirect_url=http%3A%2F%2Flocalhost%3A8080%2Foauth%2Foauth_redirect", :status => ['200', 'OK'], :body => body)

    response = @client.oauth_authorize(:app_id => 'foo', :redirect_url => "http://localhost:8080/oauth/oauth_redirect")
    assert response.success?

    assert_equal '883bdb8dbc3b6b77dbcf26845560fdbb', response.app_key
    assert_equal 'http://localhost:8080/oauth/oauth_redirect', response.redirect_url

    assert_equal 'Ultimate', response.plan
    assert_equal 2, response.usage_reports.size

    assert_equal :week, response.usage_reports[0].period
    assert_equal Time.utc(2012, 1, 30), response.usage_reports[0].period_start
    assert_equal Time.utc(2012, 02, 06), response.usage_reports[0].period_end
    assert_equal 1, response.usage_reports[0].current_value
    assert_equal 5000, response.usage_reports[0].max_value

    assert_equal :minute, response.usage_reports[1].period
    assert_equal Time.utc(2012, 2, 03), response.usage_reports[1].period_start
    assert_equal Time.utc(2012, 2, 03), response.usage_reports[1].period_end
    assert_equal 0, response.usage_reports[1].current_value
    assert_equal 0, response.usage_reports[1].max_value
  end

  def test_oauth_authorize_with_exceeded_usage_limits
    body = '<status>
              <authorized>false</authorized>
              <reason>usage limits are exceeded</reason>
              <application>
                <id>94bd2de3</id>
                <key>883bdb8dbc3b6b77dbcf26845560fdbb</key>
                <redirect_url>http://localhost:8080/oauth/oauth_redirect</redirect_url>
              </application>
              <plan>Ultimate</plan>
              <usage_reports>
                <usage_report metric="hits" period="day" exceeded="true">
                  <period_start>2010-04-26 00:00:00 +0000</period_start>
                  <period_end>2010-04-27 00:00:00 +0000</period_end>
                  <current_value>50002</current_value>
                  <max_value>50000</max_value>
                </usage_report>

                <usage_report metric="hits" period="month">
                  <period_start>2010-04-01 00:00:00 +0000</period_start>
                  <period_end>2010-05-01 00:00:00 +0000</period_end>
                  <current_value>999872</current_value>
                  <max_value>150000</max_value>
                </usage_report>
              </usage_reports>
            </status>'

    FakeWeb.register_uri(:get, "http://#{@host}/transactions/oauth_authorize.xml?provider_key=1234abcd&app_id=foo", :status => ['409'], :body => body)

    response = @client.oauth_authorize(:app_id => 'foo')

    assert !response.success?
    assert_equal 'usage limits are exceeded', response.error_message
    assert response.usage_reports[0].exceeded?
  end

  def test_oauth_authorize_with_invalid_app_id
    body = '<error code="application_not_found">application with id="foo" was not found</error>'

    FakeWeb.register_uri(:get, "http://#{@host}/transactions/oauth_authorize.xml?provider_key=1234abcd&app_id=foo", :status => ['403', 'Forbidden'], :body => body)

    response = @client.oauth_authorize(:app_id => 'foo')

    assert !response.success?
    assert_equal 'application_not_found',                   response.error_code
    assert_equal 'application with id="foo" was not found', response.error_message
  end

  def test_oauth_authorize_with_server_error
    FakeWeb.register_uri(:get, "http://#{@host}/transactions/oauth_authorize.xml?provider_key=1234abcd&app_id=foo", :status => ['500', 'Internal Server Error'], :body => 'OMG! WTF!')

    assert_raises ThreeScale::ServerError do
      @client.oauth_authorize(:app_id => 'foo')
    end
  end

  def test_report_raises_an_exception_if_no_transactions_given
    assert_raises ArgumentError do
      @client.report
    end
  end

  def test_successful_report
    FakeWeb.register_uri(:post, "http://#{@host}/transactions.xml",
                         :status => ['200', 'OK'])

    response = @client.report({:app_id    => 'foo',
                               :timestamp => Time.local(2010, 4, 27, 15, 00),
                               :usage     => {'hits' => 1}})

    assert response.success?
  end

  def test_report_encodes_transactions
    http_response = stub
    Net::HTTPSuccess.stubs(:===).with(http_response).returns(true)

    payload = {
      'transactions[0][app_id]'      => 'foo',
      'transactions[0][timestamp]'   => CGI.escape('2010-04-27 15:42:17 0200'),
      'transactions[0][usage][hits]' => '1',
      'transactions[1][app_id]'      => 'bar',
      'transactions[1][timestamp]'   => CGI.escape('2010-04-27 15:55:12 0200'),
      'transactions[1][usage][hits]' => '1',
      'provider_key'                 => '1234abcd'
    }

    @client.http.expects(:post)
    .with('/transactions.xml', payload)
    .returns(http_response)

    @client.report({:app_id    => 'foo',
                    :usage     => {'hits' => 1},
                    :timestamp => '2010-04-27 15:42:17 0200'},

                   {:app_id    => 'bar',
                    :usage     => {'hits' => 1},
                    :timestamp => '2010-04-27 15:55:12 0200'})
  end

  def test_failed_report
    error_body = '<error code="provider_key_invalid">provider key "foo" is invalid</error>'

    FakeWeb.register_uri(:post, "http://#{@host}/transactions.xml",
                         :status => ['403', 'Forbidden'],
                         :body   => error_body)

    client   = ThreeScale::Client.new(:provider_key => 'foo')
    response = client.report({:app_id => 'abc', :usage => {'hits' => 1}})

    assert !response.success?
    assert_equal 'provider_key_invalid',          response.error_code
    assert_equal 'provider key "foo" is invalid', response.error_message
  end

  def test_report_with_server_error
    FakeWeb.register_uri(:post, "http://#{@host}/transactions.xml",
                         :status => ['500', 'Internal Server Error'],
                         :body   => 'OMG! WTF!')

    assert_raises ThreeScale::ServerError do
      @client.report({:app_id => 'foo', :usage => {'hits' => 1}})
    end
  end

  def test_authorize_client_header_sent
    success_body = '<?xml version="1.0" encoding="UTF-8"?><status><authorized>true</authorized><plan>Default</plan><usage_reports><usage_report metric="hits" period="minute"><period_start>2014-08-22 09:06:00 +0000</period_start><period_end>2014-08-22 09:07:00 +0000</period_end><max_value>5</max_value><current_value>0</current_value></usage_report></usage_reports></status>'
    version       = ThreeScale::Client::VERSION
    FakeWeb.register_uri(:get, "http://#{@host}/transactions/authorize.xml?provider_key=foo&app_id=foo",
                         :status => ['200', 'OK'],
                         :body   => success_body)

    client = ThreeScale::Client.new(:provider_key => 'foo')
    response = client.authorize(:app_id => 'foo')

    assert response.success?
    request = FakeWeb.last_request
    assert_equal "plugin-ruby-v#{version}", request["X-3scale-User-Agent"]
    assert_equal "su1.3scale.net", request["host"]

  end

  def test_report_client_header_sent
    success_body = '<?xml version="1.0" encoding="UTF-8"?><status><authorized>true</authorized><plan>Default</plan><usage_reports><usage_report metric="hits" period="minute"><period_start>2014-08-22 09:06:00 +0000</period_start><period_end>2014-08-22 09:07:00 +0000</period_end><max_value>5</max_value><current_value>0</current_value></usage_report></usage_reports></status>'
    version       = ThreeScale::Client::VERSION
    FakeWeb.register_uri(:post, "http://#{@host}/transactions.xml",
                         :status => ['200', 'OK'],
                         :body   => success_body)
    client = ThreeScale::Client.new(:provider_key => 'foo')
    response = client.report({:app_id => 'abc', :usage => {'hits' => 1}})

    request = FakeWeb.last_request
    assert_equal "plugin-ruby-v#{version}", request["X-3scale-User-Agent"]
    assert_equal "su1.3scale.net", request["host"]
  end

  def test_authrep_client_header_sent
    success_body = '<?xml version="1.0" encoding="UTF-8"?><status><authorized>true</authorized><plan>Default</plan><usage_reports><usage_report metric="hits" period="minute"><period_start>2014-08-22 09:06:00 +0000</period_start><period_end>2014-08-22 09:07:00 +0000</period_end><max_value>5</max_value><current_value>0</current_value></usage_report></usage_reports></status>'
    version       = ThreeScale::Client::VERSION
    FakeWeb.register_uri(:get, "http://#{@host}/transactions/authrep.xml?provider_key=foo&app_id=abc&%5Busage%5D%5Bhits%5D=1",
                         :status => ['200', 'OK'],
                         :body   => success_body)

    client = ThreeScale::Client.new(:provider_key => 'foo')
    response = client.authrep(:app_id => 'abc')

    assert response.success?
    request = FakeWeb.last_request
    assert_equal "plugin-ruby-v#{version}", request["X-3scale-User-Agent"]
    assert_equal "su1.3scale.net", request["host"]
  end

  private

  #OPTIMIZE this tricky test helper relies on fakeweb catching the urls requested by the client
  # it is brittle: it depends in the correct order or params in the url
  #
  def assert_authrep_url_with_params(str, protocol = 'http')
    authrep_url = "#{protocol}://#{@host}/transactions/authrep.xml?provider_key=#{@client.provider_key}"
    params = str # unless str.scan(/log/)
    params << "&%5Busage%5D%5Bhits%5D=1" unless params.scan(/usage.*hits/)
    parsed_authrep_url = URI.parse(authrep_url + params)
    # set to have the client working
    body = '<status>
              <authorized>true</authorized>
              <plan>Ultimate</plan>
            </status>'

    # this is the actual assertion, if fakeweb raises the client is submiting with wrong params
    FakeWeb.register_uri(:get, parsed_authrep_url, :status => ['200', 'OK'], :body => body)
  end

  def assert_secure_authrep_url_with_params(str = '&%5Busage%5D%5Bhits%5D=1')
    assert_authrep_url_with_params(str, 'https')
  end
end

class ThreeScale::NetHttpPersistentClientTest < ThreeScale::ClientTest
  def client(options = {})
    ThreeScale::Client::HTTPClient.persistent_backend = ThreeScale::Client::HTTPClient::NetHttpPersistent
    ThreeScale::Client.new({:provider_key => '1234abcd', :persistent => true}.merge(options))
  end
end

class ThreeScale::NetHttpKeepAliveClientTest < ThreeScale::NetHttpPersistentClientTest
  def client(options = {})
    ThreeScale::Client::HTTPClient.persistent_backend = ThreeScale::Client::HTTPClient::NetHttpKeepAlive
    super
  end
end
