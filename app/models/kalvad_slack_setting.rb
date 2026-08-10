# frozen_string_literal: true

class KalvadSlackSetting < ApplicationRecord
  BOOL_FIELDS = %i[
    enabled
    post_issue_created
    post_issue_updated
    post_issue_closed
    post_wiki_created
    post_wiki_updated
    post_news
    post_private_issues
    post_private_notes
    display_watchers
    display_description_on_create
  ].freeze

  belongs_to :project

  validates :project_id, uniqueness: true
  validates :webhook_url,
            format: { with: %r{\Ahttps?://}i, allow_blank: true,
                      message: :kalvad_slack_invalid_webhook_url }

  def self.for(project)
    find_or_initialize_by(project_id: project.id)
  end

  def deliverable?
    enabled? && webhook_url.present? && channel.to_s != '-'
  end
end
