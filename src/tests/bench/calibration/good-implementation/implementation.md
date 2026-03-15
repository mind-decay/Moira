# Implementation: User Notification System

## Files Created

### src/notifications/types.ts
- `Notification` type with fields: id, jobId, jobType, userId, status, timestamp, summary, errorSummary?
- `NotificationResult` type: success | failed | rate_limited
- `ChannelType` enum: email, in_app

### src/notifications/service.ts
- `NotificationService` class
- Constructor takes: preferencesCache, rateLimiter, channels map
- `dispatch(job: Job)`: async, loads preferences, checks rate limit, dispatches to channels
- Handles missing owner (system jobs) by returning early
- Logs all dispatch results for audit

### src/notifications/channel.ts
- `NotificationChannel` interface with `send(notification)` method
- Abstract retry logic in `RetryableChannel` base class
- Retry: 3 attempts, exponential backoff (1s, 2s, 4s)

### src/notifications/channels/email.ts
- `EmailChannel` extends `RetryableChannel`
- Uses existing `EmailService` for delivery
- Formats notification as email template

### src/notifications/channels/in-app.ts
- `InAppChannel` extends `RetryableChannel`
- Writes to `user_notifications` table
- Marks as unread, includes link to job details

### src/notifications/preferences.ts
- `NotificationPreferences` class with in-memory cache
- `get(userId, jobType)`: returns channel list, falls back to defaults
- Cache TTL: 5 minutes, uses Map with timestamp tracking
- Default preferences: email only

### src/notifications/rate-limiter.ts
- Token bucket implementation
- 10 tokens per user per minute
- `check(userId)`: returns boolean, consumes token if available

## Integration Points
- Registered as event listener on `JobQueue.onComplete`
- Email channel uses existing `EmailService` (no new dependency)
- In-app channel creates new `user_notifications` table (migration included)
