<template>
  <div
    class="drag-and-drop-upload sci-drag-area"
    :class="{ 'dragging': dragging }"
    @dragover.prevent="dragging = true"
    @dragleave.prevent="dragging = false"
    @drop.prevent="onDrop"
    @click="openPicker"
  >
    <input
      ref="fileInput"
      type="file"
      class="hidden-file-input"
      :accept="acceptAttr"
      @change="onSelect"
    >
    <div class="drag-and-drop-upload__inner flex flex-col items-center justify-center text-center p-4">
      <i class="sn-icon sn-icon-file-upload mb-2 text-sn-dark-grey"></i>
      <span class="sci-link">{{ supportingText }}</span>
    </div>
  </div>
</template>

<script>
// 拖拽 / 点击上传（对齐官方 DragAndDropUpload 接口：emits onFile:dropped / onFile:error）。
// 仅接受 supportedFormats 指定的扩展名；大小校验交由父组件（AIImportModal.setFile）。
export default {
  name: 'DragAndDropUpload',
  props: {
    supportingText: { type: String, default: '' },
    supportedFormats: { type: Array, default: () => ['pdf'] }
  },
  data() {
    return { dragging: false };
  },
  computed: {
    acceptAttr() {
      return this.supportedFormats.map((f) => `.${f}`).join(',');
    }
  },
  methods: {
    openPicker() {
      this.$refs.fileInput.click();
    },
    onSelect(e) {
      const file = e.target.files && e.target.files[0];
      if (file) this.emitFile(file);
      e.target.value = '';
    },
    onDrop(e) {
      this.dragging = false;
      const file = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
      if (file) this.emitFile(file);
    },
    emitFile(file) {
      const ext = (file.name.split('.').pop() || '').toLowerCase();
      if (this.supportedFormats.length && !this.supportedFormats.includes(ext)) {
        this.$emit('onFile:error', `Unsupported file type .${ext}`);
        return;
      }
      this.$emit('onFile:dropped', file);
    }
  }
};
</script>

<style scoped>
.drag-and-drop-upload { border: 2px dashed #cbd5e1; border-radius: 6px; cursor: pointer; }
.drag-and-drop-upload.dragging { border-color: #3b82f6; background: #eff6ff; }
.hidden-file-input { display: none; }
</style>
