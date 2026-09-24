# frozen_string_literal: true

require "test_helper"
require 'rack/test'
require 'prometheus_exporter/middleware'

class PrometheusExporterMiddlewareTest < Minitest::Test
  include Rack::Test::Methods

  class FakeClient
    attr_reader :last_send

    def send_json(args)
      @last_send = args
    end
  end

  def client
    @client ||= FakeClient.new
  end

  def inner_app
    Proc.new do |env|
      [200, {}, "OK"]
    end
  end

  def now
    @now = Process.clock_gettime(Process::CLOCK_REALTIME)
  end

  def app
    @middleware ||= begin
      app = PrometheusExporter::Middleware.new(inner_app, client: client, instrument: true)
      def app.request_start
        1234567891.123
      end
      app
    end
  end

  def test_converting_apache_request_start
    now_microsec = '1234567890123456'

    header 'X-Request-Start', "t=#{now_microsec}"
    get '/'
    assert last_response.ok?

    refute_nil client.last_send
    refute_nil client.last_send[:queue_time]
    assert_in_delta 1, client.last_send[:queue_time], 0.05
  end

  def test_converting_nginx_request_start
    now = '1234567890.123'
    header 'X-Request-Start', "t=#{now}"
    get '/'
    assert last_response.ok?

    refute_nil client.last_send
    refute_nil client.last_send[:queue_time]
    assert_in_delta 1, client.last_send[:queue_time], 0.05
  end

  def test_a_header_in_wrong_format
    header 'X-Request-Start', ""
    get '/'
    assert last_response.ok?

    refute_nil client.last_send
    assert_nil client.last_send[:queue_time]
  end

  def test_does_not_patch_redis_5_client
    with_fake_redis('5.4.1', instance_methods: []) do |client_class|
      PrometheusExporter::Middleware.new(inner_app, client: client, instrument: true)
      refute client_class.method_defined?(:call__mp_unpatched)
    end
  end

  def test_patches_redis_4_client
    with_fake_redis('4.8.1', instance_methods: [:call, :call_pipeline]) do |client_class|
      PrometheusExporter::Middleware.new(inner_app, client: client, instrument: true)
      assert client_class.method_defined?(:call__mp_unpatched)
    end
  end

  private

  def with_fake_redis(version, instance_methods:)
    client_class = Class.new
    instance_methods.each { |name| client_class.define_method(name) { |*| } }
    redis = Module.new
    redis.const_set(:VERSION, version)
    redis.const_set(:Client, client_class)
    Object.const_set(:Redis, redis)
    yield client_class
  ensure
    Object.send(:remove_const, :Redis)
  end
end
