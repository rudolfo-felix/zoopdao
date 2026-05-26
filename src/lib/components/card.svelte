<script lang="ts">
	import type { Card } from '@/types';
	import { ZOOP_THEME_ASSET_PREFIX } from '$lib/config/theme';

	type CardWithAsset = Card & { assetType?: string };

	interface CardProps {
		card: CardWithAsset;
		className?: string;
	}

	let { card, className = '' }: CardProps = $props();
	let expanded = $state(false);
	let pinned = $state(false);
	const showMore = $derived(!!card.text && card.text.length > 220);

	const cardColors = {
		landmark: 'border-dark-deep',
		nature: 'border-sea-green',
		sense: 'border-sand',
		history: 'border-sand',
		action: 'border-driftwood'
	} as const;

	const cardFillColors: Record<string, string> = {
		landmark: '#D20A0A',
		nature: '#3CA5E6',
		sense: '#3CA03C',
		history: '#E6C800',
		action: '#E6C800',
		functionality: '#3CA5E6',
		'post-story': '#D20A0A'
	};

	let borderColor = cardColors[card.type as keyof typeof cardColors];
	const assetType = card.assetType ?? card.type;
	const fillColor = cardFillColors[assetType] ?? '#ffffff';

	const heightClass = $derived(showMore ? (expanded ? 'h-auto min-h-96' : 'h-96') : 'h-96');

	function openPreview() {
		if (!showMore) return;
		if (pinned) return;
		expanded = true;
	}

	function closePreview() {
		if (!showMore) return;
		if (pinned) return;
		expanded = false;
	}

	function togglePinned() {
		if (!showMore) return;
		pinned = !pinned;
		expanded = pinned ? true : false;
	}
</script>

<div
	class="relative w-64 {heightClass} rounded-xl border {borderColor} {className} flex flex-col overflow-hidden transition-[height] duration-200"
	style={`background-color: ${fillColor};`}
	onmouseenter={openPreview}
	onmouseleave={closePreview}
>
	<div
		class="pointer-events-none absolute inset-x-0 top-0 h-96 bg-cover bg-top"
		style={`background-image: url('${ZOOP_THEME_ASSET_PREFIX}/cards/${assetType}.svg');`}
	></div>
	<div class="relative z-10 flex h-full flex-col">
		<div class="h-24 w-full flex items-center pl-[4.5rem] pr-4">
			<h3 class="text-white font-bold leading-snug text-xl">
				{card.title}
			</h3>
		</div>
		<div class={`relative px-4 pb-4 ${showMore && !expanded ? 'flex-1 min-h-0' : ''}`}>
			<div
				class={`relative rounded-lg bg-white/95 px-4 py-3 ${showMore ? 'pb-10' : ''} [box-shadow:0_0_18px_18px_rgba(255,255,255,0.92)] ${
					showMore && !expanded ? 'h-full' : ''
				}`}
			>
				<span
					class={`block whitespace-pre-line break-words leading-7 text-[15px] text-zinc-700 ${showMore && !expanded ? 'line-clamp-10' : ''}`}
				>
					{card.text}
				</span>
				{#if showMore}
					<button
						type="button"
						class="absolute bottom-2 right-2 rounded-md border border-black/20 bg-white/90 px-2 py-1 text-xs font-semibold text-black hover:bg-yellow-200 active:bg-yellow-300"
						onmouseenter={openPreview}
						onclick={togglePinned}
					>
						{expanded ? 'Fechar' : 'Ver mais'}
					</button>
				{/if}
			</div>
		</div>
	</div>
</div>
