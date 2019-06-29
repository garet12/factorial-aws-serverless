import json
import os
import boto3
from boto3.dynamodb.conditions import Key


def lambda_handler(event, context):
    try:
        number = int(event['queryStringParameters']['number'])
    except KeyError as e:
        print('Wrong parameter!')
        return {
            "statusCode": 400,
            "body": json.dumps({
                "message": "Parameter 'number' is missing from request!",
            }),
        }

    if number < 0:
        print('{} is smaller than 1!'.format(number))
        return {
            "statusCode": 400,
            "body": json.dumps({
                "message": "Given number is smaller than 1!",
            }),
        }

    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table(os.environ['dynamodbtable'])
    response = table.query(KeyConditionExpression=Key('number').eq(number))

    if response['Count'] > 0:
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "The result for {} is {}!".format(number, response['Items'][0]['result']),
            }),
        }

    sqs = boto3.client('sqs')
    sqs.send_message(QueueUrl=os.environ['sqs'], MessageBody=str(number))

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Result for {} could not be found. It will be calculated as soon as possible!".format(number),
        }),
    }
