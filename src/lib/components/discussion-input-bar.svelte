<script lang="ts">
	import { FileText, MessageSquare, Send, Plus } from 'lucide-svelte';
	import { m } from '@src/paraglide/messages';
	import { getLocale } from '@src/paraglide/runtime.js';
	import { supabase } from '@/supabase';
	import {
		RAG_ALLOWED_EXTENSIONS,
		RAG_MAX_FILE_SIZE_BYTES,
		RAG_MAX_FILES_PER_ROUND
	} from '$lib/rag/constants';

	interface DiscussionInputBarProps {
		onSend: (message: string) => void;
		onOpenHistory: () => void;
		onDraftChange?: (draft: string) => void;
		gameId: number;
		proposalId: number | null;
		round: number;
		userId?: string | null;
		disabled?: boolean;
		historyDisabled?: boolean;
		documentsDisabled?: boolean;
		inputDisabled?: boolean;
		lockedPlaceholder?: string | null;
		inline?: boolean;
	}

	let {
		onSend,
		onOpenHistory,
		onDraftChange = undefined,
		gameId,
		proposalId,
		round,
		userId = null,
		disabled = false,
		historyDisabled = undefined,
		documentsDisabled = undefined,
		inputDisabled = undefined,
		lockedPlaceholder = null,
		inline = false
	}: DiscussionInputBarProps = $props();

// Default fallbacks: if per-control flags are not provided, fall back to `disabled`
historyDisabled = historyDisabled ?? disabled;
documentsDisabled = documentsDisabled ?? disabled;
inputDisabled = inputDisabled ?? disabled;

	let message = $state('');
	let attachments = $state<
		{
			id: string;
			name: string;
			size: number | null;
			status: 'uploading' | 'uploaded' | 'pending' | 'indexed' | 'error';
			storagePath: string;
			documentId?: number | null;
		}[]
	>([]);
	let uploadError = $state<string | null>(null);
	let fileInput: HTMLInputElement | null = null;
	let actionInProgress = $state<Record<string, 'deleting' | 'reindexing'>>({});

	const DOCUMENTS_BUCKET = 'discussion-documents';

	$effect(() => {
		// Mirror draft changes upward so other UI (e.g. user bubble) can react.
		if (typeof onDraftChange === 'function') {
			onDraftChange(message);
		}
	});

	function buildStoragePath() {
		const proposalKey = proposalId ? `proposal-${proposalId}` : `game-${gameId}`;
		return `${proposalKey}/round-${round}`;
	}

	function sanitizeFilename(name: string) {
		return name.replace(/[^a-zA-Z0-9._-]/g, '_');
	}

	function formatFileSize(size: number | null) {
		if (!size) return '';
		if (size < 1024) return `${size} B`;
		const kb = size / 1024;
		if (kb < 1024) return `${kb.toFixed(1)} KB`;
		const mb = kb / 1024;
		return `${mb.toFixed(1)} MB`;
	}

	function formatMaxFileSizeMb() {
		return Math.round(RAG_MAX_FILE_SIZE_BYTES / 1024 / 1024);
	}

	function formatAttachmentStatus(status: typeof attachments[number]['status']) {
		if (status === 'uploading') return m.uploading();
		if (status === 'pending') return m.upload_pending();
		if (status === 'indexed') return m.upload_indexed();
		if (status === 'error') return m.upload_failed();
		return '';
	}

	function mapIngestError(code: string | undefined) {
		switch (code) {
			case 'upload-limit-exceeded':
				return `${m.upload_limit_exceeded()} (${RAG_MAX_FILES_PER_ROUND})`;
			case 'unsupported-file-type':
				return m.upload_invalid_type();
			case 'file-too-large':
				return `${m.upload_too_large()} (${formatMaxFileSizeMb()} MB)`;
			default:
				return m.upload_failed();
		}
	}

	async function refreshAttachments() {
		if (!proposalId || round !== 7 || !userId) {
			attachments = [];
			return;
		}

		const path = buildStoragePath();
		const { data, error } = await supabase.storage.from(DOCUMENTS_BUCKET).list(path, {
			limit: 100,
			sortBy: { column: 'created_at', order: 'desc' }
		});

		if (error) {
			uploadError = error.message;
			return;
		}

		const { data: documentRows, error: documentsError } = await supabase
			.from('documents')
			.select('id, storage_path, metadata')
			.eq('proposal_id', proposalId)
			.eq('round', round)
			.eq('user_id', userId);

		if (documentsError) {
			uploadError = documentsError.message;
			return;
		}

		const docByPath = new Map(
			(documentRows ?? []).map((doc) => [doc.storage_path as string, doc])
		);

		attachments =
			data
				?.filter((item) => docByPath.has(`${path}/${item.name}`))
				.map((item) => ({
				id: item.id ?? `${path}/${item.name}`,
				name: item.name,
				size: (item.metadata as { size?: number } | null)?.size ?? null,
				status: (() => {
					const storagePath = `${path}/${item.name}`;
					const doc = docByPath.get(storagePath) as { metadata?: { status?: string } } | undefined;
					switch (doc?.metadata?.status) {
						case 'indexed':
							return 'indexed';
						case 'pending':
							return 'pending';
						case 'failed':
							return 'error';
						default:
							return 'uploaded';
					}
				})(),
				storagePath: `${path}/${item.name}`,
				documentId: (docByPath.get(`${path}/${item.name}`) as { id?: number } | undefined)?.id
			})) ?? [];
	}

	async function uploadFiles(files: File[]) {
		if (!proposalId || round !== 7 || !userId) return;
		uploadError = null;

		const existingCount = attachments.length;
		if (existingCount + files.length > RAG_MAX_FILES_PER_ROUND) {
			uploadError = `${m.upload_limit_exceeded()} (${RAG_MAX_FILES_PER_ROUND})`;
			return;
		}

		for (const file of files) {
			const extension = `.${file.name.split('.').pop() ?? ''}`.toLowerCase();
			if (!RAG_ALLOWED_EXTENSIONS.includes(extension as (typeof RAG_ALLOWED_EXTENSIONS)[number])) {
				uploadError = m.upload_invalid_type();
				return;
			}

			if (file.size > RAG_MAX_FILE_SIZE_BYTES) {
				uploadError = `${m.upload_too_large()} (${formatMaxFileSizeMb()} MB)`;
				return;
			}
		}

		const path = buildStoragePath();
		for (const file of files) {
			const attachmentId = `${Date.now()}-${file.name}`;
			attachments = [
				{
					id: attachmentId,
					name: file.name,
					size: file.size,
					status: 'uploading',
					storagePath: ''
				},
				...attachments
			];

			const storagePath = `${path}/${attachmentId}-${sanitizeFilename(file.name)}`;
			const { data: uploadData, error } = await supabase.storage
				.from(DOCUMENTS_BUCKET)
				.upload(storagePath, file, { upsert: false });

			// Debug logging: record storage upload result
			console.debug('[uploadFiles] supabase.upload result', {
				filename: file.name,
				storagePath,
				size: file.size,
				uploadData,
				error
			});

			if (error) {
				// Log the storage error for diagnostics
				console.error('[uploadFiles] supabase.upload error', error);
				attachments = attachments.map((attachment) =>
					attachment.id === attachmentId
						? { ...attachment, status: 'error', storagePath }
						: attachment
				);
				uploadError = error.message;
			} else {
				attachments = attachments.map((attachment) =>
					attachment.id === attachmentId
						? { ...attachment, status: 'uploaded', storagePath }
						: attachment
				);
				// Call ingest endpoint and log full response for diagnostics
				let ingestResponse: Response | null = null;
				let ingestBody: any = null;
				try {
					ingestResponse = await fetch('/api/documents/ingest', {
						method: 'POST',
						headers: { 'Content-Type': 'application/json' },
						body: JSON.stringify({
							proposalId,
							round,
							userId,
							files: [
								{
									storagePath,
									filename: file.name,
									mimeType: file.type,
									sizeBytes: file.size
								}
							]
						})
					});
				} catch (fetchErr) {
					console.error('[uploadFiles] ingest fetch failed', fetchErr);
					uploadError = String(fetchErr?.message ?? fetchErr);
					attachments = attachments.map((attachment) =>
						attachment.id === attachmentId
							? { ...attachment, status: 'error' }
							: attachment
					);
					continue;
				}

				try {
					ingestBody = await ingestResponse.json().catch(() => null);
				} catch (parseErr) {
					console.error('[uploadFiles] failed to parse ingest response', parseErr, { status: ingestResponse?.status });
				}

				// Debug: log ingest response and body
				console.debug('[uploadFiles] ingest response', {
					status: ingestResponse?.status,
					ok: ingestResponse?.ok,
					body: ingestBody
				});

				const failedResult =
					ingestBody?.results?.find?.(
						(result: { storagePath: string; status: string; error?: string }) =>
							result.storagePath === storagePath && result.status === 'failed'
					) ?? null;

				if (!ingestResponse?.ok || ingestBody?.success === false || failedResult) {
					const errorCode = failedResult?.error ?? ingestBody?.error;
					uploadError = mapIngestError(errorCode);
					attachments = attachments.map((attachment) =>
						attachment.id === attachmentId
							? { ...attachment, status: 'error' }
							: attachment
					);
				}
			}
		}

		await refreshAttachments();
	}

	async function handleDelete(attachment: typeof attachments[number]) {
		if (!proposalId || !attachment.storagePath || !userId) return;
		actionInProgress = { ...actionInProgress, [attachment.id]: 'deleting' };
		uploadError = null;

		const response = await fetch('/api/documents/delete', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				documentId: attachment.documentId ?? undefined,
				storagePath: attachment.storagePath,
				userId
			})
		});

		if (!response.ok) {
			uploadError = m.upload_delete_failed();
		}

		const next = { ...actionInProgress };
		delete next[attachment.id];
		actionInProgress = next;
		await refreshAttachments();
	}

	async function handleRetry(attachment: typeof attachments[number]) {
		if (!attachment.documentId || !userId) return;
		actionInProgress = { ...actionInProgress, [attachment.id]: 'reindexing' };
		uploadError = null;

		const response = await fetch('/api/documents/reindex', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				documentId: attachment.documentId,
				userId
			})
		});

		if (!response.ok) {
			uploadError = m.upload_reindex_failed();
		}

		const next = { ...actionInProgress };
		delete next[attachment.id];
		actionInProgress = next;
		await refreshAttachments();
	}

	function handleFileSelect(event: Event) {
		const input = event.target as HTMLInputElement;
		const files = Array.from(input.files ?? []);
		if (!files.length) return;
		void uploadFiles(files);
		input.value = '';
	}

	$effect(() => {
		if (!proposalId || round !== 7) {
			attachments = [];
			return;
		}
		void refreshAttachments();
	});

	function handleSend() {
		if (message.trim() && !disabled) {
			onSend(message.trim());
			message = '';
		}
	}

	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' && !e.shiftKey) {
			e.preventDefault();
			handleSend();
		}
	}

	const buttonLabels = $derived.by(() => {
		const locale = getLocale();
		const isPt = locale.toLowerCase().startsWith('pt');
		return {
			history: isPt ? 'Conversa' : 'Chat',
			files: isPt ? 'Ficheiros' : 'Files',
			send: isPt ? 'Enviar' : 'Send'
		};
	});
</script>

<!-- Discussion Input Bar -->
<div
	class="{inline
		? 'w-full'
		: 'fixed bottom-4 inset-x-0 z-50 pointer-events-auto px-3 sm:px-4'}"
>
	<div class={inline ? 'relative' : 'relative max-w-[760px] mx-auto'}>
		{#if attachments.length > 0 || uploadError}
			<div class="mb-2 rounded-2xl border border-border/40 bg-surface px-4 py-3 text-xs text-text shadow-lg">
				<div class="flex items-center justify-between">
					<span class="font-semibold">{m.attachments()}</span>
					{#if uploadError}
						<span class="text-primary">{uploadError}</span>
					{/if}
				</div>
				{#if attachments.length > 0}
					<ul class="mt-2 space-y-1">
						{#each attachments as attachment}
							<li class="flex items-center justify-between gap-2">
								<div class="min-w-0">
									<span class="block truncate">{attachment.name}</span>
									<span class="block text-[11px] text-text-muted">
										{formatAttachmentStatus(attachment.status) || formatFileSize(attachment.size)}
									</span>
								</div>
								<div class="flex flex-shrink-0 items-center gap-2 text-[11px]">
									{#if attachment.status === 'error' && attachment.documentId}
										<button
											type="button"
											class="rounded-full border border-border/60 px-2 py-1 text-text-muted hover:text-text hover:border-border"
											disabled={actionInProgress[attachment.id] === 'reindexing'}
											onclick={() => handleRetry(attachment)}
										>
											{actionInProgress[attachment.id] === 'reindexing'
												? m.upload_reindexing()
												: m.upload_retry()}
										</button>
									{/if}
									<button
										type="button"
										class="rounded-full border border-border/60 px-2 py-1 text-text-muted hover:text-text hover:border-border"
										disabled={actionInProgress[attachment.id] === 'deleting'}
										onclick={() => handleDelete(attachment)}
									>
										{actionInProgress[attachment.id] === 'deleting'
											? m.upload_deleting()
											: m.upload_delete()}
									</button>
								</div>
							</li>
						{/each}
					</ul>
				{/if}
			</div>
		{/if}
		<!-- Background bar with shadow -->
			<div class="bg-surface rounded-full px-3 py-3 sm:px-4 sm:py-4 shadow-2xl border border-border/40">
				<div class="flex items-center gap-1.5 sm:gap-2">
					<div class="flex items-center gap-1 sm:gap-1.5">
						<!-- History Button -->
						<div class="relative flex-shrink-0 w-10 h-10 sm:w-12 sm:h-12">
							<button
								onclick={onOpenHistory}
								disabled={historyDisabled}
								class="flex-shrink-0 w-10 h-10 sm:w-12 sm:h-12 rounded-full bg-white hover:bg-neutral-100 active:bg-yellow-300 transition-colors flex items-center justify-center border-2 border-yellow-400 disabled:opacity-50 disabled:cursor-not-allowed"
								aria-label={m.open_message_history()}
							title={m.open_message_history()}
						>
								<MessageSquare class="w-5 h-5 sm:w-6 sm:h-6 text-black" />
							</button>
		
						</div>

					<!-- Add Documents Button -->
					<input
						bind:this={fileInput}
						type="file"
						class="hidden"
						multiple
						accept={RAG_ALLOWED_EXTENSIONS.join(',')}
						onchange={handleFileSelect}
						disabled={documentsDisabled}
					/>
						<div class="relative flex-shrink-0 w-10 h-10 sm:w-12 sm:h-12">
							<button
								type="button"
								onclick={() => fileInput?.click()}
							disabled={
								documentsDisabled ||
								!proposalId ||
								!userId ||
								attachments.length >= RAG_MAX_FILES_PER_ROUND
							}
							class="images flex-shrink-0 w-10 h-10 sm:w-12 sm:h-12 rounded-full bg-white hover:bg-neutral-100 active:bg-yellow-300 transition-colors flex items-center justify-center border-2 border-yellow-400 disabled:opacity-50 disabled:cursor-not-allowed"
							aria-label={m.add_documents()}
							title={m.add_documents()}
						>
								<Plus class="w-5 h-5 sm:w-6 sm:h-6 text-black" />
							</button>
			
						</div>
				</div>

				<!-- Divider -->
				<div class="h-8 sm:h-10 w-px bg-border/30"></div>

				<!-- Input Field -->
				<input
					type="text"
					bind:value={message}
					onkeydown={handleKeydown}
					disabled={inputDisabled}
					placeholder={inputDisabled && lockedPlaceholder ? lockedPlaceholder : m.discussion_input_placeholder()}
					class="flex-1 min-w-0 bg-transparent text-text text-base sm:text-lg placeholder:text-text-muted outline-none disabled:opacity-50"
				/>

				<!-- Send Button -->
				<div class="relative flex-shrink-0 w-12 h-12 sm:w-14 sm:h-14">
					<button
						onclick={handleSend}
						disabled={inputDisabled || !message.trim()}
						class="flex-shrink-0 w-12 h-12 sm:w-14 sm:h-14 rounded-full bg-primary hover:bg-primary-hover active:bg-primary-active transition-colors flex items-center justify-center disabled:opacity-50 disabled:cursor-not-allowed shadow-lg"
						aria-label={m.send_message()}
						title={m.send_message()}
					>
						<Send class="w-5 h-5 sm:w-6 sm:h-6 text-white" />
					</button>
				</div>
			</div>
		</div>
	</div>
</div>
