import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';
import { ingestDocuments } from '$lib/server/rag-ingest';

const ingestSchema = z.object({
	proposalId: z.number().int().positive(),
	round: z.number().int().min(0).max(7),
	userId: z.string().min(1),
	files: z.array(
		z.object({
			storagePath: z.string().min(1),
			filename: z.string().min(1),
			mimeType: z.string().optional().nullable(),
			sizeBytes: z.number().int().nonnegative().optional().nullable()
		})
	)
});

export const POST: RequestHandler = async ({ request }) => {
	try {
		const body = await request.json();
		const payload = ingestSchema.parse(body);
		const results = await ingestDocuments(payload);
		// ingestion results returned
		return json({ success: true, results });
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		console.error('[rag-ingest] failed', { error: message, errorObj: error });
		return json({ success: false, error: message }, { status: 400 });
	}
};
