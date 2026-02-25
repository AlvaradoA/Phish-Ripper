import json
import boto3
import urllib.request
import os
import re
from botocore.exceptions import ClientError

s3 = boto3.client('s3')
SECRET_NAME = os.environ['SECRET_NAME']
RESULTS_BUCKET = os.environ['RESULTS_BUCKET']

def get_secret():
    client = boto3.client('secretsmanager', region_name='us-east-1')
    try:
        response = client.get_secret_value(SecretId=SECRET_NAME)
        secret_dict = json.loads(response['SecretString'])
        return secret_dict['abuseipdb_key']
    except ClientError as e:
        print(f"Failed to retrieve secret: {e}")
        raise e

# Cache the key outside the handler for performance
ABUSEIPDB_API_KEY = get_secret()

def check_abuseipdb(ip_address):
    url = f"https://api.abuseipdb.com/api/v2/check?ipAddress={ip_address}&maxAgeInDays=90"
    headers = {
        'Accept': 'application/json',
        'Key': ABUSEIPDB_API_KEY
    }
    try:
        req = urllib.request.Request(url, headers=headers, method='GET')
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read())['data']
    except Exception as e:
        return {"error": str(e)}

def lambda_handler(event, context):
    record = event['Records'][0]
    src_bucket = record['s3']['bucket']['name']
    src_key = record['s3']['object']['key']
    
    obj = s3.get_object(Bucket=src_bucket, Key=src_key)
    email_data = json.loads(obj['Body'].read())
    text = email_data['text']
    
    ip_pattern = r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b'
    found_ips = list(set(re.findall(ip_pattern, text)))
    
    # Filter out local/private IPs
    public_ips = [ip for ip in found_ips if not ip.startswith(('10.', '192.168.', '127.', '172.16', '169.254'))]
    
    scan_results = {"extracted_ips": public_ips, "reports": {}}
    
    for ip in public_ips[:3]: # Limit to 3 to save quota
        scan_results["reports"][ip] = check_abuseipdb(ip)
        
    if not public_ips:
        scan_results["message"] = "No public IPs found in the email text."

    s3.put_object(
        Bucket=RESULTS_BUCKET,
        Key=src_key,
        Body=json.dumps(scan_results),
        ContentType='application/json'
    )