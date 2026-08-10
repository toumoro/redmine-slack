# frozen_string_literal: true

module RedmineKalvadSlack
  class Notifier
    SUCCESS_CLASSES = [Net::HTTPSuccess, Net::HTTPRedirection].freeze
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 3

    def self.deliver(setting:, payload:)
      new(setting, payload).deliver
    end

    def initialize(setting, payload)
      @setting = setting
      @payload = payload
    end

    def deliver
      return if @setting.nil?
      return unless @setting.deliverable?

      post(@setting.webhook_url, build_body)
    end

    private

    def build_body
      body = @payload.merge(
        username: @setting.username.presence || 'Redmine',
        link_names: 1
      )
      body[:channel] = @setting.channel if @setting.channel.present?
      icon = @setting.icon.to_s
      if icon.start_with?(':')
        body[:icon_emoji] = icon
      elsif icon.start_with?('http')
        body[:icon_url] = icon
      end
      body
    end

    def post(url, body)
      uri = URI.parse(url)
      http = build_http(uri)
      req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
      req.body = body.to_json
      response = http.request(req)
      return if SUCCESS_CLASSES.any? { |klass| response.is_a?(klass) }

      Rails.logger.warn(
        "[redmine_kalvad_slack] non-2xx from Slack: #{response.code} #{response.body.to_s[0, 200]}"
      )
    rescue StandardError => e
      Rails.logger.warn("[redmine_kalvad_slack] delivery failed: #{e.class}: #{e.message}")
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http
    end
  end
end
