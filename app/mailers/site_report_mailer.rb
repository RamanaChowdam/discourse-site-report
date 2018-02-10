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
    days_in_period = end_date.day.to_i

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

    active_users_current = active_users(start_date, end_date)
    active_users_previous = active_users(previous_start_date, previous_end_date)
    daily_average_users_current = daily_average_users(days_in_period, active_users_current)
    daily_average_users_previous = daily_average_users(30, active_users_previous)
    repeat_new_users_current = repeat_new_users start_date, end_date, 2
    repeat_new_users_previous = repeat_new_users previous_start_date, previous_end_date, 2
    posts_read_current = posts_read(start_date, end_date)
    posts_read_previous = posts_read(previous_start_date, previous_end_date)

    # @data[:repeat_new_users] = create_data(repeat_new_users, previous_repeat_new_users)

    header_metadata = [
      {key: 'site_report.active_users', value: active_users_current},
      {key: 'site_report.posts', value: total_from_data(posts.data)},
      {key: 'site_report.posts_read', value: posts_read_current}

    ]

    health_data = {
      title_key: 'site_report.health_section_title',
      fields: [
        field_hash('active_users', active_users_current, active_users_previous, has_description: true),
        field_hash( 'daily_active_users', daily_average_users_current, daily_average_users_previous, has_description: true),
        field_hash('health', health(daily_average_users_current, active_users_current), health(daily_average_users_previous, active_users_previous), has_description: true)
      ]
    }

    user_data = {
      title_key: 'site_report.users_section_title',
      fields: [
        field_hash('all_users', all_users(end_date), all_users(previous_end_date), has_description: true),
        field_hash('user_visits', total_from_data(visits.data), visits.prev30Days, has_description: true),
        field_hash('mobile_visits', total_from_data(mobile_visits.data), mobile_visits.prev30Days, has_description: true),
        field_hash('new_users', total_from_data(signups.data), signups.prev30Days, has_description: true),
        field_hash('repeat_new_users', repeat_new_users_current, repeat_new_users_previous, has_description: true),
      ]
    }

    user_action_data = {
      title_key: 'site_report.user_actions_title',
      fields: [
        field_hash('posts_read', posts_read_current, posts_read_previous, has_description: true),
        field_hash('posts_liked', total_from_data(likes.data), likes.prev30Days, has_description: true),
        field_hash('posts_flagged', total_from_data(flags.data), flags.prev30Days, has_description: true),
        field_hash('response_time', average_from_data(time_to_first_response.data), time_to_first_response.prev30Days, has_description: true),

      ]
    }

    content_data = {
      title_key: 'site_report.content_section_title',
      fields: [
        field_hash('topics_created', total_from_data(topics.data), topics.prev30Days, has_description: true),
        field_hash('posts_created', total_from_data(posts.data), posts.prev30Days, has_description: true),
        field_hash('emails_sent', total_from_data(emails.data), emails.prev30Days, has_description: true),
      ]
    }


    if accepted_solutions
      user_action_data[:fields] << field_hash('solutions', total_from_data(accepted_solutions.data), accepted_solutions.prev30Days, has_description: true)
    end

    data_array = [
      health_data,
      user_data,
      user_action_data,
      content_data,
    ]

    @data = {
      period_month: period_month,
      title: subject,
      subject: subject,
      header_metadata: header_metadata,
      data_array: data_array
    }

    admin_emails = User.where(admin: true).map(&:email).select {|e| e.include?('@')}
    mail(to: admin_emails, subject: subject)
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

  def all_users(end_date)
    User.where("created_at <= ?", end_date).count
  end

  def active_users(period_start, period_end)
    UserVisit.where("visited_at >= :period_start AND visited_at <= :period_end",
                    period_start: period_start,
                    period_end: period_end).pluck(:user_id).uniq.count
  end

  def posts_read(period_start, period_end)
    UserVisit.where("visited_at >= :period_start AND visited_at <= :period_end",
                    period_start: period_start,
                    period_end: period_end).pluck(:posts_read).sum
  end

  # todo: validate
  def daily_average_users(days_in_period, active_users)
    (active_users / days_in_period.to_f).round(2)
  end

  def health(dau, mau)
    if mau > 0
      (dau * 100.0/mau).round(2)
    else
      0
    end
  end

  def field_hash(key, current, previous, opts = {})
    {
      key: "site_report.#{key}",
      value: current,
      compare: previous,
      description_key: opts[:has_description] ? "site_report.descriptions.#{key}" : nil,
      hide: false
    }
  end

  def total_from_data(data)
    data.each.pluck(:y).sum
  end

  # todo: validate!
  def average_from_data(data)
    responses = data.count
    total = data.each.pluck(:y).sum
    (total / responses).round(2)
  end
end
