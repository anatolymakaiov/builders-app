"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {convertHeicToJpeg} = require("../web_image_derivative");

test("HEIC conversion requests a browser-compatible JPEG", async () => {
  const source = Buffer.from([1, 2, 3]);
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
  let options;
  const result = await convertHeicToJpeg(source, async (value) => {
    options = value;
    return jpeg;
  });
  assert.equal(options.buffer, source);
  assert.equal(options.format, "JPEG");
  assert.equal(options.quality, 0.88);
  assert.deepEqual(result, jpeg);
});

test("HEIC conversion rejects non-JPEG decoder output", async () => {
  await assert.rejects(
    convertHeicToJpeg(Buffer.from([1]), async () => Buffer.from("bad")),
    /did not return a JPEG/,
  );
});
