# coding: utf-8
require 'fluent/plugin/google_cloud_pubsub/version'
require 'fluent/mixin/config_placeholders'

module Fluent
  class GoogleCloudPubSubOutput < BufferedOutput
    Fluent::Plugin.register_output('google_cloud_pubsub', self)

    config_set_default :buffer_type, 'memory'
    config_set_default :flush_interval, 1

    config_param :email, :string, default: nil
    config_param :private_key_path, :string, default: nil
    config_param :private_key_passphrase, :string, default: 'notasecret'
    config_param :project, :string
    config_param :topics, :string
    config_param :subscriptions, :string, default: nil
    config_param :auto_create_topic, :bool, default: true
    config_param :auto_create_subscription, :bool, default: true
    config_param :request_timeout, :integer, default: 60
    config_param :max_payload_size, :integer, default: 8388608  # 8MB

    unless method_defined?(:log)
      define_method("log") { $log }
    end

    def initialize
      super
      require 'base64'
      require 'json'
      require 'google/api_client'
    end

    def configure(conf)
      super
      raise Fluent::ConfigError, "'email' must be specifed" unless @email
      raise Fluent::ConfigError, "'private_key_path' must be specifed" unless @private_key_path
      raise Fluent::ConfigError, "'project' must be specifed" unless @project
      raise Fluent::ConfigError, "'topic' must be specifed" unless @topics
    end

    def client
      if @cached_client.nil?
        client = Google::APIClient.new(
          application_name: 'Fluentd plugin for Google Cloud Pub/Sub',
          application_version: Fluent::GoogleCloudPubSubPlugin::VERSION,
          faraday_option: { 'timeout' => @request_timeout }
        )

        key = Google::APIClient::KeyUtils.load_from_pkcs12(@private_key_path, @private_key_passphrase)

        client.authorization = Signet::OAuth2::Client.new(
          token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
          audience: 'https://accounts.google.com/o/oauth2/token',
          scope: ['https://www.googleapis.com/auth/pubsub', 'https://www.googleapis.com/auth/cloud-platform'],
          issuer: @email,
          signing_key: key
        )

        client.authorization.fetch_access_token!(:connection => client.connection)  # Work around certificate verify failed.

        @cached_client = client
      elsif @cached_client.authorization.expired?
        @cached_client.authorization.fetch_access_token!
      end

      @cached_client
    end

    def start
      super
      @cached_client = nil
      @exist_topic = {}
      @exist_subscription = {}
      @pubsub = client().discovered_api('pubsub', 'v1beta2')

      @topics_list = []
      @topics.split(",").each do |t|
        @topics_list.push "projects/#{@project}/topics/#{t}"
      end

      if @auto_create_topic
        @topics_list.each do |topic|
          create_topic(topic) unless exist_topic?(topic)
        end
      end

      @subscriptions_list = []
      if @subscriptions
        @subscriptions.split(",").each do |s|
          @subscriptions_list.push "projects/#{@project}/subscriptions/#{s}"
        end
      end

      if @auto_create_subscription
        if @subscriptions_list.empty?
          @topics_list.each do |topic|
            subscription = topic.sub(/\/topics\//, '/subscriptions/')
            create_subscription(subscription, topic) unless exist_subscription?(subscription)
          end
        else
          i = 0
          @subscriptions_list.each do |subscription|
            topic = @topics_list[i % @topics_list.length]
            create_subscription(subscription, topic) unless exist_subscription?(subscription)
            i += 1
          end
        end
      end

      @topics_mutex = Mutex.new
    end

    def format_stream(tag, es)
      buf = ''
      es.each do |time, record|
        buf << record.to_msgpack unless record.empty?
      end
      buf
    end

    def extract_response_obj(response_body)
      return nil unless response_body =~ /^{/
      JSON.parse(response_body)
    end

    def exist_subscription?(subscription)
      return true if @exist_subscription[subscription]

      res = client().execute(
        api_method: @pubsub.projects.subscriptions.get,
        parameters: {
          subscription: subscription
        }
      )

      unless res.success?
        unless res.status == 404
          res_obj = extract_response_obj(res.body)
          message = res_obj['error']['message'] || res.body
          log.error "pubsub.projects.subscriptions.get", subscription: subscription, code: res.status, message: message
        end
        return false
      else
        @exist_subscription[subscription] = 1
        return true
      end
    end

    def create_subscription(subscription, topic)
      res = client().execute(
        api_method: @pubsub.projects.subscriptions.create,
        parameters: {
          name: subscription
        },
        body_object: {
          topic: topic
        }
      )

      unless res.success?
        res_obj = extract_response_obj(res.body)
        message = res_obj['error']['message'] || res.body
        if res.status == 409
          @exist_subscription[subscription] = 1
          log.info "pubsub.projects.subscriptions.create", subscription: subscription, code: res.status, message: message
        else
          log.error "pubsub.projects.subscriptions.create", subscription: subscription, code: res.status, message: message
          raise "Failed to create subscription into Google Cloud Pub/Sub"
        end
      else
        @exist_subscription[subscription] = 1
        log.info "pubsub.projects.subscriptions.create", subscription: subscription, code: res.status
      end
    end

    def exist_topic?(topic)
      return true if @exist_topic[topic]

      res = client().execute(
        api_method: @pubsub.projects.topics.get,
        parameters: {
          topic: topic
        }
      )

      unless res.success?
        unless res.status == 404
          res_obj = extract_response_obj(res.body)
          message = res_obj['error']['message'] || res.body
          log.error "pubsub.projects.topics.get", topic: topic, code: res.status, message: message
        end
        return false
      else
        @exist_topic[topic] = 1
        return true
      end
    end

    def create_topic(topic)
      res = client().execute(
        api_method: @pubsub.projects.topics.create,
        parameters: {
          name: topic
        }
      )

      unless res.success?
        res_obj = extract_response_obj(res.body)
        message = res_obj['error']['message'] || res.body
        if res.status == 409
          @exist_topic[topic] = 1
          log.info "pubsub.projects.topics.create", topic: topic, code: res.status, message: message
        else
          log.error "pubsub.projects.topics.create", topic: topic, code: res.status, message: message
          raise "Failed to create topic into Google Cloud Pub/Sub"
        end
      else
        @exist_topic[topic] = 1
        log.info "pubsub.projects.topics.create", topic: topic, code: res.status
      end
    end

    def select_topic
      if @topics_list.length == 1
        @topics_list[0]
      else
        @topics_mutex.synchronize do
          topic = @topics_list.shift
          @topics_list.push topic
          topic
        end
      end
    end

    def publish(rows)
      topic = select_topic

      data = Base64.encode64(rows.to_json)

      if data.size > @max_payload_size and rows.length > 1
          log.debug "Divide this request because a payload size exceeds the allowable limit.", topic: topic, size: data.size, length: rows.length
          mid = rows.length / 2
          max = rows.length - 1
          divided_rows = []
          divided_rows << rows[0..mid-1]
          divided_rows << rows[mid..max]
          divided_rows.each {|r| publish(r)}
          return
      end

      messages = [{
        #attributes: {
        #  key: "value"
        #},
        data: data
      }]

      res = client().execute(
        api_method: @pubsub.projects.topics.publish,
        parameters: {
          topic: topic
        },
        body_object: {
          messages: messages
        }
      )

      res_obj = extract_response_obj(res.body)

      unless res.success?
        message = res_obj['error']['message'] || res.body
        log.error "pubsub.projects.topics.publish", topic: topic, code: res.status, message: message, size: data.size, length: rows.length
        raise "Failed to publish into Google Cloud Pub/Sub"
      else
        message = res_obj['messageIds'] || res.body
        log.debug "pubsub.projects.topics.publish", topic: topic, code: res.status, message: message, size: data.size, length: rows.length
      end
    end

    def write(chunk)
      rows = []
      chunk.msgpack_each do |row|
        rows << row
      end
      publish(rows)
    end
  end
end
