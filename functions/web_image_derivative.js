const heicConvert = require("heic-convert");

async function convertHeicToJpeg(sourceBuffer, convert = heicConvert) {
  const jpeg = Buffer.from(await convert({
    buffer: sourceBuffer,
    format: "JPEG",
    quality: 0.88,
  }));
  if (jpeg.length < 4 || jpeg[0] !== 0xff || jpeg[1] !== 0xd8) {
    throw new Error("HEIC decoder did not return a JPEG image");
  }
  return jpeg;
}

module.exports = {convertHeicToJpeg};
