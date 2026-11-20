# frozen_string_literal: true

module RedmineKalvadSlack
  module Patches
    module IssuePatch
      def self.prepended(base)
        base.class_eval do
          after_create_commit :send_kalvad_slack_create
          after_update_commit :send_kalvad_slack_update
        end
      end

      private

      def send_kalvad_slack_create
        setting = kalvad_slack_setting
        return unless setting&.enabled?
        return unless setting.post_issue_created?
        return if is_private? && !setting.post_private_issues?

        payload = RedmineKalvadSlack::PayloadBuilder.issue_created(self, setting)
        RedmineKalvadSlack::Notifier.deliver(setting: setting, payload: payload)
      end

      def send_kalvad_slack_update
        return unless kalvad_slack_should_post_update?

        setting = kalvad_slack_setting
        payload = build_kalvad_slack_update_payload(setting)
        return if payload.nil?

        RedmineKalvadSlack::Notifier.deliver(setting: setting, payload: payload)
      end

      def kalvad_slack_should_post_update?
        return false if current_journal.nil?

        setting = kalvad_slack_setting
        return false unless setting&.enabled?
        return false if is_private? && !setting.post_private_issues?
        return false if current_journal.private_notes? && !setting.post_private_notes?
        return false if kalvad_slack_bot_note_only?

        true
      end

      # A note the n8n automation account posts on its own (the auto-acknowledgement
      # sent to the client) is noise in Slack. Anything else it does — a status or
      # assignee change, an attachment — still posts, note included. The account is
      # the one chosen in the redmine_n8n_webhook settings; without that plugin,
      # nothing is skipped.
      def kalvad_slack_bot_note_only?
        return false unless defined?(RedmineN8nWebhook) && RedmineN8nWebhook.respond_to?(:bot_user?)
        return false unless RedmineN8nWebhook.bot_user?(current_journal.user)

        current_journal.details.empty?
      end

      def build_kalvad_slack_update_payload(setting)
        if kalvad_slack_status_closed_transition?
          return nil unless setting.post_issue_closed?

          return RedmineKalvadSlack::PayloadBuilder.issue_closed(self, current_journal, setting)
        end

        return nil unless setting.post_issue_updated?

        RedmineKalvadSlack::PayloadBuilder.issue_updated(self, current_journal, setting)
      end

      def kalvad_slack_status_closed_transition?
        detail = current_journal.details.find { |d| d.property == 'attr' && d.prop_key == 'status_id' }
        return false if detail.nil?

        new_status = IssueStatus.find_by(id: detail.value)
        new_status&.is_closed?
      end

      def kalvad_slack_setting
        project&.kalvad_slack_setting
      end
    end
  end
end
