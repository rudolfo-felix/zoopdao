<script lang="ts">
	import { goto } from '$app/navigation';
	import { Button } from '@/components/ui/button';
	import { ArrowLeft } from 'lucide-svelte';
	import { m } from '@src/paraglide/messages';
	import { localizeUrl } from '@src/paraglide/runtime.js';
	import clickSound from '@/sounds/click.mp3';
	import { onMount } from 'svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	let click_sound: HTMLAudioElement;

	onMount(() => {
		click_sound = new Audio(clickSound);
		click_sound.volume = 0.5;
	});

	const proposal = data.proposal;

	function handleBack() {
		click_sound.play();
		goto(localizeUrl('/').toString());
	}
</script>

<div class="min-h-screen bg-[#efe7e2] p-4">
	<div class="max-w-4xl mx-auto">
		<!-- Back Button -->
		<div class="mb-4">
			<Button variant="ghost" size="icon" onclick={handleBack} class="text-dark-green">
				<ArrowLeft class="h-6 w-6" />
			</Button>
		</div>

		<!-- Proposal View -->
		<div class="bg-white rounded-lg border-2 border-dark-green/20 p-6 md:p-8">
			<h1 class="text-3xl font-bold text-dark-green mb-6">{proposal.title}</h1>

			<!-- Theory of Change Section -->
			<div class="space-y-6">
				<h2 class="text-2xl font-bold text-dark-green">{m.theory_of_change()}</h2>
				
				<!-- Long-term Objectives -->
				<div class="space-y-4">
					<div class="block text-lg font-semibold text-dark-green">
						{m.long_term_objectives()}
						<span class="text-sm font-normal text-gray-600 ml-2">({m.long_term_objectives_description()})</span>
					</div>
					
					{#each proposal.objectives as objective, objectiveIndex}
						<div class="border-2 border-dark-green/20 rounded-lg p-4 bg-gray-50">
							<div class="mb-3">
								<span class="text-sm font-medium text-dark-green">
									{m.objective()} {objectiveIndex + 1}:
								</span>
								<p class="text-gray-700 mt-1">{objective.value}</p>
							</div>
							
							<!-- Preconditions -->
							<div class="ml-4 space-y-3 mt-4">
								<div class="block text-sm font-semibold text-dark-green">
									{m.preconditions_and_goals()}
									<span class="text-xs font-normal text-gray-600 ml-2">({m.preconditions_and_goals_description()})</span>
								</div>
								
								{#each objective.preconditions as precondition, preconditionIndex}
									<div class="border border-dark-green/10 rounded p-3 bg-white">
										<div class="mb-2">
											<span class="text-xs font-medium text-dark-green">
												{m.precondition()} {preconditionIndex + 1}:
											</span>
											<p class="text-gray-700 mt-1 text-sm">{precondition.value}</p>
										</div>
										
										<!-- Indicative Steps -->
										<div class="ml-4 space-y-2 mt-3">
											<div class="block text-xs font-semibold text-dark-green">
												{m.indicative_steps()}
											</div>
											{#each precondition.indicativeSteps as step}
												<p class="text-gray-700 text-sm">{step.value}</p>
											{/each}
										</div>
										
										<!-- Key Indicators -->
										<div class="ml-4 space-y-2 mt-3">
											<div class="block text-xs font-semibold text-dark-green">
												{m.key_indicators()}
												<span class="text-xs font-normal text-gray-600 ml-2">({m.key_indicators_description()})</span>
											</div>
											{#each precondition.keyIndicators as indicator}
												<p class="text-gray-700 text-sm">{indicator.value}</p>
											{/each}
										</div>
									</div>
								{/each}
							</div>
						</div>
					{/each}
				</div>
				
				<!-- Functionalities -->
				<div>
					<label class="block text-lg font-semibold text-dark-green mb-2">
						{m.functionalities()}
					</label>
					<div class="bg-gray-50 border border-dark-green/10 rounded p-4">
						<p class="text-gray-700 whitespace-pre-line">{proposal.functionalities}</p>
					</div>
				</div>
			</div>

			<!-- Discussion Field -->
			<div class="mt-6">
				<label class="block text-sm font-medium text-dark-green mb-2">
					{m.proposal_discussion()}
				</label>
				<div class="bg-gray-50 border border-dark-green/10 rounded p-4">
					<p class="text-gray-700 whitespace-pre-line">{proposal.discussion}</p>
				</div>
			</div>
		</div>
	</div>
</div>

