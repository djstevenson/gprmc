const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2] || '.';
const digit = process.argv[3];

if (!/^[0-9a-f]$/.test(digit)) {
  throw new Error(`expected a single hex digit argument (0-9a-f), got ${JSON.stringify(digit)}`);
}

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: 1920, height: 1080 },
    // Supersampled 4x and downscaled by ffmpeg at encode time, so text labels
    // (which don't anti-alias sub-pixel positions as smoothly as vector
    // strokes do) move more smoothly across frames.
    deviceScaleFactor: 4,
  });

  const suffix = new RegExp(`${digit}\\.html$`);
  const files = fs.readdirSync(dir)
    .filter(f => suffix.test(f))
    .sort();

  for (const file of files) {
    const inputPath = path.resolve(dir, file);
    const outputPath = path.join(dir, file.replace(/\.html$/, '.png'));

    await page.goto(`file://${inputPath}`);
    await page.screenshot({ path: outputPath, omitBackground: true });

    // console.log(`${file} -> ${outputPath}`);
  }

  await browser.close();
})();
