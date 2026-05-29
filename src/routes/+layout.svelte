<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import { applyZoopTheme } from '$lib/config/theme';
	import { supabase } from '$lib/supabase';
	import { invalidateAll } from '$app/navigation';

	let { children } = $props();

	onMount(() => {
		applyZoopTheme();

		// Re-run layout loads when auth state changes so child pages
		// receive the updated user/session immediately after sign-in.
		const { data } = supabase.auth.onAuthStateChange((event, _session) => {
			// Invalidate all load functions on sign-in/sign-out/token refresh
			if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'TOKEN_REFRESHED') {
				// best-effort: re-run load() functions so `+layout.ts` returns fresh `userId`
				try {
					invalidateAll();
				} catch (e) {
					// ignore — invalidateAll may not be available in older kit versions
					// fallback to a full reload if needed
					// location.reload();
				}
			}
		});

		return () => data.subscription?.unsubscribe();
	});
</script>

{@render children()}
