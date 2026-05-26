<script lang="ts">
	import HelpDialog from '@/components/help-dialog.svelte';
	import AssemblyMap from '@/components/map.svelte';
	import ParticipantsContainer from '@/components/participants-container.svelte';
	import RoundIndicator from '@/components/round-indicator.svelte';
	import StoryDialog from '@/components/story-dialog.svelte';
	import DiscussionInputBar from '@/components/discussion-input-bar.svelte';
	import DiscussionHistoryDialog from '@/components/discussion-history-dialog.svelte';
	import Button from '@/components/ui/button/button.svelte';
	import { GameState } from '@/state/game-state.svelte';
	import { CircleHelp, ScrollText, LogOut, FileText } from 'lucide-svelte';
	import type { PageData } from './$types';
	import EndDialog from '@/components/end-dialog.svelte';
	import { m } from '@src/paraglide/messages';
	import { getLocale } from '@src/paraglide/runtime.js';
	import fanfare from '@/sounds/fanfare.mp3';
	import bubbles from '@/sounds/bubbles-sound-effect.mp3';
	import { onMount, onDestroy } from 'svelte';
	import { createAudio, playAudio } from '$lib/utils/sound';
	import { createGameTour } from '@/components/ui/shepherd/game-tour.svelte.js';
	import type { Tour } from 'shepherd.js';
	import RoundTransition from '@/components/round-transition.svelte';
	import { goto } from '$app/navigation';
	import StatusPill from '@/components/status-pill.svelte';
	import ProposalDialog from '@/components/proposal-dialog.svelte';
	import {
		calculateAIAgentsCount,
		generateAIAgents,
		createParticipants
	} from '@/utils/participants';
	import type { AIAgent, AIMessage, Participant, Role } from '@/types';
	import { supabase } from '@/supabase';
	import {
		storeHumanMessage,
		getDiscussionMessages,
		mapDiscussionMessageRow
	} from '@/utils/discussion-messages';
	import { AquariumLayoutState } from '@/state/aquarium-layout.svelte';
	import {
		DiscussionTimelineState,
		type TimelineMessage
	} from '@/state/discussion-timeline.svelte';
	import { ENABLE_ROUND7_SCENE_ORCHESTRATION } from '$lib/config/feature-flags';

	let tour: Tour | undefined;

	let fanfareAudio: HTMLAudioElement | null = null;
	let startupAudio: HTMLAudioElement | null = null;

	let tourCompleted = $state(false);

	// Ensure overlay is removed when tour completes
	$effect(() => {
		if (tourCompleted) {
			// Use setTimeout to ensure DOM is updated
			setTimeout(() => {
				const overlay = document.querySelector('.shepherd-modal-overlay-container');
				if (overlay) {
					overlay.remove();
				}
				// Also remove any shepherd elements
				const shepherdElements = document.querySelectorAll('.shepherd-element');
				shepherdElements.forEach((el) => el.remove());
			}, 100);
		}
	});

	onMount(() => {
		fanfareAudio = createAudio(fanfare);
		startupAudio = createAudio(bubbles);

		if (gameState.state === 'starting') {
			tour = createGameTour();
			tour.on('complete', () => {
				tourCompleted = true;
				// Ensure overlay is removed
				const overlay = document.querySelector('.shepherd-modal-overlay-container');
				if (overlay) {
					overlay.remove();
				}
			});
			tour.on('cancel', () => {
				tourCompleted = true;
				// Ensure overlay is removed
				const overlay = document.querySelector('.shepherd-modal-overlay-container');
				if (overlay) {
					overlay.remove();
				}
			});
			tour.start();
		} else {
			if (tour) {
				tour.complete();
				tour.cancel();
			}
			tour = undefined;
			tourCompleted = true;
			// Ensure overlay is removed
			const overlay = document.querySelector('.shepherd-modal-overlay-container');
			if (overlay) {
				overlay.remove();
			}
		}
	});

	onDestroy(() => {
		if (tour) {
			tour.complete();
			tour.cancel();
		}
		// Ensure overlay is removed
		const overlay = document.querySelector('.shepherd-modal-overlay-container');
		if (overlay) {
			overlay.remove();
		}
		gameState.cleanup();
	});

	let { data }: { data: PageData } = $props();

	let gameState = new GameState(
		data.cards,
		data.rounds,
		data.game,
		data.gameRounds,
		data.playerId,
		data.players,
		data.playerCards,
		data.playerAnswers,
		data.gameMode
	);

	let aquariumLayout = new AquariumLayoutState();
	let showRoundTransition = $state(false);
	type TransitionState = 'starting' | 'transitioning' | 'ending' | 'ended';
	let transitionState: TransitionState = $state('starting');
	let previousRound = $state(0);

	const enableDiscussionChat = true;
	const ENABLE_DISCUSSION_RELOAD = true;
	const chatRound = $derived.by(() => gameState.currentRound === 7);
	const SINGLE_AI_MODE_ROUND7 = false;
	const round7PromptLimit = $derived.by(() =>
		gameState.mode === 'pedagogic' ? gameState.getPedagogicRound7UserPrompts() : 5
	);
	const TOP_MID_AI_AGENT_ID = 'ai-agent-aquari';
	const DEBUG_AI_TIMING = false;
	const SINGLE_AI_AGENT: AIAgent = {
		id: TOP_MID_AI_AGENT_ID,
		name: 'Aquari',
		role: 'research'
	};

	let hasUserChattedThisRound = $state(false);
	let userDraft = $state('');
	let userLastSentMessage = $state<string | null>(null);
	let userIsSending = $state(false);
	let round7TurnHint = $state(0);
	const userIsTyping = $derived.by(() => userDraft.trim().length > 0);
	let lastChatRound = $state(-1);

	// AI Agents and Participants
	let aiAgents = $state<AIAgent[]>([]);
	let aiMessages = $state<AIMessage[]>([]);
	let typingAgents = $state<Set<string>>(new Set()); // Track which agents are currently typing
	let round7VisibleAiAgentIds = $state<string[]>([TOP_MID_AI_AGENT_ID]);

	// Initialize AI agents based on human players count
	$effect(() => {
		if (!enableDiscussionChat) {
			aiAgents = [];
			aiMessages = [];
			typingAgents = new Set();
			return;
		}
		if (chatRound && SINGLE_AI_MODE_ROUND7) {
			aiAgents = [SINGLE_AI_AGENT];
			return;
		}
		const humanPlayers = gameState.players.filter((p) => p.is_active !== false);
		if (humanPlayers.length > 0 && aiAgents.length === 0) {
			try {
				const aiCount = calculateAIAgentsCount(humanPlayers.length);
				aiAgents = generateAIAgents(aiCount);
			} catch (error) {
				console.error('Error initializing AI agents:', error);
			}
		}
	});

	// Create participants list (humans + AI)
	const participants = $derived.by(() => {
		const humanPlayers = gameState.players.filter((p) => p.is_active !== false);
		const agents = enableDiscussionChat ? aiAgents : [];
		return createParticipants(humanPlayers, agents);
	});

	// Generate AI messages after each round completion
	$effect(() => {
			if (gameState.currentRound !== lastChatRound) {
				lastChatRound = gameState.currentRound;
				hasUserChattedThisRound = false;
				userDraft = '';
				userLastSentMessage = null;
				userIsSending = false;
				round7TurnHint = 0;
				round7VisibleAiAgentIds = [TOP_MID_AI_AGENT_ID];
			}
		});

	$effect(() => {
		if (!enableDiscussionChat || !chatRound || !hasUserChattedThisRound) {
			typingAgents = new Set();
		}
	});

	$effect(() => {
		if (
			gameState.currentRound !== previousRound &&
			gameState.currentRound > 0 &&
			gameState.currentRound < 7
		) {
			showRoundTransition = true;
			transitionState = 'starting';
			previousRound = gameState.currentRound;
		}
	});

	$effect(() => {
		if (gameState.mode !== 'pedagogic') {
			return;
		}
		// Round 7 is prompt-limited (no timer).
		if (gameState.currentRound < 1 || gameState.currentRound > 6) {
			return;
		}

		const currentGameRound = gameState.gameRounds.find(
			(round) => round.round === gameState.currentRound
		);
		if (currentGameRound && !currentGameRound.timer_duration) {
			gameState.startRoundTimer();
		}
	});

	function handleTransitionComplete() {
		showRoundTransition = false;
		if (keepStoryDialogOpen && !chatRound) {
			openStoryDialog = true;
		}
	}

	let playerState = $derived.by(() => {
		return gameState.playersState[gameState.playerId].state;
	});

	let currentPlayerState = $derived.by(() => {
		return gameState.playersState[gameState.playerId] || { state: 'done' };
	});

	$effect(() => {
		if (chatRound) {
			keepStoryDialogOpen = false;
			return;
		}
		if (!openStoryDialog && !showRoundTransition) {
			keepStoryDialogOpen = false;
		}
	});

	let openStoryDialog = $state(false);
	let openHelpDialog = $state(false);
	let openEndDialog = $state(false);
	let pendingEndDialogTimer: number | null = null;
	let openProposalDialog = $state(false);
	let openHistoryDialog = $state(false);

	$effect(() => {
		// Debug: log when history dialog open state changes to help trace automatic opens
		openHistoryDialog;
		try {
			console.debug('openHistoryDialog state changed', { openHistoryDialog });
			console.debug(new Error('openHistoryDialog stack').stack);
		} catch (e) {
			/* ignore */
		}
	});
	let keepStoryDialogOpen = $state(false);
	let showLayoutDebug = $state(false);
	let safeAreaObserver: ResizeObserver | null = null;

	$effect(() => {
		if (openProposalDialog && openHistoryDialog) {
			openHistoryDialog = false;
		}
	});

	$effect(() => {
		if (openEndDialog && openHistoryDialog) {
			openHistoryDialog = false;
		}
	});

	function updateSafeArea() {
		if (typeof window === 'undefined') return;
		const statusEl = document.querySelector('.status-pill');
		const roundEl = document.querySelector('.round-indicator-wrap');
		const bottomEl =
			document.querySelector('.discussion-controls') ||
			document.querySelector('.discussion-entry-controls');
		const avatarBoundary = document.querySelector('.avatar-boundary');
		const topPadding = 12;
		const bottomPadding = 16;

		const roundBottom = roundEl ? roundEl.getBoundingClientRect().bottom : 0;
		const isRound7 = chatRound;
		if (roundBottom > 0) {
			// Keep the status pill below the title area to prevent overlap on landscape layouts.
			const topForPill = isRound7 ? roundBottom + 2 : Math.max(104, roundBottom + 12);
			document.documentElement.style.setProperty('--status-pill-top', `${topForPill}px`);
		} else {
			document.documentElement.style.removeProperty('--status-pill-top');
		}

		const statusBottom = statusEl ? statusEl.getBoundingClientRect().bottom : 0;
		const statusHeight = statusEl ? statusEl.getBoundingClientRect().height : 0;
		const topPx = isRound7
			? roundBottom + statusHeight + 24
			: Math.max(statusBottom, roundBottom) + topPadding;
		const bottomPx = bottomEl
			? window.innerHeight - bottomEl.getBoundingClientRect().top + bottomPadding
			: aquariumLayout.safeBottomPx || 0;

		aquariumLayout.setSafeArea(topPx, bottomPx);

		if (avatarBoundary) {
			const sideMargin = Math.max(16, Math.min(72, window.innerWidth * 0.06));
			avatarBoundary.style.top = `${topPx}px`;
			avatarBoundary.style.bottom = `${bottomPx}px`;
			avatarBoundary.style.left = `${sideMargin}px`;
			avatarBoundary.style.right = `${sideMargin}px`;
			const rect = avatarBoundary.getBoundingClientRect();
			aquariumLayout.setContainerRect(rect.left, rect.top, rect.width, rect.height);
		}

		const mapEl = document.querySelector('.map-image') as HTMLImageElement | null;
		if (mapEl) {
			// `object-contain` means the rendered image content may be smaller than the element's box.
			// Use the contained rect so avatar math stays stable across aspect ratios (e.g. iPad landscape).
			const rect = mapEl.getBoundingClientRect();
			const naturalAspect =
				mapEl.naturalWidth && mapEl.naturalHeight
					? mapEl.naturalWidth / mapEl.naturalHeight
					: 1200 / 800;
			const boxAspect = rect.width / rect.height;

			let contentLeft = rect.left;
			let contentTop = rect.top;
			let contentWidth = rect.width;
			let contentHeight = rect.height;

			if (boxAspect > naturalAspect) {
				// Height-limited: horizontal letterboxing.
				contentHeight = rect.height;
				contentWidth = rect.height * naturalAspect;
				contentLeft = rect.left + (rect.width - contentWidth) / 2;
			} else {
				// Width-limited: vertical letterboxing.
				contentWidth = rect.width;
				contentHeight = rect.width / naturalAspect;
				contentTop = rect.top + (rect.height - contentHeight) / 2;
			}

			aquariumLayout.setTableRect(contentLeft, contentTop, contentWidth, contentHeight);
		}
	}

	function attachSafeAreaObservers() {
		if (typeof window === 'undefined') return;
		safeAreaObserver?.disconnect();
		safeAreaObserver = new ResizeObserver(() => updateSafeArea());

		const statusEl = document.querySelector('.status-pill');
		const roundEl = document.querySelector('.round-indicator-wrap');
		const bottomEl =
			document.querySelector('.discussion-controls') ||
			document.querySelector('.discussion-entry-controls');

		if (statusEl) safeAreaObserver.observe(statusEl);
		if (roundEl) safeAreaObserver.observe(roundEl);
		if (bottomEl) safeAreaObserver.observe(bottomEl);
		updateSafeArea();
	}

	onMount(() => {
		if (typeof window === 'undefined') return;
		const params = new URLSearchParams(window.location.search);
		showLayoutDebug = params.get('debug') === 'layout';
		attachSafeAreaObservers();
		window.addEventListener('resize', updateSafeArea);
		return () => {
			window.removeEventListener('resize', updateSafeArea);
			safeAreaObserver?.disconnect();
		};
	});

	$effect(() => {
		if (typeof window === 'undefined') return;
		chatRound;
		requestAnimationFrame(attachSafeAreaObservers);
	});

	// Discussion timeline (single source of truth for history + avatar chat UI)
	let discussionTimeline = new DiscussionTimelineState();
	let lastLoadedDiscussionRound = $state<number | null>(null);

	function splitContentParts(content: string): string[] {
		return content
			.split('\n\n')
			.map((p) => p.trim())
			.filter(Boolean);
	}

	function toTitleCaseRole(role: string) {
		return role.charAt(0).toUpperCase() + role.slice(1);
	}

	function resolveAgentIdByRole(role: Role | null): string | null {
		if (!role) return null;
		const found = aiAgents.find((a) => a.role === role);
		return found?.id ?? null;
	}

	function resolveAgentNameByRole(role: Role | null): string {
		if (!role) return 'AI Agent';
		const found = aiAgents.find((a) => a.role === role);
		return found?.name ?? toTitleCaseRole(role);
	}

	function timelineMessagesFromDbMessage(dbMsg: any): TimelineMessage[] {
		const msg = mapDiscussionMessageRow(dbMsg);
		const parts = splitContentParts(msg.content);
		const senderType = msg.participantType === 'human' ? 'human' : 'ai';
		const isSelf = senderType === 'human' && msg.participantId === data.playerId;

		const role = msg.agentRole as Role | null;
		const resolvedAgentId = resolveAgentIdByRole(role);
		const senderId =
			senderType === 'human'
				? String(msg.participantId ?? 'human')
				: (msg.metadata?.agent_id ?? resolvedAgentId ?? (role ? `role:${role}` : 'ai'));

		const senderName =
			senderType === 'human' ? (isSelf ? 'You' : 'Participant') : resolveAgentNameByRole(role);

		const createdAt = msg.createdAt;
		const dbId = msg.id;
		const clientTempId = msg.metadata?.client_temp_id;

		// Stable per-part keys so we can split/join deterministically for fetch + realtime.
		return (parts.length ? parts : ['']).map((part, idx) => ({
			key: `db:${dbId}:${idx}`,
			dbId,
			clientTempId,
			round: msg.round,
			senderType,
			senderId,
			senderRole: senderType === 'ai' ? (role ?? undefined) : undefined,
			senderName,
			content: part,
			createdAt,
			status: 'sent'
		}));
	}

	function addOptimisticHumanMessage(content: string) {
		const clientTempId = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
		discussionTimeline.upsert({
			key: `temp:${clientTempId}`,
			clientTempId,
			round: gameState.currentRound,
			senderType: 'human',
			senderId: String(data.playerId),
			senderName: 'You',
			content,
			createdAt: new Date().toISOString(),
			status: 'sending'
		});
		return clientTempId;
	}

	function getDiscussionStorageKeys(round: number) {
		const keys: string[] = [];
		if (data.proposalId) keys.push(`proposal:${data.proposalId}`);
		if (data.game?.code) keys.push(`gamecode:${data.game.code}`);
		keys.push(`game:${data.game.id}`);
		return keys.map((base) => `discussion:${base}:round:${round}`);
	}

	function loadCachedDiscussion(round: number): TimelineMessage[] {
		if (typeof window === 'undefined') return [];
		try {
			const keys = getDiscussionStorageKeys(round);
			for (const key of keys) {
				const raw = window.localStorage.getItem(key);
				if (!raw) continue;
				const parsed = JSON.parse(raw);
				if (Array.isArray(parsed) && parsed.length > 0) {
					return parsed as TimelineMessage[];
				}
			}
			return [];
		} catch {
			return [];
		}
	}

	const discussionMessages = $derived.by(() => {
		const baseMessages = discussionTimeline.messages.map((msg) => ({
			id: msg.key,
			content: msg.content,
			senderType: msg.senderType,
			senderName: msg.senderName,
			round: msg.round,
			timestamp: new Date(msg.createdAt),
			status: msg.status
		}));

		if (!chatRound || typingAgents.size === 0) return baseMessages;

		const typingPreviewMessages = Array.from(typingAgents).map((agentId) => {
			const agent = aiAgents.find((candidate) => candidate.id === agentId);
			return {
				id: `typing:${agentId}`,
				content: m.writing(),
				senderType: 'ai' as const,
				senderName: agent?.name ?? 'AI',
				round: gameState.currentRound,
				timestamp: new Date(),
				status: 'sending' as const
			};
		});

		return [...baseMessages, ...typingPreviewMessages];
	});

	const userPromptUsedCountRound7 = $derived.by(() => {
		if (!enableDiscussionChat || !chatRound) return 0;
		discussionTimeline.messages.length;
		const selfId = String(data.playerId);
		return discussionTimeline.messages.filter((msg) => {
			if (msg.round !== 7) return false;
			if (msg.senderType !== 'human') return false;
			if (msg.senderId !== selfId) return false;
			if (msg.status === 'failed') return false;
			return msg.content.trim().length > 0;
		}).length;
	});

	const userPromptRemainingRound7 = $derived.by(() => {
		if (!enableDiscussionChat || !chatRound) return round7PromptLimit;
		return Math.max(0, round7PromptLimit - userPromptUsedCountRound7);
	});

	const round7PromptStatusMessage = $derived.by(() => {
		if (!enableDiscussionChat || !chatRound) return null;
		const locale = getLocale();
		const isPt = locale.toLowerCase().startsWith('pt');
		const remaining = userPromptRemainingRound7;
		if (userPromptUsedCountRound7 <= 0) {
			return isPt
				? `Pode enviar-me ${round7PromptLimit} mensagens`
				: `You can send ${round7PromptLimit} messages.`;
		}
		return isPt
			? `Mensagens restantes: ${remaining}/${round7PromptLimit}.`
			: `Messages left: ${remaining}/${round7PromptLimit}.`;
	});

	const aiIsThinking = $derived.by(() => typingAgents.size > 0);
	let debouncedAiIsThinking = $state(false);
	let aiThinkingClearTimer: ReturnType<typeof setTimeout> | null = null;
	$effect(() => {
		if (aiIsThinking) {
			if (aiThinkingClearTimer) {
				clearTimeout(aiThinkingClearTimer);
				aiThinkingClearTimer = null;
			}
			debouncedAiIsThinking = true;
			return;
		}
		if (aiThinkingClearTimer) clearTimeout(aiThinkingClearTimer);
		aiThinkingClearTimer = setTimeout(() => {
			debouncedAiIsThinking = false;
			aiThinkingClearTimer = null;
		}, 300);
	});

	$effect(() => {
		if (!enableDiscussionChat || !chatRound || !ENABLE_DISCUSSION_RELOAD) return;
		if (typeof window === 'undefined') return;
		try {
			for (const key of getDiscussionStorageKeys(gameState.currentRound)) {
				window.localStorage.setItem(key, JSON.stringify(discussionTimeline.messages));
			}
		} catch {
			// Ignore storage errors (quota, private mode).
		}
	});

	// Derive per-agent messages for the participants ring from the same timeline.
	$effect(() => {
		if (!enableDiscussionChat || !chatRound) {
			aiMessages = [];
			return;
		}
		// Re-run when agents are (re)initialized so DB messages can resolve `role:*` ids.
		aiAgents.length;

		const resolveAgentId = (msg: TimelineMessage) => {
			if (msg.senderType !== 'ai') return msg.senderId;
			const role =
				msg.senderRole ??
				(msg.senderId.startsWith('role:') ? (msg.senderId.slice(5) as Role) : null);
			if (role) {
				const found = aiAgents.find((a) => a.role === role);
				if (found) return found.id;
			}
			return msg.senderId.startsWith('role:') ? msg.senderId.slice(5) : msg.senderId;
		};

		aiMessages = discussionTimeline.messages
			.filter((msg) => msg.senderType === 'ai')
			.map((msg) => ({
				id: msg.key,
				agent_id: resolveAgentId(msg),
				round: msg.round,
				content: msg.content,
				created_at: msg.createdAt
			}));
	});

	const latestAiMessageById = $derived.by(() => {
		const map: Record<string, string> = {};
		if (!enableDiscussionChat || !chatRound) return map;
		aiAgents.length;
		const resolveAgentId = (msg: TimelineMessage) => {
			if (msg.senderType !== 'ai') return msg.senderId;
			const role =
				msg.senderRole ??
				(msg.senderId.startsWith('role:') ? (msg.senderId.slice(5) as Role) : null);
			if (role) {
				const found = aiAgents.find((a) => a.role === role);
				if (found) return found.id;
			}
			return msg.senderId.startsWith('role:') ? msg.senderId.slice(5) : msg.senderId;
		};
		for (const msg of discussionTimeline.messages) {
			if (msg.senderType !== 'ai') continue;
			if (msg.round !== gameState.currentRound) continue;
			const id = resolveAgentId(msg);
			map[id] = msg.content;
		}
		// Fallback to aiMessages if timeline is empty
		if (Object.keys(map).length === 0 && aiMessages.length > 0) {
			for (const m of aiMessages) {
				if (m.round !== gameState.currentRound) continue;
				map[m.agent_id] = m.content;
			}
		}
		return map;
	});

	const DEBUG_PREVIEW = false;

	const previewStateBySender = $derived.by(() => {
		const state: Record<string, { open: boolean; rank: number }> = {};
		if (!enableDiscussionChat || !chatRound) return state;

		// Gather messages (AI + user) from timeline; fallback to aiMessages + userLastSentMessage
		let pool = discussionTimeline.messages.filter(
			(msg) => msg.round === gameState.currentRound && msg.content.trim().length > 3
		);

		// Fallback if timeline is empty
		if (pool.length === 0) {
			pool = aiMessages
				.filter((m) => m.round === gameState.currentRound && m.content.trim().length > 3)
				.map((m) => ({
					key: m.id,
					dbId: undefined,
					clientTempId: undefined,
					round: m.round,
					senderType: 'ai',
					senderId: m.agent_id,
					content: m.content,
					createdAt: m.created_at,
					status: 'sent'
				})) as any;
			if (userLastSentMessage && userLastSentMessage.trim().length > 3) {
				pool.push({
					key: 'user-latest',
					round: gameState.currentRound,
					senderType: 'human',
					senderId: String(data.playerId),
					content: userLastSentMessage,
					createdAt: new Date().toISOString(),
					status: 'sent'
				} as any);
			}
		}

		const resolveAgentId = (msg: TimelineMessage) => {
			if (msg.senderType !== 'ai') return msg.senderId;
			const role =
				msg.senderRole ??
				(msg.senderId.startsWith('role:') ? (msg.senderId.slice(5) as Role) : null);
			if (role) {
				const found = aiAgents.find((a) => a.role === role);
				if (found) return found.id;
			}
			return msg.senderId.startsWith('role:') ? msg.senderId.slice(5) : msg.senderId;
		};

		const sorted = [...pool].sort(
			(a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
		);
		const lastTwo = sorted.slice(-2);
		lastTwo.forEach((msg, idx) => {
			const senderId = msg.senderType === 'ai' ? resolveAgentId(msg as any) : String(data.playerId);
			state[senderId] = { open: true, rank: idx };
		});
		return state;
	});

	$effect(() => {
		if (!DEBUG_PREVIEW) return;
		console.info('previewStateBySender', previewStateBySender);
	});

	$effect(() => {
		if (!DEBUG_PREVIEW) return;
		console.info('previewStateBySender', previewStateBySender);
	});

	// Load existing round messages when entering the chat round.
	$effect(() => {
		if (!enableDiscussionChat || !chatRound || !ENABLE_DISCUSSION_RELOAD) {
			discussionTimeline.reset();
			lastLoadedDiscussionRound = null;
			return;
		}

		const currentRound = gameState.currentRound;
		if (lastLoadedDiscussionRound === currentRound) return;
		lastLoadedDiscussionRound = currentRound;

		const gameId = data.game.id;
		let cancelled = false;
		(async () => {
			try {
				const dbMessages = await getDiscussionMessages(supabase, gameId, { round: currentRound });
				if (cancelled) return;

				if (dbMessages.length === 0) {
					const cached = loadCachedDiscussion(currentRound);
					if (cached.length > 0) {
						discussionTimeline.upsert(cached);
						const lastHuman = [...cached]
							.reverse()
							.find((m) => m.senderType === 'human' && m.senderId === String(data.playerId));
						if (lastHuman?.content) {
							userLastSentMessage = lastHuman.content;
						}
						return;
					}
				}

				const nextTimeline: TimelineMessage[] = [];
				for (const dbMsg of dbMessages) {
					nextTimeline.push(
						...timelineMessagesFromDbMessage({
							id: dbMsg.id,
							game_id: dbMsg.gameId,
							proposal_id: dbMsg.proposalId,
							round: dbMsg.round,
							participant_type: dbMsg.participantType,
							participant_id: dbMsg.participantId,
							agent_role: dbMsg.agentRole,
							content: dbMsg.content,
							created_at: dbMsg.createdAt,
							metadata: dbMsg.metadata
						})
					);
				}

				// Replace timeline with DB snapshot for this round. We keep any optimistic entries
				// (they'll be reconciled via client_temp_id or the insert response).
				discussionTimeline.upsert(nextTimeline);

				// If we're coming back/reloading, infer "has user chatted" from persisted messages.
				const hasSelfMessage = dbMessages.some(
					(m) =>
						m.participantType === 'human' &&
						m.participantId === data.playerId &&
						m.round === currentRound
				);
				if (hasSelfMessage) {
					hasUserChattedThisRound = true;
					const last = [...dbMessages]
						.reverse()
						.find((m) => m.participantType === 'human' && m.participantId === data.playerId);
					if (last?.content) userLastSentMessage = last.content;
				}
			} catch (error) {
				console.error('Error loading discussion messages:', error);
			}
		})();

		return () => {
			cancelled = true;
		};
	});

	// Subscribe to realtime inserts so the history dialog updates live while open.
	$effect(() => {
		if (!enableDiscussionChat || !chatRound) return;
		const gameId = data.game.id;
		const currentRound = gameState.currentRound;

		const channel = supabase
			.channel(`discussion_messages:${gameId}:${currentRound}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'discussion_messages',
					filter: `game_id=eq.${gameId}`
				},
				(payload) => {
					try {
						const row = (payload as any).new;
						if (!row) return;
						if (row.round !== currentRound) return;

						const clientTempId = row?.metadata?.client_temp_id;
						if (clientTempId) {
							discussionTimeline.removeByClientTempId(clientTempId);
						}
						discussionTimeline.upsert(timelineMessagesFromDbMessage(row));
					} catch (error) {
						console.error('Failed to ingest realtime discussion message:', error);
					}
				}
			)
			.subscribe();

		return () => {
			channel.unsubscribe();
		};
	});

	$effect(() => {
		if (gameState.state === 'starting') {
			playAudio(startupAudio);
		}
	});

	// Original logic: Show end dialog when game state is 'finished'
	// This is now commented but kept for reference - the new logic shows the dialog
	// after discussion rounds complete instead
	// $effect(() => {
	// 	if (gameState.state === 'finished') {
	// 		fanfareAudio?.play();
	// 		openEndDialog = true;
	// 	}
	// });

	// Round 7 closes after the configured user prompt quota is exhausted and AI typing ends.
	// Wait 2s after conditions settle so the user can see the last AI message.
	$effect(() => {
		if (!chatRound || openEndDialog) return;
		if (userPromptUsedCountRound7 < round7PromptLimit) return;
		if (typingAgents.size > 0 || userIsSending) return;

		if (pendingEndDialogTimer) clearTimeout(pendingEndDialogTimer);
		pendingEndDialogTimer = setTimeout(() => {
			// Re-check conditions before opening
			if (!chatRound || openEndDialog) return;
			if (userPromptUsedCountRound7 < round7PromptLimit) return;
			if (typingAgents.size > 0 || userIsSending) return;
			playAudio(fanfareAudio);
			openEndDialog = true;
			pendingEndDialogTimer = null;
		}, 2000) as unknown as number;

		return () => {
			if (pendingEndDialogTimer) {
				clearTimeout(pendingEndDialogTimer);
				pendingEndDialogTimer = null;
			}
		};
	});

	function getTopMidAgent(agents: AIAgent[]) {
		return agents.find((agent) => agent.id === TOP_MID_AI_AGENT_ID) ?? agents[0] ?? null;
	}

	function normalizeRound7ActiveAgentIds(ids: string[], agents: AIAgent[]) {
		const available = new Set(agents.map((agent) => agent.id));
		const topMid = getTopMidAgent(agents);
		if (!topMid) return [] as string[];

		const merged = new Set<string>([topMid.id]);
		for (const id of ids) {
			if (available.has(id)) merged.add(id);
		}

		const ordered = [topMid.id, ...Array.from(merged).filter((id) => id !== topMid.id)];
		return ordered.slice(0, 3);
	}

	async function handleSendMessage(message: string) {
		try {
			if (chatRound) {
				if (userPromptUsedCountRound7 >= round7PromptLimit) {
					alert(m.message_limit_reached());
					return;
				}

				hasUserChattedThisRound = true;
				// Keep the user bubble empty while the new message is being persisted,
				// to avoid flashing the previous message between sends.
				userIsSending = true;
			}
			const gameId = data.game.id;
			const proposalId = data.proposalId || null; // Get proposal_id from loader
			const currentRound = gameState.currentRound;
			const playerId = data.playerId;
			const userMessageCount = discussionMessages.filter(
				(msg) => msg.senderType === 'human' && msg.round === currentRound
			).length;
			// (Round 7 prompt quota is enforced above.)

			// Optimistic UI: show immediately in timeline/history (even if the history dialog is open).
			const clientTempId = addOptimisticHumanMessage(message);

			// Save human message to database
			const savedMessage = await storeHumanMessage(
				supabase,
				gameId,
				proposalId,
				currentRound,
				playerId,
				message,
				{ clientTempId }
			);

			if (!savedMessage) {
				discussionTimeline.markFailedByClientTempId(clientTempId);
				userIsSending = false;
				console.error('Failed to save message');
				return;
			}
			// Replace optimistic entry with persisted DB message.
			discussionTimeline.removeByClientTempId(clientTempId);
			discussionTimeline.upsert(
				timelineMessagesFromDbMessage({
					id: savedMessage.id,
					game_id: savedMessage.gameId,
					proposal_id: savedMessage.proposalId,
					round: savedMessage.round,
					participant_type: savedMessage.participantType,
					participant_id: savedMessage.participantId,
					agent_role: savedMessage.agentRole,
					content: savedMessage.content,
					created_at: savedMessage.createdAt,
					metadata: savedMessage.metadata
				})
			);
				if (chatRound) {
					userLastSentMessage = savedMessage.content;
					userDraft = '';
					userIsSending = false;
					round7TurnHint = Math.min(round7PromptLimit, round7TurnHint + 1);
				}

			const logAiTiming = (event: string, payload: Record<string, unknown>) => {
				if (DEBUG_AI_TIMING) {
					console.info('[AI timing]', event, payload);
				}
			};
			const waitForAiDelay = (ms: number) =>
				SINGLE_AI_MODE_ROUND7
					? Promise.resolve()
					: new Promise((resolve) => setTimeout(resolve, ms));

			// Round 7: one batch request returning JSON for all agents; UI schedules avatar rendering.
			if (aiAgents.length > 0) {
				// Stable idempotency key: retrying AI generation for the same human message should not double-insert.
				const clientRequestId = `human:${savedMessage.id}`;
				const agentsPayload = aiAgents.map((agent) => ({
					id: agent.id,
					name: agent.name,
					role: agent.role
				}));

				// Show only one agent typing while the batch request is in flight (sequential coordination).
				const preflightTopMid = getTopMidAgent(aiAgents);
				typingAgents = preflightTopMid ? new Set([preflightTopMid.id]) : new Set();

				type BatchResult = {
					success: boolean;
					requestId?: string;
					scenePlan?: {
						userTurn: number;
						activeAgentIds: string[];
						speakingOrder: string[];
						revealAgentIds: string[];
						handoffText?: string;
						errorMode?: 'none' | 'hard_error';
						routing?: {
							selectedAgentId: string;
							confidence: number;
							matchedTerms: string[];
							scoreByAgent: Record<string, number>;
							reason: string;
							routingSource?: 'rule' | 'llm_planner' | 'fallback';
							plannerUsed?: boolean;
							plannerReason?: string;
						};
					};
					messages?: Array<{
						agentId: string;
						agentName: string;
						agentRole: Role;
						round: number;
						content: string;
						dbId: number;
						createdAt: string;
					}>;
					errors?: Array<{ agentId: string; code: string; message: string }>;
					error?: { code: string; message: string; requestId?: string };
				};

				let batch: BatchResult | null = null;
				try {
					const response = await fetch('/api/ai/messages/batch', {
						method: 'POST',
						headers: { 'Content-Type': 'application/json' },
						body: JSON.stringify({
							gameId,
							proposalId,
							round: 7,
							userId: data.userId,
							locale: getLocale(),
							latestUserMessage: message,
							agents: agentsPayload,
							activeAgentIds: ENABLE_ROUND7_SCENE_ORCHESTRATION
								? round7VisibleAiAgentIds
								: undefined,
							userTurnHint: chatRound ? Math.max(1, round7TurnHint) : undefined,
							clientRequestId
						})
					});
					const result = (await response.json()) as BatchResult;
					batch = result;
					if (!response.ok) {
						console.warn('Batch AI HTTP error:', {
							status: response.status,
							requestId: result?.requestId,
							code: result?.error?.code,
							message: result?.error?.message
						});
					}
				} catch (batchError) {
					console.error('Batch AI request failed:', batchError);
					batch = null;
				}
				const isHardError =
					batch?.scenePlan?.errorMode === 'hard_error' || (!batch?.success && Boolean(batch?.error));
				if (!batch || isHardError) {
					typingAgents = new Set();
					if (batch?.errors?.length) {
						console.warn('Batch AI returned hard errors:', batch.errors);
					}
					return;
				}

				const messagesByAgentId = new Map<string, NonNullable<BatchResult['messages']>[number]>();
				if (batch?.messages) {
					for (const msg of batch.messages) {
						if (msg?.agentId) messagesByAgentId.set(msg.agentId, msg);
					}
				}
				if (batch?.errors?.length) {
					const mode = batch.scenePlan?.errorMode ?? 'none';
					if (mode === 'hard_error') {
						console.warn('Batch AI returned hard errors:', batch.errors);
					}
				}

				const perAgentDelay = () => 1000 + Math.random() * 1000;
				const interMessageDelay = () => 700 + Math.random() * 900;
				const topMidAgent = getTopMidAgent(aiAgents);
				const fallbackSpeakingAgents = topMidAgent ? [topMidAgent] : aiAgents.slice(0, 1);
				const scenePlan = ENABLE_ROUND7_SCENE_ORCHESTRATION ? batch?.scenePlan : undefined;
				if (scenePlan) {
					console.info('[AI round7]', {
						requestId: batch?.requestId,
						errorMode: scenePlan.errorMode,
						selectedAgentId: scenePlan.routing?.selectedAgentId ?? null,
						source: scenePlan.routing?.routingSource ?? 'rule',
						reason: scenePlan.routing?.reason ?? null
					});
				}
				if (DEBUG_AI_TIMING && scenePlan?.routing) {
					console.info('[AI routing]', {
						requestId: batch?.requestId,
						selectedAgentId: scenePlan.routing.selectedAgentId,
						source: scenePlan.routing.routingSource ?? 'rule',
						reason: scenePlan.routing.reason,
						plannerUsed: scenePlan.routing.plannerUsed ?? false
					});
				}
				const speakingOrder = scenePlan?.speakingOrder?.length
					? scenePlan.speakingOrder
					: ENABLE_ROUND7_SCENE_ORCHESTRATION
						? fallbackSpeakingAgents.map((agent) => agent.id)
						: aiAgents.map((agent) => agent.id);
				const speakingAgents = speakingOrder
					.map((agentId) => aiAgents.find((agent) => agent.id === agentId))
					.filter(Boolean) as AIAgent[];
				const activeAgentIds = scenePlan?.activeAgentIds?.length
					? scenePlan.activeAgentIds
					: ENABLE_ROUND7_SCENE_ORCHESTRATION
						? [topMidAgent?.id ?? TOP_MID_AI_AGENT_ID]
						: aiAgents.map((agent) => agent.id);
				round7VisibleAiAgentIds = normalizeRound7ActiveAgentIds(activeAgentIds, aiAgents);

				// Schedule avatar rendering sequentially for a more natural feel.
				const batchStart = performance.now();
				for (let index = 0; index < speakingAgents.length; index += 1) {
					const agent = speakingAgents[index];

					typingAgents = new Set([agent.id]);
					const typingStart = performance.now();
					const typingDelay = perAgentDelay();
					logAiTiming('typing:start', {
						agentId: agent.id,
						agentName: agent.name,
						delayMs: Math.round(typingDelay)
					});
					await waitForAiDelay(typingDelay);

					const msg = messagesByAgentId.get(agent.id);
					if (msg?.dbId && msg.content) {
						logAiTiming('bubble:open', {
							agentId: agent.id,
							agentName: agent.name,
							elapsedMs: Math.round(performance.now() - typingStart)
						});
						discussionTimeline.upsert(
							timelineMessagesFromDbMessage({
								id: msg.dbId,
								game_id: gameId,
								proposal_id: proposalId,
								round: msg.round ?? currentRound,
								participant_type: 'ai_agent',
								participant_id: null,
								agent_role: msg.agentRole ?? agent.role,
								content: msg.content,
								created_at: msg.createdAt,
								metadata: {
									agent_id: msg.agentId,
									client_request_id: clientRequestId,
									server_request_id: batch?.requestId ?? null
								}
							})
						);
						} else {
							logAiTiming('bubble:open:missing', {
								agentId: agent.id,
								agentName: agent.name,
								elapsedMs: Math.round(performance.now() - typingStart)
							});
						}
						if (index < speakingAgents.length - 1) {
						const gapDelay = interMessageDelay();
						logAiTiming('inter-message:wait', {
							nextAgentId: speakingAgents[index + 1]?.id,
							delayMs: Math.round(gapDelay)
						});
						await waitForAiDelay(gapDelay);
					}
				}
				logAiTiming('batch:complete', {
					elapsedMs: Math.round(performance.now() - batchStart)
				});

				typingAgents = new Set();
			}
		} catch (error) {
			console.error('Error sending message:', error);
		} finally {
			if (chatRound) {
				userIsSending = false;
			}
		}
	}

	function handleOpenHistory() {
		openHistoryDialog = true;
	}

	async function handleLeaveGame() {
		const confirmed = confirm(m.confirm_leave_discussion());

		if (confirmed) {
			const success = await gameState.markPlayerInactive();
			if (!success) {
				alert(m.leave_discussion_failed());
			}
			goto('/');
		}
	}
</script>

<div class="w-screen h-[100dvh] relative">
	<AssemblyMap layout={aquariumLayout} />
	<RoundIndicator rounds={gameState.rounds} currentRound={gameState.currentRound} />
	<StatusPill
		playerState={currentPlayerState}
		currentRound={gameState.currentRound}
		round7WritingMessage={round7PromptStatusMessage}
	/>
	<ProposalDialog bind:open={openProposalDialog} proposalId={data.proposalId ?? null} />

	{#if !chatRound}
		<div
			class="discussion-entry-controls fixed bottom-4 left-1/2 -translate-x-1/2 w-[calc(100%-1.5rem)] sm:w-[calc(100%-2rem)] max-w-[520px] z-50 pointer-events-auto flex flex-col gap-3"
		>
			<Button
				size="lg"
				onclick={async () => {
					openStoryDialog = true;
					keepStoryDialogOpen = true;
					if (gameState.currentRound > 0) {
						gameState.playerMove();
					}
				}}
				class="story-button rounded-full px-4"
				disabled={!tourCompleted}
			>
				<ScrollText />
				{m.story_sheet()}
			</Button>
			<button
				type="button"
				class="tour-proposal-button w-full rounded-full border-2 border-sand bg-white px-4 py-3 text-center text-base font-semibold text-black shadow-lg transition-colors hover:bg-sand/20"
				disabled={!tourCompleted}
				onclick={() => {
					openHistoryDialog = false;
					openProposalDialog = true;
				}}
			>
				<FileText class="mr-2 inline-block h-4 w-4" />
				{m.view_full_proposal()}
			</button>
		</div>
	{/if}

	{#if showLayoutDebug}
		<div
			class="fixed left-3 right-3 z-[90] pointer-events-none border-2 border-dashed border-fuchsia-500/70 rounded-2xl bg-fuchsia-500/5"
			style={`top:${aquariumLayout.safeTopPx}px; bottom:${aquariumLayout.safeBottomPx}px;`}
		></div>
		<div
			class="fixed left-3 bottom-3 z-[91] rounded-lg bg-black/80 px-3 py-2 text-xs text-white pointer-events-none"
		>
			safeTop: {Math.round(aquariumLayout.safeTopPx)}px · safeBottom:{' '}
			{Math.round(aquariumLayout.safeBottomPx)}px
		</div>
	{/if}
	<div
		class="fixed avatar-boundary left-3 right-3 z-[60] pointer-events-none rounded-2xl"
		style={`top:${aquariumLayout.safeTopPx}px; bottom:${aquariumLayout.safeBottomPx}px;`}
		aria-hidden="true"
	></div>
	<StoryDialog bind:open={openStoryDialog} {gameState} proposalId={data.proposalId ?? null} historyOpen={openHistoryDialog} />

	<!-- Discussion Input: Button for rounds 1-6, Input Bar for round 7 -->
	{#if enableDiscussionChat && chatRound && !openProposalDialog}
		<div
			class="discussion-controls fixed bottom-4 left-1/2 -translate-x-1/2 w-[calc(100%-1.5rem)] sm:w-[calc(100%-2rem)] max-w-[760px] z-50 pointer-events-auto flex flex-col gap-3"
		>
			<!-- Discussion Input Bar (Round 7 only) -->
			<DiscussionInputBar
				inline
				onSend={handleSendMessage}
				onOpenHistory={handleOpenHistory}
				onDraftChange={(draft) => (userDraft = draft)}
				gameId={data.game.id}
				proposalId={data.proposalId ?? null}
				round={gameState.currentRound}
				userId={data.userId}
				disabled={!tourCompleted}
				historyDisabled={!tourCompleted}
				documentsDisabled={!tourCompleted}
				inputDisabled={!tourCompleted || debouncedAiIsThinking || userPromptRemainingRound7 <= 0}
				lockedPlaceholder={userPromptRemainingRound7 <= 0
					? getLocale() === 'pt'
						? 'Sem prompts restantes.'
						: 'No prompts left.'
					: debouncedAiIsThinking
						? m.discussion_waiting_placeholder()
						: null}
			/>
			<button
				type="button"
				class="tour-proposal-button w-full rounded-full border-2 border-sand bg-white px-4 py-3 text-center text-base font-semibold text-black shadow-lg transition-colors hover:bg-sand/20"
				disabled={!tourCompleted}
				onclick={() => {
					openHistoryDialog = false;
					openProposalDialog = true;
				}}
			>
				<FileText class="mr-2 inline-block h-4 w-4" />
				{m.view_full_proposal()}
			</button>
		</div>
	{/if}

	<!-- Discussion History Dialog -->
	{#if enableDiscussionChat && chatRound && !openProposalDialog && !openEndDialog}
		<DiscussionHistoryDialog
			bind:open={openHistoryDialog}
			messages={discussionMessages}
			onClose={() => (openHistoryDialog = false)}
		/>
	{/if}
	<Button
		size="default"
		onclick={() => (openHelpDialog = true)}
		class="absolute top-4 left-4 help-button z-50 pointer-events-auto"
		disabled={!tourCompleted}
	>
		{m.help()}
		<CircleHelp />
	</Button>
	<HelpDialog bind:open={openHelpDialog} />
	<Button
		variant="default"
		size="default"
		class="absolute top-4 right-4 exit-button z-50 pointer-events-auto"
		onclick={handleLeaveGame}
		disabled={!tourCompleted}
	>
		{m.exit()}
		<LogOut size={16} />
	</Button>
	<!-- Participants (Humans + AI Agents) positioned around aquarium -->
	<ParticipantsContainer
		{participants}
		playersState={gameState.playersState}
		aiMessages={chatRound ? aiMessages : []}
		round7VisibleAiAgentIds={chatRound ? round7VisibleAiAgentIds : []}
		currentRound={gameState.currentRound}
		{tourCompleted}
		{transitionState}
		currentPlayerId={data.playerId}
		typingAgents={chatRound ? typingAgents : new Set()}
		userChatIsTyping={chatRound ? userIsTyping : false}
		userChatDraft={chatRound ? userDraft : ''}
		userChatMessage={chatRound ? userLastSentMessage : null}
		userChatIsSending={chatRound ? userIsSending : false}
		{latestAiMessageById}
		{previewStateBySender}
		layout={aquariumLayout}
	/>

	{#if showRoundTransition}
		<RoundTransition
			round={gameState.currentRound}
			onComplete={handleTransitionComplete}
			bind:transitionState
		/>
	{/if}

	<EndDialog
		bind:open={openEndDialog}
		{gameState}
		autoSaveOnOpen={false}
		{discussionMessages}
		proposalId={data.proposalId ?? null}
	/>
</div>
