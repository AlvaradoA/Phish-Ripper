import json
import boto3
import uuid
import os

s3 = boto3.client('s3')
RAW_BUCKET = os.environ['RAW_BUCKET']

def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])
        email_content = body.get('email_text', '')
        
        scan_id = str(uuid.uuid4())
        
        s3.put_object(
            Bucket=RAW_BUCKET,
            Key=f"{scan_id}.json",
            Body=json.dumps({"text": email_content}),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'scan_id': scan_id, 'message': 'Upload successful, scanning started.'})
        }
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}