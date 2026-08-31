import axios from '../../packs/custom_axios.js';

export default {
  watch: {
    visible(newValue) {
      if (newValue) {
        this.setDefaultRole();
      } else {
        this.defaultRole = null;
      }
    }
  },
  mounted() {
    this.fetchUserRoles();
  },
  data() {
    return {
      visible: false,
      defaultRole: null,
      defaultRoleId: null,
      userRoles: [],
    }
  },
  methods: {
    changeRole(role) {
      this.defaultRole = role;
    },
    fetchUserRoles() {
      axios.get(this.userRolesUrl())
        .then((response) => {
          this.userRoles = response.data.data;
          this.defaultRoleId = response.data.default_role_id;
          this.setDefaultRole();
        });
    },
    setDefaultRole() {
      if (!this.visible || this.defaultRoleId === null) return;
      const role = this.userRoles.find((r) => r[0] === this.defaultRoleId);
      this.defaultRole = role ? this.defaultRoleId : null;
    },
  }
};
