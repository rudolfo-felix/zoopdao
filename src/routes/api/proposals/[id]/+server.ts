import { supabase } from '$lib/supabase';
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

// GET: Fetch a single proposal by ID
export const GET: RequestHandler = async ({ params }) => {
	try {
		const proposalId = parseInt(params.id);
		
		if (isNaN(proposalId)) {
			return error(400, { message: 'Invalid proposal ID' });
		}
		
		const { data, error: dbError } = await supabase
			.from('proposals')
			.select('*')
			.eq('id', proposalId)
			.single();
		
		if (dbError) {
			console.error('Error fetching proposal:', dbError);
			return error(404, { message: 'Proposal not found' });
		}
		
		return json({ proposal: data }, { status: 200 });
	} catch (err) {
		console.error('Error in GET /api/proposals/[id]:', err);
		return error(500, { message: 'Internal server error' });
	}
};

