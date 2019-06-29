import os
import boto3


def lambda_handler(event, context):
    n = int(event['Records'][0]['body'])
    f = 1
    for i in range(1, n + 1):
        f = f * i
    print(n, '! = ', f)

    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table(os.environ['dynamodbtable'])
    table.put_item(Item={'number': n, 'result': str(f)})
