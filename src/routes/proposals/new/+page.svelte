<script lang="ts">
	import { goto } from '$app/navigation';
	import { Button } from '@/components/ui/button';
	import { Input } from '@/components/ui/input';
	import { Textarea } from '@/components/ui/textarea';
	import { X } from 'lucide-svelte';
	import { m } from '@src/paraglide/messages';
	import { localizeUrl } from '@src/paraglide/runtime.js';
	import clickSound from '@/sounds/click.mp3';
	import { onMount } from 'svelte';
	import { getVotingPeriods } from '$lib/data/voting-periods';

	// Theory of Change data structure
	type IndicativeStep = { id: string; value: string };
	type KeyIndicator = { id: string; value: string };
	type Precondition = {
		id: string;
		value: string;
		indicativeSteps: IndicativeStep[];
		keyIndicators: KeyIndicator[];
	};
	type Objective = {
		id: string;
		value: string;
		preconditions: Precondition[];
	};

	let click_sound: HTMLAudioElement;

	onMount(() => {
		click_sound = new Audio(clickSound);
		click_sound.volume = 0.5;
	});

	let title = $state('');
	let objectives = $state<Objective[]>([
		{ id: '1', value: '', preconditions: Array(2).fill(null).map((_, i) => ({
			id: `1-${i + 1}`,
			value: '',
			indicativeSteps: [{ id: `1-${i + 1}-step-1`, value: '' }],
			keyIndicators: [{ id: `1-${i + 1}-indicator-1`, value: '' }]
		})) },
		{ id: '2', value: '', preconditions: Array(2).fill(null).map((_, i) => ({
			id: `2-${i + 1}`,
			value: '',
			indicativeSteps: [{ id: `2-${i + 1}-step-1`, value: '' }],
			keyIndicators: [{ id: `2-${i + 1}-indicator-1`, value: '' }]
		})) }
	]);
	let functionalities = $state('');
	let discussion = $state('');
	let votingPeriod = $state('');
	let proposalLanguage = $state(getLocale()); // Default to current locale

	// Get voting periods for current year only (excluding exceptional periods)
	const currentYear = new Date().getFullYear();
	const votingPeriods = getVotingPeriods(currentYear);



	function validateForm(): boolean {
		if (!title.trim()) return false;
		if (objectives.length < 2) return false;
		for (const objective of objectives) {
			if (!objective.value.trim()) return false;
			if (objective.preconditions.length < 2) return false;
			for (const precondition of objective.preconditions) {
				if (!precondition.value.trim()) return false;
				if (precondition.indicativeSteps.length < 1) return false;
				for (const step of precondition.indicativeSteps) {
					if (!step.value.trim()) return false;
				}
				if (precondition.keyIndicators.length < 1) return false;
				for (const indicator of precondition.keyIndicators) {
					if (!indicator.value.trim()) return false;
				}
			}
		}
		if (!functionalities.trim()) return false;
		if (!discussion.trim()) return false;
		if (!votingPeriod) return false;
		return true;
	}

	function handleExit() {
		click_sound.play();
		goto(localizeUrl('/'));
	}

	async function handleSubmit() {
		click_sound.play();
		if (!validateForm()) {
			alert(m.form_validation_error());
			return;
		}
		
		try {
			const response = await fetch('/api/proposals', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({
					title,
					objectives,
					functionalities,
					discussion,
					voting_period_id: votingPeriod,
					language: proposalLanguage
				})
			});
			
			if (!response.ok) {
				const error = await response.json();
				alert(error.error || m.proposal_submission_error());
				return;
			}
			
			// Success - navigate back to homepage
			goto(localizeUrl('/'));
		} catch (error) {
			console.error('Error submitting proposal:', error);
			alert(m.proposal_submission_error());
		}
	}
</script>

<div class="min-h-screen bg-[#efe7e2] p-4">
	<div class="max-w-4xl mx-auto">
		<!-- Exit Button -->
		<div class="flex justify-end mb-4">
			<Button variant="ghost" size="icon" onclick={handleExit} class="text-dark-green">
				<X class="h-6 w-6" />
			</Button>
		</div>

		<!-- Form -->
		<div class="bg-white rounded-lg border-2 border-dark-green/20 p-6 md:p-8">
			<h1 class="text-3xl font-bold text-dark-green mb-6">{m.new_proposal()}</h1>

			<form onsubmit={(e) => { e.preventDefault(); handleSubmit(); }} class="space-y-6">
				<!-- Title Field -->
				<div>
					<label for="title" class="block text-sm font-medium text-dark-green mb-2">
						{m.proposal_title()}
					</label>
					<Input
						id="title"
						type="text"
						bind:value={title}
						placeholder={m.proposal_title_placeholder()}
						required
						class="w-full"
					/>
				</div>

				<!-- Theory of Change Section -->
				<div class="space-y-6">
					<h2 class="text-2xl font-bold text-dark-green">{m.theory_of_change()}</h2>
					
					<!-- Long-term Objectives -->
					<div class="space-y-4">
						<div class="block text-lg font-semibold text-dark-green">
							{m.long_term_objectives()} <span class="text-red-500">*</span>
							<span class="text-sm font-normal text-gray-600 ml-2">({m.long_term_objectives_description()})</span>
						</div>
						
						{#each objectives as objective, objectiveIndex}
							<div class="border-2 border-dark-green/20 rounded-lg p-4 bg-gray-50">
								<div class="flex items-start gap-2 mb-3">
									<span class="text-sm font-medium text-dark-green mt-2">
										{m.objective()} {objectiveIndex + 1}:
									</span>
									<Input
										bind:value={objective.value}
										placeholder={m.objective_placeholder()}
										required
										class="flex-1"
									/>
								</div>
								
								<!-- Preconditions -->
								<div class="ml-4 space-y-3 mt-4">
									<div class="block text-sm font-semibold text-dark-green">
										{m.preconditions_and_goals()} <span class="text-red-500">*</span>
										<span class="text-xs font-normal text-gray-600 ml-2">({m.preconditions_and_goals_description()})</span>
									</div>
									
									{#each objective.preconditions as precondition, preconditionIndex}
										<div class="border border-dark-green/10 rounded p-3 bg-white">
											<div class="flex items-start gap-2 mb-2">
												<span class="text-xs font-medium text-dark-green mt-2">
													{m.precondition()} {preconditionIndex + 1}:
												</span>
												<Input
													bind:value={precondition.value}
													placeholder={m.precondition_placeholder()}
													required
													class="flex-1"
												/>
											</div>
											
											<!-- Indicative Steps -->
											<div class="ml-4 space-y-2 mt-3">
												<div class="block text-xs font-semibold text-dark-green">
													{m.indicative_steps()} <span class="text-red-500">*</span>
												</div>
												{#each precondition.indicativeSteps as step}
													<Input
														bind:value={step.value}
														placeholder={m.step_placeholder()}
														required
														class="w-full text-sm"
													/>
												{/each}
											</div>
											
											<!-- Key Indicators -->
											<div class="ml-4 space-y-2 mt-3">
												<div class="block text-xs font-semibold text-dark-green">
													{m.key_indicators()} <span class="text-red-500">*</span>
													<span class="text-xs font-normal text-gray-600 ml-2">({m.key_indicators_description()})</span>
												</div>
												{#each precondition.keyIndicators as indicator}
													<Input
														bind:value={indicator.value}
														placeholder={m.indicator_placeholder()}
														required
														class="w-full text-sm"
													/>
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
						<label for="functionalities" class="block text-lg font-semibold text-dark-green mb-2">
							{m.functionalities()} <span class="text-red-500">*</span>
						</label>
						<Textarea
							id="functionalities"
							bind:value={functionalities}
							placeholder={m.functionalities_placeholder()}
							required
							class="w-full min-h-[150px]"
						/>
					</div>
				</div>

				<!-- Discussion Field -->
				<div>
					<label for="discussion" class="block text-sm font-medium text-dark-green mb-2">
						{m.proposal_discussion()}
					</label>
					<Textarea
						id="discussion"
						bind:value={discussion}
						placeholder={m.proposal_discussion_placeholder()}
						required
						class="w-full min-h-[150px]"
					/>
				</div>

				<!-- Voting Period Selection (placeholder for ZD-154) -->
				<div>
					<label for="votingPeriod" class="block text-sm font-medium text-dark-green mb-2">
						{m.voting_period()}
					</label>
					<select
						id="votingPeriod"
						bind:value={votingPeriod}
						required
						class="border-dark-green bg-white ring-offset-white focus-visible:ring-dark-green flex h-10 w-full rounded-md border px-3 py-2 text-base focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 md:text-sm"
					>
						<option value="">{m.select_voting_period()}</option>
						{#each votingPeriods as period}
							<option value={period.id}>{period.label}</option>
						{/each}
					</select>
				</div>

				<!-- Submit Button -->
				<div class="flex justify-end gap-4 pt-4">
					<Button type="button" variant="outline" onclick={handleExit}>
						{m.cancel()}
					</Button>
					<Button type="submit" size="lg">
						{m.submit_proposal()}
					</Button>
				</div>
			</form>
		</div>
	</div>
</div>

