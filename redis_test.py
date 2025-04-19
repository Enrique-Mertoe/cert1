#!/usr/bin/env python3
import sys

try:
    import redis
except ImportError:
    print("❌ Python Redis package not found")
    print("Please install it with: sudo apt-get install python3-redis")
    sys.exit(1)


def test_redis_connection(host='localhost', port=6379):
    try:
        # Attempt to connect to Redis
        r = redis.Redis(host=host, port=port, db=0)

        # Test if Redis is responsive by setting and getting a value
        r.set('test_key', 'connection_successful')
        result = r.get('test_key')

        if result == b'connection_successful':
            print(f"✅ Successfully connected to Redis on {host}:{port}")
            r.delete('test_key')
            return True
        else:
            print(f"❌ Connected to Redis on {host}:{port}, but data operations failed")
            return False

    except redis.ConnectionError as e:
        print(f"❌ Failed to connect to Redis on {host}:{port}")
        print(f"Error: {e}")
        return False
    except Exception as e:
        print(f"❌ Unknown error while connecting to Redis on {host}:{port}")
        print(f"Error: {e}")
        return False


if __name__ == "__main__":
    # Allow command-line arguments to specify host and port
    host = sys.argv[1] if len(sys.argv) > 1 else 'localhost'
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 6379

    success = test_redis_connection(host, port)
    if not success:
        print("\nTroubleshooting tips:")
        print("1. Make sure Redis is running")
        print("2. Check if port 6379 is correctly mapped in docker-compose.yml")
        print("3. Ensure Redis is listening on the expected port")
        print("4. Verify there are no firewall rules blocking the connection")
        print("\nTo check Docker status:")
        print("  sudo docker ps")
        print("\nTo view Docker logs:")
        print("  sudo docker-compose logs redis")
        sys.exit(1)
    sys.exit(0) 