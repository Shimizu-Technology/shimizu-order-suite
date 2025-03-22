# Redis Configuration Guide for High Traffic

This guide explains how to configure Redis for high traffic scenarios, particularly when expecting 500-1000 users.

## The Warning

If you see this warning in your Sidekiq logs:

```
WARNING: Your Redis instance will evict Sidekiq data under heavy load.
The 'noeviction' maxmemory policy is recommended (current policy: 'allkeys-lru').
```

This means your Redis instance is configured to delete data when it reaches memory limits, which can cause job loss.

## Updating Redis Configuration on Render

### 1. Change the Eviction Policy

1. Log into your [Render Dashboard](https://dashboard.render.com/)
2. Navigate to your Redis service
3. Go to the "Environment" section
4. Add the following environment variable:
   - Key: `MAXMEMORY_POLICY`
   - Value: `noeviction`

This setting tells Redis to return errors when memory is full rather than deleting data. Sidekiq can properly retry jobs when this happens.

### 2. Increase Redis Memory (Before High Traffic Event)

1. In your Render Dashboard, find your Redis service
2. Click on "Change Plan"
3. Select a plan with at least 1GB of memory (recommended for 500-1000 users)
4. Confirm the upgrade

### 3. Monitor Redis Memory Usage

Use the `/health/sidekiq` endpoint we've added to monitor Redis memory usage. Set up alerts if Redis memory usage exceeds 80%.

## Sidekiq Configuration Changes

We've already made the following changes to optimize Sidekiq:

1. Increased worker concurrency from 5 to 8
2. Added queue priorities to ensure critical jobs are processed first
3. Set expiration times for different job types
4. Added job lifecycle settings to prevent memory bloat

## Testing

Before your high-traffic event:

1. Test the system with a smaller number of simulated users
2. Monitor the `/health/sidekiq` endpoint to see memory usage
3. Check for any job failures or performance issues

## Troubleshooting

If you still see issues during high traffic:

1. Check Redis memory usage - if consistently above 90%, consider upgrading to a larger plan
2. Look for slow jobs that might be blocking workers
3. Consider increasing the concurrency setting in `sidekiq.yml` if CPU resources allow
4. Ensure your database can handle the increased load from more workers

## Additional Resources

- [Sidekiq Redis Configuration](https://github.com/sidekiq/sidekiq/wiki/Using-Redis#memory)
- [Redis Memory Management](https://redis.io/topics/memory-optimization)
- [Render Redis Documentation](https://render.com/docs/redis)
