<script lang="ts">
	import type { GameState } from '@/state/game-state.svelte';
	import Card from './card.svelte';
	import { Button } from './ui/button';
	import * as Dialog from './ui/dialog';
	import Textarea from './ui/textarea/textarea.svelte';
	import CharacterCard from './character-card.svelte';
	import { m } from '@src/paraglide/messages';
	import { getLocale } from '@src/paraglide/runtime.js';
	import { ROUNDS } from '../data/rounds';
	import { onMount } from 'svelte';
	import paperSound from '@/sounds/rustling-paper.mp3';
	import clickSound from '@/sounds/ui-click.mp3';
	import { createAudio, playAudio } from '$lib/utils/sound';
	import { Flag, FileText, Sparkles } from 'lucide-svelte';
	import Timer from './timer.svelte';
	import PostStory from './post-story-icon.svelte';
	import { getCharacterCategory, type Card as CardData, type Character } from '@src/lib/types';
	import SpeciesInfoDialog from './species-info-dialog.svelte';
	import ProposalDialog from '@/components/proposal-dialog.svelte';
	import { ZOOP_THEME_ASSET_PREFIX } from '$lib/config/theme';
	import { getProposalCardType } from '$lib/utils/proposal-cards';
	import { getProposalTextForRound as getProposalTextForRoundUtil } from '$lib/utils/proposal-points';
	import { ENABLE_AI_QUESTION_ASSISTANT } from '$lib/config/feature-flags';

	let audio: HTMLAudioElement | null = null;
	let click_sound: HTMLAudioElement | null = null;

	onMount(() => {
		click_sound = createAudio(clickSound, 0.5);
		audio = createAudio(paperSound, 0.5);
	});
	interface StoryDialogProps {
		open: boolean;
		gameState: GameState;
		proposalId?: number | null;
		historyOpen?: boolean;
	}

	let { open = $bindable(false), gameState, proposalId = null, historyOpen = false }: StoryDialogProps = $props();
	// Short window to block automatic submits when the history dialog opens
	let preventSubmitUntil = $state<number>(0);

	$effect(() => {
		if (historyOpen) {
			// block auto-submit for a brief moment after opening history to avoid races
			preventSubmitUntil = Date.now() + 800;
		}
	});
	let openProposalDialog = $state(false);
	let proposal = $state<any>(null);

	async function fetchProposal() {
		if (!proposalId) {
			proposal = null;
			return;
		}

		try {
			const response = await fetch(`/api/proposals/${proposalId}`);
			if (!response.ok) {
				throw new Error('Failed to fetch proposal');
			}
			const { proposal: proposalData } = await response.json();
			if (proposalData?.objectives && typeof proposalData.objectives === 'string') {
				try {
					proposalData.objectives = JSON.parse(proposalData.objectives);
				} catch (parseError) {
					console.error('Error parsing objectives:', parseError);
				}
			}
			proposal = proposalData;
		} catch (error) {
			console.error('Failed to load proposal:', error);
			proposal = null;
		}
	}

	$effect(() => {
		if (open) {
			fetchProposal();
		} else {
			proposal = null;
		}
	});

	let currentRound = $derived.by(() => {
		// Use gameState.currentRound directly, but ensure it's a number
		const round = gameState.currentRound;
		return typeof round === 'number' ? round : 0;
	});

	let sortedRounds = $derived.by(() => {
		if (!gameState.rounds || gameState.rounds.length === 0) {
			console.warn('No rounds found in gameState.rounds:', gameState.rounds);
			return [];
		}
		const sorted = [...gameState.rounds].sort((a, b) => a.index - b.index);
		console.log('Sorted rounds:', sorted);
		return sorted;
	});

	let player = $derived.by(() => {
		return gameState.players.find((player) => player.id === gameState.playerId);
	});

	function getProposalTextForRound(roundIndex: number): string {
		if (!proposal) return '';
		return getProposalTextForRoundUtil(proposal, roundIndex);
	}

	function getFallbackCardType(roundIndex: number): CardData['type'] {
		return getProposalCardType(roundIndex);
	}

	function buildProposalCard(roundIndex: number, text: string): CardData & { assetType?: string } {
		return {
			id: -roundIndex,
			type: getFallbackCardType(roundIndex),
			title: getTranslation(ROUNDS[roundIndex]?.title),
			text,
			assetType: roundIndex === 6 ? 'functionality' : undefined,
			hero_steps: [],
			character_category: ['human']
		};
	}
	$effect(() => {
		if (open && playerState === 'writing') {
			// Start timer only when dialog is actually open
			// Use setTimeout to ensure dialog is fully rendered before starting timer
			setTimeout(() => {
				// Round 7 is prompt-limited (no timer).
				if (currentRound === 7) return;
				const currentGameRound = gameState.gameRounds.find((r) => r.round === currentRound);
				if (currentGameRound && !currentGameRound.timer_duration) {
					gameState.startRoundTimer();
				}
			}, 100);

			playAudio(audio);
			setTimeout(() => {
				const round = document.getElementById(`round-${currentRound}`);
				if (round) {
					round.scrollIntoView({ behavior: 'smooth', block: 'center' });
				}
			}, 100); // Ensures DOM updates before scrolling
		}
	});

	let playerAnswers = $derived.by(() => {
		return gameState.playersAnswers.filter((answer) => answer.player_id === gameState.playerId);
	});
	let currentAnswer = $state('');

	const ASSISTANT_MAX_TOTAL = 3;
	let assistantRemaining = $state<number>(ASSISTANT_MAX_TOTAL);
	let assistantQuestion = $state<string | null>(null);
	let assistantError = $state<string | null>(null);
	let assistantStatusKey = $state<string | null>(null);
	let assistantStatusLoading = $state(false);
	let assistantGenerating = $state(false);

	function getAssistantButtonLabel(remaining: number) {
		const remainingLabel =
			getLocale() === 'pt'
				? `${remaining} ${remaining === 1 ? 'restante' : 'restantes'}`
				: `${remaining} left`;
		return `${getLocale() === 'pt' ? 'Pergunta IA' : 'AI question'} (${remainingLabel})`;
	}

	function createClientRequestId(): string {
		try {
			return crypto.randomUUID();
		} catch {
			return `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
		}
	}

	async function refreshAssistantRemaining(params: { gameId: number; round: number; userId: string }) {
		if (!ENABLE_AI_QUESTION_ASSISTANT) return;
		assistantStatusLoading = true;
		assistantError = null;
		try {
			const response = await fetch(
				`/api/ai/assistant?gameId=${params.gameId}&round=${params.round}&userId=${encodeURIComponent(
					params.userId
				)}`,
				{ method: 'GET' }
			);
			const result = await response.json();
			if (!response.ok || !result?.success) {
				throw new Error(result?.error?.message ?? 'Failed to load assistant status.');
			}
			if (typeof result.remaining === 'number' && Number.isFinite(result.remaining)) {
				assistantRemaining = Math.max(0, Math.min(ASSISTANT_MAX_TOTAL, result.remaining));
			} else {
				assistantRemaining = ASSISTANT_MAX_TOTAL;
			}
		} catch (error) {
			console.warn('Failed to refresh assistant remaining:', error);
			assistantRemaining = ASSISTANT_MAX_TOTAL;
		} finally {
			assistantStatusLoading = false;
		}
	}

	async function requestAssistantQuestion() {
		if (assistantGenerating) return;
		if (!ENABLE_AI_QUESTION_ASSISTANT) return;

		const round = currentRound;
		if (round < 1 || round > 6) return;

		const userId = player?.user_id;
		const gameId = gameState.getGameId();
		if (!userId || !Number.isFinite(gameId) || gameId <= 0) {
			assistantError = getLocale() === 'pt' ? 'Falha ao obter contexto do participante.' : 'Missing participant context.';
			return;
		}

		assistantGenerating = true;
		assistantError = null;

		function isPortugueseLocale() {
			return getLocale() && getLocale().toLowerCase().startsWith('pt');
		}

		function buildClientFallbackQuestion(params: { roleLabel: string | null; proposalPoint: string | null; round: number }) {
			const focusLabel = (ROUNDS[params.round] && ROUNDS[params.round].title) || (isPortugueseLocale() ? 'Ponto da proposta' : 'Proposal point');
			const role = params.roleLabel ? `as ${params.roleLabel}` : 'given your role';
			if (isPortugueseLocale()) {
				const rolePt = params.roleLabel ? `como ${params.roleLabel}` : 'dado o teu papel';
				if (params.proposalPoint) {
					return `Qual é a consideração mais importante ${rolePt} para preencher "${focusLabel}" neste ponto?`;
				}
				return `Que pergunta ajuda a preencher "${focusLabel}" ${rolePt} neste momento?`;
			}

			if (params.proposalPoint) {
				return `What is the most important consideration ${role} for filling "${focusLabel}" in this point?`;
			}
			return `What question would help fill "${focusLabel}" ${role} right now?`;
		}

		const controller = new AbortController();
		// Increase timeout to allow slower model/provider responses and help debugging
		const timeoutMs = 8000;
		const timeout = setTimeout(() => controller.abort(), timeoutMs);

		// Debug: log payload and timeout so we can inspect network activity in devtools
		console.debug('AI assistant request', {
			gameId: gameId,
			proposalId,
			round,
			userId,
			locale: getLocale(),
			timeoutMs
		});

		try {
			const response = await fetch('/api/ai/assistant', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					gameId,
					proposalId,
					round,
					userId,
					locale: getLocale(),
					clientRequestId: createClientRequestId()
				}),
				signal: controller.signal
			});

			clearTimeout(timeout);
			const result = await response.json();
			console.debug('AI assistant response', { ok: response.ok, status: response.status, result });
			if (!response.ok || !result?.success) {
				throw new Error(result?.error?.message ?? 'Failed to generate assistant question.');
			}

			if (typeof result.remaining === 'number' && Number.isFinite(result.remaining)) {
				assistantRemaining = Math.max(0, Math.min(ASSISTANT_MAX_TOTAL, result.remaining));
			}

			if (result.limitReached) {
				assistantQuestion = null;
				return;
			}

			assistantQuestion = typeof result.question === 'string' ? result.question : null;
			if (!assistantQuestion) {
				throw new Error('Assistant returned no question.');
			}
		} catch (error) {
			clearTimeout(timeout);
			if ((error as any)?.name === 'AbortError') {
				console.warn('Assistant request aborted (timeout reached)');
			} else {
				console.error('Assistant request failed:', error);
			}
			// Fallback: build a lightweight contextual question locally so the user isn't blocked by provider latency.
			try {
				const roleLabel = player?.role ?? null;
				const proposalPointText = getProposalTextForRound(round) || null;
				assistantQuestion = buildClientFallbackQuestion({ roleLabel, proposalPoint: proposalPointText, round });
			} catch (e) {
				assistantError =
					getLocale() === 'pt'
						? 'Não foi possível gerar uma pergunta agora.'
						: 'Could not generate a question right now.';
			}
		} finally {
			assistantGenerating = false;
		}
	}

	$effect(() => {
		if (!open) {
			assistantRemaining = ASSISTANT_MAX_TOTAL;
			assistantQuestion = null;
			assistantError = null;
			assistantStatusKey = null;
			assistantStatusLoading = false;
			assistantGenerating = false;
		}
	});

	$effect(() => {
		if (!open) return;
		if (playerState !== 'writing') return;
		if (!ENABLE_AI_QUESTION_ASSISTANT) return;
		if (currentRound < 1 || currentRound > 6) return;

		const userId = player?.user_id;
		const gameId = gameState.getGameId();

		// Debug: log game/player context to help diagnose authorization mismatches
		console.debug('Assistant status refresh context', {
			clientGameId: gameId,
			players0_game_id: gameState.players?.[0]?.game_id ?? null,
			players_length: gameState.players?.length ?? 0,
			playerId: player?.id ?? null,
			player_user_id: player?.user_id ?? null,
			currentRound
		});
		if (!userId || !Number.isFinite(gameId) || gameId <= 0) return;

		const key = `${gameId}:${userId}:${currentRound}`;
		if (assistantStatusKey === key) return;
		assistantStatusKey = key;
		assistantRemaining = ASSISTANT_MAX_TOTAL;
		assistantQuestion = null;
		assistantError = null;

		let cancelled = false;
		(async () => {
			await refreshAssistantRemaining({ gameId, round: currentRound, userId });
			if (cancelled) return;
		})();

		return () => {
			cancelled = true;
		};
	});

	async function submitAnswer() {
		if (playerState === 'writing') {
			if (historyOpen) {
				console.debug('submitAnswer aborted because discussion history is open');
				return;
			}
			if (Date.now() < (preventSubmitUntil ?? 0)) {
				console.debug('submitAnswer blocked by recent history open (preventSubmitUntil)', {
					preventSubmitUntil,
					now: Date.now()
				});
				return;
			}
			// Debug: log stack trace to find unexpected automatic submits
			try {
				console.debug('submitAnswer() called', {
					playerState,
					currentRound: gameState.currentRound,
					playerId: gameState.playerId,
					playersLength: gameState.players?.length ?? 0
				});
				console.debug(new Error('submitAnswer stack').stack);
			} catch (e) {
				/* ignore */
			}
			// Check if there's only one human player
			const humanPlayers = gameState.players.filter((p) => p.is_active !== false);
			const isSinglePlayer = humanPlayers.length === 1;
			const currentRoundBefore = gameState.currentRound;

			if (currentAnswer.trim() === '') {
				await gameState.submitAnswer(
					getLocale() === 'pt' ? '(Submissão vazia)' : '(Empty submission)'
				);
				alert(
					getLocale() === 'pt'
						? 'Não escreveste nada nesta ronda! Podes editar a tua discussão no final da participação.'
						: "You didn't write anything for this round! You can edit your discussion at the end of the participation."
				);
			} else {
				await gameState.submitAnswer(currentAnswer);
			}

			// If single player, wait for the round to advance
			if (isSinglePlayer) {
				// Wait for the database to process the answer and check round completion
				// check_round_completion will call roll_dice which creates a new game_round
				// The subscription will pick up the new round automatically
				let attempts = 0;
				const maxAttempts = 10; // Wait up to 2 seconds (10 * 200ms)

				while (attempts < maxAttempts) {
					await new Promise((resolve) => setTimeout(resolve, 200));

					// Check if the round has advanced
					if (gameState.currentRound > currentRoundBefore) {
						console.log('Round advanced from', currentRoundBefore, 'to', gameState.currentRound);
						break;
					}

					attempts++;
				}

				// If round didn't advance, log for debugging
				if (gameState.currentRound === currentRoundBefore) {
					console.warn(
						'Round did not advance after submit. Current round:',
						gameState.currentRound
					);
				}
			}

			open = false;
			currentAnswer = '';
		}
	}

	function onSubmit() {
		// Allow manual submit even if blocking window is active
		preventSubmitUntil = 0;
		playAudio(click_sound);
		submitAnswer();
	}

	function getTranslation(key: string | null | undefined): string {
		if (!key) return ''; // Return an empty string if the key is undefined
		const translation = m[key as keyof typeof m];
		if (typeof translation === 'function') {
			try {
				// Try calling without arguments first (for simple translations)
				return (translation as () => string)();
			} catch {
				// If that fails, try with empty object (for translations with parameters)
				try {
					return (translation as (params: { nickname: string }) => string)({ nickname: '' });
				} catch {
					return 'Translation missing';
				}
			}
		} else {
			console.warn(`Translation for key "${key}" is missing or not a function.`);
			return 'Translation missing';
		}
	}

	function handleTimeUp() {
		// Do not auto-submit on round 7 (discussion round) — user must submit manually
		if (currentRound === 7) {
		    console.debug('Timer finished for round 7 — skipping automatic submit');
		    return;
		}
		submitAnswer();
	}

	let playerState = $derived.by(() => {
		const state = gameState.playersState[gameState.playerId];
		return state?.state || 'starting';
	});

	let showSpeciesDialog = $state(false);
	function isNonHumanCharacter(character: Character | null | undefined): boolean {
		if (!character) return false;
		const category = getCharacterCategory(character);
		return category === 'non-human';
	}
</script>

<Dialog.Root bind:open>
	<Dialog.Content
		interactOutsideBehavior="ignore"
		class="overflow-y-auto flex flex-col gap-y-10 max-h-[95vh] w-[95vw] md:w-[50dvw] lg:w-[45dvw] bg-white rounded-2xl shadow-lg pb-80 md:pb-5"
		style="transform-origin: center center; z-index: 100;"
	>
		{#if sortedRounds.length === 0}
			<div class="p-8 text-center">
				<p class="text-gray-500">
					{getLocale() === 'pt'
						? 'Não há rondas disponíveis. Verifica se as rondas estão carregadas na base de dados.'
						: 'No rounds available. Please check if rounds are loaded in the database.'}
				</p>
			</div>
		{:else}
			{#each sortedRounds as round (round.index)}
				{@const answer = playerAnswers.find((answer) => answer.round === round.index)}
				{@const proposalText = getProposalTextForRound(round.index)}
				{@const displayCard = proposalText ? buildProposalCard(round.index, proposalText) : null}
				{@const isCurrentRound = round.index === currentRound}
				{@const isFutureRound = round.index > (currentRound ?? -1)}
				<div
					id={`round-${round.index}`}
					class="flex flex-col items-center gap-8 w-full {round.index > (currentRound ?? -1)
						? 'opacity-30 grayscale'
						: ''}"
				>
					<div class="shrink-0 flex flex-col items-stretch">
						{#if round.index === 0}
							{#if displayCard}
								<Card card={displayCard} />
							{:else}
								<CharacterCard character={player?.character ?? 'child'} />
							{/if}
							{#if player && isNonHumanCharacter(player.character)}
								<Button variant="outline" class="mt-2" onclick={() => (showSpeciesDialog = true)}
									>{getLocale() === 'pt'
										? 'Saber mais sobre a tua personagem'
										: 'Learn more about your character'}</Button
								>
								<SpeciesInfoDialog
									bind:open={showSpeciesDialog}
									character={player?.character ?? 'child'}
								/>
							{/if}
							{:else if round.index === 7}
								<div
									class="w-64 h-96 bg-white rounded-xl bg-center border-2 border-gray-400/50 relative"
									style={`background-image: url('${ZOOP_THEME_ASSET_PREFIX}/cards/post-story.svg');`}
								>
									<div
										class="absolute inset-0 pb-32 px-4 flex flex-col justify-end text-center gap-3"
									>
										<h3 class={`text-2xl font-bold text-white`}>{m.post_story()}</h3>
									</div>
								</div>
						{:else if displayCard}
							<Card card={displayCard} />
						{:else}
							<div
								class="w-64 h-96 rounded-lg border-black border-dashed border-2 flex items-center justify-center"
							>
								<p class="text-sm text-center">{m.card_not_selected()}</p>
							</div>
						{/if}
						{#if isCurrentRound}
							<Button
								variant="outline"
								class="mt-2 w-full flex items-center justify-center gap-2 hover:bg-tertiary/40"
								onclick={() => (openProposalDialog = true)}
								disabled={!proposalId}
							>
								<FileText class="h-4 w-4" />
								{m.view_full_proposal()}
							</Button>
						{/if}
					</div>
					<div class="flex flex-col items-stretch w-full">
						<div class="flex items-center gap-2">
							{#if round.index === 0}
								<div
									class="w-8 h-8 rounded-full bg-[#FF6157] bos-accent-bg grid place-items-center"
								>
									<Flag class="w-4 h-4 text-white flex items-center justify-center" />
								</div>
							{:else if round.index === 7}
								<div
									class="w-8 h-8 rounded-full grid place-items-center {isFutureRound
										? 'bg-red-500'
										: 'bg-deep-teal'}"
								>
									<div class="w-4 h-4 flex items-center justify-center">
										<PostStory color={'white'} />
									</div>
								</div>
							{:else}
								<div
									class="w-8 h-8 rounded-full grid place-items-center {isFutureRound
										? 'bg-red-500'
										: 'bg-deep-teal'}"
								>
									<span
										class="text-white font-medium text-center text-base flex items-center justify-center"
										>{round.index}</span
									>
								</div>
							{/if}
						</div>
						{#if round.index === currentRound && playerState === 'writing'}
							{#if round.index !== 7}
								<div class="relative mb-4">
									<Textarea class="mt-2" bind:value={currentAnswer} />
								</div>
							{/if}
							{#if ENABLE_AI_QUESTION_ASSISTANT && round.index >= 1 && round.index <= 6}
								{#if assistantQuestion}
									<div
										class="mb-4 rounded-xl border border-sand bg-sand/20 px-4 py-3 text-sm text-black"
									>
										<div class="flex items-center gap-2 font-semibold">
											<Sparkles class="h-4 w-4" />
											<span>{getLocale() === 'pt' ? 'Pergunta IA' : 'AI question'}</span>
										</div>
										<p class="mt-1 leading-snug">{assistantQuestion}</p>
									</div>
								{:else if assistantError}
									<div class="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm">
										<p class="text-red-700">{assistantError}</p>
									</div>
								{/if}
							{/if}
							<div class="flex flex-col gap-2 bg-white">
								{#if open &&
									playerState === 'writing' &&
									gameState.mode === 'pedagogic' &&
									gameState.getTimerDurationForRound(currentRound) > 0}
									<div class="w-full">
										<Timer
											onTimeUp={handleTimeUp}
											duration={gameState.getTimerDurationForRound(currentRound)}
										/>
									</div>
								{/if}
								<div class="flex items-center justify-end gap-2">
									{#if ENABLE_AI_QUESTION_ASSISTANT && round.index >= 1 && round.index <= 6}
										<Button
											variant="outline"
											class="flex items-center justify-center gap-2 hover:bg-tertiary/40"
											disabled={
												assistantGenerating ||
												assistantRemaining <= 0 ||
												!player?.user_id ||
												assistantStatusLoading
											}
											onclick={() => {
												if (!assistantGenerating) {
													playAudio(click_sound);
													requestAssistantQuestion();
												}
											}}
										>
											{#if assistantGenerating}
												<div class="w-4 h-4 border-2 border-t-transparent border-gray-700 rounded-full animate-spin" aria-hidden="true"></div>
												<span>{getLocale() === 'pt' ? 'A gerar...' : 'Generating...'}</span>
											{:else}
												<Sparkles class="h-4 w-4" />
												{getAssistantButtonLabel(assistantRemaining)}
											{/if}
										</Button>
									{/if}
									<Button onclick={onSubmit}>{m.submit()}</Button>
								</div>
							</div>
						{:else if round.index !== 7}
							<Textarea class="mt-2" value={answer?.answer ?? ''} disabled />
						{/if}
					</div>
				</div>
				{#if round.index !== 7}
					<div class="h-0.5 border-t-2 border-gray-200"></div>
				{/if}
			{/each}
		{/if}
	</Dialog.Content>
</Dialog.Root>

<ProposalDialog bind:open={openProposalDialog} {proposalId} />
