# frozen_string_literal: true

module Scinote
  module WechatGateway
    # SciNote 后端写入适配器：把 Intake 的抽象动作落到真实 SciNote 服务。
    # 审计链：实验作者用真实绑定用户身份（CreateExperimentService 内部置 created_by=@user），
    # 不落 bot 名下。
    #
    # 依赖的宿主常量（Rails 运行时由 autoload 解析，无需 require）：
    #   CreateExperimentService / Project / Experiment / User
    #
    # v1 范围：
    #   - 新建实验走 CreateExperimentService（真实服务，含权限校验）
    #   - 追加写入 experiment.description
    #   - 收尾走 TimeTrackable#complete!（写 done_at，状态机计算为 done，可在列表按状态筛选），
    #     正文补充一行留痕；草稿软锁见 Intake#confirm（本地草稿索引层，非 SciNote 只读锁）
    #   - 媒体上传暂时以正文占位记录，真实 ActiveStorage 挂接见 Ticket 05
    class ScinoteServiceWriter
      include Canaid::Helpers::PermissionsHelper

      def initialize(user, default_project: nil, formulation_writer: nil)
        @user = user
        @default_project = default_project
        @formulation_writer = formulation_writer
      end

      # 新建实验草稿，返回整数主键 id。start_date/due_date 为可选日期（Date/DateTime）。
      # project_id 显式指定目标项目（微信端「先选项目再建实验」）；不传时回落全局默认项目。
      def create_experiment(title, body, start_date: nil, due_date: nil, project_id: nil)
        project = project_id.present? ? Project.find(project_id) : resolve_project
        # CreateExperimentService 无权限时返回 nil（ActiveRecord::Rollback），
        # 此处提前拦下，避免 nil.id 的 NoMethodError 冒泡成 500。
        raise '无权限在该项目下创建实验（需要项目的「创建实验」权限）' unless can_create_project_experiments?(@user, project)

        team = project.team
        params = {
          project: project,
          name: title,
          description: body
        }
        params[:start_date] = start_date if start_date
        params[:due_date] = due_date if due_date
        exp = CreateExperimentService.new(@user, team, params).call
        raise '创建实验失败（服务返回空，通常是权限或参数被拒）' unless exp

        exp.id
      end

      # 新建项目（建在默认目标项目所属 team 下），返回整数主键 id。
      # start_date / due_date 为可选 Date；CreateProjectService 内部整包
      # build(@params)，故直接作为 key 传入即可落库。
      def create_project(name, description = nil, start_date: nil, due_date: nil)
        team = resolve_team
        params = { name: name }
        params[:description] = description if description.present?
        params[:start_date] = start_date if start_date
        params[:due_date] = due_date if due_date
        project = CreateProjectService.new(@user, team, params).call
        raise '无权限在该团队创建项目' unless project

        project.id
      end

      # 在指定实验下新建任务（MyModule）。due_date 为可选截止日期（Date/DateTime）。
      # 返回整数主键 id。
      def create_mymodule(experiment_id, name, description = nil, due_date: nil)
        exp = Experiment.find(experiment_id)
        team = exp.team
        my_module_params = { name: name }
        my_module_params[:description] = description if description.present?
        my_module_params[:due_date] = due_date if due_date
        mm = CreateMyModuleService.new(@user, team, {
          experiment: exp,
          project: exp.project,
          my_module: my_module_params
        }).call
        raise '无权限在该实验下创建任务（需 create_experiment_tasks 权限）' unless mm && mm.persisted?

        mm.id
      end

      # 追加一段实验正文（不覆盖原内容）。
      def append_note(exp_id, block)
        exp = Experiment.find(exp_id)
        new_desc = [exp.description.to_s, block].reject(&:empty?).join("\n")
        exp.update!(description: new_desc, last_modified_by: @user)
        true
      end

      # 追加一段任务（MyModule）正文 —— 「当前落点是任务」时的写入路径。
      # 任务在 SciNote 里自带 Overview 描述框，写由 update_my_module_description 权限把关。
      # 网关只追加、不覆盖，也不推进任务状态（状态流转一律回 Web 端，ADR 0027）。
      def append_task_note(mm_id, block)
        mm = MyModule.find(mm_id)
        raise '无权限写入该任务（需要任务的「编辑描述」权限）' unless can_update_my_module_description?(@user, mm)

        new_desc = [mm.description.to_s, block].reject(&:empty?).join("\n")
        mm.update!(description: new_desc, last_modified_by: @user)
        true
      end

      # 读取任务元信息；不存在/无权访问抛异常（由 Intake 捕获转成提示）。
      # experiment_id / project_id 供 /settask 同步「当前实验 / 默认项目」使用。
      def get_my_module(mm_id)
        mm = visible_my_module(mm_id)
        { id: mm.id, title: mm.name, date: mm.created_at&.strftime('%Y-%m-%d'),
          experiment_id: mm.experiment_id, project_id: mm.experiment.project_id }
      end

      # 任务是否可作为「当前录入落点」（/settask 的准入校验）：
      # 存在 + 未归档 + 可读 + 有「编辑描述」写权限。
      # 可读 ≠ 可写：只能读的任务不该成为落点，否则用户发的内容会静默丢失。
      def my_module_available?(mm_id)
        mm = MyModule.find_by(id: mm_id)
        return false if mm.nil? || mm.archived?
        return false unless MyModule.readable_by_user(@user, mm.team).exists?(id: mm_id)

        can_update_my_module_description?(@user, mm)
      end

      # 读取实验元信息；不存在/无权访问抛异常（由 Intake 捕获转成提示）。
      # project_id 供 /setexp 同步「当前项目」使用（切到某实验即切到它所属项目）。
      def get_experiment(exp_id)
        exp = Experiment.find(exp_id)
        { id: exp.id, title: exp.name, date: exp.created_at&.strftime('%Y-%m-%d'),
          project_id: exp.project_id }
      end

      # 读取项目元信息；不存在抛异常（由 Intake 捕获转成提示）。
      def get_project(project_id)
        p = Project.find(project_id)
        { id: p.id, title: p.name, date: p.created_at&.strftime('%Y-%m-%d') }
      end

      # 项目是否可作为「建实验的目标」：存在 + 未归档 + 有 EXPERIMENTS_CREATE 权限。
      # /newexp 前的预校验（Q9）：预设项目失效时据此清空并重新引导。
      def project_available?(project_id)
        p = Project.find_by(id: project_id)
        return false if p.nil? || p.archived?

        can_create_project_experiments?(@user, p)
      end

      # 媒体附件：v1 仅以正文占位记录，保证录入不丢；真实挂接 Ticket 05。
      def upload(exp_id, path, caption)
        append_note(exp_id, "📎 附件：#{caption}（#{path}）")
      end

      # 同上，写入当前任务。
      def upload_task(mm_id, path, caption)
        append_task_note(mm_id, "📎 附件：#{caption}（#{path}）")
      end

      # 列出实验：/list 最近、/search 关键词（复用 Experiment.search）。
      def list_experiments(q: nil, limit: 5)
        scope = Experiment.search(@user, false, q.presence)
        scope.limit(limit).map do |exp|
          { id: exp.id, title: exp.name, date: exp.created_at&.strftime('%Y-%m-%d') }
        end
      end

      # 列出项目。
      #   scope: :creatable -> 只列「有创建实验权限」的项目（/listproject 默认，建实验候选列表）
      #   scope: :readable  -> 列全部可读项目（/listproject all）
      # 跨用户所属的全部 team 查询（不再局限于默认项目那个 team）。
      def list_projects(limit: 5, scope: :creatable)
        ids = project_ids_for(scope)
        return [] if ids.empty?

        Project.where(id: ids)
               .order(created_at: :desc)
               .limit(limit)
               .map do |p|
          { id: p.id, title: p.name, date: p.created_at&.strftime('%Y-%m-%d') }
        end
      end

      # 列出指定实验下的任务（MyModule）。
      # 只列用户可读的（readable_by_user）—— /settask 的候选必须过可见性，
      # 否则等于把别人的任务 ID 清单递给用户（ADR 0025）。
      def list_mymodules(experiment_id, limit: 5)
        exp = Experiment.find(experiment_id)
        exp.my_modules.readable_by_user(@user, exp.team)
           .where(archived: false)
           .order(created_at: :desc)
           .limit(limit)
           .map do |m|
          { id: m.id, title: m.name, date: m.created_at&.strftime('%Y-%m-%d') }
        end
      end

      # 真实收尾：写入 done_at（TimeTrackable#complete!），状态机计算为 done，
      # 可在实验列表按状态筛选。正文留痕由 Intake#done 的 append_note 负责。
      def complete_experiment(exp_id)
        exp = Experiment.find(exp_id)
        exp.complete!
        true
      end

      # 打可信时间戳（保留接口：仅追加正文留痕，不写原生状态；收尾请用 complete_experiment）。
      def timestamp(exp_id)
        append_note(exp_id, "🔒 完成于 #{Time.now.iso8601}")
      end

      # F12：把 AI 抽取结果落到 ai_eln Formulation 实体（未配置 writer 即 no-op）。
      def persist_formulation(record, exp_id)
        return nil unless @formulation_writer

        exp = Experiment.find(exp_id)
        @formulation_writer.write(record, team: exp.team, created_by: @user)
      end

      # 指派用户到实验（F6 组长指派）。前置校验发送者对实验有 manage_users 权限。
      # role: :normal（普通成员）| :owner（所有者）。
      # 返回 true；无权限/用户不存在抛异常（由 Intake 转成提示）。
      def assign_user(exp_id, target_user_id, role: :normal)
        exp = Experiment.find(exp_id)
        raise '无权限指派该实验成员（需 manage_users 权限）' unless can_manage_experiment_users?(@user, exp)

        target = User.find(target_user_id)
        assignment = exp.user_assignments.find_or_initialize_by(user: target, team: exp.team)
        assignment.user_role = role == :owner ? UserRole.find_predefined_owner_role : UserRole.find_predefined_normal_user_role
        assignment.assigned_by = @user
        assignment.assigned = :manually
        assignment.save!
        true
      end

      # F9：管理员跨用户查询实验（需实例管理员权限，直查模型绕过 per-user 可见性）。
      # 默认在发送者所属 team 内查询，可用 team_id 指定；query 为标题/正文关键词。
      def admin_experiments(query: nil, team_id: nil, limit: 10)
        raise '需要实例管理员权限' unless InstanceAdmin.admin?(@user)

        team_ids = team_id ? [team_id] : @user.teams.pluck(:id)
        scope = Experiment.joins(:project)
                          .where(projects: { team_id: team_ids, archived: false })
        if query.present?
          scope = scope.where('experiments.name ILIKE :q OR experiments.description ILIKE :q', q: "%#{query}%")
        end
        scope.order(created_at: :desc).limit(limit).map do |exp|
          { id: exp.id, title: exp.name, date: exp.created_at&.strftime('%Y-%m-%d') }
        end
      end

      # F10：设备预约。SciNote 无 EquipmentBooking 模型，实为 CalendarEvent
      # （event_type: equipment_booking，subject 为设备 RepositoryRow）。
      def book_equipment(row_id, start_time:, end_time:, name: nil)
        row = RepositoryRow.find(row_id)
        raise '该实例未开启设备预约功能' unless Repository.equipment_booking_enabled?
        raise '无权限预约该设备' unless can_create_equipment_bookings?(@user, row.repository)

        event = CalendarEvent.create!(
          name: name.presence || "设备预约 #{start_time.strftime('%m-%d %H:%M')}",
          subject: row,
          team: row.team,
          created_by: @user,
          event_type: :equipment_booking,
          start_datetime: start_time,
          end_datetime: end_time,
          metadata: {}
        )
        { id: event.id, name: event.name }
      end

      private

      # 取任务并做可见性校验；不存在/不可读抛异常（由 Intake 转成友好提示）。
      # 只读 + 未归档才算可见，避免把别人的任务当落点。
      def visible_my_module(mm_id)
        mm = MyModule.find_by(id: mm_id)
        raise "任务 ##{mm_id} 不存在" if mm.nil?
        raise "任务 ##{mm_id} 不可访问（不存在或你无读取权限）" unless
          MyModule.readable_by_user(@user, mm.team).exists?(id: mm_id)

        mm
      end

      def resolve_project
        return @default_project if @default_project

        pid = Scinote::WechatGateway.configuration.default_project_id
        raise 'WECHAT_GATEWAY_PROJECT_ID 未配置：微信录入需要一个默认目标项目' if pid.nil?

        @default_project = Project.find(pid)
      end

      # 建项目/其它需要 team 的动作所用的团队。
      # 优先：实例级默认项目所属 team；否则用户第一个 team。
      #（不再依赖「用户必须先设默认项目」，避免新用户 /newproject 直接报错。）
      def resolve_team
        @team ||= begin
          pid = Scinote::WechatGateway.configuration.default_project_id
          team = pid.present? ? Project.find_by(id: pid)&.team : nil
          team || @user.teams.first ||
            raise('未找到可用团队：该用户不属于任何 team')
        end
      end

      # 按 scope 收集项目 id（逐 team 查询后合并，避免跨 team 权限作用域歧义）。
      def project_ids_for(scope)
        @user.teams.flat_map do |team|
          rel = Project.where(team_id: team.id).readable_by_user(@user, team).where(archived: false)
          rel = rel.with_granted_permissions(@user, ProjectPermissions::EXPERIMENTS_CREATE) if scope.to_sym == :creatable
          rel.pluck(:id)
        end.uniq
      end
    end
  end
end
