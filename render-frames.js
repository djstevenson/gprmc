const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const inputDir = process.argv[2] || '.';
const outputDir = process.argv[3] || 'frames';

fs.mkdirSync(outputDir, { recursive: true });

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: 1920, height: 1080 },
    // Supersampled 4x and downscaled by ffmpeg at encode time, so text labels
    // (which don't anti-alias sub-pixel positions as smoothly as vector
    // strokes do) move more smoothly across frames.
    deviceScaleFactor: 4,
  });

  const files = fs.readdirSync(inputDir)
    .filter(f => /^gauges\d+\.html$/.test(f))
    .sort();

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    const inputPath = path.resolve(inputDir, file);
    const outputPath = path.join(outputDir, `frame${String(i + 1).padStart(6, '0')}.png`);

    await page.goto(`file://${inputPath}`);
    await page.screenshot({ path: outputPath });

    // console.log(`${file} -> ${outputPath}`);
  }

  await browser.close();
})();
