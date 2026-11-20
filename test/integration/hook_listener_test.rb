# frozen_string_literal: true

require_relative '../test_helper'

class KalvadSlackHookListenerTest < Redmine::IntegrationTest
  fixtures :projects, :users, :members, :member_roles, :roles,
           :issues, :issue_statuses, :trackers, :enumerations,
           :enabled_modules, :journals, :journal_details

  def setup
    KalvadSlackSetting.where(project_id: 1).destroy_all
    KalvadSlackSetting.create!(
      project_id: 1,
      webhook_url: 'https://hooks.slack.test/x',
      channel: '#redmine',
      enabled: true,
      post_issue_created: true,
      post_issue_updated: true,
      post_issue_closed: true
    )
    @calls = []
    RedmineKalvadSlack::Notifier.singleton_class.alias_method :__orig_deliver, :deliver
    RedmineKalvadSlack::Notifier.singleton_class.send(:define_method, :deliver) do |setting:, payload:|
      @calls << [setting, payload]
    end
    RedmineKalvadSlack::Notifier.instance_variable_set(:@calls, @calls)
  end

  def teardown
    RedmineKalvadSlack::Notifier.singleton_class.alias_method :deliver, :__orig_deliver
  end

  def test_issue_create_triggers_notifier
    issue = Issue.new(project_id: 1, tracker_id: 1, status_id: 1, priority_id: 5,
                      author_id: 2, subject: 'Hook test', description: 'd')
    assert issue.save
    assert_operator RedmineKalvadSlack::Notifier.instance_variable_get(:@calls).size, :>=, 1
  end

  def test_note_only_update_by_n8n_bot_is_skipped
    with_n8n_bot(2) do
      issue = Issue.find(1)
      issue.init_journal(User.find(2), 'Nous avons bien reçu votre demande.')
      assert issue.save
      assert_empty notifier_calls
    end
  end

  def test_field_change_by_n8n_bot_is_posted
    with_n8n_bot(2) do
      issue = Issue.find(1)
      issue.init_journal(User.find(2), 'Triage')
      issue.priority_id = 6
      assert issue.save
      assert_equal 1, notifier_calls.size
    end
  end

  def test_note_by_other_user_is_posted
    with_n8n_bot(2) do
      issue = Issue.find(1)
      issue.init_journal(User.find(3), 'Une vraie réponse')
      assert issue.save
      assert_equal 1, notifier_calls.size
    end
  end

  private

  def notifier_calls
    RedmineKalvadSlack::Notifier.instance_variable_get(:@calls)
  end

  # Stands in for redmine_n8n_webhook, which is not installed in this plugin's tests.
  def with_n8n_bot(user_id)
    created = !defined?(::RedmineN8nWebhook)
    Object.const_set(:RedmineN8nWebhook, Module.new) if created
    mod = ::RedmineN8nWebhook
    had = mod.respond_to?(:bot_user?)
    mod.singleton_class.alias_method(:__orig_bot_user?, :bot_user?) if had
    mod.define_singleton_method(:bot_user?) { |user| user&.id == user_id }
    yield
  ensure
    if had
      mod.singleton_class.alias_method(:bot_user?, :__orig_bot_user?)
    else
      mod.singleton_class.send(:remove_method, :bot_user?)
    end
    Object.send(:remove_const, :RedmineN8nWebhook) if created
  end
end
