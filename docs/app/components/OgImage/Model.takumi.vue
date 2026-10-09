<script setup lang="ts">
  const props = defineProps({
    title: { type: String, default: 'LDAP Studio' },
    description: { type: String, default: 'A native macOS LDAP client' },
  })
</script>

<template>
  <div class="flex h-full w-full flex-col justify-between bg-black p-16 text-[#f5f5f7]">
    <div class="flex items-center">
      <img src="/logo.png" width="72" height="72" />
      <div class="ml-5 flex text-[30px] font-semibold">LDAP Studio</div>
    </div>
    <div class="flex flex-col">
      <div class="flex text-[110px] leading-none font-semibold tracking-tight">
        {{ props.title }}
      </div>
      <div class="mt-6 flex max-w-225 text-[40px] leading-snug text-[#86868b]">
        {{ props.description }}
      </div>
    </div>
    <div class="flex text-[24px] tracking-widest text-[#2997ff] uppercase">
      github.com/dethdkn/ldap-studio
    </div>
  </div>
</template>
