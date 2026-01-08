import type { PageLoad } from './$types';

export const load: PageLoad = async ({ fetch }) => {
	try {
		// Fetch proposals for current voting period
		const response = await fetch('/api/proposals');
		if (!response.ok) {
			return { proposals: [] };
		}
		const data = await response.json();
		return { proposals: data.proposals || [] };
	} catch (error) {
		console.error('Error loading proposals:', error);
		return { proposals: [] };
	}
};

