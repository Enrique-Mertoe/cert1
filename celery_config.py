from celery import Celery
import os

# Docker Redis configuration
REDIS_HOST = os.getenv('REDIS_HOST', 'redis')  # Using Docker service name
REDIS_PORT = os.getenv('REDIS_PORT', '6379')  # Using internal Redis port
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', None)
REDIS_DB = os.getenv('REDIS_DB', '0')

# Construct Redis URL
redis_url = f"redis://{f':{REDIS_PASSWORD}@' if REDIS_PASSWORD else ''}{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}"

# Initialize Celery
celery = Celery('vpn_tasks',
                broker=redis_url,
                backend=redis_url)

# Configure Celery
celery.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='UTC',
    enable_utc=True,
    task_track_started=True,
    task_time_limit=300,  # 5 minutes
    worker_max_tasks_per_child=1,  # Restart worker after each task
    broker_connection_retry_on_startup=True,
    broker_connection_retry=True,
    broker_connection_max_retries=10
)
