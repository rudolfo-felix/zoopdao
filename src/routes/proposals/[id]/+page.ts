import { error } from '@sveltejs/kit';
import type { PageLoad } from './$types';

export const load: PageLoad = async ({ params, fetch }) => {
	try {
		const proposalId = params.id;
		
		// Fetch proposal
		const response = await fetch(`/api/proposals/${proposalId}`);
		if (!response.ok) {
			return error(404, { message: 'Proposal not found' });
		}
		
		const { proposal } = await response.json();
		
		return {
			proposal
		};
	} catch (err) {
		console.error('Error loading proposal:', err);
		return error(500, { message: 'Failed to load proposal' });
	}
};

