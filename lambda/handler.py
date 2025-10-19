import json
import os
import re
import boto3
from botocore.config import Config
from typing import Dict, Any


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for prompt injection detection.

    Analyzes user input using AWS Bedrock to detect prompt injection attempts.

    Args:
        event: Lambda event containing 'user_input' field
        context: Lambda context

    Returns:
        Dict with 'safe' (bool) and 'reasoning' (str) fields

    Raises:
        KeyError: If required environment variables are missing
        ValueError: If environment variables have invalid values
    """
    # Get required environment variables - fail hard if not present
    prompt_template = os.environ['PROMPT_TEMPLATE']
    model_id = os.environ['MODEL_ID']
    max_tokens = int(os.environ['MAX_TOKENS'])
    temperature = float(os.environ['TEMPERATURE'])

    # Extract user input from event - fail hard if not present
    user_input = event['user_input']

    # Create the full prompt with user input
    full_prompt = f"{prompt_template}\n{user_input}\n=== END USER REQUEST ==="

    # Log the complete input being sent to the model
    print("="*80)
    print("MODEL INPUT (complete prompt sent to Bedrock):")
    print("="*80)
    print(full_prompt)
    print("="*80)

    # Configure boto3 client with retries and timeout
    config = Config(
        retries={
            'max_attempts': 5,
            'mode': 'adaptive'
        },
        read_timeout=300,  # 5 minutes
        connect_timeout=60
    )

    # Initialize Bedrock client with retry configuration
    bedrock_runtime = boto3.client('bedrock-runtime', config=config)

    # Call Bedrock Converse API
    response = bedrock_runtime.converse(
        modelId=model_id,
        messages=[
            {
                'role': 'user',
                'content': [
                    {
                        'text': full_prompt
                    }
                ]
            }
        ],
        inferenceConfig={
            'maxTokens': max_tokens,
            'temperature': temperature
        }
    )

    # Extract the model's response - fail hard if structure is unexpected
    output = response['output']
    message = output['message']
    content_blocks = message['content']

    if not content_blocks:
        print("ERROR: No content blocks in model response")
        print(f"Full response: {json.dumps(response, default=str)}")
        raise ValueError('No content blocks in model response')

    # Get the text from the first content block - fail hard if not present
    model_output = content_blocks[0]['text']

    # Log the raw model output for debugging
    print("="*80)
    print("MODEL OUTPUT (raw response from Bedrock):")
    print("="*80)
    print(model_output)
    print("="*80)

    # Parse and validate the response
    validation_result = validate_model_response(model_output)

    if not validation_result['valid']:
        print(f"VALIDATION FAILED: {validation_result['reason']}")
        return {
            'safe': False,
            'reasoning': f'Lambda deterministic failure: {validation_result["reason"]}'
        }

    # Extract the parsed JSON
    parsed_json = validation_result['parsed_json']

    # Return the model's assessment
    return {
        'safe': parsed_json['safe'],
        'reasoning': parsed_json['reasoning']
    }


def validate_model_response(model_output: str) -> Dict[str, Any]:
    """
    Validates that the model response meets all security criteria.

    Requirements:
    1. JSON is wrapped in ```json code fence (or is pure JSON)
    2. JSON parses correctly
    3. Exactly two keys: 'safe' and 'reasoning'
    4. 'safe' is a boolean
    5. 'reasoning' is a string
    6. No other text outside the JSON (except code fence)

    Args:
        model_output: Raw output from the model

    Returns:
        Dict with 'valid' (bool), 'reason' (str), and optionally 'parsed_json'
    """
    # Strip leading/trailing whitespace
    output = model_output.strip()

    # Check if output is wrapped in a code fence
    json_pattern = r'^```json\s*\n(.*?)\n```\s*$'
    match = re.match(json_pattern, output, re.DOTALL)

    if match:
        # Extract JSON from code fence
        json_str = match.group(1).strip()
    else:
        # Try to parse as raw JSON
        json_str = output

    # Attempt to parse JSON
    try:
        parsed = json.loads(json_str)
    except json.JSONDecodeError as e:
        return {
            'valid': False,
            'reason': f'Invalid JSON: {str(e)}',
            'parsed_json': None
        }

    # Validate that it's a dictionary
    if not isinstance(parsed, dict):
        return {
            'valid': False,
            'reason': 'JSON is not a dictionary',
            'parsed_json': None
        }

    # Validate exactly two keys
    if set(parsed.keys()) != {'safe', 'reasoning'}:
        return {
            'valid': False,
            'reason': f'JSON has incorrect keys: {list(parsed.keys())}. Expected exactly: safe, reasoning',
            'parsed_json': None
        }

    # Validate 'safe' is a boolean
    if not isinstance(parsed['safe'], bool):
        return {
            'valid': False,
            'reason': f'"safe" value is not a boolean, got {type(parsed["safe"]).__name__}',
            'parsed_json': None
        }

    # Validate 'reasoning' is a string
    if not isinstance(parsed['reasoning'], str):
        return {
            'valid': False,
            'reason': f'"reasoning" value is not a string, got {type(parsed["reasoning"]).__name__}',
            'parsed_json': None
        }

    # Check that there's no extra text outside the JSON/code fence
    if match:
        # If we matched a code fence, verify there's nothing else
        expected_output = f"```json\n{json_str}\n```"
        if output != expected_output:
            # There might be extra whitespace - let's be more lenient
            # Reconstruct what we expect and compare more carefully
            reconstructed = f"```json\n{json_str}\n```"
            if output.strip() != reconstructed.strip():
                return {
                    'valid': False,
                    'reason': 'Extra text detected outside JSON code fence',
                    'parsed_json': None
                }
    else:
        # For raw JSON, verify output matches the parsed JSON when re-serialized
        # This ensures no extra text
        if output != json_str:
            return {
                'valid': False,
                'reason': 'Extra text detected outside JSON',
                'parsed_json': None
            }

    # All validation passed
    return {
        'valid': True,
        'reason': 'Valid response',
        'parsed_json': parsed
    }
