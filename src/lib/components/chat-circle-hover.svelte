<script lang="ts">
	import { onMount } from 'svelte';

	type BoundsRect = { left: number; top: number; right: number; bottom: number };
	type CenterPoint = { x: number; y: number };

	const previewOrder: string[] = [];
	const previewRegistry = new Map<string, () => void>();
	const previewRankById = new Map<string, number>();
	let previewRankCounter = 0;

	function registerPreview(id: string, closeFn: () => void) {
		previewRegistry.set(id, closeFn);
	}

	function unregisterPreview(id: string) {
		previewRegistry.delete(id);
		previewRankById.delete(id);
		for (let i = previewOrder.length - 1; i >= 0; i -= 1) {
			if (previewOrder[i] === id) previewOrder.splice(i, 1);
		}
		previewTick += 1;
	}

	function closePreview(id: string) {
		previewRankById.delete(id);
		for (let i = previewOrder.length - 1; i >= 0; i -= 1) {
			if (previewOrder[i] === id) previewOrder.splice(i, 1);
		}
		previewTick += 1;
	}

	function openPreview(id: string, priority = 1) {
		if (!previewRegistry.has(id)) return;
		const currentRank = previewRankById.get(id);
		if (typeof currentRank === 'number' && currentRank === previewRankCounter && priority <= 1) {
			previewTick += 1;
			return;
		}
		previewRankCounter = Math.max(previewRankCounter, currentRank ?? 0) + Math.max(1, priority);
		previewRankById.set(id, previewRankCounter);
		for (let i = previewOrder.length - 1; i >= 0; i -= 1) {
			if (previewOrder[i] === id) previewOrder.splice(i, 1);
		}
		previewOrder.push(id);
		for (let i = previewOrder.length - 1; i >= 0; i -= 1) {
			if (previewOrder.indexOf(previewOrder[i]) !== i) previewOrder.splice(i, 1);
		}
		previewTick += 1;
	}

	interface ChatCircleHoverProps {
		text: string;
		isTyping?: boolean;
		typingStyle?: 'dots' | 'pulse';
		canHover?: boolean;
		variant?: 'ai' | 'user';
		bubbleClass?: string | null;
		forcePreview?: boolean;
		previewRank?: number;
		boundsRect?: BoundsRect | null;
		aquariumCenter?: CenterPoint | null;
		maxDiameter?: number | null;
	}

	let {
		text,
		isTyping = false,
		typingStyle = 'dots',
		canHover = false,
		variant = 'ai',
		bubbleClass = null,
		forcePreview = false,
		previewRank = 0,
		boundsRect = null,
		aquariumCenter = null,
		maxDiameter = null
	}: ChatCircleHoverProps = $props();

	let anchorEl: HTMLButtonElement | null = null;
	let rootEl: HTMLDivElement | null = null;
	let showChatModal = $state(false);
	let showHover = $state(false);
	let showPreview = $state(false);
	let lastSeenText = $state('');
	let previewTick = $state(0);
	let previewZ = $state(120);
	let hoverTargets = $state(0);
	let hoverStyle = $state('');
	let circleDiameter = $state(0);
	let docLang = $state('pt');
	let slotEl: HTMLElement | null = null;
	const previewId = `preview-${Math.random().toString(36).slice(2)}`;
	let wasForcePreview = $state(false);
	let lastForcePreview = $state(false);
	let forcePreviewSuppressed = $state(false);

	const lastText = $derived(text.trim());
	const hasText = $derived(lastText.length > 0);
	const showTyping = $derived(isTyping);
	const snippetMaxLetters = 3;
	const snippetText = $derived(snippet(lastText, snippetMaxLetters));
	const isExpandable = $derived(hasText && lastText.length > snippetMaxLetters);

	const bgClass = $derived(
		bubbleClass && bubbleClass.length > 0
			? bubbleClass
			: variant === 'user'
				? 'bg-deep-teal'
				: 'bg-blue-500'
	);
	const shadowClass = $derived(variant === 'user' ? 'shadow-lg' : 'shadow-lg');

	function snippet(t: string, maxLetters = 3) {
		const s = t.trim().replace(/\s+/g, ' ');
		if (s.length <= maxLetters) return s;
		return `${s.slice(0, Math.max(0, maxLetters))}…`;
	}

	function clamp(value: number, min: number, max: number) {
		return Math.max(min, Math.min(max, value));
	}

	function computeDiameter(textLength: number, minD: number, maxD: number) {
		const base = minD;
		const scaled = base + Math.sqrt(Math.max(0, textLength)) * 12;
		return clamp(scaled, minD, maxD);
	}

	function computeFontSize(diameter: number, textLength: number) {
		const bySize = diameter / 6.6;
		const lengthPenalty = Math.min(5, textLength / 70);
		return clamp(bySize - lengthPenalty, 11, 20);
	}

	function computePadding(diameter: number) {
		return clamp(Math.round(diameter * 0.12), 10, 26);
	}

	function resolveBounds() {
		let providedBounds: BoundsRect | null = null;
		if (boundsRect && boundsRect.right > boundsRect.left && boundsRect.bottom > boundsRect.top) {
			const width = boundsRect.right - boundsRect.left;
			const height = boundsRect.bottom - boundsRect.top;
			if (width >= 180 && height >= 180) {
				providedBounds = boundsRect;
			}
		}
		if (typeof document !== 'undefined') {
			const boundaryEl = document.querySelector('.avatar-boundary') as HTMLElement | null;
			if (boundaryEl) {
				const rect = boundaryEl.getBoundingClientRect();
				if (rect.width > 0 && rect.height > 0) {
					return {
						left: rect.left,
						top: rect.top,
						right: rect.right,
						bottom: rect.bottom
					};
				}
			}
		}
		if (providedBounds) return providedBounds;
		if (typeof window !== 'undefined') {
			return {
				left: 12,
				top: 12,
				right: window.innerWidth - 12,
				bottom: window.innerHeight - 12
			};
		}
		return null;
	}

	function updateHoverPosition() {
		if (!anchorEl || !rootEl) return;
		const bounds = resolveBounds();
		if (!bounds) return;
		const rootRect = rootEl.getBoundingClientRect();
		const rect = anchorEl.getBoundingClientRect();
		const anchorX = rect.left + rect.width / 2;
		const anchorY = rect.top + rect.height / 2;

		const viewportBounds = {
			left: 0,
			top: 0,
			right: window.innerWidth,
			bottom: window.innerHeight
		};
		let clampedBounds = {
			left: Math.max(bounds.left, viewportBounds.left),
			top: Math.max(bounds.top, viewportBounds.top),
			right: Math.min(bounds.right, viewportBounds.right),
			bottom: Math.min(bounds.bottom, viewportBounds.bottom)
		};
		if (
			clampedBounds.right - clampedBounds.left <= 0 ||
			clampedBounds.bottom - clampedBounds.top <= 0
		) {
			clampedBounds = viewportBounds;
		}

		const boundsPadding = 10;
		const safeBounds = {
			left: clampedBounds.left + boundsPadding,
			top: clampedBounds.top + boundsPadding,
			right: clampedBounds.right - boundsPadding,
			bottom: clampedBounds.bottom - boundsPadding
		};
		const boundsWidth = Math.max(0, safeBounds.right - safeBounds.left);
		const boundsHeight = Math.max(0, safeBounds.bottom - safeBounds.top);
		const boundsMax = Math.min(boundsWidth, boundsHeight);
		const proposedMax =
			typeof maxDiameter === 'number' && maxDiameter > 0 ? maxDiameter : boundsMax * 0.9;
		const maxD = Math.max(40, Math.min(proposedMax, boundsMax));
		const anchorSize = Math.max(rect.width, rect.height);
		const minPreviewDiameter = 120;
		let minD = Math.max(minPreviewDiameter, Math.max(56, anchorSize * 1.8));
		if (minD > maxD) minD = maxD;
		const diameter = computeDiameter(lastText.length, minD, Math.max(minD, maxD));
		const radius = diameter / 2;

		let cx = anchorX;
		let cy = anchorY;

		if (aquariumCenter) {
			const vx = aquariumCenter.x - cx;
			const vy = aquariumCenter.y - cy;
			const len = Math.hypot(vx, vy);
			if (len && len > 1) {
				const shift = Math.min(radius * 0.6, len);
				cx += (vx / len) * shift;
				cy += (vy / len) * shift;
			}
		}

		cx = clamp(cx, safeBounds.left + radius, safeBounds.right - radius);
		cy = clamp(cy, safeBounds.top + radius, safeBounds.bottom - radius);

		circleDiameter = Math.round(diameter);
		const left = cx - radius - rootRect.left;
		const top = cy - radius - rootRect.top;
		hoverStyle = `left:${left}px; top:${top}px; width:${diameter}px; height:${diameter}px;`;
	}

	function enterHover() {
		if (!canHover || showTyping || !isExpandable) return;
		hoverTargets += 1;
		showHover = true;
		requestAnimationFrame(updateHoverPosition);
	}

	function leaveHover() {
		hoverTargets = Math.max(0, hoverTargets - 1);
		if (hoverTargets === 0) showHover = false;
	}

	$effect(() => {
		if (!showHover) return;
		const update = () => requestAnimationFrame(updateHoverPosition);
		window.addEventListener('resize', update);
		window.addEventListener('scroll', update, true);
		return () => {
			window.removeEventListener('resize', update);
			window.removeEventListener('scroll', update, true);
		};
	});

	onMount(() => {
		if (typeof document === 'undefined') return;
		docLang = document.documentElement.lang || 'pt';
		slotEl = rootEl?.closest('.participant-slot') as HTMLElement | null;
		lastSeenText = lastText;
		registerPreview(previewId, () => {
			showPreview = false;
			closePreview(previewId);
		});
		return () => {
			unregisterPreview(previewId);
			if (slotEl) slotEl.classList.remove('is-previewing');
		};
	});

	$effect(() => {
		previewTick;
		if (showPreview) {
			const storedRank = previewRankById.get(previewId);
			const rank =
				typeof storedRank === 'number'
					? storedRank
					: Number.isFinite(previewRank)
						? previewRank
						: 0;
			previewZ = 2000 + Math.max(0, rank);
			if (slotEl) slotEl.style.zIndex = String(1000 + Math.max(0, rank));
			return;
		}
		if (forcePreview) {
			const rank = Number.isFinite(previewRank) ? previewRank : 0;
			previewZ = 120 + Math.max(0, rank);
			if (slotEl) slotEl.style.zIndex = String(90 + Math.max(0, rank));
			return;
		}
		previewZ = 120;
		if (slotEl) slotEl.style.zIndex = '';
	});

	$effect(() => {
		if (slotEl) {
			slotEl.classList.toggle('is-previewing', showHover || showPreview);
		}
	});

	$effect(() => {
		if (!showHover && !showPreview) return;
		boundsRect;
		aquariumCenter;
		maxDiameter;
		lastText;
		requestAnimationFrame(updateHoverPosition);
	});

	$effect(() => {
		if (!isExpandable) {
			if (showPreview) {
				showPreview = false;
				closePreview(previewId);
			}
			lastSeenText = lastText;
			return;
		}
		if (lastText && lastText !== lastSeenText) {
			lastSeenText = lastText;
			showPreview = true;
			openPreview(previewId, 1);
			requestAnimationFrame(updateHoverPosition);
		}
	});

	$effect(() => {
		if (forcePreview && !lastForcePreview) {
			forcePreviewSuppressed = false;
			if (!showPreview) {
				showPreview = true;
				openPreview(previewId, 1);
				requestAnimationFrame(updateHoverPosition);
			}
		}
		if (!forcePreview && lastForcePreview) {
			forcePreviewSuppressed = false;
		}
		lastForcePreview = forcePreview;
	});

	// Close when forced preview is lifted (without killing normal previews)
	$effect(() => {
		if (forcePreview) {
			wasForcePreview = true;
			return;
		}
		if (wasForcePreview && showPreview) {
			showPreview = false;
			closePreview(previewId);
			wasForcePreview = false;
		}
	});
</script>

<div bind:this={rootEl} class="relative" onmouseenter={enterHover} onmouseleave={leaveHover}>
	<button
		bind:this={anchorEl}
		type="button"
		class="h-9 w-9 rounded-full {bgClass} text-white {shadowClass} flex items-center justify-center overflow-hidden select-none"
		aria-label="Open message"
		onclick={() => {
			if (!hasText) return;
			if (isExpandable) {
				forcePreviewSuppressed = false;
				showPreview = true;
				openPreview(previewId, 1000);
				requestAnimationFrame(updateHoverPosition);
			}
		}}
	>
		{#if showTyping}
			{#if typingStyle === 'dots'}
				<div class="flex items-center gap-1">
					<span class="h-1.5 w-1.5 rounded-full bg-white/90 animate-bounce [animation-delay:0ms]"
					></span>
					<span class="h-1.5 w-1.5 rounded-full bg-white/90 animate-bounce [animation-delay:150ms]"
					></span>
					<span class="h-1.5 w-1.5 rounded-full bg-white/90 animate-bounce [animation-delay:300ms]"
					></span>
				</div>
			{:else}
				<span class="h-2 w-2 rounded-full bg-white/80 animate-pulse"></span>
			{/if}
		{:else}
			<span
				class="px-1 text-[10px] font-semibold leading-none whitespace-nowrap overflow-hidden text-ellipsis"
				>{snippet(lastText)}</span
			>
		{/if}
	</button>

	{#if isExpandable && (showHover || showPreview) && !showTyping}
		<div
			class="absolute rounded-full {bgClass} text-white shadow-2xl"
			style={`z-index:${previewZ}; ${hoverStyle}`}
			onmouseenter={enterHover}
			onmouseleave={leaveHover}
			onclick={() => {
				forcePreviewSuppressed = false;
				showPreview = true;
				openPreview(previewId, 1000);
				requestAnimationFrame(updateHoverPosition);
			}}
		>
			<button
				type="button"
				class="absolute left-1/2 -translate-x-1/2 top-2 h-6 w-6 rounded-full bg-white/30 text-white flex items-center justify-center text-sm font-bold shadow-md hover:bg-white/45"
				aria-label={docLang === 'pt' ? 'Fechar' : 'Close'}
				onclick={(event) => {
					event.stopPropagation();
					forcePreviewSuppressed = true;
					showPreview = false;
					closePreview(previewId);
				}}
			>
				×
			</button>
			<div
				class="h-full w-full rounded-full flex items-center justify-center p-5"
			>
				<div
					class="max-w-[80%] text-center overflow-hidden"
					style={`--circle-font:${computeFontSize(circleDiameter, lastText.length)}px;`}
					lang={docLang}
				>
					<div
						class="text-sm leading-relaxed text-white"
						style="text-justify: inter-word; text-align-last: center; hyphens: auto; word-break: normal; overflow-wrap: break-word;"
					>
						{lastText}
					</div>
				</div>
			</div>
		</div>
	{/if}

	{#if showChatModal && hasText}
		<div
			class="fixed inset-0 z-[200] flex items-center justify-center p-4"
			role="dialog"
			aria-modal="true"
			onclick={() => (showChatModal = false)}
			onkeydown={(e) => {
				if (e.key === 'Escape') showChatModal = false;
			}}
			tabindex="0"
		>
			<div class="absolute inset-0 bg-black/40"></div>
			<div
				class="relative w-full max-w-[560px] rounded-2xl {bgClass} text-white shadow-2xl px-5 py-4"
				onclick={(e) => e.stopPropagation()}
			>
				<button
					type="button"
					class="absolute right-3 top-3 h-9 w-9 rounded-full bg-white/15 hover:bg-white/25"
					aria-label="Close"
					onclick={() => (showChatModal = false)}
				>
					<span class="sr-only">Close</span>
					<span aria-hidden="true" class="text-lg leading-none">×</span>
				</button>
				<div class="text-sm whitespace-normal break-words pr-10">{lastText}</div>
			</div>
		</div>
	{/if}
</div>
