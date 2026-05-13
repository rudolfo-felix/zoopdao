import { createHash } from 'node:crypto';
import {
	IAEDU_API_KEY,
	IAEDU_CHANNEL_ID,
	IAEDU_ENDPOINT,
	IAEDU_THREAD_ID
} from '$env/static/private';
import { env } from '$env/dynamic/private';
import type {
	AiAgentRole,
	AiGenerateRequest,
	AiGenerateResult,
	AiGenerateSuccess
} from '../llm-types';

const DEFAULT_ENDPOINT =
	'https://api.iaedu.pt/agent-chat/api/v1/agent/cmamvd3n40000c801qeacoad2/stream';
const USER_INFO_PREFIX = 'zoopdao';

function isTruthyEnv(value: string | undefined): boolean {
	if (!value) return false;
	const v = value.trim().toLowerCase();
	return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}

function normalizeEndpoint(value: string): string {
	const trimmed = value.trim();
	if (!trimmed) return trimmed;
	const parts = trimmed.split('://');
	if (parts.length < 2) return trimmed.replace(/\/{2,}/g, '/');
	const scheme = parts.shift()!;
	const rest = parts.join('://');
	return `${scheme}://${rest.replace(/\/{2,}/g, '/')}`;
}

function stripInvisible(text: string): string {
	// Some streams contain zero-width chars; strip them for stable placeholder/id detection.
	return text.replace(/[\u00AD\u200B-\u200D\u2060\uFEFF\u202A-\u202E\u2066-\u2069]/g, '');
}

function stripEdgePunctuation(text: string): string {
	return text.replace(/^[\s"'`([{<:]+|[\s"'`\])}>:,.!?;]+$/g, '').trim();
}

function isPlaceholderText(value: string | null | undefined): boolean {
	const t = stripInvisible((value ?? '')).trim().toLowerCase();
	if (!t) return false;
	return (
		t === 'processing' ||
		t === 'thinking' ||
		t === 'loading' ||
		t === 'working' ||
		t === 'please wait' ||
		t === 'unexpected processing error' ||
		t === 'erro inesperado de processamento'
);
}

const UUID_LIKE_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const LONG_HEX_RE = /^[0-9a-f]{24,}$/i;
const COMPACT_ALNUM_ID_RE = /^[a-z0-9_-]{20,}$/i;

function isIdentifierLikeText(value: string | null | undefined): boolean {
	const text = stripEdgePunctuation(stripInvisible((value ?? '')).trim());
	if (!text) return false;
	if (UUID_LIKE_RE.test(text) || LONG_HEX_RE.test(text)) return true;
	if (!COMPACT_ALNUM_ID_RE.test(text) || text.includes(' ')) return false;
	const hasLetters = /[a-z]/i.test(text);
	const hasDigits = /\d/.test(text);
	return hasLetters && hasDigits;
}

function isUsableAssistantText(value: string | null | undefined): value is string {
	const text = (value ?? '').trim();
	if (!text) return false;
	if (isPlaceholderText(text)) return false;
	if (isIdentifierLikeText(text)) return false;
	return true;
}

type IaeduParseDiagnostics = {
	eventsCount: number;
	errorEventsCount: number;
	tokenLength: number;
	contentSegmentsCount: number;
	textCandidatesCount: number;
	source: string | null;
};

function collectTextCandidates(value: unknown, depth = 0, acc: string[] = []): string[] {
	if (depth > 6 || value == null) return acc;
	if (typeof value === 'string') {
		const trimmed = value.trim();
		if (trimmed) acc.push(trimmed);
		return acc;
	}
	if (Array.isArray(value)) {
		for (const item of value) collectTextCandidates(item, depth + 1, acc);
		return acc;
	}
	if (typeof value === 'object') {
		const obj = value as Record<string, unknown>;
		const priorityKeys = ['content', 'text', 'message', 'answer', 'output', 'response'];
		for (const key of priorityKeys) {
			if (key in obj) collectTextCandidates(obj[key], depth + 1, acc);
		}
		for (const [key, nested] of Object.entries(obj)) {
			if (!priorityKeys.includes(key)) collectTextCandidates(nested, depth + 1, acc);
		}
	}
	return acc;
}

function buildPrompt(request: AiGenerateRequest): string {
	if (request.promptPayload && typeof request.promptPayload === 'object') {
		return JSON.stringify(request.promptPayload);
	}

	const orgName = request.organizationName?.trim();
	const orgLine = orgName ? `Organization: ${orgName}` : null;
	const currentUserName = request.currentUserProfile?.name?.trim() || null;
	const currentUserRole = request.currentUserProfile?.role?.trim() || null;
	const currentUserDescription = request.currentUserProfile?.description?.trim() || null;
	const currentUserProfileBlock =
		currentUserName || currentUserRole || currentUserDescription
			? [
					'Current user profile:',
					`- Name: ${currentUserName ?? '-'}`,
					`- Role: ${currentUserRole ?? '-'}`,
					`- Description: ${currentUserDescription ?? '-'}`
				].join('\n')
			: null;
	const summary = request.discussionSummary?.trim();
	const summaryBlock = summary ? `Discussion summary:\n${summary}` : null;
	const assemblyParticipants = request.assemblyParticipants?.trim();
	const assemblyParticipantsBlock = assemblyParticipants
		? `Assembly participants:\n${assemblyParticipants}`
		: null;
	const chatHistory = Array.isArray(request.chatHistory) ? request.chatHistory : [];
	const chatHistoryBlock =
		chatHistory.length > 0
			? `Recent discussion messages:\n${chatHistory
					.map((msg) => `${msg.senderName} (${msg.senderType}, Round ${msg.round}): ${msg.content}`)
					.join('\n')}`
			: null;
	const promptParts = [
		request.systemPrompt?.trim() || null,
		orgLine,
		currentUserProfileBlock,
		request.agentName?.trim() ? `Agent: ${request.agentName.trim()}` : null,
		`Round: ${request.round}`,
		request.proposalPoint ? `Proposal point:\n${request.proposalPoint}` : null,
		assemblyParticipantsBlock,
		summaryBlock,
		chatHistoryBlock,
		request.ragContext ? `RAG context:\n${request.ragContext}` : null,
		request.latestUserMessage ? `Latest user message:\n${request.latestUserMessage}` : null
	].filter(Boolean);

	return promptParts.join('\n\n');
}

function resolveInputSource(request: AiGenerateRequest): 'manual' | 'auto' {
	if (request.inputSource) return request.inputSource;
	return request.latestUserMessage ? 'manual' : 'auto';
}

function buildUserInfo(request: AiGenerateRequest): string {
	const source = resolveInputSource(request);
	const rawUserId = request.userId?.trim() || 'anonymous';
	const encryptedId = createHash('sha256').update(rawUserId).digest('hex');
	const userId = `${USER_INFO_PREFIX}${encryptedId}`;

	return JSON.stringify({
		user_id: userId,
		input_source: source
	});
}

function parseIaeduResponse(text: string): {
	content: string | null;
	error?: unknown;
	diagnostics: IaeduParseDiagnostics;
} {
	const events: Array<Record<string, unknown>> = [];
	let tokenBuffer = '';
	const contentSegments: Array<{ type: string | null; content: string }> = [];
	const textCandidates: string[] = [];
	let selectedSource: string | null = null;

	const getType = (event: Record<string, unknown>): string | null => {
		const t = event?.type;
		if (typeof t === 'string' && t) return t;
		const e = (event as any)?.event;
		if (typeof e === 'string' && e) return e;
		return null;
	};

	const appendTokenIfAny = (event: Record<string, unknown>) => {
		const t = getType(event);
		const content = (event as any)?.content;
		if (typeof content === 'string' && t && (t === 'token' || t === 'delta' || t === 'chunk')) {
			tokenBuffer += content;
			return;
		}
		const token = (event as any)?.token;
		if (typeof token === 'string' && token) {
			tokenBuffer += token;
			return;
		}
		const delta = (event as any)?.delta;
		if (typeof delta === 'string' && delta) {
			tokenBuffer += delta;
		}
	};

	for (const line of text.split('\n')) {
		let trimmed = line.trim();
		if (!trimmed) continue;
		if (trimmed.startsWith('event:')) continue;
		if (trimmed.startsWith('data:')) {
			trimmed = trimmed.slice('data:'.length).trim();
			if (!trimmed || trimmed === '[DONE]') continue;
		}
		try {
			const event = JSON.parse(trimmed);
			events.push(event);
			collectTextCandidates(event, 0, textCandidates);
			appendTokenIfAny(event);
			const t = getType(event);
			const content = (event as any)?.content;
			if (typeof content === 'string' && content.trim()) {
				contentSegments.push({ type: t, content: content.trim() });
			}
		} catch {
			// Ignore non-JSON lines, but allow raw text fallback below.
		}
	}

	let finalMessage: string | null = null;
	const errorEvents: unknown[] = [];

	for (const event of events) {
		const t = getType(event);
		const content = (event as any)?.content;
		if (
			(t === 'message' || t === 'final' || t === 'completion') &&
			typeof content === 'string' &&
			content.trim() &&
			!isPlaceholderText(content) &&
			!isIdentifierLikeText(content)
		) {
			finalMessage = content;
			selectedSource = 'event_message';
		}
		const message = (event as any)?.message;
		if (
			!finalMessage &&
			typeof message === 'string' &&
			(t === 'message' || t === 'final') &&
			!isPlaceholderText(message) &&
			!isIdentifierLikeText(message)
		) {
			finalMessage = message;
			selectedSource = 'event_message_field';
		}
		if (t === 'error') {
			errorEvents.push(event);
		}
	}

	if (!finalMessage) {
		for (const event of events) {
			const t = getType(event);
			const content = (event as any)?.content;
			// Only treat "content" as a final message when it isn't clearly a token/delta stream chunk.
			if (
				typeof content === 'string' &&
				content.trim() &&
				t !== 'error' &&
				t !== 'token' &&
				t !== 'delta' &&
				t !== 'chunk' &&
				!isPlaceholderText(content) &&
				!isIdentifierLikeText(content)
			) {
				finalMessage = content;
				selectedSource = 'event_content';
				break;
			}
		}
	}

	const token = tokenBuffer.trim();
	const candidate = finalMessage?.trim() ?? null;
	const candidateLooksInvalid = isPlaceholderText(candidate) || isIdentifierLikeText(candidate);

	// Prefer token streams (they represent actual generated text) over placeholder/id-like message events.
	if (token && (!candidate || candidateLooksInvalid)) {
		finalMessage = token;
		selectedSource = 'token_stream';
	}

	// If we still have placeholder/id-like content, try the last valid content segment.
	if (finalMessage && (isPlaceholderText(finalMessage) || isIdentifierLikeText(finalMessage))) {
		for (let i = contentSegments.length - 1; i >= 0; i -= 1) {
			const seg = contentSegments[i];
			if (!isPlaceholderText(seg.content) && !isIdentifierLikeText(seg.content)) {
				finalMessage = seg.content;
				selectedSource = 'content_segment';
				break;
			}
		}
	}

	if (!finalMessage && token) {
		finalMessage = token;
		selectedSource = 'token_stream_fallback';
	}

	if (!finalMessage || isPlaceholderText(finalMessage) || isIdentifierLikeText(finalMessage)) {
		for (let i = textCandidates.length - 1; i >= 0; i -= 1) {
			const candidate = textCandidates[i];
			if (!isUsableAssistantText(candidate)) continue;
			// Ignore very short status-like fragments.
			if (candidate.length < 8) continue;
			finalMessage = candidate;
			selectedSource = 'candidate_scan';
			break;
		}
	}

	if (!events.length && text.trim()) {
		finalMessage = text.trim();
		selectedSource = 'raw_text';
	}

	// Final safety check: never allow placeholders/opaque IDs to pass as a "successful" model message.
	if (!isUsableAssistantText(finalMessage)) {
		finalMessage = null;
	}

	// Some streams include non-fatal "error" events (warnings/diagnostics) alongside a valid message.
	// Treat error events as fatal only when no usable content was produced.
	if (!finalMessage && errorEvents.length > 0) {
		return {
			content: null,
			error: errorEvents[0],
			diagnostics: {
				eventsCount: events.length,
				errorEventsCount: errorEvents.length,
				tokenLength: token.length,
				contentSegmentsCount: contentSegments.length,
				textCandidatesCount: textCandidates.length,
				source: selectedSource
			}
		};
	}

	return {
		content: finalMessage,
		diagnostics: {
			eventsCount: events.length,
			errorEventsCount: errorEvents.length,
			tokenLength: token.length,
			contentSegmentsCount: contentSegments.length,
			textCandidatesCount: textCandidates.length,
			source: selectedSource
		}
	};
}

function safeStringify(value: unknown): string {
	try {
		return JSON.stringify(value);
	} catch {
		return String(value);
	}
}

function extractProviderErrorText(errorPayload: unknown): string {
	if (!errorPayload || typeof errorPayload !== 'object') return '';
	const candidate = (errorPayload as any).content ?? (errorPayload as any).message ?? '';
	return typeof candidate === 'string' ? candidate.trim() : '';
}

function isFatalProviderErrorPayload(errorPayload: unknown): boolean {
	if (!errorPayload || typeof errorPayload !== 'object') return false;
	const type = String((errorPayload as any).type ?? '').toLowerCase();
	if (type && type !== 'error') return false;
	const content = extractProviderErrorText(errorPayload).toLowerCase();
	if (!content) return false;
	return (
		content.includes('unexpected processing error') ||
		content.includes('erro inesperado de processamento') ||
		content.includes('invalid') ||
		content.includes('malformed')
	);
}

function isRateLimitText(value: string | null | undefined): boolean {
	const text = stripInvisible(value ?? '').trim();
	return text === 'Rate limit reached (429)';
}

function deriveRetryThreadId(baseThreadId: string, attempt: number, startedAt: number): string {
	if (attempt <= 1) return baseThreadId;
	const suffix = createHash('sha1')
		.update(`${baseThreadId}:${attempt}:${startedAt}`)
		.digest('hex')
		.slice(0, 8);
	const extra = `-${suffix}-${attempt}`;
	const maxLen = 120;
	let base = baseThreadId;
	if (base.length + extra.length > maxLen) {
		base = base.slice(0, Math.max(1, maxLen - extra.length));
	}
	return `${base}${extra}`;
}

export async function generateAIMessageIaedu(
	request: AiGenerateRequest,
	options?: { signal?: AbortSignal }
): Promise<AiGenerateResult> {
	const startedAt = Date.now();
	const debugRaw = isTruthyEnv(env.IAEDU_DEBUG_LOG_RAW);
	const maxAttempts = 2;
	const apiKey = IAEDU_API_KEY;
	if (!apiKey) {
		return {
			success: false,
			error: {
				code: 'unauthorized',
				message: 'IAEDU API key is not configured.',
				provider: 'iaedu'
			}
		};
	}

	const endpoint = normalizeEndpoint(IAEDU_ENDPOINT || DEFAULT_ENDPOINT);
	const channelId = IAEDU_CHANNEL_ID || '';
	const dynamicThreadId = request.providerThreadId?.trim() || '';
	const threadId = dynamicThreadId || IAEDU_THREAD_ID || '';

	if (!channelId) {
		return {
			success: false,
			error: {
				code: 'invalid_request',
				message: 'IAEDU channel id is not configured.',
				provider: 'iaedu'
			}
		};
	}

	if (!threadId) {
		return {
			success: false,
			error: {
				code: 'invalid_request',
				message: 'IAEDU thread id is not configured.',
				provider: 'iaedu'
			}
		};
	}

	const prompt = buildPrompt(request);
	const userInfo = buildUserInfo(request);
	const payloadSchema =
		request.promptPayload && typeof request.promptPayload === 'object'
			? ((request.promptPayload as Record<string, unknown>).schema ?? null)
			: null;
	const roleTitle =
		request.promptPayload && typeof request.promptPayload === 'object'
			? ((request.promptPayload as any)?.identity?.roleTitle ?? null)
			: null;

	console.log('[iaedu] request', {
		agentName: request.agentName ?? null,
		platformRole: request.agentRole,
		roleTitle,
		round: request.round,
		inputSource: resolveInputSource(request),
		promptLength: prompt.length,
		payloadSchema,
		threadSource: dynamicThreadId ? 'request' : 'env',
		threadSuffix: threadId ? threadId.slice(-8) : null,
		hasRagContext: Boolean(request.ragContext),
		endpoint,
		maxAttempts
	});

	try {
		for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
			if (attempt > 1) {
				await new Promise((r) => setTimeout(r, 700 * attempt));
				console.log('[iaedu] retrying', { attempt, elapsedMs: Date.now() - startedAt });
			}
			const threadIdForAttempt = deriveRetryThreadId(threadId, attempt, startedAt);
			const formData = new FormData();
			formData.append('channel_id', channelId);
			formData.append('thread_id', threadIdForAttempt);
			formData.append('user_info', userInfo);
			formData.append('message', prompt);

			const response = await fetch(endpoint, {
				method: 'POST',
				headers: {
					'x-api-key': apiKey
				},
				// Let fetch set multipart boundaries when using FormData.
				body: formData,
				signal: options?.signal
			});

			if (!response.ok) {
				const details = await response.text();
				if (response.status === 429 && attempt < maxAttempts) {
					console.log('[iaedu] rate limited (http)', {
						status: response.status,
						elapsedMs: Date.now() - startedAt,
						attempt
					});
					continue;
				}
				console.log('[iaedu] response error', {
					status: response.status,
					elapsedMs: Date.now() - startedAt,
					attempt
				});
				return {
					success: false,
					error: {
						code: response.status === 429 ? 'rate_limited' : 'provider_error',
						message: 'IAEDU request failed.',
						details,
						provider: 'iaedu'
					}
				};
			}

			const rawText = await response.text();
			console.log('[iaedu] response ok', {
				status: response.status,
				elapsedMs: Date.now() - startedAt,
				rawLength: rawText.length,
				attempt,
				threadSuffix: threadIdForAttempt ? threadIdForAttempt.slice(-8) : null
			});
			const { content, error, diagnostics } = parseIaeduResponse(rawText);
			console.log('[iaedu] parsed', {
				elapsedMs: Date.now() - startedAt,
				attempt,
				hasContent: Boolean(content),
				hasError: Boolean(error),
				...diagnostics
			});

			if (debugRaw && (error || isPlaceholderText(content))) {
				const lines = rawText
					.split('\n')
					.map((l) => l.trimEnd())
					.filter((l) => l.trim())
					.slice(0, 30);
				console.log('[iaedu] raw preview', {
					elapsedMs: Date.now() - startedAt,
					firstLines: lines
				});
			}

			if (error) {
				console.log('[iaedu] response parse error', {
					elapsedMs: Date.now() - startedAt,
					error: safeStringify(error).slice(0, 600),
					attempt
				});
				if (isFatalProviderErrorPayload(error)) {
					return {
						success: false,
						error: {
							code: 'provider_error',
							message: 'IAEDU returned an error response.',
							details: safeStringify(error).slice(0, 1200),
							provider: 'iaedu'
						}
					};
				}
				if (attempt < maxAttempts) continue;
				return {
					success: false,
					error: {
						code: 'provider_error',
						message: 'IAEDU returned an error response.',
						details: safeStringify(error).slice(0, 1200),
						provider: 'iaedu'
					}
				};
			}

			if (!content) {
				console.log('[iaedu] empty content', {
					elapsedMs: Date.now() - startedAt,
					attempt
				});
				if (attempt < maxAttempts) continue;
				return {
					success: false,
					error: {
						code: 'provider_error',
						message: 'IAEDU returned an empty response.',
						provider: 'iaedu'
					}
				};
			}

			// IAEDU sometimes returns rate-limit info as "content" instead of an HTTP 429.
			if (isRateLimitText(content)) {
				console.log('[iaedu] rate limited (content)', {
					elapsedMs: Date.now() - startedAt,
					attempt,
					threadSuffix: threadIdForAttempt ? threadIdForAttempt.slice(-8) : null
				});
				if (attempt < maxAttempts) continue;
				return {
					success: false,
					error: {
						code: 'rate_limited',
						message: 'IAEDU rate limit reached.',
						details: content,
						provider: 'iaedu'
					}
				};
			}

			if (isPlaceholderText(content)) {
				console.log('[iaedu] placeholder content', {
					elapsedMs: Date.now() - startedAt,
					attempt
				});
				if (debugRaw || attempt === maxAttempts) {
					console.log('[iaedu] placeholder raw snippet', {
						elapsedMs: Date.now() - startedAt,
						attempt,
						snippet: rawText.slice(0, 500)
					});
				}
				if (attempt < maxAttempts) continue;
				return {
					success: false,
					error: {
						code: 'provider_error',
						message: 'IAEDU returned a placeholder response.',
						details: content,
						provider: 'iaedu'
					}
				};
			}

			const success: AiGenerateSuccess = {
				success: true,
				provider: 'iaedu',
				model: 'iaedu',
				message: {
					content,
					agentRole: request.agentRole,
					round: request.round,
					createdAt: new Date().toISOString()
				}
			};

			console.log('[iaedu] success', {
				elapsedMs: Date.now() - startedAt,
				contentLength: content.length,
				attempt
			});
			return success;
		}

		return {
			success: false,
			error: {
				code: 'provider_error',
				message: 'IAEDU request failed.',
				provider: 'iaedu'
			}
		};
	} catch (error) {
		if (error instanceof Error && error.name === 'AbortError') {
			console.log('[iaedu] request aborted', {
				elapsedMs: Date.now() - startedAt
			});
			return {
				success: false,
				error: {
					code: 'timeout',
					message: 'IAEDU request timed out.',
					provider: 'iaedu'
				}
			};
		}
		console.log('[iaedu] request failed', {
			elapsedMs: Date.now() - startedAt,
			error: error instanceof Error ? error.message : String(error)
		});
		return {
			success: false,
			error: {
				code: 'provider_error',
				message: 'IAEDU request failed.',
				details: error instanceof Error ? error.message : String(error),
				provider: 'iaedu'
			}
		};
	}
}
