<script lang="ts">
	import CharacterOption from '@/components/character-option.svelte';
	import Button from '@/components/ui/button/button.svelte';
	import { GameLobbyState } from '@/state/game-lobby-state.svelte';
	import { CHARACTER_CATEGORIES, getCharacterCategory, type CharacterCategory } from '@/types';
	import type { PageData } from './$types';
	import { m } from '@src/paraglide/messages.js';
	import clickSound from '@/sounds/click.mp3';
	import { onMount } from 'svelte';

	let click: HTMLAudioElement;

	onMount(() => {
		click = new Audio(clickSound);
		click.volume = 0.5;
	});

	let { data }: { data: PageData } = $props();

	let gameState = new GameLobbyState(data.game, data.players, data.playerId);
	const currentPlayer = $derived(gameState.players.find((player) => player.id === data.playerId))!;

	// Default to human category and skip directly to character selection
	let selectedCategory = $state<CharacterCategory>('human');

	onMount(() => {
		if (currentPlayer.character) {
			selectedCategory = getCharacterCategory(currentPlayer.character);
		}
	});
</script>

<div class="h-full flex flex-col items-center justify-center bg-white relative">
	<div
		class="sticky top-0 z-10 w-full bg-white border-b shadow-sm py-2 px-4 flex justify-between items-center"
	>
		<div class="bg-dark-green p-2 flex flex-col items-center justify-center rounded-lg text-center">
			<p class="text-white md:text-sm text-xs font-medium">Lobby code</p>
			<p class="text-white lg:text-4xl md:text-xl text-md font-bold">{data.game.code}</p>
		</div>

		<div class="flex gap-3">
			<div class="flex items-center justify-center">
				{#if gameState.state === 'waiting' && currentPlayer.nickname === null}
					<!-- Back button removed as category selection is hidden -->
				{:else if !currentPlayer.is_owner}
					<p class="text-dark-green font-bold text-center px-2">
						Waiting for host to start the game...
					</p>
				{/if}

				{#if currentPlayer.is_owner}
					{#if gameState.state === 'ready'}
						<p class="text-dark-green font-bold text-center px-2">All players are ready!</p>
					{/if}
					<Button
						size="default"
						disabled={gameState.state !== 'ready'}
						onclick={() => {
							click.play();
							gameState.startGame();
						}}
					>
						{m.start_game()}
					</Button>
				{/if}
			</div>
		</div>
	</div>

	<!-- Character selection (category selection hidden, defaulting to human) -->
	<p class="text-dark-green text-lg font-bold my-2">{m.select_character()}</p>
	<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-10">
		{#each CHARACTER_CATEGORIES[selectedCategory] as character}
			{@const player = gameState.players.find((player) => player.character === character)}
			{@const isReady = currentPlayer.nickname !== null}
			<CharacterOption
				{character}
				{player}
				selected={currentPlayer.character === character}
				disabled={isReady && currentPlayer.character !== character}
				onSelect={() => gameState.updatePlayerCharacter(character)}
				onReady={(nickname, description) =>
					gameState.updatePlayerNicknameDescription(nickname, description)}
			/>
		{/each}
	</div>
</div>
