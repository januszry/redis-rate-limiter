# redis-rate-limiter
rate limiter implemented with redis lua script

Features:
- Check and set (CAS) is implemented with lua script. This is probably the only way to support CAS for single redis client. (See https://redis.io/commands/eval)
- Support punishment. If a limiter is reached and punishment is set, same event will be banned for a specified period.

Flow:
- For every limiter, no more than `limit` events can pass.
- If only the event passed all limiters, the event can pass.
- If the event passed all limiters and the `counter` equals `limit` and there is any punishment, ban this event with maximum of all punishments of limiters.

Limiter configuration example:
```lang=javascript
[
  { period: 60, limit: 3, punishment: 60 * 15 },
  { period: 60 * 60, limit: 9 },
]
```

see examples for more details
