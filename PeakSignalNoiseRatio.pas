UNIT PeakSignalNoiseRatio;

{=============================================================================================================
   Gabriel Moraru
   2024.05

   This is a port (but contains also major reworks) from C to Delphi.
   The original C code can be downloaded from http://tdistler.com/iqa
--------------------------------------------------------------------------------------------------------------
   Peak Signal-to-Noise Ratio
   (UNUSED)

   Calculates the Peak Signal-to-Noise-Ratio between 2 equal-sized 8-bit images.

   Params:
      ReferenceImage: Original image
      CompareImage  : Distorted image
      stride        : The length (in bytes) of each horizontal line in the image.
                      This may be different from the image width.
   PSNR
     PSNR(a,b) = 10*log10(L^2 / MSE(a,b)), where L=2^b - 1 (8bit = 255)
     Peak Signal-to-Noise Ratio is the ratio between the reference signal and the distortion signal in an image, given in decibels.
     The higher the PSNR, the closer the distorted image is to the original.
     In general, a higher PSNR value should correlate to a higher quality image, but tests have shown that this isn't always the case.
     However, PSNR is a popular quality metric because it's easy and fast to calculate while still giving okay results.
     For images A = [a1 .. aM], B = [b1 .. bM], and MAX equal to the maximum possible pixel value (2^8 - 1 = 255 for 8-bit images):
     More info: http://en.wikipedia.org/wiki/PSNR
-------------------------------------------------------------------------------------------------------------}

INTERFACE

USES
   System.Math, SsimDef, MeanSquaredError;

function psnr(ReferenceImage, CompareImage: ByteImage; ImgWidth, ImgHeigth, stride: integer): Single;  // Returns: PSNR


IMPLEMENTATION

function psnr(ReferenceImage, CompareImage: ByteImage; ImgWidth, ImgHeigth, stride: integer): Single;
CONST
   L_sqd: integer = 255*255;
begin
  Assert(Length(ReferenceImage) = Length(CompareImage), 'The images must have the same width, height, and stride.');
  Result:= 10 * log10(L_sqd / mse(ReferenceImage, CompareImage, ImgWidth, ImgHeigth, stride));
end;

end.
