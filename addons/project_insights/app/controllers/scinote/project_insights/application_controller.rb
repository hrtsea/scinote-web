# frozen_string_literal: true

module Scinote
  module ProjectInsights
    # addon 内控制器基类，复用核心 ApplicationController 的
    # 登录门控（authenticate_user!）与 current_user / current_team 助手。
    class ApplicationController < ::ApplicationController
    end
  end
end
