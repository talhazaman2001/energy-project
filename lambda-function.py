# Code for Lambda function to be used in Smart Energy Monitoring System

import json
import boto3
from datetime import datetime

# Initialise DynamoDB resource and table
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('EnergyData')

def lambda_handler(event, context):
    """
    AWS Lambda function to process energy consumption data from IoT devices.

    This function takes data from IoT devices, validates it, and stores it in DynamoDB.
    It also sends alerts via SNS if abnormal energy consumption is detected.
    """

    # Parse the incoming event (JSON)
    try:
        energy_data = json.loads(event['body'])
        device_id = energy_data['device_id']
        timestamp = energy_data.get('timestamp', datetime.now().isoformat())
        energy_usage = energy_data['energy_usage']

        # Store energy data in DynamoDB
        response = table.put_item(
            Item = {
                'device_id': device_id,
                'timestamp': timestamp,
                'energy_usage': energy_usage
            }
        )

        # If energy usage is above a threshold, send an alert
        if energy_usage > 1000: 
            send_alert (device_id, energy_usage)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Energy data processed successfully.',
                'device_id': device_id,
                'timestamp': timestamp,
                'energy_usage': energy_usage
            })
        }
    
    except Exception as e: 
        # Any exception during processing: missing value/failure to communicate with DynamoDB, function returns 500 status code & logs error.
        return {
            'statuscode': 500,
            'body': json.dumps({'error' : str(e)})
        }
    

def send_alert(device_id, energy_usage):
    """
    Sends an alert via SNS when abnormal energy consumption is detected.
    
    Args:
        device_id (str): The ID of the device with abnormal energy consumption.
        energy_usage (float): The energy usage value that triggered an alert.
    """
    sns = boto3.client('sns')
    topic_arn = 'arn:aws:sns:region:account-id:EnergyAlerts'
    message = (f'ALERT: Device {device_id} has abnormal energy consumption.\n'
               f'Energy Usage: {energy_usage} kWh')
    
    # Publish the message to SNS
    sns.publish(
        TopicArn = topic_arn,
        Message = message,
        Subject = 'Abnormal Energy Consumption Alert'
    )


