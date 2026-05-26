<script lang="ts">
	import { Button } from '@/components/ui/button';
	import { ChevronLeft } from 'lucide-svelte';
	import RelativeTime from '@/components/relative-time.svelte';
	import CharacterCard from '@/components/character-card.svelte';
	import Card from '@/components/card.svelte';
	import { Flag } from 'lucide-svelte';
	import PostStory from '@/components/post-story-icon.svelte';
	import { CARDS } from '$lib/data/cards';
	import { ROUNDS } from '$lib/data/rounds';
	import type { Card as CardType } from '$lib/types';
	import type { Round } from '$lib/types';
	import { m } from '@src/paraglide/messages';
	import { getLocale } from '@src/paraglide/runtime';
	import { Share2, Check } from 'lucide-svelte';
	import { onDestroy } from 'svelte';
	import { localizeHref } from '@src/paraglide/runtime';
	import { getProposalCardType } from '$lib/utils/proposal-cards';

	let isCopied = $state(false);
	let copyTimeout: ReturnType<typeof setTimeout>;

	const buttonColor = {
		landmark: 'bg-dark-deep',
		nature: 'bg-sea-green',
		sense: 'bg-sand',
		history: 'bg-sand',
		action: 'bg-driftwood'
	} as const;

	let { data } = $props();
	let story = data.story;
	let cards = data.cards;
	let proposal = data.proposal;

	let storyCharacter = (story.character?.type ?? 'custom') as any;

	let sortedRounds = Object.entries(story.rounds)
		.map(([key, round]) => ({
			...round,
			roundNumber: parseInt(key)
		}))
		.sort((a, b) => a.roundNumber - b.roundNumber);

	function getCardDetails(cardId: number | null): CardType | null {
		if (!cardId) return null;
		return cards.find((card): card is CardType => card.id === cardId) ?? null;
	}

	function getRoundDetails(roundNumber: number): Round | null {
		return ROUNDS.find((round) => round.index === roundNumber) ?? null;
	}

	function getTranslation(key: string | null | undefined): string {
		if (!key) return ''; // Return an empty string if the key is undefined
		const translation = m[key as keyof typeof m];
		if (typeof translation === 'function') {
			return translation();
		} else {
			console.warn(`Translation for key "${key}" is missing or not a function.`);
			return 'Translation missing';
		}
	}

	function getRoleLabel(): string {
		const customRole = (story.character as any)?.custom_role as string | null | undefined;
		if (customRole && customRole.trim().length > 0) return customRole.trim();
		const type = story.character?.type as unknown as string | null | undefined;
		if (type) {
			const roleKey = `character_${type}_title`;
			const translated = getTranslation(roleKey);
			if (translated && translated !== 'Translation missing') return translated;
			return type
				.split('-')
				.map((w) => w.charAt(0).toUpperCase() + w.slice(1))
				.join(' ');
		}
		return '-';
	}

	function getVoteLabel(vote: string | null | undefined): string {
		if (!vote) return '-';
		if (vote === 'yes') return m.vote_yes();
		if (vote === 'no') return m.vote_no();
		if (vote === 'abstain') return m.vote_abstain();
		return vote;
	}

	function getModeLabel(mode: string | null | undefined): string {
		if (mode === 'pedagogic') return m.pedagogic_mode();
		if (mode === 'decision_making') return m.decision_making_mode();
		return '-';
	}

	async function copyToClipboard() {
		const url = window.location.href;
		await navigator.clipboard.writeText(url);

		// Set copied state
		isCopied = true;

		// Clear any existing timeout
		if (copyTimeout) clearTimeout(copyTimeout);

		// Reset after 2 seconds
		copyTimeout = setTimeout(() => {
			isCopied = false;
		}, 2000);
	}

	// Cleanup timeout on component destroy
	onDestroy(() => {
		if (copyTimeout) clearTimeout(copyTimeout);
	});

	function normalizeObjectives(objectives: unknown) {
		if (!objectives) return [];
		if (Array.isArray(objectives)) return objectives;
		if (typeof objectives === 'string') {
			try {
				return JSON.parse(objectives);
			} catch {
				return [];
			}
		}
		return [];
	}

	const objectives = $derived.by(() => normalizeObjectives(proposal?.objectives));
	const objectiveValues = $derived.by(() =>
		objectives
			.map((objective: { value?: string }) => objective.value)
			.filter((value: string | undefined): value is string => !!value)
	);
	const preconditions = $derived.by(() =>
		objectives
			.flatMap((objective: { preconditions?: { value?: string }[] }) => objective.preconditions ?? [])
			.map((precondition) => precondition.value)
			.filter((value: string | undefined): value is string => !!value)
	);
	const indicativeSteps = $derived.by(() =>
		objectives
			.flatMap((objective: { preconditions?: { indicativeSteps?: { value?: string }[] }[] }) => objective.preconditions ?? [])
			.flatMap((precondition) => precondition.indicativeSteps ?? [])
			.map((step) => step.value)
			.filter((value: string | undefined): value is string => !!value)
	);
	const keyIndicators = $derived.by(() =>
		objectives
			.flatMap((objective: { preconditions?: { keyIndicators?: { value?: string }[] }[] }) => objective.preconditions ?? [])
			.flatMap((precondition) => precondition.keyIndicators ?? [])
			.map((indicator) => indicator.value)
			.filter((value: string | undefined): value is string => !!value)
	);

	function getProposalPointsForRound(roundNumber: number): string[] {
		if (!proposal) return [];
		if (roundNumber === 0) return proposal.title ? [proposal.title] : [];
		if (roundNumber === 1) return objectiveValues[0] ? [objectiveValues[0]] : [];
		if (roundNumber === 2) return objectiveValues[1] ? [objectiveValues[1]] : [];
		if (roundNumber === 3) return preconditions;
		if (roundNumber === 4) return indicativeSteps;
		if (roundNumber === 5) return keyIndicators;
		if (roundNumber === 6) return proposal.functionalities ? [proposal.functionalities] : [];
		return [];
	}

	function getProposalTextForRound(roundNumber: number): string {
		const points = getProposalPointsForRound(roundNumber);
		if (points.length === 0) return '';
		return points.join(' • ');
	}

	function splitChatMessages(text: string): string[] {
		// Round 7 is stored as "Name: message\n\nName: message..."
		return text
			.split(/\n{2,}/)
			.map((s) => s.trim())
			.filter(Boolean);
	}
</script>

<div class="flex flex-col p-6 lg:p-24 w-screen mx-auto">
	<div class="flex items-center">
		<Button class="p-0 text-lg gap-1" variant={'ghost'} href={localizeHref('/stories')}
			><ChevronLeft strokeWidth={4} size={32} absoluteStrokeWidth={true} />
			{m.view_all_stories()}</Button
		>
	</div>

	<div class="mt-4">
		<RelativeTime date={data.story.created_at} />
	</div>
	<div class="flex flex-col gap-4">
		<div class="flex flex-col gap-4">
			<div class="flex">
				<div class="flex mt-4 flex-wrap w-full items-center justify-between">
					<h1 class="font-bold text-deep-teal text-4xl">{proposal?.title ?? data.story.story_title}</h1>
					<div class="flex gap-4 items-center mt-4">
						<Button
							variant={'outline'}
							onclick={copyToClipboard}
							class="transition-all duration-200"
						>
							{#if isCopied}
								<Check class="w-4 h-4 mr-2" /> {m.copied()}
							{:else}
								<Share2 class="w-4 h-4 mr-2" /> {m.share()}
							{/if}
						</Button>
						<Button href={localizeHref('/')}>{m.participate()}</Button>
					</div>
				</div>
			</div>
			<div class="flex flex-col gap-2">
				<p class="text-lg">
					<span class="text-gray-500">{getLocale() === 'pt' ? 'Cargo' : 'Role'}:</span>
					<span class="font-bold text-black"> {getRoleLabel()}</span>
				</p>
				<p class="text-lg">
					<span class="text-gray-500">{getLocale() === 'pt' ? 'Modo' : 'Mode'}:</span>
					<span class="font-bold text-black"> {getModeLabel((story as any)?.discussion_mode ?? null)}</span>
				</p>
				<p class="text-lg">
					<span class="text-gray-500">{getLocale() === 'pt' ? 'Voto final' : 'Final vote'}:</span>
					<span class="font-bold text-black"> {getVoteLabel((story as any).vote ?? null)}</span>
				</p>
				<p class="text-lg">
					<span class="text-gray-500">{getLocale() === 'pt' ? 'Participante' : 'NA'}:</span>
					<span class="font-bold text-black"> {story.player_name}</span>
				</p>
				{#if story.character.description?.trim()}
					<p class="text-gray-500 text-sm">"{story.character.description}"</p>
				{/if}
			</div>
			<div>
				<div class="flex gap-2 flex-wrap">
					{#each story.card_types as type}
						<span
							class="capitalize inline-block px-4 py-2 text-xs rounded-md mb-2 {buttonColor[
								type as keyof typeof buttonColor
							]} text-white"
						>
							{getTranslation(`${type}_type`)}
						</span>
					{/each}
				</div>
			</div>
		</div>
	</div>

	<div class="flex items-center gap-4 my-4">
		<div class="h-[1px] flex-1 bg-gray-200"></div>
		<h2 class="text-xl font-medium text-deep-teal">{m.story()}</h2>
		<div class="h-[1px] flex-1 bg-gray-200"></div>
	</div>
	<div class="flex items-center justify-center w-full mb-8">
		<div class="flex flex-col gap-6 mt-8">
			{#each sortedRounds as round (round.roundNumber)}
				<div class="flex gap-4 md:gap-8 w-full relative">
					{#if round.round < sortedRounds.length - 1}
						<div class="absolute left-4 md:left-4 top-8 w-[2px] h-full bg-deep-teal -z-10"></div>
					{/if}

					<div class="flex-shrink-0">
						{#if round.round === 0}
							<div class="w-8 h-8 rounded-full bg-[#FF6157] bos-accent-bg grid place-items-center self-start">
								<Flag class="w-4 h-4 text-white" />
							</div>
						{:else if round.round === 7}
							<div
								class="w-8 h-8 rounded-full text-white bg-deep-teal grid place-items-center self-start"
							>
								<PostStory color={'white'} />
							</div>
						{:else}
							<div
								class="w-8 h-8 rounded-full text-sm font-bold text-white bg-deep-teal grid place-items-center self-start"
							>
								{round.round}
							</div>
						{/if}
					</div>

					<div class="flex-1 max-w-[75ch]">
						{#if round.roundNumber === 7}
							{@const msgs = splitChatMessages(round.answer)}
							{#if msgs.length > 3}
								<div class="max-h-56 overflow-y-scroll pr-2 space-y-3">
									{#each msgs as msg}
										<p class="text-pretty whitespace-pre-wrap break-words">{msg}</p>
									{/each}
								</div>
							{:else}
								<div class="space-y-3">
									{#each msgs as msg}
										<p class="text-pretty whitespace-pre-wrap break-words">{msg}</p>
									{/each}
								</div>
							{/if}
						{:else}
							<p class="text-pretty whitespace-pre-wrap break-words">{round.answer}</p>
						{/if}
						{#if getProposalPointsForRound(round.roundNumber).length > 0}
							<div class="mt-3 rounded-lg border border-deep-teal border-opacity-10 bg-gray-50 px-4 py-3">
								<p class="text-xs font-semibold uppercase tracking-wide text-deep-teal text-opacity-70">
									{m.proposal_points()}
								</p>
								<ul class="mt-2 list-disc pl-5 text-sm text-gray-700 space-y-1">
									{#each getProposalPointsForRound(round.roundNumber) as point}
										<li>{point}</li>
									{/each}
								</ul>
							</div>
						{/if}
					</div>
				</div>
			{/each}
		</div>
	</div>
	<div class="flex items-center gap-4 my-4">
		<div class="h-[1px] flex-1 bg-gray-200"></div>
		<h2 class="text-xl font-medium text-deep-teal">{m.cards_drawn()}</h2>
		<div class="h-[1px] flex-1 bg-gray-200"></div>
	</div>
	<div class="flex gap-4 items-center justify-start w-full">
		<div class="relative w-full">
			<div class="flex-1 overflow-x-auto md:overflow-x-scroll snap-x snap-mandatory md:snap-none">
				<div class="flex gap-8 px-4 min-w-min">
					<div class="flex-shrink-0">
						<div class="group/char flex gap-4 flex-col w-fit">
							<div class="flex snap-center items-center gap-2 justify-center">
								<div class="w-8 h-8 rounded-full bg-[#FF6157] bos-accent-bg grid place-items-center">
									<Flag class="w-4 h-4 text-white flex items-center justify-center" />
								</div>
								<span class="font-medium text-center text-base flex items-center justify-center">
									{m.intro()}
								</span>
							</div>
							{#if getProposalTextForRound(0)}
								<Card
									card={{
										id: 0,
										type: 'nature',
										title: getTranslation(ROUNDS[0]?.title),
										text: getProposalTextForRound(0),
										hero_steps: [],
										character_category: ['human']
									}}
								/>
							{:else}
								<CharacterCard character={storyCharacter} />
							{/if}
						</div>
					</div>
					<div class="h-999 w-[2px] bg-gray-200 flex-shrink-0"></div>

					<div class="flex-1">
						<div class="flex gap-8 px-4 min-w-min">
							{#each sortedRounds as round, index (round.roundNumber)}
								{#if round.round !== 0 && round.round !== 7}
									{@const card = getCardDetails(round.card_id)}
									{@const roundDetails = getRoundDetails(round.round)}
									{@const proposalText = getProposalTextForRound(round.roundNumber)}
									{@const functionalityAsset =
										proposalText && round.roundNumber === 6 ? 'functionality' : undefined}
									{@const displayCard = card
										? {
												...card,
												text: proposalText || card.text,
												assetType: functionalityAsset
											}
										: proposalText
											? {
													id: -round.roundNumber,
													type: round.type ?? getProposalCardType(round.roundNumber),
													title: getTranslation(roundDetails?.title),
													text: proposalText,
													assetType: functionalityAsset,
													hero_steps: [],
													character_category: ['human']
												}
											: null}

									<div class="flex-shrink-0 snap-center flex flex-col items-center gap-4">
										<div class="flex items-center justify-center gap-2">
											<div
												class="w-8 h-8 rounded-full text-white bg-deep-teal grid place-items-center"
											>
												{round.round}
											</div>
											<span class="font-medium text-center text-base">
												{getTranslation(roundDetails?.title)}
											</span>
										</div>

										{#if displayCard}
											<Card card={displayCard} />
										{/if}
									</div>
								{/if}
							{/each}
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
	<div class="flex flex-col gap-4 items-center mt-16">
		<p>{m.try_for_yourself()}!</p>
		<Button href={'/'}>{m.participate()}</Button>
	</div>
</div>
