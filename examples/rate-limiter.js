const fs = require('fs')
const Redis = require('ioredis')

const redisClient = new Redis()

redisClient.defineCommand('checkAndSet', {
  numberOfKeys: 3,
  lua: fs.readFileSync('rate-limiter.lua'),
})

const limiters = [
  { period: 60, limit: 3, punishment: 60 * 15 },
  { period: 60 * 60, limit: 9 },
]

const keyPrefix = 'rate-limiter'
const eventId = 'test-event'


module.exports = redisClient.checkAndSet(keyPrefix, eventId, JSON.stringify(limiters))
  .then(retStr => {
    const ret = JSON.parse(retStr)
    if (ret.success === true) {
      console.log('Accept %s', eventId)
      if (ret.punishment) {
        console.log('Ban %s for %s seconds', eventId, ret.punishment)
      }
    } else if (ret.success === false) {
      console.log('Reject %s: %s', eventId, ret.reason)
    }
    return ret.success
  })
