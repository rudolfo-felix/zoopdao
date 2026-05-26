<script lang="ts">
	import { goto } from '$app/navigation';
	import { Button } from '@/components/ui/button';
	import { ArrowLeft, Calendar, Clock, PenLine } from 'lucide-svelte';
	import { m } from '@src/paraglide/messages';
	import { localizeUrl } from '@src/paraglide/runtime.js';
	import { getLocale } from '@src/paraglide/runtime.js';
	import clickSound from '@/sounds/click.mp3';
	import { onMount } from 'svelte';
	import { supabase } from '$lib/supabase';
	import { createAudio, playAudio } from '$lib/utils/sound';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	type VoteChoice = 'yes' | 'no' | 'abstain';
	type VoteContext = 'preview' | 'discussion';
	type VoteMode = 'no_discussion' | 'pedagogic' | 'decision_making';
	type VoteRow = {
		user_id: string;
		choice: VoteChoice;
		created_at: string;
		cargo: string | null;
		discussion_mode: VoteMode | null;
	};

	let click_sound: HTMLAudioElement | null = null;
	let isCreatingGame = $state(false);
	let voteSelection: VoteChoice | '' = $state('');
	let voteLoading = $state(false);
	let voteError = $state('');
	let voteSuccess = $state(false);
	let voteTotals = $state<{ yes: number; no: number; abstain: number }>(data.votes.totals);
	let totalVotes = $state<number>(data.votes.totalVotes || 0);
	let userChoice = $state<VoteChoice | null>(data.votes.userChoice as VoteChoice | null);
	let userContext = $state<VoteContext | null>(data.votes.userContext as VoteContext | null);
	let showVotesTable = $state(false);
	let votesTableLoading = $state(false);
	let votesTableError = $state('');
	let votesTableRows = $state<VoteRow[]>([]);

	onMount(() => {
		click_sound = createAudio(clickSound, 0.5);
		refreshVotesWithAuth();
	});

	const proposal = $derived(data.proposal);
	const status = $derived(data.status);
	const allPeriods = $derived(
		data.allPeriods.map((p) => ({
			...p,
			startDate: new Date(p.startDate),
			endDate: new Date(p.endDate)
		}))
	);
	const currentPeriod = $derived(allPeriods.find((p) => p.id === proposal.voting_period_id));
	const createdAtRaw = $derived(
		proposal.voting_period_id === 'february-2026-exceptional'
			? '2025-12-11T00:00:00Z'
			: (proposal.created_at ??
					(proposal as any).createdAt ??
					(proposal as any).inserted_at ??
					currentPeriod?.startDate?.toISOString() ??
					null)
	);
	const periodHasStarted = $derived(currentPeriod ? new Date() >= currentPeriod.startDate : true);
	const periodHasEnded = $derived(currentPeriod ? new Date() > currentPeriod.endDate : false);
	const showResults = $derived(periodHasStarted && (status === 'open' || periodHasEnded));
	const votingDisabled = $derived(
		status !== 'open' || voteLoading || !!userChoice || !periodHasStarted
	);
	const voteOptions = $derived([
		{ key: 'yes' as VoteChoice, label: m.vote_yes(), color: 'bg-green-200 border-green-500' },
		{ key: 'no' as VoteChoice, label: m.vote_no(), color: 'bg-rose-200 border-rose-500' },
		{ key: 'abstain' as VoteChoice, label: m.vote_abstain(), color: 'bg-gray-200 border-gray-400' }
	]);
	const resultOptions = $derived([
		{ key: 'yes' as VoteChoice, label: m.vote_yes(), bar: 'bg-green-500' },
		{ key: 'no' as VoteChoice, label: m.vote_no(), bar: 'bg-rose-500' },
		{ key: 'abstain' as VoteChoice, label: m.vote_abstain(), bar: 'bg-gray-500' }
	]);
	const longTermObjectivesLabel = $derived.by(() =>
		getLocale().toLowerCase().startsWith('pt')
			? 'Objetivos a longo prazo'
			: 'Long-term goals'
	);

	function getVotingPeriodLabelById(periodId: string): string {
		const period = allPeriods.find((p) => p.id === periodId);
		if (!period) return periodId;
		const locale = getLocale() === 'pt' ? 'pt-PT' : getLocale() || 'en-US';
		const start = period.startDate.toLocaleDateString(locale, { day: 'numeric', month: 'short' });
		const end = period.endDate.toLocaleDateString(locale, {
			day: 'numeric',
			month: 'short',
			year: 'numeric'
		});
		return `${start} - ${end}`;
	}

	function getTranslation(key: string | null | undefined): string {
		if (!key) return '';
		const translation = (m as any)[key];
		return typeof translation === 'function' ? translation() : '';
	}

	function getOnboardingCargoLabel(): string | null {
		if (typeof window === 'undefined') return null;
		try {
			const raw = localStorage.getItem('zoopdao:onboarding:v1');
			if (!raw) return null;
			const parsed = JSON.parse(raw) as { role?: string | null; customRole?: string };

			const role = parsed.role ?? null;
			const customRole = (parsed.customRole ?? '').trim();
			if (role === 'other') return customRole.length > 0 ? customRole : null;

			if (role && role !== 'other') {
				const translated = getTranslation(`character_${role}_title`);
				return translated?.trim()?.length ? translated : role;
			}

			return null;
		} catch {
			return null;
		}
	}

	function getModeLabel(mode: VoteMode | null): string {
		if (!mode) return '-';
		if (getLocale() === 'pt') {
			if (mode === 'no_discussion') return 'Sem discussão';
			if (mode === 'pedagogic') return 'Pedagógico';
			if (mode === 'decision_making') return 'Tomada de Decisão';
			return mode;
		}
		if (mode === 'no_discussion') return 'No discussion';
		if (mode === 'pedagogic') return 'Pedagogic';
		if (mode === 'decision_making') return 'Decision making';
		return mode;
	}

	function formatDate(dateInput?: Date | string | null) {
		const date = dateInput instanceof Date ? dateInput : dateInput ? new Date(dateInput) : null;
		if (!date || typeof date.getTime !== 'function' || Number.isNaN(date.getTime())) return '-';
		const locale = getLocale() === 'pt' ? 'pt-PT' : getLocale() || 'en-US';
		return date.toLocaleDateString(locale, {
			day: 'numeric',
			month: '2-digit',
			year: 'numeric'
		});
	}

	function formatTimeAgoCompact(dateInput?: Date | string | null) {
		const date = dateInput instanceof Date ? dateInput : dateInput ? new Date(dateInput) : null;
		if (!date || typeof date.getTime !== 'function' || Number.isNaN(date.getTime())) return '-';

		const diffMs = Date.now() - date.getTime();
		if (diffMs < 60_000) return getLocale() === 'pt' ? 'agora mesmo' : 'just now';

		const minutes = Math.floor(diffMs / 60_000);
		const hours = Math.floor(minutes / 60);
		const days = Math.floor(hours / 24);
		const months = Math.floor(days / 30);
		const years = Math.floor(days / 365);

		const locale = getLocale();
		const prefix = locale === 'pt' ? 'há ' : '';
		const suffix = locale === 'pt' ? '' : ' ago';

		if (years > 0) return `${prefix}${years}y${suffix}`;
		if (months > 0) return `${prefix}${months}mo${suffix}`;
		if (days > 0) return `${prefix}${days}d${suffix}`;
		if (hours > 0) return `${prefix}${hours}h${suffix}`;
		return `${prefix}${minutes}m${suffix}`;
	}

	function getPercentage(choice: VoteChoice) {
		if (!totalVotes) return 0;
		return Math.round((voteTotals[choice] / totalVotes) * 100);
	}

	async function loadVotesTable() {
		if (votesTableLoading) return;
		votesTableLoading = true;
		votesTableError = '';
		try {
			const {
				data: { session }
			} = await supabase.auth.getSession();
			const headers: Record<string, string> = {};
			if (session?.access_token) headers['Authorization'] = `Bearer ${session.access_token}`;
			const res = await fetch(`/api/proposals/${proposal.id}/votes?include=votes`, { headers });
			if (!res.ok) {
				votesTableError =
					getLocale() === 'pt' ? 'Falha ao carregar votos.' : 'Failed to load votes.';
				return;
			}
			const payload = await res.json();
			votesTableRows = (payload?.votes ?? []) as VoteRow[];
		} catch (err) {
			console.error('Failed to load votes table', err);
			votesTableError = getLocale() === 'pt' ? 'Falha ao carregar votos.' : 'Failed to load votes.';
		} finally {
			votesTableLoading = false;
		}
	}

	async function toggleVotesTable() {
		showVotesTable = !showVotesTable;
		if (showVotesTable && votesTableRows.length === 0) {
			await loadVotesTable();
		}
	}

	async function refreshVotesWithAuth() {
		try {
			const {
				data: { session }
			} = await supabase.auth.getSession();
			const headers: Record<string, string> = {};
			if (session?.access_token) {
				headers['Authorization'] = `Bearer ${session.access_token}`;
			}
			const res = await fetch(`/api/proposals/${proposal.id}/votes`, { headers });
			if (res.ok) {
				const payload = await res.json();
				voteTotals = payload.totals;
				totalVotes = payload.totalVotes;
				userChoice = payload.userChoice;
				userContext = payload.userContext;
				if (payload.userChoice) {
					voteSelection = payload.userChoice;
				}
			}
		} catch (err) {
			console.error('Failed to refresh votes', err);
		}
	}

	async function handleVote() {
		if (!voteSelection || votingDisabled) return;
		voteLoading = true;
		voteError = '';
		voteSuccess = false;

		try {
			let {
				data: { session },
				error: sessionError
			} = await supabase.auth.getSession();

			if (!session || sessionError) {
				const { data: anonData, error: anonError } = await supabase.auth.signInAnonymously();
				if (anonError || !anonData.session) {
					voteError = m.vote_sign_in_required();
					voteLoading = false;
					return;
				}
				session = anonData.session;
			}

			const headers: Record<string, string> = { 'Content-Type': 'application/json' };
			if (session?.access_token) {
				headers['Authorization'] = `Bearer ${session.access_token}`;
			}

			const res = await fetch(`/api/proposals/${proposal.id}/votes`, {
				method: 'POST',
				headers,
				body: JSON.stringify({
					choice: voteSelection,
					context: 'preview',
					cargo: getOnboardingCargoLabel(),
					mode: 'no_discussion'
				})
			});

			if (res.status === 409) {
				voteError = m.vote_error_duplicate();
				await refreshVotesWithAuth();
				return;
			}
			if (res.status === 400) {
				const body = await res.json().catch(() => ({}));
				voteError =
					body?.error === 'Voting closed' ? m.vote_error_closed() : m.vote_error_generic();
				return;
			}
			if (res.status === 401) {
				voteError = m.vote_sign_in_required();
				return;
			}
			if (!res.ok) {
				voteError = m.vote_error_generic();
				return;
			}

			const payload = await res.json();
			voteTotals = payload.totals;
			totalVotes = payload.totalVotes;
			userChoice = payload.userChoice;
			userContext = payload.userContext;
			voteSelection = payload.userChoice;
			voteSuccess = true;
			if (showVotesTable) await loadVotesTable();
		} catch (err) {
			console.error('Vote failed:', err);
			voteError = m.vote_error_generic();
		} finally {
			voteLoading = false;
		}
	}

	async function handleStartDiscussion() {
		if (isCreatingGame) return;

		playAudio(click_sound);
		isCreatingGame = true;

		try {
			// Ensure we have a session (anonymous or authenticated)
			const {
				data: { session },
				error: sessionError
			} = await supabase.auth.getSession();

			if (!session) {
				// Create anonymous session if none exists
				const { data: authData, error: authError } = await supabase.auth.signInAnonymously();

				if (authError || !authData.session) {
					console.error('Error creating anonymous session:', authError);
					alert(
						getLocale() === 'pt'
							? 'Falha ao criar sessão. Tenta novamente.'
							: 'Failed to create session. Please try again.'
					);
					isCreatingGame = false;
					return;
				}
			}

			// Create a new discussion with proposal_id
			const { data: gameData, error: gameError } = await supabase.rpc('create_game', {
				p_proposal_id: proposal.id,
				p_mode: 'pedagogic'
			});

			if (gameError) {
				console.error('Error creating discussion:', gameError);
				alert(
					getLocale() === 'pt'
						? `Falha ao criar discussão: ${gameError.message}. Tenta novamente.`
						: `Failed to create discussion: ${gameError.message}. Please try again.`
				);
				isCreatingGame = false;
				return;
			}

			if (!gameData?.game_code) {
				console.error('Error creating discussion: Missing game_code in response.', gameData);
				alert(
					getLocale() === 'pt'
						? 'Falha ao criar discussão. Tenta novamente.'
						: 'Failed to create discussion. Please try again.'
				);
				isCreatingGame = false;
				return;
			}

			// Navigate to mode selection with the discussion code
			await goto(localizeUrl(`/${gameData.game_code}/mode`).toString());
		} catch (error) {
			console.error('Error starting discussion:', error);
			const msg = error instanceof Error ? error.message : 'Unknown error';
			alert(
				getLocale() === 'pt'
					? `Falha ao iniciar discussão: ${msg}. Tenta novamente.`
					: `Failed to start discussion: ${msg}. Please try again.`
			);
		} finally {
			isCreatingGame = false;
		}
	}

	function handleViewFullProposal() {
		playAudio(click_sound);
		goto(localizeUrl(`/proposals/${proposal.id}`).toString());
	}

	function handleBack() {
		playAudio(click_sound);
		goto(localizeUrl('/').toString());
	}
</script>

<div class="min-h-screen bg-[#efe7e2] bos-bg p-4">
	<div class="max-w-3xl mx-auto">
		<!-- Back Button -->
		<div class="mb-4">
			<Button variant="ghost" size="icon" onclick={handleBack} class="text-deep-teal">
				<ArrowLeft class="h-6 w-6" />
			</Button>
		</div>

		<!-- Preview Card -->
		<div
			class="bg-white rounded-lg border-2 border-deep-teal border-opacity-20 p-6 md:p-8 shadow-lg"
		>
			<!-- Header -->
			<div class="mb-6">
				<h1 class="bos-title text-3xl font-bold text-deep-teal mb-4">{proposal.title}</h1>

				<div class="flex flex-wrap items-center gap-4 text-sm text-gray-600">
					<div class="flex items-center gap-2">
						<Calendar class="h-4 w-4" />
						<span>{m.voting_period()}: {getVotingPeriodLabelById(proposal.voting_period_id)}</span>
					</div>
					<div class="flex items-center gap-2 text-xs text-gray-600">
						<PenLine class="h-4 w-4" />
						<span>{m.timeline_created()}: {formatDate(createdAtRaw)}</span>
					</div>
					<div class="flex items-center gap-2">
						<Clock class="h-4 w-4" />
						<span class={`font-semibold ${status === 'open' ? 'text-green-600' : 'text-gray-400'}`}>
							{status === 'open' ? m.proposal_status_open() : m.proposal_status_closed()}
						</span>
					</div>
				</div>
			</div>

			<!-- Preview Content -->
			<div class="space-y-4 mb-6">
				<!-- Objectives Preview -->
				<div>
					<h3 class="bos-title text-lg font-semibold text-deep-teal mb-2">
						{longTermObjectivesLabel}
					</h3>
					<ul class="list-disc list-inside space-y-1 text-gray-700">
						{#each proposal.objectives.slice(0, 2) as objective}
							<li>{objective.value}</li>
						{/each}
					</ul>
				</div>

				<!-- Functionalities Preview -->
				<div>
					<h3 class="bos-title text-lg font-semibold text-deep-teal mb-2">{m.functionalities()}</h3>
					<p class="text-gray-700 whitespace-pre-line">{proposal.functionalities}</p>
				</div>
			</div>

			<!-- Actions (moved above voting) -->
			<div class="flex flex-col sm:flex-row gap-3 pt-4 pb-2">
				{#if status === 'open'}
					<Button
						variant="outline"
						size="lg"
						onclick={handleViewFullProposal}
						class="flex-1 border-2 border-black text-black bg-white hover:bg-gray-100 min-h-[52px]"
					>
						{m.view_full_proposal()}
					</Button>
					<Button
						size="lg"
						onclick={handleStartDiscussion}
						disabled={isCreatingGame}
						class="flex-1 min-h-[52px]"
					>
						{isCreatingGame ? m.loading() : m.start_discussion()}
					</Button>
				{:else}
					<Button
						variant="outline"
						size="lg"
						onclick={handleViewFullProposal}
						class="w-full border-2 border-black text-black bg-white hover:bg-gray-100 min-h-[52px]"
					>
						{m.view_full_proposal()}
					</Button>
				{/if}
			</div>

			<!-- Voting + Results (only during open voting window) -->
			{#if showResults}
				<div class="grid md:grid-cols-3 gap-4 mb-6">
					<!-- Vote Card -->
					{#if status === 'open'}
						<div class="md:col-span-2 bg-white border border-deep-teal/20 rounded-lg p-4 md:p-6">
							<div class="mb-4">
								<p class="text-sm font-semibold text-deep-teal uppercase tracking-wide whitespace-pre-line">
									{getLocale() === 'pt'
										? 'Vota já ou depois da discussão\nsó podes votar 1 vez'
										: 'Vote now or after the discussion\nyou only can vote once'}
								</p>
							</div>

							<div class="grid grid-cols-3 gap-3 mb-4">
								{#each voteOptions as option}
									<label
										class={`flex items-center justify-center text-sm font-semibold rounded-md border p-3 cursor-pointer transition ${voteSelection === option.key ? option.color : 'border-deep-teal/30 bg-white hover:border-deep-teal/60'} ${votingDisabled ? 'opacity-50 cursor-not-allowed' : ''}`}
									>
										<input
											type="radio"
											class="hidden"
											name="vote-option"
											value={option.key}
											checked={voteSelection === option.key}
											onchange={() => (voteSelection = option.key)}
											disabled={votingDisabled}
										/>
										{option.label}
									</label>
								{/each}
							</div>

							<Button
								size="lg"
								class="w-full disabled:bg-gray-300 disabled:text-gray-600 disabled:hover:bg-gray-300"
								disabled={votingDisabled || !voteSelection}
								onclick={handleVote}
							>
								{status !== 'open'
									? m.vote_closed_label()
									: voteLoading
										? m.loading()
										: userChoice
											? m.vote_already_submitted()
											: m.vote_submit()}
							</Button>

							{#if voteError}
								<p class="mt-3 text-sm text-rose-600">{voteError}</p>
							{:else if voteSuccess}
								<p class="mt-3 text-sm text-green-700">{m.vote_submitted()}</p>
							{:else if userChoice}
								<p class="mt-3 text-sm text-green-700">{m.vote_already_submitted()}</p>
							{/if}

							{#if userContext && userContext !== 'preview'}
								<p class="mt-2 text-xs text-gray-600">{m.vote_already_elsewhere()}</p>
							{/if}
						</div>
					{/if}

					<!-- Results -->
					<div class={`space-y-4 ${status === 'open' ? '' : 'md:col-span-3'}`}>
						<div class="bg-gray-50 border border-deep-teal/20 rounded-lg p-4">
							<p class="text-sm font-semibold text-deep-teal uppercase mb-3">{m.vote_results()}</p>
							{#each resultOptions as option}
								<div class="mb-3 last:mb-0">
									<div class="flex items-center justify-between text-sm">
										<span>{option.label}</span>
										<div class="flex items-center gap-2">
											<span class="font-semibold">{voteTotals[option.key]}</span>
											<span class="text-gray-500">{getPercentage(option.key)}%</span>
										</div>
									</div>
									<div class="h-2 mt-1 bg-gray-200 rounded-full overflow-hidden">
										<div
											class={`h-full ${option.bar}`}
											style={`width: ${getPercentage(option.key)}%;`}
										></div>
									</div>
								</div>
							{/each}
							<p class="mt-2 text-xs text-gray-600">{m.vote_total_votes({ total: totalVotes })}</p>

							{#if totalVotes > 0}
								<div class="mt-3">
									<Button
										variant="outline"
										size="sm"
										class="w-full border-2 border-black text-black bg-white hover:bg-gray-100"
										onclick={toggleVotesTable}
									>
										{getLocale() === 'pt' ? 'Ver votos' : 'View votes'}
									</Button>
								</div>
							{/if}
						</div>
					</div>
				</div>

				{#if showVotesTable}
					<div class="bg-white border border-deep-teal/20 rounded-lg p-4 md:p-6 mb-6">
						<div class="flex items-center justify-between mb-3">
							<p class="text-sm font-semibold text-deep-teal uppercase tracking-wide">
								{getLocale() === 'pt' ? 'Votos' : 'Votes'}
							</p>
						</div>

						{#if votesTableError}
							<p class="text-sm text-rose-600 mb-3">{votesTableError}</p>
						{/if}

						<div class="overflow-x-auto">
							<table class="min-w-[720px] w-full text-sm">
								<thead class="text-xs uppercase text-gray-500">
									<tr class="border-b">
										<th class="text-left py-2 pr-3">{getLocale() === 'pt' ? 'ID' : 'ID'}</th>
										<th class="text-left py-2 pr-3">{getLocale() === 'pt' ? 'Voto' : 'Vote'}</th>
										<th class="text-left py-2 pr-3">{getLocale() === 'pt' ? 'Data' : 'Date'}</th>
										<th class="text-left py-2 pr-3">{getLocale() === 'pt' ? 'Cargo' : 'Role'}</th>
										<th class="text-left py-2 pr-3">{getLocale() === 'pt' ? 'Modo' : 'Mode'}</th>
									</tr>
								</thead>
								<tbody>
									{#if votesTableLoading}
										<tr>
											<td class="py-3 text-gray-600" colspan="5">{m.loading()}</td>
										</tr>
									{:else if votesTableRows.length === 0}
										<tr>
											<td class="py-3 text-gray-600" colspan="5">
												{getLocale() === 'pt' ? 'Sem votos.' : 'No votes.'}
											</td>
										</tr>
									{:else}
										{#each votesTableRows as row (row.user_id)}
											<tr class="border-b last:border-b-0">
												<td class="py-3 pr-3 font-mono text-xs text-gray-700" title={row.user_id}>
													{row.user_id.slice(0, 8)}
												</td>
												<td class="py-3 pr-3">
													{row.choice === 'yes'
														? m.vote_yes()
														: row.choice === 'no'
															? m.vote_no()
															: m.vote_abstain()}
												</td>
												<td class="py-3 pr-3">
													<div class="font-semibold text-gray-900">
														{formatTimeAgoCompact(row.created_at)}
													</div>
													<div class="text-xs text-gray-500">{formatDate(row.created_at)}</div>
												</td>
												<td class="py-3 pr-3">{row.cargo ?? '-'}</td>
												<td class="py-3 pr-3">{getModeLabel(row.discussion_mode)}</td>
											</tr>
										{/each}
									{/if}
								</tbody>
							</table>
						</div>
					</div>
				{/if}
			{/if}
		</div>
	</div>
</div>
