# frozen_string_literal: true

# 工作台（/eln_workbench）—— 按登录角色渲染的首页（REQ-DASHBOARD / SCN-DASH-1~7）
#
# 形状与 eln_ui 各 controller 一致：宿主 layout 提供侧栏/顶栏，内容区只留挂载点
# #eln-workbench，交给 ELN系统-Vue3/src/entries/workbench.js 接管；数据只有一处
# 来源 —— WorkbenchPayload 从真库实时取出、以 JSON 块注入，没有第二个数据源。
#
# 闸门（access_control D8 同源同层，不新建权限位）：
#   check_team_membership —— 无当前 team 直接 403（工作台是「团队视角」页面）
#
# ⚠ 别再加 require_login：宿主 ApplicationController 第 6 行已有
#   `before_action :authenticate_user!`，父类回调先跑、未登录链就断了，
#   自定义的永远执行不到 —— 而且它曾经指向 '/login' 这条**根本不存在**的路由
#   （recognize_path('/login') → RoutingError）。留着就是把未登录用户送去 404 的雷。
#
# ⚠ 本轮只做「负责人单视图」一档（原型画布 4:66~4:293 只承载这一形态）；
#   SCN-DASH-1/2/4 的组员 / 组长 / 管理员差异化布局记 OPEN-WORKBENCH-4。
module Scinote
  module Workbench
    class WorkbenchController < ApplicationController
      before_action :check_team_membership

      # ⚠ 别在这里手工 gsub('<')：只挡 `<` 漏了 `&` 和 U+2028/U+2029，
      #   Rails 自带 json_escape 才是正解（转义放视图层，见 index.html.erb）。
      def index
        @payload = payload
      end

      private

      def check_team_membership
        render_403 if current_team.nil?
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
