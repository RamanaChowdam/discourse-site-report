require_dependency 'report'
require_relative '../helpers/site_report_helper'

class SiteReportMailer < ActionMailer::Base
  include Rails.application.routes.url_helpers
  include ApplicationHelper
  include SiteReportHelper
  helper :application
  add_template_helper SiteReportHelper
  append_view_path Rails.root.join('plugins', 'discourse-site-report', 'app', 'views')
  default from: SiteSetting.notification_email

  def report
    subject = site_report_title
    start_date = 1.month.ago.beginning_of_month
    end_date = 1.month.ago.end_of_month
    previous_start_date = 2.months.ago.beginning_of_month
    previous_end_date = 2.months.ago.end_of_month
    period_month = start_date.strftime('%B')

    visits = Report.find(:visits, start_date: start_date, end_date: end_date)
    mobile_visits = Report.find(:mobile_visits, start_date: start_date, end_date: end_date)
    signups = Report.find(:signups, start_date: start_date, end_date: end_date)
    profile_views = Report.find(:profile_views, start_date: start_date, end_date: end_date)
    topics = Report.find(:topics, start_date: start_date, end_date: end_date)
    posts = Report.find(:posts, start_date: start_date, end_date: end_date)
    time_to_first_response = Report.find(:time_to_first_response, start_date: start_date, end_date: end_date)
    topics_with_no_response = Report.find(:topics_with_no_response, start_date: start_date, end_date: end_date)
    emails = Report.find(:emails, start_date: start_date, end_date: end_date)
    flags = Report.find(:flags, start_date: start_date, end_date: end_date)
    likes = Report.find(:likes, start_date: start_date, end_date: end_date)
    accepted_solutions = Report.find(:accepted_solutions, start_date: start_date, end_date: end_date)

    # @data = {}
    #
    # discourse_reports.each do |key, discourse_report|
    #   @data[key] = create_data(discourse_report.total, discourse_report.prev30Days )
    # end

    active_users_current = active_users(start_date, end_date)
    active_users_previous = active_users(previous_start_date, previous_end_date)
    repeat_new_users_current = repeat_new_users start_date, end_date, 2
    repeat_new_users_previous = repeat_new_users previous_start_date, previous_end_date, 2
    posts_read_current = posts_read(start_date, end_date)
    posts_read_previous = posts_read(previous_start_date, previous_end_date)

    # @data[:repeat_new_users] = create_data(repeat_new_users, previous_repeat_new_users)

    header_metadata = [
      { key: 'site_report.active_users', value: active_users_current },
      { key: 'site_report.posts', value: posts.total },
      { key: 'site_report.posts_read', value: posts_read_current }

    ]

    @data = {
      period_month: period_month,
      title: subject,
      subject: subject,

    }
    admin_emails = User.where(admin: true).map(&:email).select {|e| e.include?('@')}
    # mail(to: admin_emails, subject: subject)
  end

  def repeat_new_users(period_start, period_end, num_visits)
    sql = <<~SQL
      WITH period_new_users AS (
      SELECT 
      u.id
      FROM users u
      WHERE u.created_at >= :period_start
      AND u.created_at <= :period_end
      ),
      period_visits AS (
      SELECT
      uv.user_id,
      COUNT(1) AS visit_count
      FROM user_visits uv
      WHERE uv.visited_at >= :period_start
      AND uv.visited_at <= :period_end
      GROUP BY uv.user_id
      )
      SELECT
      pnu.id
      FROM period_new_users pnu
      JOIN period_visits pv
      ON pv.user_id = pnu.id
      WHERE pv.visit_count >= :num_visits
    SQL

    ActiveRecord::Base.exec_sql(sql, period_start: period_start, period_end: period_end, num_visits: num_visits).count
  end

  def all_users
    User.all.uniq.count
  end

  def active_users(period_start, period_end)
    UserVisit.where("visited_at >= :period_start AND visited_at <= :period_end",
                    period_start: period_start,
                    period_end: period_end).pluck(:user_id).uniq
  end

  def posts_read(period_start, period_end)
    UserVisit.where("visited_at >= :period_start AND visited_at <= :period_end",
                    period_start: period_start,
                    period_end: period_end).pluck(:posts_read).sum
  end

  def create_data(current, previous)
    {
      value: current,
      compare: previous,
    }
  end
end
