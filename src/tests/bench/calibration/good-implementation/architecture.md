# Architecture: User Notification System

## Component Design

### NotificationService
- Entry point for dispatching notifications
- Receives job completion events from JobQueue via event listener
- Loads user preferences (cached) to determine channels
- Delegates to channel-specific dispatchers

### NotificationChannel (interface)
- `send(notification: Notification): Result`
- Implemented by: EmailChannel, InAppChannel
- Each channel handles its own retry logic

### NotificationPreferences
- Per-user, per-job-type configuration
- Stored in user_preferences table
- Cached in-memory with 5-minute TTL

### RateLimiter
- Token bucket per user, 10 tokens/minute
- Shared across all channels
- Returns `rate_limited` status if exceeded

## Data Flow

```
JobQueue.onComplete(job)
  -> NotificationService.dispatch(job)
    -> PreferencesCache.get(job.owner, job.type)
    -> RateLimiter.check(job.owner)
    -> for each channel in preferences:
         channel.send(notification) [async]
```

## File Structure

```
src/notifications/
  service.ts           # NotificationService
  channel.ts           # NotificationChannel interface
  channels/
    email.ts           # EmailChannel implementation
    in-app.ts          # InAppChannel implementation
  preferences.ts       # NotificationPreferences + cache
  rate-limiter.ts      # RateLimiter
  types.ts             # Notification, Result types
```
