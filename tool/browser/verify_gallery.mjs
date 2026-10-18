import assert from 'node:assert/strict';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { chromium } from 'playwright';
import { root, serveGallery } from './server.mjs';

const evidence = resolve(root, '.tmp/gallery-browser');
mkdirSync(evidence, {recursive: true});
const local = process.env.GALLERY_URL ? null : await serveGallery();
const url = process.env.GALLERY_URL ?? local.url;
const executablePath = process.env.GALLERY_BROWSER ?? [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
].find(existsSync);
const browser = await chromium.launch({executablePath, headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
const errors = [], failedRequests = [], checks = [];
const page = await browser.newPage({viewport: {width: 1440, height: 960}});
page.setDefaultTimeout(15000);
page.on('pageerror', error => errors.push(error.message));
page.on('response', response => { if (response.status() >= 400) failedRequests.push(`${response.status()} ${response.url()}`); });

async function snapshot() { return page.locator('body').ariaSnapshot(); }
async function until(check, message) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) { if (await check()) return; await page.waitForTimeout(100); }
  throw new Error(message);
}
async function hasText(text) { await until(async () => (await snapshot()).includes(text), `Missing UI text: ${text}`); }
async function enableAccessibility() {
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({state: 'attached', timeout: 30000});
  await placeholder.evaluate(element => element.click());
  await page.getByRole('button', {name: 'GitHub', exact: true}).waitFor();
}
async function select(category) {
  console.log(`Checking ${category}`);
  await page.getByRole('button', {name: category, exact: true}).click();
  await page.waitForTimeout(250);
}
async function capture(name) { await page.screenshot({path: resolve(evidence, `${name}.png`)}); }
async function focusEditor(input) {
  await input.click();
  // Focus can reuse a semantics textarea with a cached value while Flutter
  // reconnects editing. Let focus and the following frame finish before typing.
  await input.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await until(async () => (await input.evaluate(element => element.matches(':focus'))) && (await input.inputValue()).length > 0, 'Editor did not attach its focused value');
}
async function editDocument(edit) {
  await page.getByRole('button', {name: 'Source', exact: true}).click();
  const input = page.getByRole('alertdialog').getByRole('textbox');
  await focusEditor(input);
  const value = JSON.parse(await input.inputValue());
  edit(value);
  await input.fill(JSON.stringify(value));
  await page.getByRole('button', {name: 'Apply', exact: true}).click();
  await page.waitForTimeout(200);
}
async function run({material = false} = {}) {
  await page.getByRole('button', {name: material ? 'Render' : 'Run', exact: true}).click();
  await page.waitForTimeout(1600);
  await hasText(material ? 'WebGL material preview' : 'nodes evaluated locally');
}

try {
  await page.goto(url, {waitUntil: 'networkidle'});
  await enableAccessibility();
  const examples = [
    ['game', 'Visual scripting', 'And… lift off.'],
    ['workflow', 'Workflow & process', 'Automatically approved'],
    ['shader', 'Shader & material', 'Live material'],
    ['data', 'Dataflow & ETL', '3 rows made it through.'],
    ['ml', 'ML architecture', '66.4%'],
    ['audio', 'Modular audio', '220 Hz · sine'],
    ['mindmap', 'Graph-based UI', '6 connected ideas'],
  ];
  for (const [id, category, result] of examples) {
    await select(category); await hasText(result);
    assert.equal(new URL(page.url()).hash || '#game', `#${id}`);
    if (id !== 'audio' && id !== 'mindmap') await run({material: id === 'shader'});
    if (id === 'shader') {
      await page.waitForFunction(() => window.saiGallery.state.shader?.ok === true);
      const canvas = page.locator('canvas[aria-label="Live WebGL material preview"]');
      await canvas.waitFor(); await page.waitForTimeout(250);
      const pixels = await canvas.evaluate(canvas => {
        const gl = canvas.getContext('webgl'), sample = new Uint8Array(canvas.width * canvas.height * 4);
        gl.readPixels(0, 0, canvas.width, canvas.height, gl.RGBA, gl.UNSIGNED_BYTE, sample);
        const colors = new Set(); for (let i = 0; i < sample.length; i += 64) colors.add(`${sample[i]},${sample[i+1]},${sample[i+2]}`);
        return {error: gl.getError(), colors: colors.size};
      });
      assert.equal(pixels.error, 0); assert.ok(pixels.colors > 10, 'Shader must draw a nonuniform material');
      checks.push({name: 'shader-gpu', ...pixels});
    }
    if (id === 'audio') {
      await page.getByRole('button', {name: 'Play patch', exact: true}).click();
      await page.waitForFunction(() => window.saiGallery.state.audio?.active === true);
      assert.equal(await page.evaluate(() => window.saiGallery.state.audio.frequency), 220);
      await page.getByRole('button', {name: 'Stop', exact: true}).click();
      assert.equal(await page.evaluate(() => window.saiGallery.state.audio.active), false);
      await page.getByRole('button', {name: 'Play patch', exact: true}).click();
      await page.waitForTimeout(2300);
      assert.equal(await page.evaluate(() => window.saiGallery.state.audio.active), false);
      checks.push({name: 'web-audio', manualStop: true, timedStop: true});
    }
    await capture(id); checks.push({name: id, passed: true});
  }
  assert.equal(await page.getByRole('button', {name: 'Run', exact: true}).count(), 0);
  await hasText('Live map');
  await editDocument(document => { document.spaces.main.nodes.idea.data.label = 'Connected thinking'; });
  await hasText('Connected thinking');
  assert.equal(/invocations|0 ms|evaluated locally/.test(await snapshot()), false);
  checks.push({name: 'structural-map-without-execution', passed: true});
  // Exercise the real inline text editor, including several browser keystrokes.
  const ideaText = page.getByRole('textbox').first();
  await focusEditor(ideaText);
  const originalIdea = await ideaText.inputValue();
  await ideaText.fill('Direct idea');
  await ideaText.press('End');
  await page.keyboard.type(' editing');
  await hasText('Direct idea editing');
  await page.getByRole('button', {name: 'Source', exact: true}).click();
  const ideaSource = page.getByRole('alertdialog').getByRole('textbox');
  await focusEditor(ideaSource);
  assert.ok(Object.values(JSON.parse(await ideaSource.inputValue()).spaces.main.nodes).some(node => node.data.label === 'Direct idea editing'));
  await page.getByRole('button', {name: 'Cancel', exact: true}).click();
  await page.getByRole('button', {name: 'Undo', exact: true}).click();
  await hasText(originalIdea);
  await page.getByRole('button', {name: 'Redo', exact: true}).click();
  await hasText('Direct idea editing');
  assert.ok(!(await snapshot()).includes('NODE PROPERTIES'));
  checks.push({name: 'inline-idea-text-history', passed: true});

  await select('Visual scripting');
  const checkbox = page.getByRole('checkbox').first();
  await checkbox.click();
  await run(); await hasText('Staying grounded.');
  await page.getByRole('button', {name: 'Undo', exact: true}).click();
  await run(); await hasText('lift off.');
  const slider = page.getByRole('slider').first();
  const sliderBox = await slider.boundingBox();
  await page.mouse.move(sliderBox.x + sliderBox.width * .545, sliderBox.y + sliderBox.height / 2);
  await page.mouse.down();
  await page.mouse.move(sliderBox.x + sliderBox.width * .9, sliderBox.y + sliderBox.height / 2, {steps: 10});
  await page.mouse.up();
  await page.getByRole('button', {name: 'Source', exact: true}).click();
  const sliderSource = page.getByRole('alertdialog').getByRole('textbox');
  await focusEditor(sliderSource);
  const sliderDocument = JSON.parse(await sliderSource.inputValue());
  assert.ok(sliderDocument.spaces.main.nodes.impulse.data.strength > 7);
  await page.getByRole('button', {name: 'Cancel', exact: true}).click();
  await page.getByRole('button', {name: 'Undo', exact: true}).click();
  checks.push({name: 'inline-checkbox-slider-history', passed: true});

  await select('Modular audio');
  await page.getByRole('button', {name: 'sine', exact: true}).click();
  await page.getByRole('menuitem', {name: 'triangle', exact: true}).click();
  await page.getByRole('button', {name: 'Play patch', exact: true}).click();
  await page.waitForFunction(() => window.saiGallery.state.audio?.active === true);
  assert.equal(await page.evaluate(() => window.saiGallery.state.audio.waveform), 'triangle');
  await page.getByRole('button', {name: 'Stop', exact: true}).click();
  await page.getByRole('button', {name: 'Undo', exact: true}).click();
  checks.push({name: 'inline-dropdown-audio', passed: true});

  await select('Dataflow & ETL');
  await page.getByRole('button', {name: 'Edit Dataset (JSON)', exact: true}).click();
  const rowsInput = page.getByRole('alertdialog').getByRole('textbox');
  await focusEditor(rowsInput); await rowsInput.fill('{}');
  await page.getByRole('button', {name: 'Apply', exact: true}).click();
  await hasText('Expected a JSON array.');
  await focusEditor(rowsInput);
  await rowsInput.fill('[{"name":"Test","score":90}]');
  await page.getByRole('button', {name: 'Apply', exact: true}).click();
  await run(); await hasText('1 rows made it through.');
  await page.getByRole('button', {name: 'Undo', exact: true}).click();
  await run(); await hasText('3 rows made it through.');
  checks.push({name: 'inline-json-validation-history', passed: true});

  await select('Workflow & process');
  await editDocument(document => { document.spaces.main.nodes.expense.data.value = 1200; });
  await run(); await hasText('Manager review required');
  await page.getByRole('button', {name: 'Undo', exact: true}).isDisabled().then(disabled => assert.ok(disabled, 'Import resets history'));
  await page.getByRole('button', {name: 'Source', exact: true}).click();
  await page.getByRole('alertdialog').getByRole('textbox').click();
  await page.getByRole('alertdialog').getByRole('textbox').fill('{');
  await page.getByRole('button', {name: 'Apply', exact: true}).click();
  await until(async () => /SyntaxError|FormatException|Unexpected/.test(await snapshot()), 'Malformed JSON must show validation feedback');
  await capture('invalid-json');
  await page.getByRole('button', {name: 'Cancel', exact: true}).click();
  await run(); await hasText('Manager review required');
  checks.push({name: 'edited-workflow-and-atomic-invalid-import', passed: true});

  await page.getByRole('button', {name: 'More actions', exact: true}).click();
  await page.getByRole('menuitem', {name: 'Reset example', exact: true}).click();
  await hasText('Automatically approved');
  await page.getByRole('button', {name: 'Connection style', exact: true}).click();
  await page.getByRole('menuitem', {name: 'orthogonal', exact: true}).click();
  await page.getByRole('button', {name: 'More actions', exact: true}).click();
  await page.getByRole('menuitem', {name: 'Show minimap', exact: true}).click();
  await hasText('Hide minimap');
  await page.getByRole('button', {name: 'Fit graph', exact: true}).click();
  await capture('routing-and-minimap');
  checks.push({name: 'reset-routing-fit-minimap', passed: true});

  await page.goto('about:blank');
  await page.goto(`${url}#ml`, {waitUntil: 'domcontentloaded'});
  await enableAccessibility(); await hasText('Peek inside a tiny network.');
  assert.equal(new URL(page.url()).hash, '#ml');
  await page.reload({waitUntil: 'domcontentloaded'}); await enableAccessibility();
  await hasText('Peek inside a tiny network.');
  checks.push({name: 'deep-link-reload', passed: true});
  for (const [width, height] of [[1024, 768], [1440, 600], [390, 844]]) {
    await page.setViewportSize({width, height}); await page.waitForTimeout(350);
    if (width < 1180) {
      await page.getByRole('button', {name: 'Preview', exact: true}).click();
      await hasText('PREVIEW'); assert.ok(!(await snapshot()).includes('NODE PROPERTIES')); await page.waitForTimeout(400); await capture(`responsive-${width}-preview`);
      await page.keyboard.press('Escape');
      await page.waitForTimeout(400);
    }
    await capture(`responsive-${width}`);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    checks.push({name: `viewport-${width}x${height}`, passed: true});
  }
  assert.deepEqual(errors, []); assert.deepEqual(failedRequests, []);
  writeFileSync(resolve(evidence, 'report.json'), JSON.stringify({url, checks, errors, failedRequests}, null, 2));
  console.log(JSON.stringify({passed: true, checks: checks.length, evidence}));
} catch (error) {
  await capture('failure');
  writeFileSync(resolve(evidence, 'failure.txt'), `${error.stack}\n${await snapshot()}\n${JSON.stringify({errors, failedRequests})}`);
  throw error;
} finally {
  await browser.close(); if (local) await new Promise(resolve => local.server.close(resolve));
}
