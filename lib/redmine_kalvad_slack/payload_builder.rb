# frozen_string_literal: true

module RedmineKalvadSlack
  module PayloadBuilder
    SLACK_ESCAPES = { '&' => '&amp;', '<' => '&lt;', '>' => '&gt;' }.freeze

    ATTR_LABELS = {
      'subject' => :field_subject,
      'description' => :field_description,
      'status_id' => :field_status,
      'priority_id' => :field_priority,
      'assigned_to_id' => :field_assigned_to,
      'category_id' => :field_category,
      'fixed_version_id' => :field_fixed_version,
      'tracker_id' => :field_tracker,
      'project_id' => :field_project,
      'parent_id' => :field_parent_issue,
      'start_date' => :field_start_date,
      'due_date' => :field_due_date,
      'estimated_hours' => :field_estimated_hours,
      'done_ratio' => :field_done_ratio,
      'is_private' => :field_is_private
    }.freeze

    ATTR_FINDERS = {
      'status_id' => IssueStatus,
      'priority_id' => IssuePriority,
      'assigned_to_id' => User,
      'category_id' => IssueCategory,
      'fixed_version_id' => Version,
      'tracker_id' => Tracker,
      'project_id' => Project
    }.freeze

    module_function

    def issue_created(issue, setting)
      project = issue.project
      url = url_for_issue(issue)

      attachment = {
        color: Color::CREATED,
        title: "#{issue.tracker.name} ##{issue.id}: #{issue.subject}",
        title_link: url,
        fields: issue_fields(issue, setting),
        footer: escape(project.name),
        ts: issue.created_on.to_i
      }
      if setting.display_description_on_create? && issue.description.present?
        attachment[:text] = escape(issue.description)
      end

      text = "[#{project_link(project)}] #{slack_link(url, "##{issue.id}")} " \
             "#{l(:label_kalvad_slack_issue_created, user: escape(issue.author.name))}"
      text << mentions(issue.description)

      {
        text: text,
        attachments: [attachment]
      }
    end

    def issue_updated(issue, journal, setting,
                      color: Color::UPDATED, label_key: :label_kalvad_slack_issue_updated)
      project = issue.project
      url = url_for_issue(issue, journal)

      attachment = {
        color: color,
        title: "#{issue.tracker.name} ##{issue.id}: #{issue.subject}",
        title_link: url,
        fields: journal_fields(journal),
        footer: escape(project.name),
        ts: journal_timestamp(journal)
      }
      note = note_text(journal, setting)
      attachment[:text] = note if note.present?

      text = "[#{project_link(project)}] #{slack_link(url, "##{issue.id}")} " \
             "#{l(label_key, user: escape(journal.user&.name.to_s))}"
      text << mentions(journal.notes)

      {
        text: text,
        attachments: [attachment]
      }
    end

    def issue_closed(issue, journal, setting)
      issue_updated(issue, journal, setting,
                    color: Color::CLOSED,
                    label_key: :label_kalvad_slack_issue_closed)
    end

    def wiki_created(page)
      wiki_payload(page, label_key: :label_kalvad_slack_wiki_created)
    end

    def wiki_updated(page)
      wiki_payload(page, label_key: :label_kalvad_slack_wiki_updated)
    end

    def news_created(news)
      project = news.project
      url = url_for_news(news)

      attachment = {
        color: Color::NEWS,
        title: news.title,
        title_link: url,
        text: escape(news.summary.presence || news.description.to_s),
        footer: escape(project.name),
        ts: news.created_on.to_i
      }

      {
        text: "[#{project_link(project)}] #{slack_link(url, escape(news.title))} " \
              "#{l(:label_kalvad_slack_news_created, user: escape(news.author&.name.to_s))}",
        attachments: [attachment]
      }
    end

    # ---- helpers ----

    def wiki_payload(page, label_key:)
      project = page.project
      url = url_for_wiki(page)

      attachment = {
        color: Color::WIKI,
        title: page.title,
        title_link: url,
        footer: escape(project.name),
        ts: (page.updated_on || page.created_on).to_i
      }

      {
        text: "[#{project_link(project)}] #{slack_link(url, escape(page.title))} " \
              "#{l(label_key, user: escape((page.content&.author || page.last_author)&.name.to_s))}",
        attachments: [attachment]
      }
    end

    def issue_fields(issue, setting)
      fields = [
        { title: l(:field_tracker),     value: escape(issue.tracker.name),  short: true },
        { title: l(:field_status),      value: escape(issue.status.name),   short: true },
        { title: l(:field_priority),    value: escape(issue.priority.name), short: true },
        { title: l(:field_assigned_to), value: assignee_value(issue),       short: true },
        { title: l(:field_author),      value: escape(issue.author.name),   short: true }
      ]
      if setting.display_watchers? && issue.watcher_users.any?
        fields << {
          title: l(:field_watcher),
          value: escape(issue.watcher_users.map(&:name).join(', ')),
          short: false
        }
      end
      fields
    end

    def journal_fields(journal)
      details = journal.visible_details(User.current)
      details.filter_map { |detail| detail_field(journal, detail) }
    end

    def detail_field(_journal, detail)
      case detail.property
      when 'attr'
        attr_field(detail)
      when 'attachment'
        attachment_field(detail)
      when 'cf'
        cf_field(detail)
      end
    end

    def attr_field(detail)
      label = attr_label(detail.prop_key)
      old_v = attr_format(detail.prop_key, detail.old_value)
      new_v = attr_format(detail.prop_key, detail.value)
      { title: escape(label), value: format_change(old_v, new_v), short: true }
    end

    def attr_label(prop_key)
      key = ATTR_LABELS[prop_key.to_s]
      key ? l(key) : prop_key.to_s.humanize
    end

    def attr_format(prop_key, value)
      return '' if value.nil?

      finder = ATTR_FINDERS[prop_key.to_s]
      return value.to_s unless finder

      obj = finder.find_by(id: value)
      return '' unless obj

      # For assigned_to, include Slack @mention if available
      if prop_key.to_s == 'assigned_to_id' && obj.is_a?(User)
        sid = slack_user_id(obj)
        return sid.present? ? "<@#{sid}> #{obj.name}" : obj.name
      end

      obj.name.to_s
    end

    def cf_field(detail)
      cf = CustomField.find_by(id: detail.prop_key)
      label = cf ? cf.name : detail.prop_key
      old_v = detail.old_value.to_s
      new_v = detail.value.to_s
      { title: escape(label), value: format_change(old_v, new_v), short: true }
    end

    def attachment_field(detail)
      filename = detail.value.to_s
      added = detail.value.present? && detail.old_value.blank?
      title = added ? l(:label_attachment_added) : l(:label_attachment_deleted)
      value = added ? "`#{escape(filename)}`" : "~#{escape(detail.old_value.to_s)}~"
      { title: escape(title), value: value, short: false }
    end

    def format_change(old_v, new_v)
      if old_v.blank?
        "*#{escape(new_v)}*"
      elsif new_v.blank?
        "~#{escape(old_v)}~"
      else
        "~#{escape(old_v)}~ -> *#{escape(new_v)}*"
      end
    end

    def note_text(journal, setting)
      return nil if journal.notes.blank?
      return nil if journal.private_notes? && !setting.post_private_notes?

      escape(journal.notes)
    end

    def journal_timestamp(journal)
      (journal.created_on || Time.current).to_i
    end

    def assignee_value(issue)
      user = issue.assigned_to
      return '-' unless user

      sid = slack_user_id(user)
      sid.present? ? "<@#{sid}> #{escape(user.name)}" : escape(user.name)
    end

    def project_link(project)
      slack_link(url_for_project(project), escape(project.name))
    end

    def slack_link(url, text)
      url.present? ? "<#{url}|#{text}>" : text
    end

    def url_for_issue(issue, journal = nil)
      base = "#{redmine_base_url}/issues/#{issue.id}"
      journal ? "#{base}#change-#{journal.id}" : base
    end

    def url_for_project(project)
      "#{redmine_base_url}/projects/#{project.identifier}"
    end

    def url_for_wiki(page)
      "#{redmine_base_url}/projects/#{page.project.identifier}/wiki/#{page.title}"
    end

    def url_for_news(news)
      "#{redmine_base_url}/news/#{news.id}"
    end

    def redmine_base_url
      protocol = Setting.protocol.presence || 'http'
      host = Setting.host_name.to_s
      prefix = Redmine::Utils.relative_url_root.to_s
      url = host.start_with?(/https?:/) ? host : "#{protocol}://#{host}"
      "#{url}#{prefix}".chomp('/')
    end

    def escape(text)
      text.to_s.gsub(/[&<>]/, SLACK_ESCAPES)
    end

    def l(key, **)
      I18n.t(key, **)
    end

    # @mentions support — extracts @username patterns from text and formats
    # them as a "To: @user1, @user2" suffix for the Slack message.
    def mentions(text)
      return '' if text.nil?

      names = extract_usernames(text)
      names.present? ? "\nTo: #{names.join(', ')}" : ''
    end

    def extract_usernames(text)
      return [] if text.nil?

      # Slack usernames: lowercase letters, numbers, dashes, underscores;
      # must start with a letter or number.
      text.scan(/@[a-z0-9][a-z0-9_\-]*/).uniq
    end

    # Looks up a user's Slack user ID from the "Slack Userid" custom field.
    # Returns the ID string or nil.
    def slack_user_id(user)
      return nil unless user

      cf = UserCustomField.find_by(name: 'Slack Userid')
      return nil unless cf

      user.custom_field_value(cf).presence
    end
  end
end
