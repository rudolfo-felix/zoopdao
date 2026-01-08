<script lang="ts">
	import { goto } from '$app/navigation';
	import { Button } from '@/components/ui/button';
	import { m } from '../paraglide/messages.js';
	import { setLocale, getLocale, localizeUrl } from '../paraglide/runtime.js';
	import type { Locale } from '../paraglide/runtime.js';
	import clickSound from '@/sounds/click.mp3';
	import { onMount } from 'svelte';
	import { getVotingPeriods } from '$lib/data/voting-periods';
	
	let { data } = $props();

	let click_sound: HTMLAudioElement;

	onMount(() => {
		click_sound = new Audio(clickSound);
		click_sound.volume = 0.5;
	});

	const proposals = $derived(data.proposals || []);
	const currentYear = new Date().getFullYear();
	const votingPeriods = getVotingPeriods(currentYear);
	
	function getVotingPeriodLabel(periodId: string): string {
		const period = votingPeriods.find(p => p.id === periodId);
		return period?.label || periodId;
	}
	
	function handleProposalClick(proposalId: number) {
		click_sound.play();
		// TODO: Navigate to proposal flow (will be implemented in future stories)
		// For now, just show an alert
		alert(`Proposal ${proposalId} clicked - navigation to proposal flow will be implemented`);
	}

	let selectedLanguage = $state(getLocale()); // Default language

	// List of available languages
	const languages = [
		{ code: 'en', label: '🇬🇧 English' },
		{ code: 'pt', label: '🇵🇹 Português' }
	];

	// Function to change the language
	function changeLanguage(lang: Locale) {
		selectedLanguage = lang;
		setLocale(lang); // Update the locale using the Paraglide runtime
	}
</script>

<div class="h-screen flex flex-col items-center justify-center bg-[#efe7e2] relative p-4">
	<div class="z-10 flex flex-col items-center justify-center max-w-md relative">
		<div
			class="absolute -left-56 top-0 w-32 h-32 md:w-48 md:h-48 lg:w-52 lg:h-52 flex items-center justify-center"
		>
			<img src="/images/illustrations/step_5_1.png" alt="" class="w-full h-full object-contain" />
		</div>
		<div
			class="absolute -right-56 top-0 w-32 h-32 md:w-48 md:h-48 lg:w-52 lg:h-52 flex items-center justify-center"
		>
			<img src="/images/illustrations/step_2_1.png" alt="" class="w-full h-full object-contain" />
		</div>
		<h1 class="flex items-center justify-center text-dark-green font-black text-5xl md:text-7xl">
			ZoopDAO
		</h1>
		<p class="text-dark-green text-center text-lg mb-5 px-4 italic">
			"Participate on the multispecies governance in Aquário Vasco da Gama"
		</p>
		<div
			class="w-full flex flex-col items-stretch justify-center gap-6 mt-4 p-4 rounded-lg border-2"
		>
			<div class="flex flex-col items-center justify-center">
				<Button size="lg" href={localizeUrl('/proposals/new').toString()}>{m.new_proposal()}</Button>
			</div>
			<div class="flex items-center gap-4 w-full">
				<div class="h-px w-full bg-dark-green"></div>
				<p class="text-dark-green text-center text-lg font-bold">{m.or()}</p>
				<div class="h-px w-full bg-dark-green"></div>
			</div>
			<!-- Proposals List -->
			<div class="w-full flex flex-col items-center justify-center gap-2">
				<p class="flex items-center justify-center text-dark-green font-medium mb-2">
					{m.current_proposals()}
				</p>
				{#if proposals.length === 0}
					<p class="text-gray-500 text-sm italic">{m.no_proposals()}</p>
				{:else}
					<div class="w-full space-y-2 max-h-64 overflow-y-auto">
						{#each proposals as proposal}
							<button
								onclick={() => handleProposalClick(proposal.id)}
								class="w-full p-3 bg-white border-2 border-dark-green/20 rounded-lg hover:border-dark-green/60 hover:bg-gray-50 transition-all text-left"
							>
								<div class="flex flex-col gap-1">
									<p class="font-semibold text-dark-green">{proposal.title}</p>
									<p class="text-xs text-gray-500">
										{m.voting_period()}: {getVotingPeriodLabel(proposal.voting_period_id)}
									</p>
								</div>
							</button>
						{/each}
					</div>
				{/if}
			</div>
			<div class="flex items-center gap-4 w-full">
				<div class="h-px w-full bg-dark-green"></div>
				<p class="text-dark-green text-center text-lg font-bold">{m.or()}</p>
				<div class="h-px w-full bg-dark-green"></div>
			</div>
			<div class="flex flex-col items-center justify-center">
				<Button
					variant="outline"
					size="lg"
					href={localizeUrl('/stories').toString()}
					class="text-dark-green hover:text-dark-green/90 mb-4 bg-white hover-bg-gray-200 transition-all duration-200 ease-in-out border-dark-green/20 hover:border-dark-green/90"
				>
					{m.browse_stories()}
				</Button>
			</div>
		</div>
		<div
			class="absolute -right-56 bottom-0 w-32 h-32 md:w-48 md:h-48 lg:w-52 lg:h-52 flex items-center justify-center"
		>
			<img src="/images/illustrations/step_4_1.png" alt="" class="w-full h-full object-contain" />
		</div>
		<div
			class="absolute -left-56 bottom-0 w-32 h-32 md:w-48 md:h-48 lg:w-52 lg:h-52 flex items-center justify-center"
		>
			<img src="/images/illustrations/step_6_1.png" alt="" class="w-full h-full object-contain" />
		</div>
	</div>
	<div class="absolute top-4 right-4">
		<select
			class="p-2 border rounded"
			bind:value={selectedLanguage}
			onchange={(e) => changeLanguage((e.currentTarget as HTMLSelectElement).value as Locale)}
		>
			{#each languages as { code, label }}
				<option value={code}>{label}</option>
			{/each}
		</select>
	</div>
</div>
