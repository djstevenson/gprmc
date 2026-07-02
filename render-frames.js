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
    deviceScaleFactor: 1,
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

    console.log(`${file} -> ${outputPath}`);
  }

  await browser.close();
})();
