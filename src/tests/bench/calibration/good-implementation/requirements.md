# Requirements: User Notification System

## Functional Requirements

1. **R1**: When a job completes (success or failure), dispatch notification to the job owner
2. **R2**: Support two notification channels: email and in-app
3. **R3**: Users can configure default notification preferences (which channels, per job type)
4. **R4**: Notifications include: job ID, job type, completion status, timestamp, summary
5. **R5**: Failed jobs include error summary in notification
6. **R6**: Rate limiting: max 10 notifications per user per minute

## Non-Functional Requirements

7. **NR1**: Notification dispatch must not block job completion (async)
8. **NR2**: Failed notification delivery should retry up to 3 times with exponential backoff
9. **NR3**: Notification preferences are cached to avoid DB lookups on every job completion

## Edge Cases

- User has no notification preferences configured: use system defaults (email only)
- Job has no owner (system jobs): skip notification
- Both channels fail: log error, mark notification as failed, do not retry indefinitely
