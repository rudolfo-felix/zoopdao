import { HuggingFaceInferenceEmbeddings } from '@langchain/community/embeddings/hf';
import { env } from '$env/dynamic/private';

const DEFAULT_EMBEDDING_MODEL = env.API_EMBEDDING_MODEL || 'BAAI/bge-m3';

export function createHuggingFaceEmbeddings() {
	const apiKey = env.HF_TOKEN || env.HUGGINGFACEHUB_API_KEY;
	if (!apiKey) {
		throw new Error('HF_TOKEN is not configured.');
	}

	return new HuggingFaceInferenceEmbeddings({
		model: DEFAULT_EMBEDDING_MODEL,
		apiKey,
		provider: 'hf-inference'
	});
}
