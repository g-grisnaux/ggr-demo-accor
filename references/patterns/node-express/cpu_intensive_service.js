// Pattern: Profiling — CPU-intensive nested loop
// Adapt: replace with domain-relevant aggregation logic

function aggregate(req, res) {
  const counts = {};
  for (let i = 0; i < 100; i++) {
    for (const key in counts) delete counts[key];
    for (let j = 0; j < 10000; j++) {
      const key = `bucket-${j % 50}`;
      counts[key] = (counts[key] || 0) + 1;
    }
  }
  res.json({ buckets: Object.keys(counts).length, iterations: 100 * 10000 });
}

module.exports = { aggregate };
