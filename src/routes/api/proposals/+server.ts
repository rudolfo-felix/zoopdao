import { supabase } from '$lib/supabase';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

// GET: Fetch proposals for current voting period
export const GET: RequestHandler = async ({ url }) => {
	try {
		const votingPeriodId = url.searchParams.get('voting_period_id');
		const currentYear = new Date().getFullYear();
		
		// Get current voting periods
		const periods = [
			`march-${currentYear}`,
			`june-${currentYear}`,
			`september-${currentYear}`,
			`december-${currentYear}`
		];
		
		// If specific period requested, filter by it; otherwise get all current year periods
		const periodFilter = votingPeriodId 
			? periods.includes(votingPeriodId) 
				? votingPeriodId 
				: null
			: periods;
		
		if (!periodFilter) {
			return json({ proposals: [] }, { status: 200 });
		}
		
		let query = supabase
			.from('proposals')
			.select('*')
			.order('created_at', { ascending: false });
		
		if (Array.isArray(periodFilter)) {
			query = query.in('voting_period_id', periodFilter);
		} else {
			query = query.eq('voting_period_id', periodFilter);
		}
		
		const { data, error } = await query;
		
		if (error) {
			console.error('Error fetching proposals:', error);
			return json({ error: error.message }, { status: 500 });
		}
		
		return json({ proposals: data || [] }, { status: 200 });
	} catch (error) {
		console.error('Error in GET /api/proposals:', error);
		return json({ error: 'Internal server error' }, { status: 500 });
	}
};

// POST: Create a new proposal
export const POST: RequestHandler = async ({ request }) => {
	try {
		const body = await request.json();
		const { title, objectives, functionalities, discussion, voting_period_id } = body;
		
		// Validation
		if (!title || !objectives || !functionalities || !discussion || !voting_period_id) {
			return json({ error: 'Missing required fields' }, { status: 400 });
		}
		
		// Validate objectives structure
		if (!Array.isArray(objectives) || objectives.length < 2) {
			return json({ error: 'At least 2 objectives are required' }, { status: 400 });
		}
		
		// Validate each objective has required structure
		for (const objective of objectives) {
			if (!objective.value || !Array.isArray(objective.preconditions)) {
				return json({ error: 'Invalid objective structure' }, { status: 400 });
			}
			if (objective.preconditions.length < 2) {
				return json({ error: 'Each objective must have at least 2 preconditions' }, { status: 400 });
			}
			for (const precondition of objective.preconditions) {
				if (!precondition.value || 
				    !Array.isArray(precondition.indicativeSteps) || 
				    !Array.isArray(precondition.keyIndicators)) {
					return json({ error: 'Invalid precondition structure' }, { status: 400 });
				}
				if (precondition.indicativeSteps.length < 1 || precondition.keyIndicators.length < 1) {
					return json({ error: 'Each precondition must have at least 1 indicative step and 1 key indicator' }, { status: 400 });
				}
			}
		}
		
		// Get current user
		const { data: { user }, error: userError } = await supabase.auth.getUser();
		
		const { data, error } = await supabase
			.from('proposals')
			.insert({
				title,
				objectives: objectives,
				functionalities,
				discussion,
				voting_period_id,
				user_id: user?.id || null
			})
			.select()
			.single();
		
		if (error) {
			console.error('Error creating proposal:', error);
			return json({ error: error.message }, { status: 500 });
		}
		
		return json({ proposal: data }, { status: 201 });
	} catch (error) {
		console.error('Error in POST /api/proposals:', error);
		return json({ error: 'Internal server error' }, { status: 500 });
	}
};

