# redmics - redmine icalendar export plugin
# Copyright (c) 2010  Frank Schwarz, frank.schwarz@buschmais.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'icalendar'

class ICalendarController < ApplicationController
  before_filter :find_optional_project
  accept_rss_auth :index

  def index
    # project
    project_condition = @project ? ["project_id IN (?)", ([@project.id] + @project.descendants.collect(&:id))] : nil

    # issue status
    case params[:status]
    when 'all'
      status_condition = []
    when 'open'
      status_condition = ["issue_statuses.is_closed = ?", false]
    else
      status_condition = nil
    end

    # assignment
    case params[:assigned_to]
    when 'me'
      assigned_to_condition = ["assigned_to_id = #{User.current.id}"]
    when '+'
      assigned_to_condition = ["assigned_to_id is not null"]
    when '*'
      assigned_to_condition = []
    else
    end

    events = []
    # queries
    unless status_condition.nil? || assigned_to_condition.nil?
      events += Issue.where(project_condition)
                     .includes(:tracker, :assigned_to, :priority, :project, :status, :fixed_version, :author)
                     .where(status_condition)
		     .where(assigned_to_condition)
    end
    events += Version.where(project_condition).includes(:project);

    @cal_string = create_calendar(events).to_ical
    send_data @cal_string, :type => Mime::ICS, :filename => 'issues.ics'
  end

private

  def find_optional_project
    @project = Project.find_by_identifier(params[:project_id])
  end

  def create_calendar(events)
    cal = Icalendar::Calendar.new
    events.each { |i|
      due_date = i.due_date
      start_date = i.start_date if i.respond_to?(:start_date)
      start_date ||= due_date
      if i.is_a? Issue
        due_date ||= i.fixed_version.due_date if i.fixed_version
        due_date ||= start_date
      end
      next unless start_date && due_date

      event = Icalendar::Event.new
      event.dtstart        start_date, {'VALUE' => 'DATE'}
      event.dtend          due_date + 1, {'VALUE' => 'DATE'}
      project_prefix = @project.nil? ? "#{i.project.name}: " : "" # add project name if this is a global feed
      if i.is_a? Issue
        event.summary      "#{project_prefix}#{i.subject} (#{i.status.name})"
        event.url          url_for(:controller => 'issues', :action => 'show', :id => i.id)
        unless i.fixed_version.nil?
          event.categories   [i.fixed_version.name]
        end
        contacts = [i.author, i.assigned_to] + i.watcher_users
        contacts.compact.uniq.each do |contact|
          event.add_contact contact.name, {"ALTREP" => contact.mail}
        end
        event.organizer    "mailto:#{i.author.mail}", {"CN" => i.author.name}
        event.status       i.assigned_to == nil ? "TENTATIVE" : "CONFIRMED"
        event.created      i.created_on.to_date, {'VALUE' => 'DATE'}
      elsif i.is_a? Version
        event.summary      "#{project_prefix}%s '#{i.name}'" % l(:label_calendar_deadline)
        event.url          url_for(:controller => 'versions', :action => 'show', :id => i.id)
      else
      end
      unless i.description.nil?
        event.description = i.description
      end
      cal.add_event(event)
    }
    return cal
  end

end

