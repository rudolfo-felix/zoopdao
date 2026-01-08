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

