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

      # 工作区列表数据源（服务端分页/排序）。
      #
      # 契约（ADR-0034 rev3，2026-10-08）：POST + JSON 参数
      #   { page, per_page, order: {column, dir}, search, view_mode, filters }
      #   → JSON:API 形状 { data: [{ id, type, attributes }], meta: { total_pages,
      #     total_count, filtered_count } }
      # 这是宿主 shared/datatable 栈（/projects 同款，ADR-0035 V2.0）的 loadData/
      # formatData 原生协议；前端由 webpack entry `vue_teams_table`（AG Grid 薄封装）消费。
      def datatable
        teams = sort_workspaces(workspace_scope.to_a)

        per_page = datatable_per_page
        total = teams.size
        total_pages = [ (total.to_f / per_page).ceil, 1 ].max
        page = [ [ params.fetch(:page, 1).to_i, 1 ].max, total_pages ].min

        rows = teams.drop((page - 1) * per_page).first(per_page).map { |team| workspace_row(team) }

        render json: {
          data: rows.map { |row| { id: row[:id], type: 'team', attributes: row.except(:id) } },
          meta: {
            total_pages: total_pages,
            total_count: total,
            filtered_count: total
          }
        }
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

      # 工作区列表数据源（ADR-0034 rev3）：由 `datatable` 端点消费，JSON:API 行结构，
      # 渲染交给 vue_teams_table（宿主 shared/datatable AG Grid 栈）。
      # 「记录范围 / 角色 / 能否退出」等判定全部在此集中，保证单一真源。
      # 选项对齐 shared/datatable 栟的每页条数下拉（perPageOptions [10, 20, 50, 100]）。
      DATATABLE_PER_PAGE_OPTIONS = [10, 20, 50, 100].freeze
      DATATABLE_PER_PAGE_DEFAULT = 20

      # 记录范围：普通用户看自己加入的工作区；实例级系统管理员看全部（保留该功能）。
      def workspace_scope
        scope = current_user.system_admin? ? Team.all : @user.teams
        scope.preload(:created_by, user_assignments: %i[user user_role]).distinct
      end

      def datatable_per_page
        requested = params.fetch(:per_page, DATATABLE_PER_PAGE_DEFAULT).to_i
        DATATABLE_PER_PAGE_OPTIONS.include?(requested) ? requested : DATATABLE_PER_PAGE_DEFAULT
      end

      # shared/datatable 栈的排序请求形状：order: { column: <colId=field>, dir: 'asc'|'desc' }。
      # 首次加载 order 为 null ⇒ 默认按名称升序（与原生 TeamsDatatable 缺省一致）。
      def datatable_order
        order = params[:order] || {}
        column = order[:column].to_s
        dir = order[:dir].to_s
        [column.presence || 'name', dir == 'desc' ? 'desc' : 'asc']
      end

      # 排序语义对齐原生 TeamsDatatable（Ruby 侧排序后分页；工作区数量可控，保持同法）：
      #   name（默认）→ 名称；id → 工作区 ID；created_by → 创建人姓名（users.full_name，代码侧排序，
      #   与 10-07 版 TeamsDatatable 同口径）；created_at → 创建时间；role → 当前用户在该工作区的角色；
      #   members(_count) → 成员数。
      def sort_workspaces(teams)
        column, dir = datatable_order
        descending = dir == 'desc'
        sorted =
          case column
          when 'members', 'members_count'
            teams.sort_by { |team| [ team.users.count, team.name.to_s.downcase ] }
          when 'role'
            teams.sort_by do |team|
              role = workspace_role(team)
              [ role ? 0 : 1, role.to_s.downcase, team.name.to_s.downcase ]
            end
          when 'id'
            teams.sort_by { |team| [ team.id, team.name.to_s.downcase ] }
          when 'created_by'
            teams.sort_by do |team|
              creator = team.created_by&.full_name.to_s.downcase
              [ creator, team.name.to_s.downcase ]
            end
          when 'created_at'
            teams.sort_by { |team| [ team.created_at, team.name.to_s.downcase ] }
          else
            teams.sort_by { |team| team.name.to_s.downcase }
          end
        descending ? sorted.reverse : sorted
      end

      def workspace_assignment(team)
        team.user_assignments.find { |assignment| assignment.user_id == @user.id }
      end

      def workspace_role(team)
        workspace_assignment(team)&.user_role&.name
      end

      def workspace_row(team)
        assignment = workspace_assignment(team)
        {
          id: team.id,
          name: team.name,
          # 创建人 / 创建时间（用户既有需求，10-07 首次落地；创建人真源 = users.full_name）
          created_by: team.created_by&.full_name.presence || I18n.t('users.settings.teams.index.na'),
          created_at: team.created_at.strftime('%Y-%m-%d %H:%M'),
          role: workspace_role(team) || I18n.t('users.settings.teams.index.na'),
          members_count: team.users.count,
          # 名称列仅在「可管理该工作区」时才是链接，与 load_team 的 can_manage_team? 门槛一致
          # （实例级系统管理员走 bypass），避免渲染出点进去 403 的链接。
          can_manage: can_manage_team?(team) || system_admin_bypass?,
          members_url: members_users_settings_team_path(team),
          # 「能否退出」必须与 UserTeamsController#destroy 的后端判定完全一致（同一事实只许一个真源），
          # 否则会出现「按钮能点但后端拒绝」的分歧。后端用的是：最后一个持有
          # TeamPermissions::USERS_MANAGE 的人不可退出。注意不要自己按 UserRole.owner_role 去判：
          # 其一它返回 id 为空的未持久化对象（宿主 Bug，where 会退化成 user_role_id IS NULL）；
          # 其二 Owner 名字覆盖不到那些带 team_manage 的自定义角色。
          can_leave: assignment.present? &&
                     !assignment.last_with_permission?(TeamPermissions::USERS_MANAGE),
          leave_url: assignment ? leave_user_team_html_path(assignment, format: :json, leave: true) : nil
        }
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
