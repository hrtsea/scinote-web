# frozen_string_literal: true

# D9.4 —— 可见性矩阵页面（PI 在项目里对「成员 × 实验」逐格放行/收回）
#
# 为什么不用 AccessPermissions::BaseController：
#   它的 before_action 链里有一条无 only 的 check_manage_permissions（抽象、抛 NotImplementedError），
#   子类即使自己先跑完 set_*，那条回调照样会炸。这里继承 ApplicationController 自己控权限，
#   代价是要自己取 project —— 但只有三行，比绕开抽象基类便宜。
#
# 权限位：can_manage_project_users?（Canaid 注入 ActionController 的 helper）。
#   project_head 角色（D9 build 脚本，19 位）含 project_users_manage，PI 因此能开这个页面；
#   兜底分支不依赖常量名，避免 Canaid 注入方式变化时整页 500。

module Scinote
  module AccessControl
    class VisibilityMatrixController < ApplicationController
      before_action :set_matrix_project
      before_action :check_matrix_permissions

      def show
        @matrix = Scinote::AccessControl::VisibilityMatrixService.call(@project)
        @enabled = Scinote::AccessControl.enabled?
        @wl_role_name = Scinote::AccessControl::VisibilityMatrix::WL_ROLE_NAME
        @strategy = @project.respond_to?(:experiment_visibility_strategy) ? @project.experiment_visibility_strategy : 'inherit'

        respond_to do |format|
          format.html
          format.json { render json: @matrix.merge(strategy: @strategy) }
        end
      end

      # D2 —— 切换「新建实验的默认可见性」策略（inherit / isolated）
      #   只影响**此后新建**的实验；存量实验与矩阵里已放行的格子都不动。
      #   已放行的格子是 manually 行，原生 job 第 96 行会跳过它们，天然不会被覆盖。
      def update_strategy
        return render json: { error: 'unavailable' }, status: :service_unavailable unless @project.respond_to?(:experiment_visibility_strategy)

        strategy = params[:strategy].to_s == 'isolated' ? :isolated : :inherit
        @project.update!(experiment_visibility_strategy: strategy)

        render json: { strategy: @project.experiment_visibility_strategy }
      end

      # D5 —— 把「当前策略」补回到**存量**实验/任务
      #
      # 为什么需要它（实测）：切回 inherit 后存量实验**不会**自动补回 ——
      # 开关只影响此后新建的对象。PI 切完策略会发现成员还是看不见，这是真实困惑。
      #
      # 为什么不需要快照：隔离是「在 job 里拦截复制」而非「删行」，所以补谁、补什么角色
      # 都能从 Project 现有 UA 推导出来。这否掉了词汇表 §14「必须存快照才能回滚」的设想。
      #
      # 只在 inherit 下允许 —— isolated 是 PI 主动选的「默认不继承」，
      # 在那种策略下提供「一键补继承」等于给了个自相矛盾的按钮。
      def backfill
        result = Scinote::AccessControl::VisibilityMatrixService.backfill!(@project, assigner: current_user)
        render json: result, status: :ok
      end

      # POST/DELETE toggles 一格
      #   params: project_id, user_id, experiment_id, on=true|false, scope=experiment|task
      def toggle
        user = User.find_by(id: params[:user_id])
        experiment = @project.experiments.find_by(id: params[:experiment_id])

        return render json: { error: 'not_found' }, status: :not_found if user.blank? || experiment.blank?

        # scope=experiment → 只开实验壳；scope=task → 连实验下的任务一起开。
        #
        # 早期版本无条件把 scope 固定成 :experiment，是因为当时「任务级」= 在 Experiment 上
        # 建一条 task_owner 行 —— 那是宿主永不识别的错位授权（Experiment#permission_granted?
        # 查 ExperimentPermissions::READ，task_owner 行读不到 → PI 以为成功、成员看不见）。
        # 现在 scope=:task 的语义改成「实验上行 + 逐个 MyModule 建行」（见 decorator），
        # 任务可见性落在它真正被判定的那一层，所以可以放开。
        # 但 WL+task 角色缺失时仍必须回落 —— 否则 grant 返回 false，UI 会显示失败却不给理由。
        scope = params[:scope].to_s == 'task' ? :task : :experiment
        if scope == :task && Scinote::AccessControl::VisibilityMatrix::WL_TASK_ROLE_NAME &&
           UserRole.find_by(name: Scinote::AccessControl::VisibilityMatrix::WL_TASK_ROLE_NAME,
                            predefined: false).nil?
          scope = :experiment
        end

        want_on = %w[true 1 yes].include?(params[:on].to_s)

        result = if want_on
                   experiment.send(:grant_member_visibility!, user, scope: scope)
                 else
                   experiment.send(:revoke_member_visibility!, user, scope: scope)
                 end

        render json: {
          user_id: user.id,
          experiment_id: experiment.id,
          on: result ? true : false,
          result: result,
          status: status_code(experiment, user, scope)
        }, status: :ok
      end

      private

      def set_matrix_project
        @project = current_team.projects.active.find_by(id: params[:project_id])
        render_404 unless @project
      end

      def check_matrix_permissions
        return if respond_to?(:can_manage_project_users?, true) && can_manage_project_users?(@project)

        row = @project.user_assignments.find_by(user: current_user, team: current_team)
        return if row&.user_role&.permissions&.include?('project_users_manage')

        render_403
      end

      # 矩阵服务是纯 Ruby，controller 只负责把它翻译成一格的状态
      def status_code(experiment, user, scope)
        return :unavailable unless experiment.respond_to?(:ac_manually_granted?, true)

        experiment.send(:ac_manually_granted?, user, scope: scope) ? :granted : :revoked
      end
    end
  end
end
