<script lang="ts">
	import { Button } from './ui/button';
	import * as Dialog from './ui/dialog';
	import { m } from '@src/paraglide/messages';
	import { localizeHref } from '@src/paraglide/runtime';
	import { getLocale } from '@src/paraglide/runtime.js';
	import clickSound from '@/sounds/click.mp3';
	import { onMount } from 'svelte';
	import { createAudio, playAudio } from '$lib/utils/sound';
	import { GameState } from '@/state/game-state.svelte';
	import type { Player, PlayerAnswer } from '@/types';
	import { ROLES } from '@/types';
	import { CHARACTER } from '../data/characters';
	import { goto } from '$app/navigation';
	import { Textarea } from './ui/textarea';
	import { supabase } from '@/supabase';
	import { getDiscussionMessages } from '@/utils/discussion-messages';
	import { ZOOP_THEME_ASSET_PREFIX } from '$lib/config/theme';
	import { ROUNDS } from '$lib/data/rounds';
	import { User } from 'lucide-svelte';

	let audio: HTMLAudioElement | null = null;
	onMount(() => {
		audio = createAudio(clickSound, 0.5);
	});

	interface EndDialogProps {
		open: boolean;
		gameState: GameState;
		autoSaveOnOpen?: boolean;
		discussionMessages?: Array<{
			id: string;
			content: string;
			senderType: 'human' | 'ai';
			senderName: string;
			round: number;
			timestamp: Date;
		}>;
		proposalId?: number | null;
	}

	let {
		open = $bindable(false),
		gameState,
		autoSaveOnOpen = false,
		discussionMessages = [],
		proposalId = null
	}: EndDialogProps = $props();
	let currentPlayerId = $state(gameState?.playerId || -1);
	let discussionMessagesRound7 = $state<
		Array<{ senderName: string; content: string; timestamp: Date }>
	>([]);
	let vote = $state<'yes' | 'no' | 'abstain' | null>(null);
	let proposal = $state<any>(null);
	let existingProposalVote = $state<{
		choice: 'yes' | 'no' | 'abstain';
		context: 'preview' | 'discussion';
	} | null>(null);
	let isSubmitting = $state(false);
	let round7MessagesLoaded = $state(false);
	let autoSaveDone = $state(false);
	const voteOptions = [
		{ key: 'yes' as const, label: () => m.vote_yes(), color: 'bg-green-200 border-green-500' },
		{ key: 'no' as const, label: () => m.vote_no(), color: 'bg-rose-200 border-rose-500' },
		{ key: 'abstain' as const, label: () => m.vote_abstain(), color: 'bg-gray-200 border-gray-400' }
	];

	const roleSet = new Set<string>(ROLES as unknown as string[]);

	function getBadgeSrc(characterType: string | null | undefined) {
		const type = characterType ?? 'custom';
		if (roleSet.has(type)) return `${ZOOP_THEME_ASSET_PREFIX}/characters/badges/roles/${type}.svg`;
		return `${ZOOP_THEME_ASSET_PREFIX}/characters/badges/${type}.svg`;
	}

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
			fetchExistingProposalVote();
		} else {
			proposal = null;
			existingProposalVote = null;
		}
	});

	// Load discussion messages for round 7 when dialog opens
	$effect(() => {
		if (open && gameState) {
			const loadRound7Messages = async () => {
				round7MessagesLoaded = false;
				try {
					const localRound7Messages = discussionMessages.filter((msg) => msg.round === 7);
					if (localRound7Messages.length > 0) {
						discussionMessagesRound7 = localRound7Messages.map((msg) => ({
							senderName: msg.senderType === 'human' ? 'You' : msg.senderName,
							content: msg.content,
							timestamp: msg.timestamp
						}));
						return;
					}

					const gameId = gameState.getGameId();
					if (gameId > 0) {
						const messages = await getDiscussionMessages(supabase, gameId, { round: 7 });
						discussionMessagesRound7 = messages.map((msg) => ({
							senderName:
								msg.participantType === 'human'
									? 'You'
									: msg.agentRole
										? msg.agentRole.charAt(0).toUpperCase() + msg.agentRole.slice(1)
										: 'AI Agent',
							content: msg.content,
							timestamp: new Date(msg.createdAt)
						}));
					}
				} catch (error) {
					console.error('Error loading round 7 discussion messages:', error);
				} finally {
					round7MessagesLoaded = true;
				}
			};
			loadRound7Messages();
		} else {
			round7MessagesLoaded = false;
		}
	});

	// Format discussion messages for round 7 as a single text
	function formatRound7Discussion(): string {
		if (discussionMessagesRound7.length === 0) return '';
		return discussionMessagesRound7.map((msg) => `${msg.senderName}: ${msg.content}`).join('\n\n');
	}

	let storiesByPlayer = $derived.by(() => {
		const stories: Array<{ player: Player; answers: PlayerAnswer[]; isCurrent: boolean }> = [];

		if (!gameState) return [];
		const currentPlayer = gameState.players.find((p) => p.id === currentPlayerId);

		if (currentPlayer) {
			// Get all player answers and ensure we have entries for all 8 rounds (0-7)
			const playerAnswersMap = new Map<number, PlayerAnswer>();
			gameState.playersAnswers
				.filter((answer) => answer.player_id === currentPlayerId)
				.forEach((answer) => {
					playerAnswersMap.set(answer.round, answer);
				});

			// Create answers array with all 8 rounds, using discussion messages for round 7
			const playerAnswers: PlayerAnswer[] = Array.from({ length: 8 }, (_, i) => {
				if (i === 7 && discussionMessagesRound7.length > 0) {
					// For round 7, use discussion messages if available
					const existingAnswer = playerAnswersMap.get(7);
					return {
						id: existingAnswer?.id || 0,
						player_id: currentPlayerId,
						game_id: gameState.getGameId(),
						round: 7,
						answer: formatRound7Discussion()
					} as PlayerAnswer;
				} else {
					// For other rounds, use existing answer or create empty one
					const existingAnswer = playerAnswersMap.get(i);
					return (
						existingAnswer ||
						({
							id: 0,
							player_id: currentPlayerId,
							game_id: gameState.getGameId(),
							round: i,
							answer: ''
						} as PlayerAnswer)
					);
				}
			});

			// Add current player as the first element
			stories.push({
				player: currentPlayer,
				answers: playerAnswers,
				isCurrent: true
			});
		}

		gameState.players
			.filter((player) => player.is_active !== false && player.id !== currentPlayerId)
			.forEach((player) => {
				// Get all player answers and ensure we have entries for all 8 rounds (0-7)
				const playerAnswersMap = new Map<number, PlayerAnswer>();
				gameState.playersAnswers
					.filter((answer) => answer.player_id === player.id)
					.forEach((answer) => {
						playerAnswersMap.set(answer.round, answer);
					});

				// Create answers array with all 8 rounds
				const playerAnswers: PlayerAnswer[] = Array.from({ length: 8 }, (_, i) => {
					const existingAnswer = playerAnswersMap.get(i);
					return (
						existingAnswer ||
						({
							id: 0,
							player_id: player.id,
							game_id: gameState.getGameId(),
							round: i,
							answer: ''
						} as PlayerAnswer)
					);
				});

				stories.push({
					player,
					answers: playerAnswers,
					isCurrent: false
				});
			});
		return stories;
	});

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

	function getCardText(playerId: number, round: number): string {
		if (!gameState || !proposal) return '';

		const objectives = normalizeObjectives(proposal?.objectives);
		const objectiveValues = objectives
			.map((objective: { value?: string }) => objective.value)
			.filter((value: string | undefined): value is string => !!value);
		const preconditions = objectives
			.flatMap(
				(objective: { preconditions?: { value?: string }[] }) => objective.preconditions ?? []
			)
			.map((precondition) => precondition.value)
			.filter((value: string | undefined): value is string => !!value);
		const indicativeSteps = objectives
			.flatMap(
				(objective: { preconditions?: { indicativeSteps?: { value?: string }[] }[] }) =>
					objective.preconditions ?? []
			)
			.flatMap((precondition) => precondition.indicativeSteps ?? [])
			.map((step) => step.value)
			.filter((value: string | undefined): value is string => !!value);
		const keyIndicators = objectives
			.flatMap(
				(objective: { preconditions?: { keyIndicators?: { value?: string }[] }[] }) =>
					objective.preconditions ?? []
			)
			.flatMap((precondition) => precondition.keyIndicators ?? [])
			.map((indicator) => indicator.value)
			.filter((value: string | undefined): value is string => !!value);

		const points =
			round === 0
				? proposal.title
					? [proposal.title]
					: []
				: round === 1
					? objectiveValues[0]
						? [objectiveValues[0]]
						: []
					: round === 2
						? objectiveValues[1]
							? [objectiveValues[1]]
							: []
						: round === 3
							? preconditions
							: round === 4
								? indicativeSteps
								: round === 5
									? keyIndicators
									: round === 6
										? proposal.functionalities
											? [proposal.functionalities]
											: []
										: [];

		return points.length > 0 ? points.join('\n') : '';
	}

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

	function getOnboardingRoleLabel(): string | null {
		// ZD-191: lobby is no longer used; the role/cargo is chosen on the home onboarding flow
		// and stored in localStorage. Use it for display in the save dialog.
		if (typeof window === 'undefined') return null;
		try {
			const raw = localStorage.getItem('zoopdao:onboarding:v1');
			if (!raw) return null;
			const parsed = JSON.parse(raw) as {
				role?: string | null;
				customRole?: string;
			};

			const role = parsed.role ?? null;
			const customRole = (parsed.customRole ?? '').trim();

			if (role === 'other') {
				return customRole.length > 0 ? customRole : null;
			}

			if (role && role !== 'other') {
				const roleKey = `character_${role}_title`;
				const translated = getTranslation(roleKey);
				if (translated && translated !== 'Translation missing') return translated;
				return role
					.split('-')
					.map((word) => word.charAt(0).toUpperCase() + word.slice(1))
					.join(' ');
			}
			return null;
		} catch {
			return null;
		}
	}

	function getPlayerRoleLabel(player: Player): string {
		// New system: players.role stores the organizational role.
		// Legacy system: some older data used `player.character`.
		const raw = ((player as any).role ?? (player as any).character) as string | null | undefined;
		if (!raw) {
			const onboardingLabel = getOnboardingRoleLabel();
			if (onboardingLabel) return onboardingLabel;
			return getLocale() === 'pt' ? 'Cargo não definido' : 'Role not set';
		}

		// Prefer i18n role titles (we store them under character_<role>_title).
		const roleKey = `character_${raw}_title`;
		const translated = getTranslation(roleKey);
		if (translated && translated !== 'Translation missing') return translated;

		// Legacy characters table (only if it's not a role)
		const characterCard = CHARACTER.find((char) => char.type === raw);
		if (characterCard?.title) return getTranslation(characterCard.title);

		return raw
			.split('-')
			.map((word) => word.charAt(0).toUpperCase() + word.slice(1))
			.join(' ');
	}

	interface ExpandedAnswersMap {
		[key: string]: boolean;
	}

	let expandedAnswers = $state<ExpandedAnswersMap>({});

	// Toggle expansion state for an answer
	function toggleAnswerExpansion(answerId: string) {
		expandedAnswers = {
			...expandedAnswers,
			[answerId]: !expandedAnswers[answerId]
		};
	}

	// Check if an answer is expanded
	function isAnswerExpanded(answerId: string): boolean {
		return !!expandedAnswers[answerId];
	}

	let playerName = $state('');
	let storyTitle = $state('');
	const voteRequired = $derived(existingProposalVote === null);
	let isFormValid = $derived(!voteRequired || vote !== null);

	async function fetchExistingProposalVote() {
		if (!proposalId) {
			existingProposalVote = null;
			return;
		}

		try {
			let {
				data: { session },
				error: sessionError
			} = await supabase.auth.getSession();

			if (!session || sessionError) {
				const { data: anonData, error: anonError } = await supabase.auth.signInAnonymously();
				if (anonError || !anonData.session) {
					existingProposalVote = null;
					return;
				}
				session = anonData.session;
			}

			const headers: Record<string, string> = {};
			if (session?.access_token) headers['Authorization'] = `Bearer ${session.access_token}`;

			const res = await fetch(`/api/proposals/${proposalId}/votes`, { headers });
			if (!res.ok) {
				existingProposalVote = null;
				return;
			}

			const payload = await res.json();
			existingProposalVote =
				payload?.userChoice && payload?.userContext
					? { choice: payload.userChoice, context: payload.userContext }
					: null;
		} catch (err) {
			console.error('Failed to fetch existing proposal vote:', err);
			existingProposalVote = null;
		}
	}

	$effect(() => {
		if (open && gameState) {
			const currentPlayer = gameState.players.find((p) => p.id === currentPlayerId);
			playerName = currentPlayer?.nickname?.trim() || 'Participant';
			storyTitle = m.round_7_title();
		}
	});

	async function handleGameEnd(options?: { allowMissingVote?: boolean; playSound?: boolean }) {
		if (isSubmitting) return;
		const allowMissingVote = options?.allowMissingVote === true;
		const playSound = options?.playSound !== false;

		if (playSound) {
			playAudio(audio);
		}
		if (voteRequired && !vote && !allowMissingVote) return;
		isSubmitting = true;
		// Logic to save the story
		const discussionText = formatRound7Discussion();
		const id = await gameState.saveStory(
			playerName,
			storyTitle,
			discussionText,
			voteRequired ? vote : (existingProposalVote?.choice ?? null),
			proposalId
		);
		if (!id || id === false) {
			console.error('Failed to save discussion; no id returned.');
			isSubmitting = false;
			return;
		}

		// Persist proposal vote (single vote per user per proposal enforced by DB)
		if (voteRequired && vote && proposalId) {
			try {
				let {
					data: { session }
				} = await supabase.auth.getSession();
				if (!session) {
					const { data: anonData, error: anonError } = await supabase.auth.signInAnonymously();
					if (!anonError && anonData.session) {
						session = anonData.session;
					}
				}
				const headers: Record<string, string> = { 'Content-Type': 'application/json' };
				if (session?.access_token) headers['Authorization'] = `Bearer ${session.access_token}`;
				const cargo = getOnboardingRoleLabel();
				const mode = gameState?.mode ?? null;
				const res = await fetch(`/api/proposals/${proposalId}/votes`, {
					method: 'POST',
					headers,
					body: JSON.stringify({
						choice: vote,
						context: 'discussion',
						cargo,
						mode
					})
				});
				// If already voted (e.g. voted in preview), treat as success and continue.
				if (!res.ok && res.status !== 409) {
					console.error('Failed to persist proposal vote:', await res.text());
				}
			} catch (e) {
				console.error('Failed to persist proposal vote:', e);
			}
		}

		goto(localizeHref(`/stories/${id}`));
		// Reset the form
		playerName = '';
		storyTitle = '';
		vote = null;
		isSubmitting = false;
	}

	// ZD-184: Pedagogic mode auto-save when Round 7 prompt quota is exhausted.
	$effect(() => {
		if (!open) return;
		if (!autoSaveOnOpen) return;
		if (autoSaveDone) return;
		if (!gameState || gameState.mode !== 'pedagogic') return;
		if (!round7MessagesLoaded) return;
		if (!playerName.trim() || !storyTitle.trim()) return;

		autoSaveDone = true;
		handleGameEnd({ allowMissingVote: true, playSound: false });
	});

	let editMode = $state(false);
	let editingAnswerId = $state<string | null>(null);
	let editedContent = $state('');

	function startEditing(answer: PlayerAnswer) {
		if (!editMode) return;

		editingAnswerId = `${answer.player_id}-${answer.round}`;
		editedContent = answer.answer;
	}

	async function saveEdit(answer: PlayerAnswer) {
		if (!editingAnswerId || !editMode) return;

		if (answer) {
			try {
				// Call the gameState method to update the answer
				await gameState.updatePlayerAnswer(answer.id, editedContent);
			} catch (error) {
				console.error('Failed to save edit:', error);
			}
		}

		// Reset editing state
		editingAnswerId = null;
		editedContent = '';
		editMode = false;
	}

	function cancelEdit() {
		editMode = false;
		editingAnswerId = null;
		editedContent = '';
	}

	// Function to toggle edit mode
	function handleEdit(answer: PlayerAnswer) {
		playAudio(audio);
		editMode = !editMode;
		if (editMode === false) {
			cancelEdit();
		} else {
			editMode = true;
			startEditing(answer);
		}
	}
</script>

<Dialog.Root bind:open>
	<Dialog.Content
		interactOutsideBehavior="ignore"
		class="overflow-y-auto max-h-[96vh] sm:max-h-[80vh] w-[calc(100vw-2rem)] lg:max-w-4xl flex flex-col"
	>
		<div class="flex flex-col items-center justify-center gap-1">
			<p class="text-deep-teal rounded-full font-medium text-lg underline">{m.game_ended()}</p>
			<p class="text-deep-teal font-bold text-4xl text-center">{m.thanks_for_playing()}</p>
		</div>
		<!-- Always stack vote block above the story block (even on wide screens) -->
		<div class="flex flex-col gap-4 p-4 h-full">
			<div class="flex flex-col shrink-1 gap-4 order-1">
				<div class="flex flex-col gap-2">
					{#if voteRequired}
						<p class="text-sm font-semibold text-deep-teal uppercase tracking-wide">
							{m.vote_prompt()}
						</p>
						<div class="grid grid-cols-3 gap-3">
							{#each voteOptions as option}
								<button
									type="button"
									class={`min-h-[52px] rounded-md border p-3 text-sm font-semibold transition ${
										vote === option.key
											? option.color
											: 'border-deep-teal/30 bg-white hover:border-deep-teal/60'
									}`}
									onclick={() => (vote = option.key)}
								>
									{option.label()}
								</button>
							{/each}
						</div>
					{:else}
						<p class="text-sm text-gray-600">
							{getLocale() === 'pt'
								? 'Já votaste nesta proposta.'
								: 'You already voted on this proposal.'}
						</p>
					{/if}
				</div>
				<Button
					class="p-2 flex disabled:bg-gray-300 disabled:text-gray-600 disabled:hover:bg-gray-300"
					size="lg"
					onclick={handleGameEnd}
					disabled={!isFormValid || isSubmitting}
				>
					{voteRequired ? m.submit_discussion_and_vote() : m.submit_discussion()}
				</Button>
			</div>

			<div class="overflow-y-auto flex flex-col flex-grow w-full max-w-full order-2">
				{#if Object.keys(storiesByPlayer).length > 0}
					<div class="space-y-8">
						{#each storiesByPlayer as playerData, index}
							<div
								class="border-2 {playerData.isCurrent
									? 'border-deep-teal'
									: 'border-gray-300'} rounded-lg overflow-hidden"
							>
								<h2 class="text-xl font-bold text-deep-teal p-2">
									{playerData.isCurrent ? m.your_story() : m.others_stories()}
								</h2>
								<div class="bg-gray-50 p-4 flex items-center gap-3 border-b">
									{#if playerData.isCurrent}
										<!-- Match the user badge used during the live discussion (icon + black circle) -->
										<div
											class="w-16 h-16 rounded-full border-4 border-black bg-gray-200 flex items-center justify-center flex-shrink-0"
										>
											<User class="h-8 w-8 text-gray-600" />
										</div>
									{:else}
										<div class="w-16 h-16 rounded-full overflow-hidden flex-shrink-0">
											<img
												src={getBadgeSrc(
													(playerData.player as any).role ?? (playerData.player as any).character
												)}
												alt={(playerData.player as any).role ??
													(playerData.player as any).character ??
													'custom'}
												class="w-full h-full object-cover"
											/>
										</div>
									{/if}
									<div>
										<h3 class="font-bold text-2xl text-deep-teal">
											{playerData.player.nickname}
										</h3>
										<p class="text-sm text-gray-500 capitalize">
											{getPlayerRoleLabel(playerData.player)}
										</p>
									</div>
								</div>

								<div class="flex flex-col items-start pointer w-full">
									{#each playerData.answers as answer}
										{#if playerData.isCurrent && editingAnswerId === `${answer.player_id}-${answer.round}`}
											<div class="w-full p-3 bg-gray-50 border-1 border-gray-300">
												<div class="flex gap-4 mb-2">
													{#if answer.round === 0}
														<div
															class="flex gap-1 items-start text-sm font-semibold text-deep-teal"
														>
															<span>{getTranslation(ROUNDS[answer.round]?.title)}</span>
														</div>
													{:else if answer.round === 7}
														<div
															class="flex gap-1 items-start text-sm font-semibold text-deep-teal"
														>
															<span>{m.post_story()}</span>
														</div>
													{:else}
														<div
															class="flex gap-1 items-start text-sm font-semibold text-deep-teal"
														>
															<span>{getTranslation(ROUNDS[answer.round]?.title)}</span>
														</div>
														<p class="text-sm text-gray-500 italic break-words whitespace-pre-wrap">
															"{getCardText(answer.player_id, answer.round)}"
														</p>
													{/if}
												</div>

												<Textarea
													bind:value={editedContent}
													class="w-full min-h-32 p-3 border-2 border-deep-teal rounded-md focus:ring-deep-teal focus:outline-none"
													placeholder="Edit your answer..."
												></Textarea>

												<div class="flex justify-end gap-2 mt-2">
													<Button
														variant="outline"
														size="default"
														class="hover:bg-tertiary/40"
														onclick={cancelEdit}>{m.cancel()}</Button
													>
													<Button
														variant="default"
														size="default"
														onclick={() => saveEdit(answer)}
														data-answer-id={`${answer.player_id}-${answer.round}`}
													>
														{m.save()}
													</Button>
												</div>
											</div>
										{:else}
											<div class="w-full p-4 hover:bg-gray-100">
												<div class="flex justify-between gap-4">
													<button
														class="w-full text-left"
														onclick={() =>
															toggleAnswerExpansion(`${answer.player_id}-${answer.round}`)}
													>
														<div class="flex gap-4 mb-2 animate-fade-in">
															{#if answer.round === 0}
																<div
																	class="flex gap-1 items-start text-sm font-semibold text-deep-teal"
																>
																	<span>{getTranslation(ROUNDS[answer.round]?.title)}</span>
																</div>
															{:else if answer.round === 7}
																<div
																	class="flex gap-1 items-start text-sm font-semibold text-deep-teal"
																>
																	<span>{m.post_story()}</span>
																</div>
															{:else}
																<div
																	class="flex gap-1 items-start text-sm font-semibold text-deep-teal"
																>
																	<span>{getTranslation(ROUNDS[answer.round]?.title)}</span>
																</div>
																<p
																	class="text-sm text-gray-500 italic break-words whitespace-pre-wrap"
																>
																	"{getCardText(answer.player_id, answer.round)}"
																</p>
															{/if}
														</div>
														<p class="px-4 text-left w-full break-words whitespace-pre-wrap">
															{answer.answer}
														</p>
													</button>
													{#if playerData.isCurrent && editMode === false && answer.round !== 7}
														<div class="align-self-end">
															<Button
																variant={editMode ? 'default' : 'outline'}
																size="default"
																class=""
																onclick={() => handleEdit(answer)}
															>
																{m.edit()}
															</Button>
														</div>
													{/if}
												</div>
											</div>
										{/if}
									{/each}
								</div>
							</div>
						{/each}
					</div>
				{:else}
					<p class="text-center text-gray-500">Error</p>
				{/if}
			</div>
		</div>
	</Dialog.Content>
</Dialog.Root>

<style>
	.animate-fade-in {
		animation: fadeIn 0.2s ease-in-out;
	}

	@keyframes fadeIn {
		from {
			opacity: 0;
			transform: translateY(-5px);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}
</style>
