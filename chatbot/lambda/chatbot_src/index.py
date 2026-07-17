import json
import boto3
import os

bedrock_agent = boto3.client('bedrock-agent-runtime')

KB_ID = os.environ.get('KNOWLEDGE_BASE_ID', '')
MODEL_ARN = os.environ.get('MODEL_ARN', 'arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-haiku-20240307-v1:0')


def handler(event, context):
    """
    Chatbot RAG: recibe pregunta, consulta Knowledge Base, responde con contexto.
    """
    # Parsear input
    body = json.loads(event.get('body', '{}'))
    question = body.get('question', body.get('q', ''))

    if not question:
        return response(400, {'error': 'Falta el campo "question"'})

    if not KB_ID:
        return response(500, {'error': 'KNOWLEDGE_BASE_ID no configurado'})

    try:
        # RAG: Retrieve and Generate
        result = bedrock_agent.retrieve_and_generate(
            input={'text': question},
            retrieveAndGenerateConfiguration={
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': KB_ID,
                    'modelArn': MODEL_ARN,
                    'retrievalConfiguration': {
                        'vectorSearchConfiguration': {
                            'numberOfResults': 5
                        }
                    }
                }
            }
        )

        answer = result['output']['text']
        sources = []
        for citation in result.get('citations', []):
            for ref in citation.get('retrievedReferences', []):
                loc = ref.get('location', {}).get('s3Location', {})
                sources.append(loc.get('uri', 'unknown'))

        return response(200, {
            'answer': answer,
            'sources': list(set(sources)),
            'question': question
        })

    except Exception as e:
        print(f"Error: {e}")
        return response(500, {'error': str(e), 'question': question})


def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        'body': json.dumps(body, ensure_ascii=False)
    }
