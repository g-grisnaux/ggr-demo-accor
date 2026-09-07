// Pattern: Profiling — gradual memory allocation in a cache
// Adapt: use a domain-relevant cache concept
const _cache = {};

function addToCache(req, res) {
  const key = req.query.key || 'default';
  _cache[key] = Buffer.alloc(1024 * 100); // 100KB per entry
  res.json({ cached: Object.keys(_cache).length, key });
}

module.exports = { addToCache };
