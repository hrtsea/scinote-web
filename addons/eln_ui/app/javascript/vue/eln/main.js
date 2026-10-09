import { createApp } from 'vue/dist/vue.esm-bundler.js'
import App from './App.vue'
import router from './router'
import './styles/tokens.css'

createApp(App).use(router).mount('#app')
