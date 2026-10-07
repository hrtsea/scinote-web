# frozen_string_literal: true

# ELN UI —— 资源申请「谁看得见 / 谁批得动」的唯一口径（REQ-RES-APPROVER · ADR-0029）
#
# 一句话：**所有关于审批资格与可见范围的判定都只能写在这里**，
# 闸门（Workflow）、详情页（ResApplyDetailPayload）、列表（ResCenterPayload）、
# 配置面板（ProjectApproversPayload）四处必须都来问它。
#   此前四处各写一句「同团队 + 非本人」的变体，漏改一处就变成
#   「列表给了按钮、点下去 422」，或者更糟：把不该看见的单据列出来给人瞄。
#
# 裁决来源（2026-10-05 grilling Q1~Q7，用户逐条拍板）：
#   Q1-a 可见范围含草稿（本人对自己未提交的单据天然可见，剔掉会被当成提交失败）
#   Q2-2 冷启动出口 = 面板里显式的「一键初始化」按钮，**不是**自动 fallback
#   Q3-1 名单只配个人，不引入用户组（避免「组内变动→审批人自动变」的隐式行为）
#   Q4-2 列表四维筛选在**客户端**做（与 consume 页签同手法；服务端只下发候选）
#   Q5-2 不给团队/单位管理员开「不经名单即可审批」的万能位 —— 要管就先配进名单
#   Q6-1 配置面板挂资源申请页签内（DEC-012：不新造外壳，不改宿主项目页）
#   Q7-1 本轮只治理资源申请；任务关闭审核维持原口径，接缝留在本文件的 stage 泛化
#
# 🔴 fail-closed 是刻意的：名单为空 = 该阶段无人可批，单据卡住能被看见、能被修，
#    好过「随便谁都能批」这种事后没法追溯的成功。
module Scinote
  module ElnUi
    class ResourceApprovalPolicy
      STAGES = Scinote::ElnUi::ProjectApprover::STAGES
      STAGE_LABELS = Scinote::ElnUi::ProjectApprover::STAGE_LABELS

      class << self
        # ----------------------------------------------------------
        # 名单
        # ----------------------------------------------------------
        def approver_ids(project, stage)
          return [] if project.nil?

          Scinote::ElnUi::ProjectApprover
            .for_project(project).for_stage(stage).pluck(:user_id)
        end

        def approvers(project, stage)
          Scinote::ElnUi::ProjectApprover.users_for(project: project, stage: stage)
        end

        # 该阶段是否「有人能批」 —— 前面板的红字提示与后端闸门共用它
        def configured?(project, stage)
          approver_ids(project, stage).any?
        end

        # ----------------------------------------------------------
        # 闸门
        # ----------------------------------------------------------
        # 当前单据**正处在**哪个阶段（决定 reject 时该用哪份名单）
        #   submitted       → 还差初审
        #   group_approved  → 初审已过，还差终审
        def pending_stage(app)
          return nil if app.nil?
          return 'group' if app.submitted?
          return 'project' if app.group_approved?

          nil
        end

        # 这个人能不能对这张单据做这个阶段的审批动作。
        # ⚠ team 缺省时从 app.project.team_id 推 —— 让调用方不必到处传团队对象；
        #   但**传了**就按传入的口径校：跨团队一律 false，不会因为省事而放行。
        #
        # ⚠ 自审允许：申请人若被显式配为某阶段审批人，即可审批自己的单
        #   （小团队 PI 既提交又审批；名单是唯一口径，不另开身份豁免）。
        def can_approve?(user:, application:, stage:, team: nil)
          return false if user.nil? || application.nil?
          return false unless same_team?(application, team)

          Scinote::ElnUi::ProjectApprover.assigned?(
            project: application.project, user: user, stage: stage
          )
        end

        # REQ-RES-RECEIPT / ADR-0032：这个人能不能对这张单做**验货**判定。
        #
        # 与 `can_approve?` 的差别只有一处，但那一处是本规则的全部意义：
        #   ① 取的是 **`receipt` 阶段名单**，不再沿用终审名单（`ADR-0030` 的此项被修正）；
        #   ② **自验**要额外过一道项目级开关（`ReceiptPolicy#allow_self_verification`）。
        #      名单回答「谁能验」，策略回答「能不能验自己的单」——两个问题，故分两层判。
        #
        # ⚠ fail-closed：不在 `receipt` 名单里 ⇒ 一律 false，**不**回退到
        #   「同团队非本人」宽口径（那是 ADR-0029 明确废掉的推断式授权）。
        def can_verify_receipt?(user:, application:, team: nil)
          return false if user.nil? || application.nil?
          return false unless application.material?
          return false unless same_team?(application, team)

          project = application.project
          return false unless Scinote::ElnUi::ProjectApprover.assigned?(
            project: project, user: user, stage: 'receipt'
          )

          # 名单内的人若正是申请人，还要看本项目是否允许自验
          return true if application.requestor_id != user.id

          Scinote::ElnUi::ReceiptPolicy.for_project(project).allow_self_verification?
        end

        # 「我能验的项目」= 在 receipt 名单里的项目（供验货人配置面板与可审批范围用）
        def verifiable_project_ids(user, team)
          return [] if user.nil? || team.nil?

          Scinote::ElnUi::ProjectApprover.for_user(user).where(stage: 'receipt').distinct.pluck(:project_id)
        end

        # 当前状态下，这个人能执行的审批动词列表（详情页按钮组直接读它）
        def available_actions(user:, application:, team: nil)
          return [] if application.nil? || user.nil?

          case application.status
          when 'submitted'
            can_approve?(user: user, application: application, stage: 'group', team: team) ? %w[approve_group reject] : []
          when 'group_approved'
            can_approve?(user: user, application: application, stage: 'project', team: team) ? %w[approve_project reject] : []
          when 'project_approved'
            # 验货入库 / 出库确认（终态动作）
            # ⚠ ADR-0032：材料类的终态闸门已从「终审名单」换成「`receipt` 验货名单」，
            #   所以这里对材料类**不再**返回 complete —— 否则会给终审人显示一个
            #   「点了必被拒」的按钮。验货那个键由 approvals_block#canVerifyReceipt 单独暴露，
            #   与本表刻意分开：本表回答「审批谁能做什么」，验货是另一个主体的动作。
            if application.material?
              []
            else
              can_approve?(user: user, application: application, stage: 'project', team: team) ? %w[complete] : []
            end
          else
            []
          end
        end

        def same_team?(app, team)
          return true if team.nil?

          app.project && app.project.team_id == team.id
        end

        # ----------------------------------------------------------
        # 项目负责人判定（★ 双轨并列，MEMORY §7 的血泪：只认一条必把另一半降级）
        #   轨一 Project.supervised_by（原生「项目负责人」列）
        #   轨二 Project 级 UserAssignment 持 predefined owner role
        # ⚠️ UserAssignment 是**多态表**，必须限定 assignable_type='Project'，
        #    不限定就是跨层级混算（实测会把 3/4 的用户误判成「单位管理员」）。
        # ----------------------------------------------------------
        def project_owner?(user, project)
          return false if user.nil? || project.nil?
          return true if project.supervised_by_id == user.id

          owner_role = owner_role!
          return false if owner_role.nil?
          return false unless assignment_table?

          ::UserAssignment.exists?(
            assignable_type: 'Project', assignable_id: project.id,
            user_id: user.id, user_role_id: owner_role.id
          )
        end

        # 项目负责人名单（通知 + 一键初始化的候选源）
        def project_owners(project)
          return [] if project.nil?

          users = []
          users << project.supervised_by if project.supervised_by_id

          owner_role = owner_role!
          if owner_role && assignment_table?
            ids = ::UserAssignment
                  .where(assignable_type: 'Project', assignable_id: project.id,
                         user_role_id: owner_role.id)
                  .pluck(:user_id)
            users.concat(::User.where(id: ids).to_a)
          end
          users.compact.uniq(&:id)
        end

        # ----------------------------------------------------------
        # 可见范围（SCN-RES-1「按角色可见范围过滤」/ SCN-RES-3「组员仅看本人」）
        #
        # 三档，互斥理解：
        #   · 项目负责人      → 其负责项目的全部申请（含草稿）
        #   · 被指名的审批人  → 其有资格审批的项目的全部申请（含草稿）
        #   · 其余团队成员    → 仅本人提交的全部申请（含草稿）
        # ⚠ 团队/单位管理员**不因此**获得额外可见范围（Q5-2）：万能位会把判定
        #   从「一处」拆成「两处」，将来排查「他为什么看得见」要查两本账。
        # ----------------------------------------------------------
        def visible_applications(user:, team:)
          scope = Scinote::ElnUi::ResourceApplication.for_team(team)
          return scope.none if user.nil?

          own = scope.where(requestor_id: user.id)
          pids = approvable_project_ids(user, team)
          return own if pids.empty?

          own.or(scope.where(project_id: pids))
        end

        # 「我能批的项目」= 负责人 ∪ 任一阶段被指名
        def approvable_project_ids(user, team)
          return [] if user.nil? || team.nil?

          owned = ::Project.where(team_id: team.id).pluck(:id, :supervised_by_id)
                           .select { |_id, sid| sid == user.id }.map(&:first)

          assigned = if owner_role! && assignment_table?
                       ::UserAssignment
                         .where(assignable_type: 'Project', user_id: user.id,
                                user_role_id: owner_role!.id)
                         .pluck(:assignable_id)
                     else
                       []
                     end

          named = Scinote::ElnUi::ProjectApprover.for_user(user).distinct.pluck(:project_id)

          (owned + assigned + named).compact.uniq
        end

        # 可见范围的角色标签（前端页头副标题 / 空态文案都读它）
        #   manage = 至少负责或审批了一个项目；self = 只剩本人单据
        def visible_scope(user, team)
          approvable_project_ids(user, team).any? ? 'manage' : 'self'
        end

        # ----------------------------------------------------------
        # 配置权限（项目负责人即可；不给管理员开万能位）
        # ----------------------------------------------------------
        def can_configure?(user, project, team = nil)
          return false if user.nil? || project.nil?
          return false if team && project.team_id != team.id

          project_owner?(user, project)
        end

        # 我能配置审批人的项目（配置面板的左侧下拉）
        def configurable_projects(user, team)
          return [] if user.nil? || team.nil?

          ::Project.where(team_id: team.id, archived: false, template: [false, nil])
                   .to_a
                   .select { |p| project_owner?(user, p) }
        end

        # 候选审批人 = 项目成员（supervisor + Project 级 UA 上的人）。
        # 取不到成员关系时退化到团队成员（空清单会让面板没法用，宁可多列）。
        def candidates(project, team)
          return [] if project.nil?

          users = []
          users << project.supervised_by if project.supervised_by_id
          if assignment_table?
            users.concat(
              ::UserAssignment
                .where(assignable_type: 'Project', assignable_id: project.id)
                .includes(:user).map(&:user)
            )
          end
          users.concat(team_members(team)) if users.empty? && team.present?
          users.compact.uniq(&:id)
        end

        # 未配置的阶段清单（面板顶部红字提示 —— 不说，用户只会觉得「按钮点了没反应」）
        def unconfigured_stages(project)
          STAGES.reject { |s| configured?(project, s) }
        end

        private

        def owner_role!
          return nil unless defined?(::UserRole)

          ::UserRole.find_predefined_owner_role
        rescue StandardError
          nil
        end

        def assignment_table?
          defined?(::UserAssignment) && ::UserAssignment.table_exists?
        rescue StandardError
          false
        end

        def team_members(team)
          return [] if team.nil?
          return team.users.to_a if team.respond_to?(:users)

          []
        rescue StandardError
          []
        end
      end
    end
  end
end
