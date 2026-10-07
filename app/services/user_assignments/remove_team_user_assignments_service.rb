# frozen_string_literal: true

module UserAssignments
  class RemoveTeamUserAssignmentsService
    def initialize(team_user_assignment, unassigned_by)
      @user = team_user_assignment.user
      @team = team_user_assignment.assignable
      # Upstream bug fix: team Owner UA rows created by create_user_assignments! have
      # assigned_by_id = nil (optional: true), which made @unassigned_by nil and crashed
      # #call with NoMethodError on .id during team destroy. Fall back to team creator.
      @unassigned_by = unassigned_by || @team&.created_by
    end

    def call
      @team.projects.find_each do |project|
        project.user_assignments.where(user: @user).find_each do |assignment|
          UserAssignments::PropagateAssignmentJob.perform_now(assignment, assigner_id: @unassigned_by&.id, destroy: true)
        end
      end
      remove_repositories_assignments
      remove_protocols_assignments
      remove_reports_assignments
      remove_forms_assignments
    end

    private

    def remove_repositories_assignments
      @team.repositories
           .joins(:user_assignments)
           .preload(:user_assignments)
           .where(user_assignments: { user: @user, team: @team }).find_each do |repository|
        repository.user_assignments
                  .select { |assignment| assignment.user_id == @user.id && assignment.team_id == @team.id }
                  .each(&:destroy!)
      end
    end

    def remove_protocols_assignments
      @team.repository_protocols
           .joins(:user_assignments)
           .preload(:user_assignments)
           .where(user_assignments: { user: @user }).find_each do |protocol|
        protocol.user_assignments
                .select { |assignment| assignment.user_id == @user.id }
                .each(&:destroy!)
      end
    end

    def remove_reports_assignments
      @team.reports
           .joins(:user_assignments)
           .preload(:user_assignments)
           .where(user_assignments: { user: @user }).find_each do |report|
        report.user_assignments
              .select { |assignment| assignment.user_id == @user.id }
              .each(&:destroy!)
      end
    end

    def remove_forms_assignments
      @team.forms
           .joins(:user_assignments)
           .preload(:user_assignments)
           .where(user_assignments: { user: @user, team: @team }).find_each do |form|
        form.user_assignments
            .select { |assignment| assignment.user_id == @user.id && assignment.team_id == @team.id }
            .each(&:destroy!)
      end
    end
  end
end
