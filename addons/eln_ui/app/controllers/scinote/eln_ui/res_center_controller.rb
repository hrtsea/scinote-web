# frozen_string_literal: true

# ELN UI —— 资源中心页（按 Vue3 原型 ELN系统-Vue3/src/views/ResCenter.vue 重建）
#
# 形状与既有 controller 一致：宿主 layout 提供侧栏/顶栏；
# 内容区只留挂载点 #eln-res-center，交给 ELN系统-Vue3/src/entries/res_center.js 接管；
# 数据由 ResCenterPayload 从真库取出，以 JSON 块注入，没有第二个数据源。
#
# 与其他页不同的两点：
#   1. 资源中心是**跨项目**视图（不是按单个 project 加载），所以没有 set_project；
#      权限检查也宽到「当前 team 下任一 Repository / Project 可读」即可。
#   2. 5 个 tab 用同一条 payload：inventory + ledger + consume 走原生 Repository 体系；
#      apply + cost 走 addon 自有表。服务层一处取齐，前端一次拿完，
#      切 tab 不再打服务端。
module Scinote
  module ElnUi
    class ResCenterController < ApplicationController
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
        Scinote::ElnUi::ResCenterPayload.call(
          user: current_user,
          team: current_team
        )
      end
    end
  end
end
