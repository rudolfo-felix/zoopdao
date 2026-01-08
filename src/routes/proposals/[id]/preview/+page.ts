import { error } from '@sveltejs/kit';
import type { PageLoad } from './$types';
import { getVotingPeriods, getExceptionalVotingPeriods, getProposalStatus } from '$lib/data/voting-periods';

export const load: PageLoad = async ({ params, fetch }) => {
	try {
		const proposalId = params.id;
		
		// Fetch proposal
		const response = await fetch(`/api/proposals/${proposalId}`);
		if (!response.ok) {
			return error(404, { message: 'Proposal not found' });
		}
		
		const { proposal } = await response.json();
		
		// Get voting periods to determine status
		const currentYear = new Date().getFullYear();
		const allPeriods = [...getVotingPeriods(currentYear), ...getExceptionalVotingPeriods()];
		const status = getProposalStatus(proposal.voting_period_id, allPeriods);
		
		return {
			proposal,
			status,
			allPeriods
		};
	} catch (err) {
		console.error('Error loading proposal preview:', err);
		return error(500, { message: 'Failed to load proposal' });
	}
};

