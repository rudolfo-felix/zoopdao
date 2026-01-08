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

	let click_sound: HTMLAudioElement;

	onMount(() => {
		click_sound = new Audio(clickSound);
		click_sound.volume = 0.5;
	});

	let title = $state('');
	let description = $state('');
	let discussion = $state('');
	let votingPeriod = $state('');

	function handleExit() {
		click_sound.play();
		goto(localizeUrl('/'));
	}

	function handleSubmit() {
		click_sound.play();
		// TODO: Implement proposal submission (ZD-155)
		// For now, just navigate back
		goto(localizeUrl('/'));
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

				<!-- Description Section (Theory of Change - placeholder for ZD-153) -->
				<div>
					<label for="description" class="block text-sm font-medium text-dark-green mb-2">
						{m.proposal_description()}
					</label>
					<Textarea
						id="description"
						bind:value={description}
						placeholder={m.proposal_description_placeholder()}
						required
						class="w-full min-h-[200px]"
					/>
					<p class="text-sm text-gray-600 mt-2">
						{m.theory_of_change_note()}
					</p>
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
						<!-- TODO: Add voting periods in ZD-154 -->
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

