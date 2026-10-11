<template>
  <form :action="actionUrl" method="post" class="team-new-form">
    <input type="hidden" name="authenticity_token" :value="csrfToken" />

    <div class="sci-input-container mb-4 max-w-lg" style="display: block !important">
      <label>{{ labels.nameLabel }}</label>
      <input
        type="text"
        name="team[name]"
        autofocus
        class="sci-input-field"
        :placeholder="labels.namePlaceholder"
        :value="nameValue"
        data-e2e="e2e-IF-settings-workspaces-newWorkspace-name"
      />
      <br />
      <small>{{ labels.nameSublabel }}</small>
    </div>

    <div class="sci-input-container mb-4 max-w-lg" style="display: block !important">
      <label>{{ labels.descriptionLabel }}</label>
      <textarea
        name="team[description]"
        class="sci-input-field textarea"
        :value="descriptionValue"
        data-e2e="e2e-IF-settings-workspaces-newWorkspace-description"
      ></textarea>
      <br />
      <small>{{ labels.descriptionSublabel }}</small>
    </div>

    <a
      :href="cancelUrl"
      class="btn btn-secondary"
      data-e2e="e2e-BT-settings-workspaces-newWorkspace-cancel"
      >{{ labels.cancel }}</a
    >
    <button
      type="submit"
      class="btn btn-success"
      data-e2e="e2e-BT-settings-workspaces-newWorkspace-create"
    >
      {{ labels.create }}
    </button>
  </form>
</template>

<script>
// 工作区（team）创建表单的 Vue 岛。
// 提交走原生 <form>（Rails CSRF + Turbolinks 全接管），控制器 create action 零改动：
// 成功 redirect_to team_path，失败 render :new（Turbolinks 重渲染本页，name/description
// 经 props 回填）。文案与初始值由 ERB 以 prop 注入（指南 §10.2 铁律 B：客户端 i18n 不可靠）。
export default {
  name: "NewTeamForm",
  props: {
    actionUrl: { type: String, required: true },
    cancelUrl: { type: String, required: true },
    csrfToken: { type: String, required: true },
    nameValue: { type: String, default: "" },
    descriptionValue: { type: String, default: "" },
    labels: {
      type: Object,
      required: true,
      validator: (v) =>
        ["nameLabel", "namePlaceholder", "nameSublabel", "descriptionLabel", "descriptionSublabel", "cancel", "create"].every(
          (k) => typeof v[k] === "string"
        )
    }
  }
};
</script>
