export type VotingPeriod = {
	id: string;
	label: string;
	startDate: Date;
	endDate: Date;
};

/**
 * Get voting periods for a given year
 * Quarterly meeting periods:
 * - March 16th to 20th
 * - June 20th to 24th
 * - September 21st to 25th
 * - December 14th to 18th
 * 
 * Also includes exceptional periods (not available for new proposals)
 */
export function getVotingPeriods(year: number = new Date().getFullYear()): VotingPeriod[] {
	return [
		{
			id: `march-${year}`,
			label: `March 16-20, ${year}`,
			startDate: new Date(year, 2, 16), // Month is 0-indexed
			endDate: new Date(year, 2, 20)
		},
		{
			id: `june-${year}`,
			label: `June 20-24, ${year}`,
			startDate: new Date(year, 5, 20),
			endDate: new Date(year, 5, 24)
		},
		{
			id: `september-${year}`,
			label: `September 21-25, ${year}`,
			startDate: new Date(year, 8, 21),
			endDate: new Date(year, 8, 25)
		},
		{
			id: `december-${year}`,
			label: `December 14-18, ${year}`,
			startDate: new Date(year, 11, 14),
			endDate: new Date(year, 11, 18)
		}
	];
}

/**
 * Get exceptional voting periods (not available for new proposals)
 */
export function getExceptionalVotingPeriods(): VotingPeriod[] {
	return [
		{
			id: 'january-2026-exceptional',
			label: 'January 12-16, 2026',
			startDate: new Date(2026, 0, 12),
			endDate: new Date(2026, 0, 16)
		}
	];
}

/**
 * Check if a proposal is currently open (within voting period)
 */
export function isProposalOpen(periodId: string, allPeriods: VotingPeriod[]): boolean {
	const period = allPeriods.find(p => p.id === periodId);
	if (!period) return false;
	
	const now = new Date();
	return now >= period.startDate && now <= period.endDate;
}

/**
 * Get proposal status (open/closed)
 */
export function getProposalStatus(periodId: string, allPeriods: VotingPeriod[]): 'open' | 'closed' {
	return isProposalOpen(periodId, allPeriods) ? 'open' : 'closed';
}

