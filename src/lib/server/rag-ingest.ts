import { Document } from '@langchain/core/documents';
import { RecursiveCharacterTextSplitter } from '@langchain/textsplitters';
import { getSupabaseAdmin } from './supabase-admin';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, extname } from 'node:path';
import { createHuggingFaceEmbeddings } from './openrouter-embeddings';
import {
	RAG_ALLOWED_EXTENSIONS,
	RAG_MAX_FILE_SIZE_BYTES,
	RAG_MAX_FILES_PER_ROUND
} from '$lib/rag/constants';

const DOCUMENTS_BUCKET = 'discussion-documents';
export interface IngestFilePayload {
	storagePath: string;
	filename: string;
	mimeType?: string | null;
	sizeBytes?: number | null;
}

export interface IngestRequestPayload {
	proposalId: number;
	round: number;
	userId?: string | null;
	files: IngestFilePayload[];
}

type IngestResult = {
	storagePath: string;
	documentId?: number;
	status: 'indexed' | 'failed';
	error?: string;
	chunkCount?: number;
};

type ChunkBuildResult = {
	rows: Array<{
		document_id: number;
		proposal_id: number;
		round: number;
		chunk_index: number;
		content: string;
		embedding: number[];
		metadata: Record<string, unknown>;
	}>;
	chunkCount: number;
};

async function loadWithTempFile<T>(
	buffer: Buffer,
	extension: string,
	loader: (filePath: string) => Promise<T>
): Promise<T> {
	const dir = await mkdtemp(join(tmpdir(), 'rag-upload-'));
	const filePath = join(dir, `upload${extension}`);
	try {
		await writeFile(filePath, buffer);
		return await loader(filePath);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
}

async function loadDocumentsFromBuffer(
	buffer: Buffer,
	filename: string,
	extension: string
): Promise<Document[]> {
	if (extension === '.txt' || extension === '.md' || extension === '.csv') {
		return [
			new Document({
				pageContent: buffer.toString('utf-8'),
				metadata: { source: filename }
			})
		];
	}

	if (extension === '.pdf') {
		return loadWithTempFile(buffer, extension, async (filePath) => {
			const module = await import('@langchain/community/document_loaders/fs/pdf');
			const Loader = (module as any).PDFLoader;
			if (!Loader) {
				throw new Error('PDFLoader is not available.');
			}
			const loader = new Loader(filePath);
			return loader.load();
		});
	}

	if (extension === '.docx') {
		return loadWithTempFile(buffer, extension, async (filePath) => {
			const module = await import('@langchain/community/document_loaders/fs/docx');
			const Loader = (module as any).DocxLoader;
			if (!Loader) {
				throw new Error('DocxLoader is not available.');
			}
			const loader = new Loader(filePath);
			return loader.load();
		});
	}

	if (extension === '.pptx') {
		return loadWithTempFile(buffer, extension, async (filePath) => {
			const module = await import('@langchain/community/document_loaders/fs/pptx');
			const Loader = (module as any).PptxLoader ?? (module as any).PPTXLoader;
			if (!Loader) {
				throw new Error('PptxLoader is not available.');
			}
			const loader = new Loader(filePath);
			return loader.load();
		});
	}

	throw new Error(`Unsupported file type: ${extension}`);
}

function isSupportedExtension(filename: string): boolean {
	const extension = extname(filename).toLowerCase();
	return RAG_ALLOWED_EXTENSIONS.includes(extension as (typeof RAG_ALLOWED_EXTENSIONS)[number]);
}

async function buildChunksFromBuffer(params: {
	buffer: Buffer;
	filename: string;
	proposalId: number;
	round: number;
	documentId: number;
	storagePath: string;
	userId?: string | null;
}): Promise<ChunkBuildResult> {
	const { buffer, filename, proposalId, round, documentId, storagePath, userId } = params;
	const extension = extname(filename).toLowerCase();
	const rawDocs = await loadDocumentsFromBuffer(buffer, filename, extension);
	const splitter = new RecursiveCharacterTextSplitter({
		chunkSize: 1000,
		chunkOverlap: 200
	});
	const chunkDocs = await splitter.splitDocuments(rawDocs);

	const enrichedChunks = chunkDocs.map((doc, index) => {
		return new Document({
			pageContent: doc.pageContent,
			metadata: {
				...doc.metadata,
				proposal_id: proposalId,
				round,
				document_id: documentId,
				user_id: userId ?? null,
				filename,
				storage_path: storagePath,
				chunk_index: index
			}
		});
	});

	const embeddings = createHuggingFaceEmbeddings();
	const embeddingsResult = await embeddings.embedDocuments(
		enrichedChunks.map((doc) => doc.pageContent)
	);

	const rows = enrichedChunks.map((doc, index) => ({
		document_id: documentId,
		proposal_id: proposalId,
		round,
		chunk_index: index,
		content: doc.pageContent,
		embedding: embeddingsResult[index],
		metadata: doc.metadata
	}));

	return { rows, chunkCount: rows.length };
}

export async function ingestDocuments(payload: IngestRequestPayload): Promise<IngestResult[]> {
	const supabaseAdmin = getSupabaseAdmin();

	const results: IngestResult[] = [];

	const { count, error: countError } = await supabaseAdmin
		.from('documents')
		.select('id', { count: 'exact', head: true })
		.eq('proposal_id', payload.proposalId)
		.eq('round', payload.round);

	if (countError) {
		throw new Error(countError.message);
	}

	if ((count ?? 0) + payload.files.length > RAG_MAX_FILES_PER_ROUND) {
		throw new Error('upload-limit-exceeded');
	}

	for (const file of payload.files) {
		const baseResult: IngestResult = { storagePath: file.storagePath, status: 'failed' };
		let createdDocumentId: number | null = null;
			try {
			if (!isSupportedExtension(file.filename)) {
				results.push({ ...baseResult, error: 'unsupported-file-type' });
				continue;
			}

			if (
				typeof file.sizeBytes === 'number' &&
				file.sizeBytes > RAG_MAX_FILE_SIZE_BYTES
			) {
				results.push({ ...baseResult, error: 'file-too-large' });
				continue;
			}

			const { data: docRow, error: docError } = await supabaseAdmin
				.from('documents')
				.insert({
					proposal_id: payload.proposalId,
					round: payload.round,
					user_id: payload.userId,
					filename: file.filename,
					storage_path: file.storagePath,
					mime_type: file.mimeType ?? null,
					size_bytes: file.sizeBytes ?? null,
					metadata: { status: 'pending' }
				})
				.select()
				.single();

			if (docError || !docRow) {
				throw new Error(docError?.message ?? 'Failed to create document record.');
			}
			createdDocumentId = docRow.id;

			const { data: fileData, error: downloadError } = await supabaseAdmin.storage
				.from(DOCUMENTS_BUCKET)
				.download(file.storagePath);

			if (downloadError || !fileData) {
				throw new Error(downloadError?.message ?? 'Failed to download document.');
			}

			// downloaded file

			const buffer = Buffer.from(await fileData.arrayBuffer());
			const { rows, chunkCount } = await buildChunksFromBuffer({
				buffer,
				filename: file.filename,
				proposalId: payload.proposalId,
				round: payload.round,
				documentId: docRow.id,
				storagePath: file.storagePath,
				userId: payload.userId
			});

			// chunks built

			const { error: chunkError } = await supabaseAdmin.from('document_chunks').insert(rows);
			if (chunkError) {
				throw new Error(chunkError.message);
			}

			await supabaseAdmin
				.from('documents')
				.update({ metadata: { status: 'indexed', chunk_count: chunkCount } })
				.eq('id', docRow.id);

			results.push({
				storagePath: file.storagePath,
				documentId: docRow.id,
				status: 'indexed',
				chunkCount
			});
			// indexed successfully
		} catch (error) {
			const errorMessage = error instanceof Error ? error.message : String(error);
			// Log full error and stack for diagnostics
			console.error('[rag-ingest] file processing error', {
				storagePath: file.storagePath,
				filename: file.filename,
				sizeBytes: file.sizeBytes,
				error,
				stack: (error as any)?.stack
			});
			if (createdDocumentId) {
				await supabaseAdmin
					.from('documents')
					.update({ metadata: { status: 'failed', error: errorMessage } })
					.eq('id', createdDocumentId);
			}
			results.push({ ...baseResult, error: errorMessage });
			// processing failed for this file
		}
	}

	return results;
}

export async function reindexDocument(documentId: number) {
	const supabaseAdmin = getSupabaseAdmin();
	const { data: docRow, error } = await supabaseAdmin
		.from('documents')
 		.select('id, proposal_id, round, filename, storage_path, metadata, user_id')
		.eq('id', documentId)
		.single();

	if (error || !docRow) {
		throw new Error('document-not-found');
	}

	try {
		await supabaseAdmin
			.from('documents')
			.update({ metadata: { ...(docRow.metadata ?? {}), status: 'pending' } })
			.eq('id', documentId);

		const { data: fileData, error: downloadError } = await supabaseAdmin.storage
			.from(DOCUMENTS_BUCKET)
			.download(docRow.storage_path);

		if (downloadError || !fileData) {
			throw new Error(downloadError?.message ?? 'Failed to download document.');
		}

		const buffer = Buffer.from(await fileData.arrayBuffer());
		const { rows, chunkCount } = await buildChunksFromBuffer({
			buffer,
			filename: docRow.filename,
			proposalId: docRow.proposal_id,
			round: docRow.round,
			documentId: docRow.id,
			storagePath: docRow.storage_path,
			userId: docRow.user_id
		});

		const { error: deleteError } = await supabaseAdmin
			.from('document_chunks')
			.delete()
			.eq('document_id', docRow.id);

		if (deleteError) {
			throw new Error(deleteError.message);
		}

		const { error: insertError } = await supabaseAdmin.from('document_chunks').insert(rows);
		if (insertError) {
			throw new Error(insertError.message);
		}

		await supabaseAdmin
			.from('documents')
			.update({ metadata: { status: 'indexed', chunk_count: chunkCount } })
			.eq('id', docRow.id);

		// reindex complete
		return { documentId: docRow.id, chunkCount };
	} catch (error) {
		const errorMessage = error instanceof Error ? error.message : String(error);
		await supabaseAdmin
			.from('documents')
			.update({ metadata: { status: 'failed', error: errorMessage } })
			.eq('id', docRow.id);
		// reindex failed
		throw error;
	}
}

export async function deleteDocument(params: { documentId?: number; storagePath: string }) {
	const supabaseAdmin = getSupabaseAdmin();
	// delete start

	await supabaseAdmin.storage.from(DOCUMENTS_BUCKET).remove([params.storagePath]);

	if (params.documentId) {
		const { error } = await supabaseAdmin.from('documents').delete().eq('id', params.documentId);
		if (error) {
			throw new Error(error.message);
		}
	}
	// delete complete
}
