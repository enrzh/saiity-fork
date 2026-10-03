// Run through Ego with an existing Page and prototype file URL; see the design notes.
// Checks the local prototype. Does not launch the iOS app or access audio/models.
export default async function checkDesignPrototype(page, prototypeURL) {
  const assert = (await import("node:assert/strict")).default;
  const fs = await import("node:fs/promises");
  const vm = await import("node:vm");
  const prototype = new URL(prototypeURL);
  const source = await fs.readFile(prototype, "utf8");
  new vm.Script(source.match(/<script>([\s\S]*?)<\/script>/)[1]);
  await page.goto(prototype.href);
  console.log(await page.snapshot());
  await page.evaluate(() => {
    window.prototypeErrors = [];
    addEventListener("error", e => window.prototypeErrors.push(e.message));
    addEventListener("unhandledrejection", e => window.prototypeErrors.push(String(e.reason)));
    // Verify copy delivery with an in-page sink; preserve the user's OS clipboard.
    Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
      writeText: async text => { window.prototypeCopiedText = text; }
    }});
  });
  const text = selector => page.evaluate(s => document.querySelector(s)?.textContent, selector);
  await page.click('#speak-phone [data-action="primary-speak"]');
  assert.match(await text("#session-phone .session-kicker"), /Listening/);
  await page.click('#keyboard-phone [data-action="power"]');
  assert.equal(await text('#session-phone [data-action="primary-session"]'), "Enable dictation");
  await page.click('#speak-phone [data-action="power"]');
  assert.equal(await text('#session-phone [data-action="primary-session"]'), "Start dictation", "Enable must not record");
  await page.click('#keyboard-phone [data-action="primary-board"]');
  await page.click('#keyboard-phone [data-action="primary-board"]');
  assert.match(await page.evaluate(() => document.getElementById("message-draft").value), /我們下午再確認一次/);
  await page.click('#speak-phone [data-action="primary-speak"]');
  await page.click('#session-phone [data-action="primary-session"]');
  await page.click('#session-phone [data-action="copy"]');
  await page.waitForFunction(() => typeof window.prototypeCopiedText === "string");
  assert.match(await page.evaluate(() => window.prototypeCopiedText), /我們下午再確認一次/);
  await page.click('#session-phone [data-action="edit"]');
  await page.fill("#result-editor", "Updated proposal. 我們下午再確認一次。 José Müller.");
  await page.click('[data-action="save-edit"]');
  assert.match(await text("#session-phone .session-text"), /José Müller/);
  await page.click('[data-action="original"]');
  assert.match(await text(".original-text p"), /^um /);
  await page.click('[data-action="restore"]');
  assert.match(await text("#session-phone .session-text"), /^um /);
  await page.click('#speak-phone [data-action="sheet-models"]');
  await page.selectOption("#streaming-model", "Qwen3-ASR 1.7B");
  await page.keyboard.press("Escape");
  assert.equal(await text('#speak-phone [data-action="primary-speak"]'), "Finish setup");
  assert.equal(await page.evaluate(() => document.activeElement.dataset.action), "sheet-models");
  await page.click('#speak-phone [data-action="sheet-models"]');
  await page.click('input[name="engine"][value="Whisper Auto"]');
  await page.keyboard.press("Escape");
  assert.equal(await text('#speak-phone [data-action="primary-speak"]'), "Dictate again");
  for (const appearance of ["light", "dark"]) {
    await page.selectOption("#appearance", appearance);
    for (const width of [1440, 344]) {
      await page.cdp("Emulation.setDeviceMetricsOverride", {width, height:1120, deviceScaleFactor:1, mobile:false});
      const fits = await page.evaluate(() => ({
        horizontal: document.documentElement.scrollWidth <= document.documentElement.clientWidth,
        actions: [...document.querySelectorAll(".primary")].every(button => {
          const b = button.getBoundingClientRect(), p = button.closest(".phone").getBoundingClientRect();
          return b.left >= p.left && b.right <= p.right && b.top >= p.top && b.bottom <= p.bottom;
        })
      }));
      assert.ok(fits.horizontal && fits.actions, `Layout overflow at ${width}, ${appearance}`);
    }
  }
  await page.click("#large-text");
  for (const width of [344, 320]) {
    await page.cdp("Emulation.setDeviceMetricsOverride", {width,height:1120,deviceScaleFactor:1,mobile:false});
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth), "Larger text overflows the viewport");
    assert.equal(await page.evaluate(() => document.querySelector(".board-primary").getBoundingClientRect().height), 54);
  }
  await page.click('#speak-phone [data-action="sheet-settings"]');
  await page.click('[data-action="sheet-keyboard-options"]');
  await page.selectOption("#sheet-material", "solid");
  await page.click("#inset");
  assert.ok(await page.evaluate(() => document.querySelector(".board-inset").hidden));
  await page.selectOption("#sheet-material", "glass");
  assert.ok(await page.evaluate(() => document.querySelector(".board-inset").hidden), "Inset must remain optional in either material");
  await page.keyboard.press("Tab");
  assert.ok(await page.evaluate(() => !!document.activeElement.closest(".overlay")), "Sheet keyboard focus escaped");
  await page.keyboard.press("Escape");
  assert.equal(await page.evaluate(() => document.activeElement.dataset.action), "sheet-settings");
  await page.selectOption("#preview-state", "processing");
  await page.click('#session-phone [data-action="primary-session"]');
  assert.equal(await text('#session-phone [data-action="primary-session"]'), "Start dictation");
  await page.cdp("Emulation.setEmulatedMedia", {features:[{name:"prefers-reduced-motion",value:"reduce"}]});
  await page.selectOption("#preview-state", "recording");
  assert.equal(await page.evaluate(() => getComputedStyle(document.querySelector(".listening .brand")).animationName), "none");
  await page.cdp("Emulation.setEmulatedMedia", {features:[]});
  await page.selectOption("#preview-state", "recording");
  await page.click('#speak-phone [data-action="sheet-models"]');
  await page.click('input[name="engine"][value="Streaming"]');
  await page.selectOption("#streaming-model", "Qwen3-ASR 1.7B");
  await page.keyboard.press("Escape");
  assert.equal(await text('#session-phone [data-action="primary-session"]'), "Finish dictation", "A pending next model must not remove Finish");
  await page.click('#session-phone [data-action="primary-session"]');
  assert.match(await text("#session-phone .session-text"), /我們下午再確認一次/);
  assert.equal(await text('#speak-phone [data-action="primary-speak"]'), "Finish setup");
  await page.click('#keyboard-phone [data-action="sheet-language"]');
  await page.click('input[name="language"][value="中文"]');
  assert.match(await text('#keyboard-phone [data-action="sheet-language"]'), /中文/);
  assert.equal(await page.evaluate(() => document.activeElement.dataset.action), "sheet-language");
  assert.deepEqual(await page.evaluate(() => window.prototypeErrors), []);
  await page.cdp("Emulation.setDeviceMetricsOverride", {width:1440,height:1120,deviceScaleFactor:1,mobile:false});
  await page.reload();
  console.log("PASS: syntax, power/start/cancel, mixed-language delivery, copy sink, edit/original recovery, pending models, optional inset in both materials, focus, reduced motion and responsive light/dark/larger-text layout");
  console.log(await page.snapshot());
}
