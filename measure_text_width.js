// Measures the rendered pixel width of a line of text using the same
// font-family/size as templates/scroller.tt2, so make_text.pl can compute
// exactly when a scrolling text frame has cleared the screen.
//
// Usage: node measure_text_width.js < text.txt
// Prints the width in pixels (float) to stdout.

const { chromium } = require('playwright');

(async () => {
  const text = require('fs').readFileSync(0, 'utf8');

  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setContent(
    '<span id="t" style="font-family: Helvetica, Arial, sans-serif; ' +
    'font-size: 24px; white-space: nowrap; position: absolute;"></span>'
  );
  await page.locator('#t').evaluate((el, text) => { el.textContent = text; }, text);
  const width = await page.locator('#t').evaluate(el => el.getBoundingClientRect().width);
  await browser.close();

  console.log(width);
})();
