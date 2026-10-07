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

      # bang 方法的异常在 controller 收口 —— 这里才是边界。
      #   backfill 走 Project#backfill_inherited_assignments!（内部一堆 perform_now → save!），
      #   toggle 走 ac_upsert_visibility_row! / ac_record_grant!（都是 create!/save!）。
      #   不加这一层，PI 点一下就是 500 页面，连「哪一格失败」都拿不到。
      #   只接 RecordInvalid（数据问题，422 合理）；别的一律放它 500 ——
      #   NoMethodError 之类是真 bug，不该被伪装成校验错误。
      rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid

      def show
        @matrix = Scinote::AccessControl::VisibilityMatrixService.new(@project).call
        @enabled = Scinote::AccessControl.enabled?
        # 自有表的存在由 Scinote::AccessControl.verify! 在启动时兜住，这里不用再探。
        @strategy = @project.ac_visibility_strategy

        respond_to do |format|
          format.html
          format.json { render json: @matrix.merge(strategy: @strategy) }
        end
      end

      # D2 —— 切换「新建实验的默认可见性」策略（inherit / isolated）
      #   只影响**此后新建**的实验；存量实验与矩阵里已放行的格子都不动。
      #   已放行的格子是 manually 行，原生 job 第 96 行会跳过它们，天然不会被覆盖。
      #
      # ⚠ 交给 enum 自己判，不要在 controller 里猜：
      #   旧写法 `params[:strategy].to_s == 'isolated' ? :isolated : :inherit` 会把任何
      #   错字（'Isolated' / 'iso' / 空串）静默写成 inherit —— PI 以为只是没生效，
      #   实际上项目策略被改了。enum 对非法值抛 ArgumentError，这里翻成 422。
      def update_strategy
        # 不写 Project 本身（策略与项目自身字段无关），直接落 addon 自己的表 ——
        # 顺带避开一次 after_save 链（head 同步等跟这件事毫无关系的回调）。
        @project.ac_visibility_strategy = params.require(:strategy)

        render json: { strategy: @project.ac_visibility_strategy }
      rescue ArgumentError, ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # D5 —— 把「当前策略」补回到**存量**实验/任务
      #
      # 为什么需要它（实测）：切回 inherit 后存量实验**不会**自动补回 ——
      # 开关只影响此后新建的对象。PI 切完策略会发现成员还是看不见，这是真实困惑。
      #
      # 只在 inherit 下允许 —— isolated 是 PI 主动选的「默认不继承」，
      # 在那种策略下提供「一键补继承」等于给了个自相矛盾的按钮。
      def backfill
        render json: @project.backfill_inherited_assignments!(by: current_user), status: :ok
      end

      # POST toggles 一格
      #   params: project_id, user_id, experiment_id, on=true|false, scope=experiment|task
      def toggle
        user = User.find_by(id: params[:user_id])
        experiment = @project.experiments.find_by(id: params[:experiment_id])

        return render json: { error: 'not_found' }, status: :not_found if user.blank? || experiment.blank?

        scope = matrix_scope
        want_on = ActiveModel::Type::Boolean.new.cast(params[:on])

        result = if want_on
                   experiment.grant_member_visibility(user, scope: scope, by: current_user)
                 else
                   experiment.revoke_member_visibility(user, scope: scope)
                 end

        # `on` 直接从模型读，而不是把 grant 的 true/false 与 revoke 的
        # :revoked/:still_readable/:noop 压成一个布尔 —— 压完就分不清「撤了」
        # 和「撤了但仍可读」，界面只能瞎猜。
        render json: {
          user_id: user.id,
          experiment_id: experiment.id,
          on: experiment.ac_manually_granted?(user, scope: scope),
          result: result
        }, status: :ok
      end

      private

        def render_record_invalid(error)
          render json: { error: error.record.errors.full_messages.to_sentence },
                 status: :unprocessable_entity
        end

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

        # scope=experiment → 只开实验壳；scope=task → 连实验下的任务一起开。
        #
        # 早期版本无条件把 scope 固定成 :experiment，是因为当时「任务级」= 在 Experiment 上
        # 建一条 task_owner 行 —— 那是宿主永不识别的错位授权（Experiment#permission_granted?
        # 查 ExperimentPermissions::READ，task_owner 行读不到 → PI 以为成功、成员看不见）。
        # 现在 scope=:task 的语义改成「实验上行 + 逐个 MyModule 建行」（见 VisibilityGrant），
        # 任务可见性落在它真正被判定的那一层，所以可以放开。
        # 但 WL+task 角色缺失时仍必须回落 —— 否则 grant 返回 false，UI 会显示失败却不给理由。
        def matrix_scope
          return :experiment unless params[:scope].to_s == 'task'

          role_name = Scinote::AccessControl::VisibilityGrant::WL_TASK_ROLE_NAME
          UserRole.exists?(name: role_name, predefined: false) ? :task : :experiment
        end
    end
  end
end
