# frozen_string_literal: true

module Users
  module Settings
    class TeamsController < ApplicationController
      include ActionView::Helpers::TextHelper
      include ActionView::Helpers::UrlHelper
      include ApplicationHelper
      include InputSanitizeHelper

      before_action :load_user, only: %i(
        index
        new
        create
        show
        users_datatable
        members
        data_integrity
      )

      before_action :load_team, only: %i(
        show
        users_datatable
        name_html
        description_html
        update
        destroy
        members
        data_integrity
      )

      before_action :check_create_team_permission,
                    only: %i(new create)

      before_action :check_data_integrity_enabled, only: %i(data_integrity)

      before_action :set_breadcrumbs_items, only: %i(index show members data_integrity)

      layout 'fluid'

      def index
        @member_of = @user.teams.count
        @teams_payload = teams_payload
      end

      def new
        @new_team = Team.new
      end

      def create
        @new_team = Team.new(create_params)
        @new_team.created_by = @user

        if @new_team.save
          # Redirect to new team page
          redirect_to team_path(@new_team)
        else
          render :new
        end
      end

      def show
        @active_tab = :details
      end

      def members
        @active_tab = :members
      end

      def data_integrity
        @active_tab = :data_integrity
      end

      def users_datatable
        render json: ::TeamUsersDatatable.new(view_context, @team, @user)
      end

      def name_html
        render json: {
          html: render_to_string(
            partial: 'users/settings/teams/name_modal_body',
            locals: { team: @team },
            formats: :html
          )
        }
      end

      def description_html
        render json: {
          html: render_to_string(
            partial: 'users/settings/teams/description_modal_body',
            locals: { team: @team },
            formats: :html
          )
        }
      end

      def update
        if @team.update(update_params)
          @team.update(last_modified_by: current_user)
          render json: {
            status: :ok,
            html: custom_auto_link(
              @team.tinymce_render(:description),
              simple_format: false,
              tags: %w(img),
              team: current_team
            )
          }
        else
          render json: @team.errors, status: :unprocessable_entity
        end
      end

      def destroy
        @team.destroy

        flash[:notice] = I18n.t(
          'users.settings.teams.edit.modal_destroy_team.flash_success',
          team: @team.name
        )

        # Redirect back to all teams page
        redirect_to teams_path
      end

      def switch
        team = current_user.teams.find_by(id: params[:team_id])

        if team && current_user.update(current_team_id: team.id)
          flash[:success] = t('users.settings.changed_team_flash',
                              team: current_user.current_team.name)
          render json: { current_team: team.id }
        else
          render json: { message: t('users.settings.changed_team_error_flash') }, status: :unprocessable_entity
        end
      end

      private

      def check_create_team_permission
        render_403 unless can_create_teams?
      end

      def check_data_integrity_enabled
        render_403 unless Team.deletion_prevention_enabled?
      end

      def load_user
        @user = current_user
      end

      def load_team
        @team = Team.find_by(id: params[:id])
        render_403 unless can_manage_team?(@team) || system_admin_bypass?
      end

      # 实例级系统管理员可进入任意工作区的设置页并执行删除（含他人创建的 workspace）
      def system_admin_bypass?
        current_user&.respond_to?(:system_admin?) && current_user&.system_admin?
      end

      def create_params
        params.require(:team).permit(
          :name,
          :description
        )
      end

      def update_params
        params.require(:team).permit(
          :name,
          :description
        )
      end

      # 工作区列表 Vue 化（ADR-0034）：把列表数据注入 window.__ELN_TEAMS__，
      # 由预打包的 teams_table.js（Sprockets 资产）读取并渲染 AG Grid。
      def teams_payload
        scope = current_user.system_admin? ? Team.all : @user.teams
        scope.preload(:created_by, user_assignments: %i[user user_role]).distinct.map do |team|
          ua = team.user_assignments.find { |a| a.user_id == @user.id }
          role = ua&.user_role&.name
          owner_role = UserRole.owner_role
          other_owners = team.user_assignments
                            .where(user_role: owner_role)
                            .where.not(id: ua&.id)
                            .exists?
          last_admin = ua&.user_role&.owner? && !other_owners
          can_leave = ua.present? && !last_admin
          {
            id: team.id,
            name: team.name,
            show_url: team_path(team),
            created_by: team.created_by&.full_name || I18n.t('users.settings.teams.index.na'),
            created_at: I18n.l(team.created_at, format: :full_date),
            role: role || I18n.t('users.settings.teams.index.na'),
            members_count: team.users.count,
            can_leave: can_leave,
            leave_url: ua ? destroy_user_team_path(ua, leave: true) : nil
          }
        end
      end

      def set_breadcrumbs_items
        @breadcrumbs_items = []

        @breadcrumbs_items.push({
                                  label: t('breadcrumbs.teams'),
                                  url: teams_path
                                })
        if @team
          @breadcrumbs_items.push({
                                    label: @team.name,
                                    url: team_path(@team)
                                  })
        end
      end
    end
  end
end
