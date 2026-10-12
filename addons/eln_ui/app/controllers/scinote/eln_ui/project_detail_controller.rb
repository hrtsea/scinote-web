# frozen_string_literal: true

# ELN UI —— 项目详情页（按 Vue3 原型重建的页面）
#
# 这个页面是「Vue 只接管内容区」的样板：
#   - 侧栏 / 顶栏 / 布局容器仍走 SciNote 原生（宿主 layout 提供）；
#   - 内容区是一个挂载点 #eln-project-detail，交给
#     ELN系统-Vue3/src/entries/project_detail.js 构建出的 bundle 接管；
#   - 数据由 ProjectDetailPayload 从真库取出，以 <script type="application/json"> 注入，
#     bundle 读它、覆盖 mock、渲染。没有第二个数据源。
#
# 权限沿用原生 Canaid 的读判断（can_read_project?），不另立一套 —— 与 access_control
# 的 D8「同源同层」原则一致：可不适用于可见性矩阵那个「管理」权限，但读页面必须能看。

module Scinote
  module ElnUi
    class ProjectDetailController < ApplicationController
      before_action :set_project
      before_action :check_project_read_permissions

      def show
        # 懒补种（ADR-0049 D9）：必传 5 类是固定清单，但台账行是数据不会凭空出现。
        # 「已纳管」是事后状态（upsert 只在 update/update_status 调），没有创建钩子可挂 ⇒
        # 挂读路径。幂等（find_or_initialize + position 归一），每次 show 调一次成本 = 一次 COUNT。
        # ⚠ 不放 payload：那是 export/测试共用的纯读装配器，写副作用会扩散。
        Scinote::ElnUi::RequiredDocSeeder.seed!(@project)
        payload = Scinote::ElnUi::ProjectDetailPayload.call(@project, user: current_user)
        # </script> 会提前闭合注入块；< 一律转码，JSON 语义不变。
        @payload_json = JSON.generate(payload).gsub('<', '\\u003c')
        @payload = payload
      end

      # 报告 §5 第 6 项 #10：项目归档导出（结构化数据 CSV 预览包）。
      # 原生归档状态机由行菜单原生端点维护，本动作只聚合已有真相数据导出。
      def export
        csv = Scinote::ElnUi::ProjectArchiveExport.call(@project)
        send_data csv, filename: "project-#{@project.id}-archive.csv",
                  type: 'text/csv; charset=utf-8', disposition: 'attachment'
      end

      # ------------------------------------------------------------
      # 服务端网格端点（2026-10-11）：项目详情页 6 张表改用宿主 shared/datatable
      #   （AG Grid v32.3.9）后，宿主栈只能从 dataUrl 拉数 ⇒ 必须有这个端点。
      #   做法与资源中心 res_center#grid、项目列表 eln_project_list#grid 同源。
      #
      # 权限：读权限与整页**同源** —— before_action 已守 can_read_project?，
      #   能看这一页就能看这一页的表，不另立权限档（D8 同源同层）。
      #   写操作（指标 CRUD）仍各走自己的 canEditBasic 闸门，与本端点无关。
      #
      # 取数：一律 ProjectDetailPayload#grid_rows（复用既有 block，单真源）。
      # ------------------------------------------------------------
      def grid
        result = Scinote::ElnUi::ProjectDetailPayload.new(@project, user: current_user)
                                                     .grid_rows(
                                                       dataset: params[:dataset],
                                                       order: normalize_order(params[:order]),
                                                       page: params[:page].presence || 1,
                                                       per_page: params[:per_page].presence || 20
                                                     )
        render json: result
      end

      # ------------------------------------------------------------
      # 页头三键（2026-10-11 接线；在此之前它们只是三个没有 @click 的静态标签）
      # ------------------------------------------------------------

      # ① 编辑项目信息：原生有列的字段直接改 @project，二开三格写 eln_ui_project_profiles。
      #    没有 profile 行时 upsert 会当场建一行，不存在「改了却没地方存」。
      def update
        return render_403 unless current_permissions[:canEditBasic]

        # ⚠ 必须 .to_h：ActionController::Parameters 不是 Hash，没有 any?/compact
        #   （Rails 7.2 实测 NoMethodError —— 由 eln_ui_project_detail_actions_test 抓到）。
        native_attrs = project_params.slice(:name, :description, :start_date, :due_date).to_h.compact
        profile_attrs = project_params.slice(:business_code, :source, :approved_on).to_h.compact

        ::Project.transaction do
          @project.update!(native_attrs) if native_attrs.any?
          ::Scinote::ElnUi::ProjectProfile.upsert_for!(@project, profile_attrs) if profile_attrs.any?
        end

        render json: Scinote::ElnUi::ProjectDetailPayload.call(@project, user: current_user)
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      # ② 修改项目状态。本轮唯一真实的那一档是「置已结题」——它落在**原生归档**上，
      #    因为 SCN-PM-ARCH-2 的「禁建任务」语义绑在原生 archived，不绑任何二开列。
      #    其余四态（立项中 / 年度考核 / 结题中）本轮无承载语义 → 422 并说清，绝不静默存一个 UI 上兑现不了的状态。
      def change_status
        return render_403 unless current_permissions[:canChangeStatus]
        unless respond_to?(:can_archive_project?, true) && can_archive_project?(@project)
          return render_403
        end

        unless params[:status].to_s == ::Scinote::ElnUi::ProjectProfile::STATUS_LABELS.key('已结题')
          return render json: { error: '本轮仅支持置为「已结题」；其余项目状态暂无承载语义' },
                        status: :unprocessable_entity
        end

        ::Project.transaction do
          @project.archive!(current_user)
          ::Scinote::ElnUi::ProjectProfile.upsert_for!(@project, status: 'closed')
        end

        render json: Scinote::ElnUi::ProjectDetailPayload.call(@project, user: current_user)
      end

      # ③ 上传项目任务书 —— **退役壳**（ADR-0049 D8/Q11=C）。
      #    原端点写死 name=TASK_BOOK_NAME，必传清单固定为 5 类后这个绑定作废：
      #    任何一行都要能传。新端点 = upload_document（收行 id + file）。
      #    为什么不静默删路由：前端陈年 bundle 缓存可能还在打这个 URL，
      #    410 + 指路新端点让旧包fail-fast 而不是 500 或静默 404。
      def upload_task_book
        render json: { error: '「上传任务书」端点已退役，请改用必传文档行内「上传」（document 端点）' },
               status: :gone
      end

      # ③' 必传文档行内上传（ADR-0049 D7/D8，2026-10-13）。
      #     文件本体走宿主 ActiveStorage（先例：ReceiptVerification#photos），
      #     登记信息写 eln_ui_project_documents 原行 —— 「必传文档已上传」推动归档校验。
      #     id 必须落在**本项目**的 required 行上：跨项目 id 一律 404（不泄漏存在性）。
      def upload_document
        return render_403 unless current_permissions[:canUploadDocs]
        return render json: { error: '未收到文件' }, status: :unprocessable_entity if params[:file].blank?

        doc = Scinote::ElnUi::ProjectDocument.find_by!(project_id: @project.id, id: params[:id],
                                                       category: 'required')
        doc.file.attach(params[:file])
        doc.update!(uploaded: true, uploaded_on: Time.zone.today, uploader: current_user)

        render json: Scinote::ElnUi::ProjectDetailPayload.call(@project, user: current_user)
      rescue ActiveRecord::RecordNotFound
        render_404
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      # ④ 项目指标 CRUD + 达标切换（2026-10-11 起）。承载面 = 二开表 eln_ui_project_metrics
      #   （原生 projects 无项目级指标模型，与文档/任务审核同属「原生无承载面 → addon 自有表」）。
      #   权限复用 canEditBasic（与「编辑项目信息」同款），不另立权限档。
      #   创建即未达标（ok 默认 false），达标只走「切换达标」动作，不进创建/编辑表单。
      def create_metric
        return render_403 unless current_permissions[:canEditBasic]

        metric = Scinote::ElnUi::ProjectMetric.new(
          metric_params.merge(project_id: @project.id, position: next_metric_position)
        )
        metric.save!
        render json: Scinote::ElnUi::ProjectDetailPayload.call(@project, user: current_user)
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      def update_metric
        return render_403 unless current_permissions[:canEditBasic]

        metric = find_metric(params[:id])
        metric.update!(metric_params)
        render json: Scinote::ElnUi::ProjectDetailPayload.call(@project, user: current_user)
      rescue ActiveRecord::RecordNotFound
        render_404
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      def destroy_metric
        return render_403 unless current_permissions[:canEditBasic]

        metric = find_metric(params[:id])
        metric.destroy!
        render json: Scinote::ElnUi::ProjectDetailPayload.call(@project, user: current_user)
      rescue ActiveRecord::RecordNotFound
        render_404
      end

      # 达标切换：翻转 ok。创建即未达标，达标只走这里（不进创建/编辑表单）。
      # ⚠ 这是**有意**的手动覆盖：页面另有「由任务全部关闭驱动指标达标」的叙事
      #   （taskCloseReview.indicatorDriven），但用户明确选择达标由人工切换决定，
      #   故手动 toggle 优先于该驱动叙事（不互相冲突，手动值即真相）。
      def toggle_metric
        return render_403 unless current_permissions[:canEditBasic]

        metric = find_metric(params[:id])
        metric.update!(ok: !metric.ok)
        render json: Scinote::ElnUi::ProjectDetailPayload.call(@project, user: current_user)
      rescue ActiveRecord::RecordNotFound
        render_404
      end

      private

      # 排序参数收口（与 ResCenterController#normalize_order 同款）：
      #   宿主栈发来的是单个 {column, dir}，也可能（多列排序）是数组 → 统一成数组或 nil。
      def normalize_order(order)
        return nil if order.blank?

        order.is_a?(Array) ? order : [order]
      end

      # 写判据与前端渲染**同源**：两边问的都是 ProjectDetailPayload.permissions_for。
      def current_permissions
        @current_permissions ||= Scinote::ElnUi::ProjectDetailPayload.permissions_for(@project, current_user)
      end

      def project_params
        # approved_on = 立项时间（项目批准日期）—— 与项目编号/来源同属二开档案，
        #   ⚠ 不许落到 projects.created_at（那是系统时间戳，语义也不是批准日期）。
        params.require(:project)
              .permit(:name, :description, :start_date, :due_date, :business_code, :source, :approved_on)
      end

      # 指标只认本项目的 id，避免越权改到别的项目下的指标行。
      def find_metric(id)
        Scinote::ElnUi::ProjectMetric.find_by!(project_id: @project.id, id: id)
      end

      # 创建时 append：position = 当前最大+1，不做重排。
      def next_metric_position
        (Scinote::ElnUi::ProjectMetric.where(project_id: @project.id).maximum(:position) || 0) + 1
      end

      def metric_params
        params.require(:metric).permit(:name, :target, :current)
      end

      def set_project
        # ⚠ 不再用 .active：本页的「项目归档导出」Tab 本来就是给**归档态**看的，
        #   而页头「修改项目状态」把项目置为已结题（= 原生归档）之后，
        #   .active 会让这一页当场 404 —— 用户点完成功就掉进错误页，行为不可接受。
        #   （读权限仍由 check_project_read_permissions 守着，放宽的是「归档项目可见」这一件事。）
        @project = current_team.projects.find_by(id: params[:project_id])
        render_404 unless @project
      end

      def check_project_read_permissions
        return if respond_to?(:can_read_project?, true) && can_read_project?(@project)

        render_403
      end
    end
  end
end
