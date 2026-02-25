import json
import boto3
import os

s3 = boto3.client('s3')
RESULTS_BUCKET = os.environ['RESULTS_BUCKET']

def lambda_handler(event, context):
    scan_id = event.get('queryStringParameters', {}).get('id')
    
    try:
        obj = s3.get_object(Bucket=RESULTS_BUCKET, Key=f"{scan_id}.json")
        report = json.loads(obj['Body'].read())
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(report)
        }
    except s3.exceptions.NoSuchKey:
        return {
            'statusCode': 202,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'status': 'scanning'})
        }
    except Exception as e:
        return {'statusCode': 500, 'body': str(e)}