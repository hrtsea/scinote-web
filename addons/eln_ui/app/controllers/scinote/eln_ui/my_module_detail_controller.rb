# frozen_string_literal: true

# ELN UI —— 任务详情页（按 Vue3 原型重建的第四页，PAGE-TASK-DETAIL）
#
# 与另三个 controller 同一套样板：侧栏/顶栏/布局容器走 SciNote 原生，
# 内容区只留一个挂载点 #eln-task-detail，交给 ELN系统-Vue3/src/entries/task_detail.js
# 的 bundle 接管；数据由 MyModuleDetailPayload 出，以 JSON 块注入，没有第二个数据源。
#
# 与实验页不同的两件事：
#   1. 原生**有** my_modules#show（- 任务详情就是它），所以本页不能声称「替换了原生
#      任务页」—— 它是**在原生任务页之外**另起一个 ELN 视角的任务页（PRD §7.8.2 首段）。
#      实验页那边没有原生页可替换，所以措辞不一样，这里是有意区分，不是漏写。
#   2. 除了「我能不能读这个任务」，还要决定审核位给不给：DEC-003 规定关闭任务必须且
#      只能由项目负责人审核通过触发，本页用它直接映射原生 MyModulePermissions::MANAGE。
module Scinote
  module ElnUi
    class MyModuleDetailController < ApplicationController
      def index
        my_module
        @payload_json = JSON.generate(payload).gsub('<', '\\u003c')
      end

      private

      # 可读性沿用原生 PermissionCheckableModel#readable_by_user（与列表页同口径，
      # access_control D8「同源同层」）：这里再判一遍就是第二套口径。
      def my_module
        @my_module ||= MyModule.readable_by_user(current_user).find_by(id: params[:id])
        # 找不到就走原生那套 404/403 语义（不自己 render 一个「无权限」页，
        # 免得和原生行为分叉）。
        @my_module || raise(ActiveRecord::RecordNotFound)
      end

      def payload
        Scinote::ElnUi::MyModuleDetailPayload.call(
          @my_module,
          current_user,
          can_manage_task: can_manage_task?,
          can_complete_task: can_complete_task?,
          can_create_comment: can_create_comment?
        )
      end

      # ------------------------------------------------------------
      # 三个权限位直接吃原生本体（与实验页 can_manage_experiment 同一手法）：
      # 原生没有「审核关闭任务」这个独立权限位，task_manage 是本页唯一近似入口
      # （DEC-003「只能项目负责人审核关闭」的映射已记 OPEN-9 的一部分）。
      # ------------------------------------------------------------
      def can_manage_task?
        @my_module.permission_granted?(current_user, MyModulePermissions::MANAGE)
      end

      def can_complete_task?
        @my_module.permission_granted?(current_user, MyModulePermissions::COMPLETE)
      end

      def can_create_comment?
        @my_module.permission_granted?(current_user, MyModulePermissions::COMMENTS_CREATE)
      end
    end
  end
end
