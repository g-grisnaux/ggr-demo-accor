// Pattern: Code Security — SSRF via unvalidated URL parameter
// WARNING: intentionally vulnerable for IAST demo
// Adapt: use a domain-appropriate endpoint name

async function fetchUrl(req, res) {
  const url = req.query.url || '';
  try {
    const resp = await fetch(url);
    const body = await resp.text();
    res.send(body);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = { fetchUrl };
