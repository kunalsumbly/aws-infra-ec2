import json
import boto3
import os
from datetime import datetime, timezone

def lambda_handler(event, context):
    """
    Lambda function to stop EC2 instances at scheduled times.
    Includes end date logic to automatically disable after 1 month.
    """
    
    # Get environment variables
    instance_ids_str = os.environ.get('INSTANCE_IDS', '')
    end_date_str = os.environ.get('END_DATE', '2025-08-31')
    
    # Parse instance IDs
    if not instance_ids_str:
        return {
            'statusCode': 400,
            'body': json.dumps('No instance IDs provided in environment variables')
        }
    
    instance_ids = [id.strip() for id in instance_ids_str.split(',') if id.strip()]
    
    # Check if current date is past the end date
    try:
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d').replace(tzinfo=timezone.utc)
        current_date = datetime.now(timezone.utc)
        
        if current_date > end_date:
            print(f"Current date {current_date.strftime('%Y-%m-%d')} is past end date {end_date_str}. Skipping instance stop.")
            return {
                'statusCode': 200,
                'body': json.dumps(f'Scheduling period ended on {end_date_str}. No action taken.')
            }
    except ValueError as e:
        print(f"Error parsing end date: {e}")
        return {
            'statusCode': 400,
            'body': json.dumps(f'Invalid end date format: {end_date_str}')
        }
    
    # Initialize EC2 client
    ec2 = boto3.client('ec2')
    
    try:
        # Get current instance states
        response = ec2.describe_instances(InstanceIds=instance_ids)
        
        instances_to_stop = []
        instance_states = {}
        
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                state = instance['State']['Name']
                instance_states[instance_id] = state
                
                if state == 'running':
                    instances_to_stop.append(instance_id)
                    print(f"Instance {instance_id} is running and will be stopped")
                else:
                    print(f"Instance {instance_id} is in state '{state}' - skipping")
        
        # Stop running instances
        if instances_to_stop:
            stop_response = ec2.stop_instances(InstanceIds=instances_to_stop)
            print(f"Stop request sent for instances: {instances_to_stop}")
            
            # Log the stopping instances
            stopping_instances = []
            for instance in stop_response['StoppingInstances']:
                stopping_instances.append({
                    'InstanceId': instance['InstanceId'],
                    'CurrentState': instance['CurrentState']['Name'],
                    'PreviousState': instance['PreviousState']['Name']
                })
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Successfully initiated stop for {len(instances_to_stop)} instances',
                    'stopped_instances': stopping_instances,
                    'all_instance_states': instance_states,
                    'execution_time': datetime.now(timezone.utc).isoformat()
                })
            }
        else:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No running instances found to stop',
                    'all_instance_states': instance_states,
                    'execution_time': datetime.now(timezone.utc).isoformat()
                })
            }
            
    except Exception as e:
        print(f"Error stopping instances: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to stop instances: {str(e)}',
                'execution_time': datetime.now(timezone.utc).isoformat()
            })
        }