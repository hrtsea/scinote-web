# frozen_string_literal: true

# 工作台（/eln_workbench）—— 按登录角色渲染的首页（REQ-DASHBOARD / SCN-DASH-1~7）
#
# 形状与 eln_ui 各 controller 一致：宿主 layout 提供侧栏/顶栏，内容区只留挂载点
# #eln-workbench，交给 ELN系统-Vue3/src/entries/workbench.js 接管；数据只有一处
# 来源 —— WorkbenchPayload 从真库实时取出、以 JSON 块注入，没有第二个数据源。
#
# 闸门（access_control D8 同源同层，不新建权限位）：
#   1. require_login       —— 未登录回落宿主 /login
#   2. check_team_membership —— 无当前 team 直接 403（工作台是「团队视角」页面）
#
# ⚠ 本轮只做「负责人单视图」一档（原型画布 4:66~4:293 只承载这一形态）；
#   SCN-DASH-1/2/4 的组员 / 组长 / 管理员差异化布局记 OPEN-WORKBENCH-4。
module Scinote
  module Workbench
    class WorkbenchController < ApplicationController
      before_action :require_login
      before_action :check_team_membership

      def index
        @payload_json = JSON.generate(payload).gsub('<', '\\u003c')
      end

      private

      def require_login
        return if current_user

        redirect_to '/login'
      end

      def check_team_membership
        return if current_team

        render_403 and return
      end

      def payload
        Scinote::Workbench::WorkbenchPayload.call(
          user: current_user,
          team: current_team
        )
      end
    end
  end
end
