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
        datatable
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
      end

      # 工作区列表数据源（服务端分页/排序/搜索）。
      #
      # 契约（ADR-0034 rev3，2026-10-08）：POST + JSON 参数
      #   { page, per_page, order: {column, dir}, search, view_mode, filters }
      #   → JSON:API 形状 { data: [{ id, type, attributes }], meta: { total_pages,
      #     total_count, filtered_count } }
      # 这是宿主 shared/datatable 栈（/projects 同款，ADR-0035 V2.0）的 loadData/
      # formatData 原生协议；前端由 webpack entry `vue_teams_table`（AG Grid 薄封装）消费。
      #
      # 取数与字段构造已分别下沉到 Lists::TeamsService（SQL 侧）与 Lists::TeamSerializer，
      # 本 action 只负责「授权范围 + 渲染」，与 /projects、/user_groups 同一模子。
      def datatable
        teams = Lists::TeamsService.new(workspace_scope, params, user: current_user).call

        render json: teams,
               each_serializer: Lists::TeamSerializer,
               user: current_user,
               # filtered_count：栈（table.vue）会读 meta.filtered_count。
               # TeamsService 的 total_count 已统计「过滤后、分页前」的行数，
               # 故与 total_count 同值——本列表的搜索只收窄集合，不存在第二档计数。
               meta: pagination_dict(teams).merge(filtered_count: teams.total_count)
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

      # 记录范围（授权口径，属控制器职责）：普通用户看自己加入的工作区；
      # 实例级系统管理员看全部（保留该功能）。
      #
      # 原先在此处挂的 .preload 已下沉到 Lists::TeamsService（预加载是取数职责）；
      # .distinct 一并去掉：UserAssignment 对 (user, assignable, team_id) 有唯一性验证
      # （app/models/user_assignment.rb:22），故 @user.teams 不会展开出重复行。
      def workspace_scope
        current_user.system_admin? ? Team.all : @user.teams
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
