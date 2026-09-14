// Drives the real ALL front in a real Chromium, from inside the cluster.
//
// Why this exists: the Browser RUM SDK only produces anything when an actual
// browser loads the page. The Locust generator talks to the GraphQL API
// directly, so it fills APM and never RUM — which is why RUM sat at zero
// events for a week. This container loads the app over ClusterIP, so RUM,
// session replay and browser logs fill continuously and nothing has to be
// exposed to the internet.
//
// Sessions are deliberately varied: different viewports, a mix of journeys,
// and an occasional deliberate front-end crash, so Error Tracking and Session
// Replay have something real to show rather than one identical session
// repeated.

const { chromium, devices } = require('playwright');

const TARGET = process.env.TARGET_URL || 'http://frontend';
const MIN_WAIT_MS = Number(process.env.MIN_WAIT_MS || 20000);
const MAX_WAIT_MS = Number(process.env.MAX_WAIT_MS || 50000);
// Share of sessions that deliberately crash the funnel. Low on purpose: front
// errors have to look like an incident, not like the normal state of the site.
const CRASH_RATE = Number(process.env.CRASH_RATE || '0.12');

const PROFILES = [
  { name: 'desktop', viewport: { width: 1440, height: 900 } },
  { name: 'laptop', viewport: { width: 1280, height: 800 } },
  { name: 'tablet', ...devices['iPad (gen 7)'] },
  { name: 'mobile-web', ...devices['Pixel 5'] },
];

const CITIES = ['Paris', 'Lyon', 'Marseille', 'Nice', 'London', 'Amsterdam'];

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isoDaysFromNow(days) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

async function session(browser, index) {
  const profile = pick(PROFILES);
  const { name, ...contextOptions } = profile;
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();

  // Surfaced in this container's own logs so a failure here is debuggable
  // without guessing; the browser's own console goes to RUM regardless.
  page.on('pageerror', (err) => console.log(JSON.stringify({ level: 'warn', profile: name, msg: 'page error', detail: err.message })));

  try {
    await page.goto(TARGET, { waitUntil: 'networkidle', timeout: 30000 });

    // A real visitor reads before acting. Without this every session is
    // sub-second and the RUM timings look synthetic.
    await sleep(1500 + Math.random() * 2500);

    await page.selectOption('select.select-bordered', pick(CITIES)).catch(() => {});
    await page.fill('input[type=date]:nth-of-type(1)', isoDaysFromNow(5 + Math.floor(Math.random() * 20))).catch(() => {});

    await page.click('button[type=submit]');
    await page.waitForSelector("//p[contains(., 'properties')]", { timeout: 20000 });
    await sleep(2000 + Math.random() * 3000);

    if (Math.random() < CRASH_RATE) {
      // The deliberate crash: the navbar button reads a property of an
      // undefined rate object, the error boundary catches it, and RUM records
      // the error with its component stack and a replayable session.
      await page.click('text=Break the funnel').catch(() => {});
      await sleep(3000);
      console.log(JSON.stringify({ level: 'info', profile: name, session: index, msg: 'session ended on a deliberate front-end crash' }));
      return;
    }

    // Otherwise go through with a booking, which exercises the full chain and
    // links the RUM session to a backend trace.
    const bookButton = page.locator("//button[contains(@class,'btn-sm')]").first();
    if (await bookButton.count()) {
      await bookButton.click();
      await page.waitForSelector('div.alert', { timeout: 20000 }).catch(() => {});
      await sleep(2000);
    }

    // A share of sessions visit the bookings page, so RUM sees more than one
    // view per session and the funnel has depth.
    if (Math.random() < 0.4) {
      await page.click('text=My bookings').catch(() => {});
      await sleep(2000 + Math.random() * 2000);
    }

    console.log(JSON.stringify({ level: 'info', profile: name, session: index, msg: 'session completed' }));
  } catch (err) {
    console.log(JSON.stringify({ level: 'warn', profile: name, session: index, msg: 'session aborted', detail: err.message.slice(0, 160) }));
  } finally {
    // Closing the context flushes the RUM session. Leaving contexts open would
    // hold sessions in limbo and leak memory over days of running.
    await context.close();
  }
}

async function main() {
  console.log(JSON.stringify({ level: 'info', msg: 'rum traffic generator starting', target: TARGET, crash_rate: CRASH_RATE }));

  const browser = await chromium.launch({
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });

  let index = 0;
  // Runs forever; Kubernetes restarts it if the browser dies.
  for (;;) {
    index += 1;
    await session(browser, index);
    await sleep(MIN_WAIT_MS + Math.random() * (MAX_WAIT_MS - MIN_WAIT_MS));
  }
}

main().catch((err) => {
  console.log(JSON.stringify({ level: 'error', msg: 'generator failed', detail: err.message }));
  process.exit(1);
});
